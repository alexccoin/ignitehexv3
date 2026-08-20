-- First, let's ensure the pgcrypto extension is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Drop the existing trigger to recreate it properly
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_signup ON auth.users;

-- Drop the existing function to recreate it
DROP FUNCTION IF EXISTS public.handle_new_user_signup();
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create a robust user signup handler that doesn't depend on gen_random_bytes
CREATE OR REPLACE FUNCTION public.handle_new_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  wallet_addr text;
BEGIN
  -- Generate wallet address using a different approach
  wallet_addr := 'arss_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32);
  
  -- Create user profile with minimal required data
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
    'pending'::account_status
  );

  -- Create user wallet with the generated address
  INSERT INTO public.user_wallets (
    user_id,
    wallet_address,
    arss_balance
  ) VALUES (
    NEW.id,
    wallet_addr,
    1000.00 -- Welcome bonus
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
  -- Log the error for debugging but don't block signup
  RAISE LOG 'Error in handle_new_user_signup: %', SQLERRM;
  RETURN NEW;
END;
$function$;

-- Create the trigger for new user signups
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_signup();

-- Also update the existing create_user_wallet function to not use gen_random_bytes
CREATE OR REPLACE FUNCTION public.create_user_wallet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  wallet_addr text;
BEGIN
  -- Generate wallet address using md5 instead of gen_random_bytes
  wallet_addr := 'arss_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32);
  
  INSERT INTO public.user_wallets (user_id, wallet_address, arss_balance)
  VALUES (NEW.id, wallet_addr, 1000.00); -- 1000 ARSS welcome bonus
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Don't block the main operation if wallet creation fails
  RAISE LOG 'Error in create_user_wallet: %', SQLERRM;
  RETURN NEW;
END;
$function$;