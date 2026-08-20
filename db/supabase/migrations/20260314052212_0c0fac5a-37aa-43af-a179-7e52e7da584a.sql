CREATE OR REPLACE FUNCTION public.handle_new_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  wallet_addr text;
BEGIN
  -- Validate email format before allowing registration
  IF NEW.email IS NULL OR NEW.email = '' OR 
     NEW.email !~ '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format: registration rejected';
  END IF;

  -- Generate wallet address
  wallet_addr := 'arss_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32);
  
  -- Create user profile with minimal required data - AUTO APPROVED
  INSERT INTO public.user_profiles (
    user_id,
    full_name,
    address,
    city,
    country,
    postal_code,
    email_address,
    str_domain_owned,
    str_domain_username,
    bsc_wallet_address,
    btc_wallet_address,
    status
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'User ' || substring(NEW.id::text, 1, 8)),
    'To be updated',
    'To be updated', 
    'To be updated',
    'To be updated',
    NEW.email,
    'To be updated',
    'To be updated',
    'To be updated',
    'To be updated',
    'approved'::account_status
  );

  -- Create user wallet with the generated address
  INSERT INTO public.user_wallets (
    user_id,
    wallet_address,
    arss_balance
  ) VALUES (
    NEW.id,
    wallet_addr,
    1000.00
  );

  -- Assign default user role
  INSERT INTO public.user_roles (
    user_id,
    role,
    created_by
  ) VALUES (
    NEW.id,
    'user'::app_role,
    NEW.id
  )
  ON CONFLICT (user_id, role) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Re-raise email validation errors so invalid registrations are blocked
  IF SQLERRM LIKE 'Invalid email format%' THEN
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
  RAISE LOG 'Error in handle_new_user_signup: %', SQLERRM;
  RETURN NEW;
END;
$$;