-- Create a function to handle new user registration
CREATE OR REPLACE FUNCTION public.handle_new_user_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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

  -- Create user wallet
  INSERT INTO public.user_wallets (
    user_id,
    wallet_address,
    arss_balance
  ) VALUES (
    NEW.id,
    'arss_' || encode(gen_random_bytes(16), 'hex'),
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
END;
$$;

-- Create trigger on auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user_signup();

-- Also make sure the profiles table is compatible (update if exists)
CREATE OR REPLACE FUNCTION public.sync_profiles_from_auth()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update existing profiles to match auth users
  INSERT INTO public.profiles (user_id, email, full_name)
  SELECT 
    au.id,
    au.email,
    COALESCE(au.raw_user_meta_data->>'full_name', au.email)
  FROM auth.users au
  LEFT JOIN public.profiles p ON au.id = p.user_id
  WHERE p.user_id IS NULL
  ON CONFLICT (user_id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(EXCLUDED.full_name, profiles.full_name);
END;
$$;

-- Run the sync to fix any existing users
SELECT public.sync_profiles_from_auth();