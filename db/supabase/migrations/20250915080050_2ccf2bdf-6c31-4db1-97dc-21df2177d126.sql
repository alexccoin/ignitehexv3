-- Fix admin_upsert_user_profile_status to satisfy NOT NULL columns on insert
CREATE OR REPLACE FUNCTION public.admin_upsert_user_profile_status(
  target_user_id uuid,
  new_status account_status,
  full_name text DEFAULT NULL,
  email_address text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Upsert profile row and set status
  -- Provide placeholder values for NOT NULL fields to avoid 23502 errors
  INSERT INTO public.user_profiles (
    user_id,
    status,
    full_name,
    email_address,
    address,
    city,
    country,
    postal_code,
    str_domain_owned,
    str_domain_username,
    bsc_wallet_address,
    btc_wallet_address,
    created_at,
    updated_at
  )
  VALUES (
    target_user_id,
    new_status,
    COALESCE(full_name, 'No Profile Created'),
    COALESCE(email_address, 'unknown@example.com'),
    'To be updated',
    'To be updated',
    'To be updated',
    'To be updated',
    'None',
    'To be updated',
    'To be updated',
    'To be updated',
    now(),
    now()
  )
  ON CONFLICT (user_id)
  DO UPDATE SET 
    status = EXCLUDED.status,
    updated_at = now();

  RETURN true;
END;
$function$;