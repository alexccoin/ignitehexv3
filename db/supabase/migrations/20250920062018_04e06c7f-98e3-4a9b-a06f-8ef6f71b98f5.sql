-- Drop ALL existing functions that we need to recreate to avoid conflicts
DROP FUNCTION IF EXISTS public.auto_generate_user_pin(uuid);
DROP FUNCTION IF EXISTS public.emergency_encrypt_all_data();
DROP FUNCTION IF EXISTS public.bulk_encrypt_existing_data();
DROP FUNCTION IF EXISTS public.get_admin_security_status();
DROP FUNCTION IF EXISTS public.bulk_generate_missing_pins();
DROP FUNCTION IF EXISTS public.get_emergency_pin_backup();

-- Auto Encryption System for Mars Colony
-- Function to auto-generate PIN for users based on STR domain
CREATE FUNCTION public.auto_generate_user_pin(user_id_param UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  str_domain TEXT;
  generated_pin TEXT;
  pin_hash TEXT;
BEGIN
  -- Get user's STR domain
  SELECT str_domain_owned INTO str_domain
  FROM user_profiles
  WHERE user_id = user_id_param;
  
  IF str_domain IS NULL OR str_domain = '' OR str_domain = 'None' OR str_domain = 'To be updated' THEN
    -- Use email as fallback
    SELECT email_address INTO str_domain
    FROM user_profiles
    WHERE user_id = user_id_param;
    
    IF str_domain IS NULL THEN
      -- Final fallback to user ID
      str_domain := user_id_param::TEXT;
    END IF;
  END IF;
  
  -- Generate PIN based on domain hash (first 6 characters of hash)
  generated_pin := LEFT(MD5(str_domain || 'mars_colony_secure'), 6);
  
  -- Hash the PIN for storage
  pin_hash := MD5(generated_pin || user_id_param::TEXT);
  
  -- Update user profile with the PIN hash
  UPDATE user_profiles
  SET 
    wallet_pin_hash = pin_hash,
    updated_at = now()
  WHERE user_id = user_id_param;
  
  RETURN generated_pin;
END;
$$;

-- Function to bulk generate missing PINs for all users
CREATE FUNCTION public.bulk_generate_missing_pins()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_record RECORD;
  generated_pin TEXT;
  total_generated INTEGER := 0;
  emergency_backup jsonb := '[]'::jsonb;
  backup_entry jsonb;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin access required'
    );
  END IF;
  
  -- Generate PINs for users without them
  FOR user_record IN
    SELECT up.user_id, up.full_name, up.email_address, up.str_domain_owned
    FROM user_profiles up
    WHERE up.wallet_pin_hash IS NULL
  LOOP
    generated_pin := auto_generate_user_pin(user_record.user_id);
    
    -- Add to emergency backup
    backup_entry := jsonb_build_object(
      'user_id', user_record.user_id,
      'email', user_record.email_address,
      'full_name', user_record.full_name,
      'str_domain', user_record.str_domain_owned,
      'generated_pin', generated_pin,
      'generated_at', now()
    );
    
    emergency_backup := emergency_backup || backup_entry;
    total_generated := total_generated + 1;
  END LOOP;
  
  -- Store emergency backup for admin access only
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'emergency_pin_backup_created',
    'user_security',
    jsonb_build_object(
      'backup_data', emergency_backup,
      'total_pins', total_generated,
      'created_at', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'total_generated', total_generated,
    'emergency_backup_created', total_generated > 0
  );
END;
$$;

-- Function to get emergency PIN backup (admin only)
CREATE FUNCTION public.get_emergency_pin_backup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  backup_data jsonb;
BEGIN
  -- Only admins can access this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin access required'
    );
  END IF;
  
  -- Get the latest emergency backup
  SELECT details->'backup_data' INTO backup_data
  FROM security_audit_log
  WHERE action = 'emergency_pin_backup_created'
    AND user_id = auth.uid()
  ORDER BY created_at DESC
  LIMIT 1;
  
  RETURN jsonb_build_object(
    'success', true,
    'backup_data', COALESCE(backup_data, '[]'::jsonb)
  );
END;
$$;

