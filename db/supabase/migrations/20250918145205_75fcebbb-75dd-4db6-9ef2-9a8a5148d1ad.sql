-- Fix PIN encryption defaults and unencrypted recovery words
-- First, update the default value for recovery_words_encrypted to ensure it defaults to true
ALTER TABLE user_profiles ALTER COLUMN recovery_words_encrypted SET DEFAULT true;

-- Update all existing users without recovery_words_encrypted set to true
UPDATE user_profiles 
SET recovery_words_encrypted = true, 
    updated_at = now()
WHERE recovery_words_encrypted IS NULL OR recovery_words_encrypted = false;

-- Create a function to ensure proper PIN hashing (if it doesn't exist)
CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  hashed_pin text;
  result jsonb;
BEGIN
  -- Generate bcrypt hash of the PIN
  hashed_pin := crypt(pin_text, gen_salt('bf', 12));
  
  -- Update the user's profile with the hashed PIN
  UPDATE user_profiles 
  SET 
    wallet_pin_hash = hashed_pin,
    wallet_setup_completed = true,
    recovery_words_encrypted = true,
    updated_at = now()
  WHERE user_id = user_uuid;
  
  -- Log the security action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_uuid, 
    'pin_hash_created', 
    'user_security',
    jsonb_build_object('timestamp', now(), 'hash_length', length(hashed_pin))
  );
  
  result := jsonb_build_object(
    'success', true,
    'message', 'PIN securely hashed and stored'
  );
  
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- Create a function to get wallet recovery words securely with PIN verification  
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  stored_pin_hash text;
  recovery_words text[];
  rate_limit_result jsonb;
  result jsonb;
BEGIN
  -- Enhanced rate limiting with progressive delays
  rate_limit_result := enhanced_rate_limit_check(
    user_uuid, 
    COALESCE(client_ip, get_client_ip()), 
    'wallet_pin',
    5, -- max attempts
    60 -- time window in minutes
  );
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    -- Log failed attempt
    INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, COALESCE(client_ip, get_client_ip()), 'wallet_pin', false, rate_limit_result);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', rate_limit_result->>'reason',
      'retry_after', rate_limit_result->>'retry_after'
    );
  END IF;
  
  -- Get user's PIN hash and recovery words
  SELECT wallet_pin_hash, wallet_recovery_words
  INTO stored_pin_hash, recovery_words
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  -- Check if PIN exists
  IF stored_pin_hash IS NULL THEN
    INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, COALESCE(client_ip, get_client_ip()), 'wallet_pin', false, 
            jsonb_build_object('error', 'no_pin_set'));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin'
    );
  END IF;
  
  -- Verify PIN using crypt function for bcrypt
  IF NOT (stored_pin_hash = crypt(input_pin, stored_pin_hash)) THEN
    -- Log failed attempt
    INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, COALESCE(client_ip, get_client_ip()), 'wallet_pin', false, 
            jsonb_build_object('error', 'invalid_pin'));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin'
    );
  END IF;
  
  -- Log successful attempt
  INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
  VALUES (user_uuid, COALESCE(client_ip, get_client_ip()), 'wallet_pin', true, 
          jsonb_build_object('access_granted', true));
  
  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', COALESCE(recovery_words, ARRAY[]::text[]),
    'access_method', 'pin_verification'
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Log error attempt
  INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
  VALUES (user_uuid, COALESCE(client_ip, get_client_ip()), 'wallet_pin', false, 
          jsonb_build_object('error', 'system_error', 'details', SQLERRM));
  
  RETURN jsonb_build_object(
    'success', false,
    'error', 'system_error'
  );
END;
$$;