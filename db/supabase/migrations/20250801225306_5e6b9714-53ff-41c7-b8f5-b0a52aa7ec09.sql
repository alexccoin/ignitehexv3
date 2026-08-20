-- Add function to manually confirm user email without verification
CREATE OR REPLACE FUNCTION public.admin_confirm_user_email(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  
  -- Update the user's email confirmation status in auth.users
  UPDATE auth.users 
  SET 
    email_confirmed_at = COALESCE(email_confirmed_at, now()),
    updated_at = now()
  WHERE id = target_user_id;
  
  -- Also update the user profile status to approved if it's pending
  UPDATE user_profiles 
  SET 
    status = CASE 
      WHEN status = 'pending' THEN 'approved'::account_status 
      ELSE status 
    END,
    updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Return true if update was successful
  RETURN FOUND;
END;
$function$;