-- Fix RLS policy for arss_transactions to allow system balance corrections
-- and ensure all users have complete account setups

-- First, update the RLS policy for arss_transactions to allow system corrections
DROP POLICY IF EXISTS "System can create balance corrections" ON arss_transactions;
CREATE POLICY "System can create balance corrections" 
ON arss_transactions 
FOR INSERT 
WITH CHECK (
  transaction_type IN ('balance_correction', 'system_fix', 'staking_reward') 
  OR (auth.uid() = user_id AND auth.uid() IS NOT NULL)
);

-- Function to fix missing user account components
CREATE OR REPLACE FUNCTION public.fix_incomplete_user_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  fixes_applied jsonb := '[]'::jsonb;
  total_fixes INTEGER := 0;
BEGIN
  -- Fix users without profiles
  FOR user_record IN
    SELECT au.id, au.email, au.raw_user_meta_data
    FROM auth.users au
    LEFT JOIN user_profiles up ON au.id = up.user_id
    WHERE up.user_id IS NULL
  LOOP
    INSERT INTO user_profiles (
      user_id, full_name, email_address, address, city, country, postal_code,
      str_domain_owned, str_domain_username, bsc_wallet_address, btc_wallet_address,
      recovery_words_encrypted, status
    ) VALUES (
      user_record.id,
      COALESCE(user_record.raw_user_meta_data->>'full_name', SPLIT_PART(user_record.email, '@', 1)),
      user_record.email,
      'To be updated', 'To be updated', 'To be updated', 'To be updated',
      'None', 'To be updated', 'To be updated', 'To be updated',
      false, 'pending'::account_status
    );
    
    fixes_applied := fixes_applied || jsonb_build_object(
      'type', 'missing_profile',
      'user_id', user_record.id,
      'email', user_record.email
    );
    total_fixes := total_fixes + 1;
  END LOOP;

  -- Fix users without wallets
  FOR user_record IN
    SELECT au.id, au.email
    FROM auth.users au
    LEFT JOIN user_wallets uw ON au.id = uw.user_id
    WHERE uw.user_id IS NULL
  LOOP
    INSERT INTO user_wallets (user_id, wallet_address, arss_balance)
    VALUES (
      user_record.id,
      'arss_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32),
      1000.00
    );
    
    fixes_applied := fixes_applied || jsonb_build_object(
      'type', 'missing_wallet',
      'user_id', user_record.id,
      'email', user_record.email
    );
    total_fixes := total_fixes + 1;
  END LOOP;

  -- Initialize staking pools for users who have profiles but missing pools
  FOR user_record IN
    SELECT up.user_id, up.email_address
    FROM user_profiles up
    LEFT JOIN user_staking_pools usp ON up.user_id = usp.user_id AND usp.pool_type = 'str'
    WHERE usp.user_id IS NULL
  LOOP
    PERFORM initialize_user_staking_pools(user_record.user_id);
    
    fixes_applied := fixes_applied || jsonb_build_object(
      'type', 'missing_staking_pools',
      'user_id', user_record.user_id,
      'email', user_record.email_address
    );
    total_fixes := total_fixes + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'total_fixes', total_fixes,
    'fixes_applied', fixes_applied,
    'timestamp', now()
  );
END;
$function$;