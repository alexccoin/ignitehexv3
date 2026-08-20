-- Update the handle_new_user_signup function to automatically approve new users
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
    'approved'::account_status  -- Changed from 'pending' to 'approved' for instant approval
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