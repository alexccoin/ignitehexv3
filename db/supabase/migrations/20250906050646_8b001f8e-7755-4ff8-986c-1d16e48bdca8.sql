-- Fix remaining function with mutable search path security issue
DROP FUNCTION IF EXISTS public.sync_profiles_from_auth();

CREATE OR REPLACE FUNCTION public.sync_profiles_from_auth()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Update existing profiles to match auth users
  INSERT INTO public.user_profiles (user_id, full_name, email_address, address, city, country, postal_code, str_domain_owned, str_domain_username, bsc_wallet_address, btc_wallet_address)
  SELECT 
    au.id,
    COALESCE(au.raw_user_meta_data->>'full_name', au.email),
    au.email,
    'To be updated',
    'To be updated',
    'To be updated', 
    'To be updated',
    'To be updated',
    'To be updated',
    'To be updated',
    'To be updated'
  FROM auth.users au
  LEFT JOIN public.user_profiles p ON au.id = p.user_id
  WHERE p.user_id IS NULL
  ON CONFLICT (user_id) DO UPDATE SET
    email_address = EXCLUDED.email_address,
    full_name = COALESCE(EXCLUDED.full_name, public.user_profiles.full_name),
    updated_at = now();
END;
$$;