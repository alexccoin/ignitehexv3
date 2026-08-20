-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.hash_pin_secure(text, uuid);
DROP FUNCTION IF EXISTS public.verify_pin_secure(text, uuid);

-- Create function to check user security compliance
CREATE OR REPLACE FUNCTION public.check_user_security_compliance(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_profile user_profiles%ROWTYPE;
  pin_set boolean := false;
  two_fa_enabled boolean := false;
  recovery_words_secure boolean := true;
  security_score integer := 0;
  is_compliant boolean := false;
  result jsonb;
BEGIN
  -- Get user profile data
  SELECT * INTO user_profile
  FROM user_profiles 
  WHERE user_id = check_user_id;
  
  IF user_profile.user_id IS NULL THEN
    RETURN jsonb_build_object(
      'pin_set', false,
      'two_fa_enabled', false,
      'recovery_words_secure', true,
      'compliant', false,
      'score', 0,
      'error', 'Profile not found'
    );
  END IF;
  
  -- Check PIN status
  pin_set := user_profile.wallet_pin_hash IS NOT NULL;
  
  -- Check 2FA status
  two_fa_enabled := COALESCE(user_profile.two_factor_enabled, false);
  
  -- Check recovery words encryption status
  recovery_words_secure := COALESCE(user_profile.recovery_words_encrypted, true);
  
  -- Calculate security score (0-100)
  security_score := 0;
  
  IF pin_set THEN
    security_score := security_score + 50; -- PIN is worth 50 points
  END IF;
  
  IF two_fa_enabled THEN
    security_score := security_score + 30; -- 2FA is worth 30 points
  END IF;
  
  IF recovery_words_secure THEN
    security_score := security_score + 20; -- Encrypted recovery words worth 20 points
  END IF;
  
  -- User is compliant if they have at least PIN set and data encrypted
  is_compliant := pin_set AND recovery_words_secure;
  
  -- Log security compliance check
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    check_user_id,
    'security_compliance_check',
    'user_security',
    jsonb_build_object(
      'pin_set', pin_set,
      'two_fa_enabled', two_fa_enabled,
      'recovery_words_secure', recovery_words_secure,
      'score', security_score,
      'compliant', is_compliant,
      'timestamp', now()
    )
  );
  
  result := jsonb_build_object(
    'pin_set', pin_set,
    'two_fa_enabled', two_fa_enabled,
    'recovery_words_secure', recovery_words_secure,
    'compliant', is_compliant,
    'score', security_score,
    'last_checked', now()
  );
  
  RETURN result;
END;
$$;

-- Create function to securely hash and store user PIN
CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  pin_hash text;
  result jsonb;
BEGIN
  -- Validate input
  IF pin_text IS NULL OR LENGTH(pin_text) != 6 OR pin_text !~ '^\d{6}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PIN must be exactly 6 digits'
    );
  END IF;
  
  IF user_uuid IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User ID is required'
    );
  END IF;
  
  -- Hash the PIN using SHA-256 with salt
  pin_hash := encode(digest(pin_text || user_uuid::text || 'wallet_pin_salt', 'sha256'), 'hex');
  
  -- Update user profile with hashed PIN
  UPDATE user_profiles
  SET 
    wallet_pin_hash = pin_hash,
    updated_at = now()
  WHERE user_id = user_uuid;
  
  -- Log PIN setup
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_uuid,
    'wallet_pin_set',
    'user_security',
    jsonb_build_object('timestamp', now())
  );
  
  result := jsonb_build_object(
    'success', true,
    'message', 'PIN set successfully'
  );
  
  RETURN result;
END;
$$;

-- Create function to verify PIN for sensitive operations
CREATE OR REPLACE FUNCTION public.verify_pin_secure(pin_text text, user_uuid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_hash text;
  calculated_hash text;
  is_valid boolean := false;
  result jsonb;
BEGIN
  -- Validate input
  IF pin_text IS NULL OR LENGTH(pin_text) != 6 OR pin_text !~ '^\d{6}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Invalid PIN format'
    );
  END IF;
  
  -- Get stored hash
  SELECT wallet_pin_hash INTO stored_hash
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  IF stored_hash IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No PIN set for this user'
    );
  END IF;
  
  -- Calculate hash for provided PIN
  calculated_hash := encode(digest(pin_text || user_uuid::text || 'wallet_pin_salt', 'sha256'), 'hex');
  
  -- Verify PIN
  is_valid := (calculated_hash = stored_hash);
  
  -- Log verification attempt
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_uuid,
    'pin_verification_attempt',
    'user_security',
    jsonb_build_object('success', is_valid, 'timestamp', now())
  );
  
  result := jsonb_build_object(
    'success', is_valid,
    'message', CASE WHEN is_valid THEN 'PIN verified' ELSE 'Invalid PIN' END
  );
  
  RETURN result;
END;
$$;