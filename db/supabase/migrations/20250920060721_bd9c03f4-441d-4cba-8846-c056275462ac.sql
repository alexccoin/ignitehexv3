-- Create function to auto-generate PIN based on STR domain name
CREATE OR REPLACE FUNCTION public.auto_generate_user_pin(target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_str_domain text;
  generated_pin text;
  pin_hash text;
  result jsonb;
BEGIN
  -- Get user's STR domain
  SELECT str_domain_owned INTO user_str_domain
  FROM user_profiles
  WHERE user_id = target_user_id;
  
  IF user_str_domain IS NULL OR user_str_domain = 'None' THEN
    user_str_domain := 'mars-colony-' || target_user_id::text;
  END IF;
  
  -- Generate PIN from STR domain (first 6 chars of MD5 hash as numbers)
  generated_pin := lpad((('x' || substr(md5(user_str_domain || 'mars-security'), 1, 8))::bit(32)::int % 1000000)::text, 6, '0');
  
  -- Hash the generated PIN
  pin_hash := crypt(generated_pin, gen_salt('bf'));
  
  -- Update user profile with generated PIN
  UPDATE user_profiles
  SET 
    wallet_pin_hash = pin_hash,
    updated_at = now()
  WHERE user_id = target_user_id AND wallet_pin_hash IS NULL;
  
  -- Log the PIN generation in admin backup
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    target_user_id,
    'auto_pin_generated',
    'user_security',
    jsonb_build_object(
      'str_domain', user_str_domain,
      'generated_at', now(),
      'backup_pin', generated_pin
    )
  );
  
  result := jsonb_build_object(
    'success', true,
    'user_id', target_user_id,
    'str_domain', user_str_domain,
    'generated_pin', generated_pin,
    'message', 'PIN auto-generated and encrypted successfully'
  );
  
  RETURN result;
END;
$$;

-- Create function to bulk generate PINs for users without them
CREATE OR REPLACE FUNCTION public.bulk_generate_missing_pins()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_record RECORD;
  generated_count INTEGER := 0;
  emergency_backup jsonb := '[]'::jsonb;
  pin_result jsonb;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;
  
  -- Find users without PINs and generate them
  FOR user_record IN
    SELECT user_id, str_domain_owned, full_name, email_address
    FROM user_profiles
    WHERE wallet_pin_hash IS NULL
  LOOP
    -- Generate PIN for this user
    SELECT auto_generate_user_pin(user_record.user_id) INTO pin_result;
    
    IF (pin_result->>'success')::boolean THEN
      emergency_backup := emergency_backup || jsonb_build_object(
        'user_id', user_record.user_id,
        'email', user_record.email_address,
        'full_name', user_record.full_name,
        'str_domain', user_record.str_domain_owned,
        'generated_pin', pin_result->>'generated_pin',
        'generated_at', now()
      );
      generated_count := generated_count + 1;
    END IF;
  END LOOP;
  
  -- Store emergency backup for admin access only
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'bulk_pin_generation_backup',
    'emergency_backup',
    jsonb_build_object(
      'total_generated', generated_count,
      'emergency_backup', emergency_backup,
      'generated_at', now(),
      'admin_user', auth.uid()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'total_generated', generated_count,
    'emergency_backup', emergency_backup,
    'timestamp', now()
  );
END;
$$;

-- Create function to get emergency PIN backup (admin only)
CREATE OR REPLACE FUNCTION public.get_emergency_pin_backup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  backup_data jsonb;
BEGIN
  -- Only admins can access emergency backup
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;
  
  -- Get the latest emergency backup
  SELECT details->>'emergency_backup' INTO backup_data
  FROM security_audit_log
  WHERE action = 'bulk_pin_generation_backup'
    AND resource_type = 'emergency_backup'
  ORDER BY created_at DESC
  LIMIT 1;
  
  RETURN jsonb_build_object(
    'success', true,
    'backup_data', COALESCE(backup_data, '[]'::jsonb),
    'accessed_at', now(),
    'accessed_by', auth.uid()
  );
END;
$$;

-- Create function to check if user is admin and has security issues
CREATE OR REPLACE FUNCTION public.get_admin_security_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  result jsonb;
  is_user_admin boolean;
BEGIN
  -- Check if current user is admin
  SELECT is_admin(auth.uid()) INTO is_user_admin;
  
  IF NOT is_user_admin THEN
    RETURN jsonb_build_object(
      'is_admin', false,
      'show_alerts', false,
      'message', 'Regular user - no security alerts needed'
    );
  END IF;
  
  -- Get security health summary for admin
  SELECT get_security_health_summary() INTO result;
  
  RETURN jsonb_build_object(
    'is_admin', true,
    'show_alerts', true,
    'security_data', result,
    'timestamp', now()
  );
END;
$$;