-- Fix the function to cast text to account_status enum type
CREATE OR REPLACE FUNCTION public.admin_upsert_user_profile_status(
  target_user_id UUID,
  new_status TEXT,
  full_name TEXT DEFAULT NULL,
  email_address TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Check if profile exists
  SELECT EXISTS(SELECT 1 FROM user_profiles WHERE user_id = target_user_id) INTO v_exists;

  IF v_exists THEN
    -- Update existing profile - cast text to account_status
    UPDATE user_profiles 
    SET status = new_status::account_status, updated_at = now()
    WHERE user_id = target_user_id;
  ELSE
    -- Insert new profile with placeholder values - cast text to account_status
    INSERT INTO user_profiles (
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
      recovery_words_encrypted,
      created_at,
      updated_at
    )
    VALUES (
      target_user_id,
      new_status::account_status,
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
      false,
      now(),
      now()
    );
  END IF;

  RETURN true;
END;
$$;