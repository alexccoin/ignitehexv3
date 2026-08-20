-- Security fixes migration

-- 1) Harden role assignment: admin-only guard (keep SECURITY DEFINER for auth.users access)
CREATE OR REPLACE FUNCTION public.assign_admin_role(target_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  target_user_id UUID;
BEGIN
  -- Authorization: admin only
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Find user by email in auth.users
  SELECT id INTO target_user_id 
  FROM auth.users 
  WHERE email = target_email;
  
  IF target_user_id IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Remove any existing user role and assign admin role
  DELETE FROM public.user_roles WHERE user_id = target_user_id AND role = 'user';
  
  INSERT INTO public.user_roles (user_id, role, created_by)
  VALUES (target_user_id, 'admin', auth.uid())
  ON CONFLICT (user_id, role) DO NOTHING;
  
  RETURN TRUE;
END;
$$;

-- 2) Harden generic role assignment: admin-only with role validation
CREATE OR REPLACE FUNCTION public.assign_user_role(target_email text, user_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  target_user_id uuid;
BEGIN
  -- Authorization: admin only
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Validate role
  IF user_role NOT IN ('admin','moderator','support','user') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  -- Find user by email in auth.users
  SELECT id INTO target_user_id
  FROM auth.users
  WHERE email = target_email;
  
  IF target_user_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Delete existing role(s)
  DELETE FROM public.user_roles
  WHERE user_id = target_user_id;
  
  -- Insert new role
  INSERT INTO public.user_roles (user_id, role, created_by)
  VALUES (target_user_id, user_role::app_role, auth.uid())
  ON CONFLICT (user_id, role) DO NOTHING;
  
  RETURN true;
END;
$$;

-- 3) Ensure update_user_status checks admin or delegates to secure function
CREATE OR REPLACE FUNCTION public.update_user_status(target_user_id uuid, new_status text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Authorization: admin only
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Reuse existing secure function with enum coercion
  RETURN public.update_user_account_status(target_user_id, new_status::account_status);
EXCEPTION WHEN invalid_text_representation THEN
  RAISE EXCEPTION 'Invalid account status';
END;
$$;

-- 4) Guard wallet balance updates: self or admin only
CREATE OR REPLACE FUNCTION public.update_wallet_balance(target_user_id uuid, amount_change numeric, transaction_type text, source_type text, description text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  current_balance DECIMAL(18,8);
BEGIN
  -- Authorization: self or admin
  IF auth.uid() IS DISTINCT FROM target_user_id AND NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  -- Get current balance
  SELECT arss_balance INTO current_balance 
  FROM public.user_wallets 
  WHERE user_id = target_user_id;
  
  IF current_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;
  
  -- Check sufficient balance for spending
  IF transaction_type = 'spend' AND current_balance < ABS(amount_change) THEN
    RETURN FALSE;
  END IF;
  
  -- Update wallet balance
  UPDATE public.user_wallets 
  SET 
    arss_balance = arss_balance + amount_change,
    total_earned = CASE WHEN amount_change > 0 THEN total_earned + amount_change ELSE total_earned END,
    total_spent = CASE WHEN amount_change < 0 THEN total_spent + ABS(amount_change) ELSE total_spent END,
    updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Record transaction
  INSERT INTO public.arss_transactions (user_id, transaction_type, amount, source_type, description)
  VALUES (target_user_id, transaction_type, amount_change, source_type, description);
  
  RETURN TRUE;
END;
$$;

-- 5) Guard get_user_financial_profile: only owner or admin
CREATE OR REPLACE FUNCTION public.get_user_financial_profile(target_user_id uuid)
RETURNS TABLE(profile_id uuid, str_domain text, iban_accounts jsonb, visa_card_info jsonb, sourceless_account jsonb, ccoin_pool_balance numeric, recent_transfers jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT (is_admin(auth.uid()) OR auth.uid() = target_user_id) THEN
    RAISE EXCEPTION 'Access denied. Owner or admin required.';
  END IF;

  RETURN QUERY
  SELECT 
    upc.id as profile_id,
    upc.str_domain,
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', ia.id,
          'iban', ia.iban,
          'bic', ia.bic,
          'account_holder', ia.account_holder,
          'account_type', ia.account_type,
          'currency', ia.currency,
          'balance', ia.balance,
          'status', ia.status
        )
      )
      FROM public.iban_accounts ia 
      WHERE ia.user_id = target_user_id
    ) as iban_accounts,
    jsonb_build_object(
      'card_number', upc.visa_card_number,
      'status', upc.visa_card_status
    ) as visa_card_info,
    jsonb_build_object(
      'account_id', upc.sourceless_account_id,
      'wallet_address', upc.sourceless_wallet_address
    ) as sourceless_account,
    upc.ccoin_pool_balance,
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', tr.id,
          'from_type', tr.from_account_type,
          'to_type', tr.to_account_type,
          'amount', tr.amount,
          'currency', tr.currency,
          'status', tr.status,
          'created_at', tr.created_at
        )
        ORDER BY tr.created_at DESC
      )
      FROM public.transfer_reports tr 
      WHERE tr.user_id = target_user_id
      LIMIT 10
    ) as recent_transfers
  FROM public.user_profile_connections upc
  WHERE upc.user_id = target_user_id;
END;
$$;

-- 6) Remove hardcoded password in prime founder position creation
CREATE OR REPLACE FUNCTION public.create_prime_founder_position(target_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  position_id uuid;
BEGIN
  INSERT INTO founder_positions (
    user_id,
    position_number,
    current_usd_value,
    max_usd_limit,
    min_deposit_usd,
    deposit_date,
    withdrawal_available_date,
    expected_btc_return,
    status,
    title,
    input_btc_amount,
    output_btc_amount,
    ccos_mint_percentage,
    withdrawal_address,
    access_password,
    is_prime
  ) VALUES (
    target_user_id,
    1,
    350000,
    1000000,
    10000,
    now(),
    now() + INTERVAL '90 days',
    525000,
    'active',
    'Prime Founder',
    5.0,
    7.5,
    50.0,
    'bc1q9u3hth4x4hl6y8hmcmvm5pc7yvtrduc92rfhxh',
    NULL,
    true
  ) RETURNING id INTO position_id;
  
  RETURN position_id;
END;
$$;

-- 7) GitHub tokens: allow NULL plaintext token and clear existing values
ALTER TABLE public.github_integrations 
  ALTER COLUMN access_token DROP NOT NULL;

-- Clear any lingering plaintext tokens
UPDATE public.github_integrations 
SET access_token = NULL 
WHERE access_token IS NOT NULL;

-- 8) Chat policy cleanup: drop redundant policy
DROP POLICY IF EXISTS "Users can view public chat messages secure" ON public.chat_messages;