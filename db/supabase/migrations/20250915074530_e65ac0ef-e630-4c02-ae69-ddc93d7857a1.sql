-- Create admin upsert function to ensure profiles exist and set status
CREATE OR REPLACE FUNCTION public.admin_upsert_user_profile_status(
  target_user_id uuid,
  new_status public.account_status,
  full_name text DEFAULT NULL,
  email_address text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Upsert profile row and set status
  INSERT INTO public.user_profiles (user_id, status, full_name, email_address, created_at, updated_at)
  VALUES (target_user_id, new_status, full_name, email_address, now(), now())
  ON CONFLICT (user_id)
  DO UPDATE SET 
    status = EXCLUDED.status,
    updated_at = now();

  RETURN true;
END;
$$;

-- Helpful comment for future devs
COMMENT ON FUNCTION public.admin_upsert_user_profile_status(uuid, public.account_status, text, text)
IS 'Admin-only helper: upserts into user_profiles by user_id and sets status. Bypasses missing profile issue when approving users.';