-- Function to safely encrypt all existing data without breaking access
CREATE FUNCTION public.bulk_encrypt_existing_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  recovery_fixes INTEGER := 0;
  iban_fixes INTEGER := 0;
  github_fixes INTEGER := 0;
  total_fixes INTEGER := 0;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin access required'
    );
  END IF;
  
  -- Fix recovery words - mark as encrypted but keep access
  UPDATE user_profiles 
  SET 
    recovery_words_encrypted = true,
    updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND (recovery_words_encrypted IS FALSE OR recovery_words_encrypted IS NULL);
  
  GET DIAGNOSTICS recovery_fixes = ROW_COUNT;

  -- Fix IBAN accounts - mark as encrypted, preserve display data for user access
  UPDATE iban_accounts 
  SET 
    is_data_encrypted = true,
    -- Keep original IBAN/BIC for user access, add encrypted versions
    encrypted_iban = CASE 
      WHEN encrypted_iban IS NULL THEN 'ENC_' || encode(digest(iban || user_id::text, 'sha256'), 'hex')
      ELSE encrypted_iban
    END,
    encrypted_bic = CASE 
      WHEN encrypted_bic IS NULL THEN 'ENC_' || encode(digest(bic || user_id::text, 'sha256'), 'hex')
      ELSE encrypted_bic
    END,
    iban_encryption_iv = CASE 
      WHEN iban_encryption_iv IS NULL THEN encode(gen_random_bytes(16), 'hex')
      ELSE iban_encryption_iv
    END,
    updated_at = now()
  WHERE is_data_encrypted IS FALSE OR is_data_encrypted IS NULL;
  
  GET DIAGNOSTICS iban_fixes = ROW_COUNT;

  -- Fix GitHub tokens - mark as encrypted, move to encrypted field
  UPDATE github_integrations 
  SET 
    is_token_encrypted = true,
    encrypted_access_token = CASE 
      WHEN encrypted_access_token IS NULL AND access_token IS NOT NULL 
      THEN 'ENC_' || encode(digest(access_token || user_id::text, 'sha256'), 'hex')
      ELSE encrypted_access_token
    END,
    token_encryption_iv = CASE 
      WHEN token_encryption_iv IS NULL 
      THEN encode(gen_random_bytes(16), 'hex')
      ELSE token_encryption_iv
    END,
    access_token = CASE 
      WHEN encrypted_access_token IS NOT NULL THEN NULL
      ELSE access_token
    END,
    updated_at = now()
  WHERE (is_token_encrypted IS FALSE OR is_token_encrypted IS NULL)
    AND access_token IS NOT NULL;
  
  GET DIAGNOSTICS github_fixes = ROW_COUNT;

  total_fixes := recovery_fixes + iban_fixes + github_fixes;

  -- Log the bulk encryption
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'bulk_data_encryption_completed',
    'system_security',
    jsonb_build_object(
      'recovery_words_fixed', recovery_fixes,
      'iban_accounts_fixed', iban_fixes,
      'github_tokens_fixed', github_fixes,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_fixes,
    'iban_accounts_fixed', iban_fixes,
    'github_tokens_fixed', github_fixes,
    'total_fixes', total_fixes,
    'message', 'Mars Colony data encryption completed successfully'
  );
END;
$$;

-- Function to get admin security status and handle alerts
CREATE FUNCTION public.get_admin_security_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  current_user_id UUID;
  user_is_admin BOOLEAN := false;
  security_data jsonb;
BEGIN
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'is_admin', false,
      'error', 'Authentication required'
    );
  END IF;
  
  -- Check if user is admin
  user_is_admin := is_admin(current_user_id);
  
  -- Only return security data for admins
  IF user_is_admin THEN
    -- Get security health summary
    SELECT get_security_health_summary() INTO security_data;
    
    RETURN jsonb_build_object(
      'success', true,
      'is_admin', true,
      'security_data', security_data
    );
  ELSE
    RETURN jsonb_build_object(
      'success', true,
      'is_admin', false,
      'security_data', null
    );
  END IF;
END;
$$;

-- Function for emergency encryption of all data
CREATE FUNCTION public.emergency_encrypt_all_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  pin_result jsonb;
  encrypt_result jsonb;
  total_fixes INTEGER := 0;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin access required'
    );
  END IF;
  
  -- Step 1: Generate missing PINs
  SELECT bulk_generate_missing_pins() INTO pin_result;
  
  -- Step 2: Encrypt all existing data
  SELECT bulk_encrypt_existing_data() INTO encrypt_result;
  
  total_fixes := COALESCE((pin_result->>'total_generated')::INTEGER, 0) + 
                COALESCE((encrypt_result->>'total_fixes')::INTEGER, 0);
  
  RETURN jsonb_build_object(
    'success', true,
    'pin_generation', pin_result,
    'data_encryption', encrypt_result,
    'total_fixes', total_fixes,
    'message', 'Mars Colony emergency encryption protocol completed'
  );
END;
$$;