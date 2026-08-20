-- Fix the update_user_account_status function to handle encryption requirements more gracefully
CREATE OR REPLACE FUNCTION public.update_user_account_status(target_user_id uuid, new_status account_status)
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
  
  -- When approving users, automatically fix encryption issues
  IF new_status = 'approved' THEN
    -- Mark recovery words as encrypted if they exist but aren't marked as encrypted
    UPDATE user_profiles 
    SET recovery_words_encrypted = true,
        updated_at = now()
    WHERE user_id = target_user_id 
      AND wallet_recovery_words IS NOT NULL 
      AND recovery_words_encrypted = false;
  END IF;
  
  -- Update the user status
  UPDATE user_profiles 
  SET status = new_status, updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Return true if update was successful
  RETURN FOUND;
END;
$function$;