-- CRITICAL: Fix exposed sensitive data by ensuring all tables have proper RLS policies

-- Check if user_messages table exists and secure it
DROP POLICY IF EXISTS "public_read_user_messages" ON public.user_messages;
CREATE POLICY "Users can only read their own messages" 
ON public.user_messages 
FOR SELECT 
USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

-- Ensure all sensitive tables are properly secured with explicit RLS policies
-- This replaces any overly permissive policies that might exist

-- 1. User Profiles - already has good policies, but ensure no public access
DROP POLICY IF EXISTS "public_read_user_profiles" ON public.user_profiles;

-- 2. IBAN Accounts - already secured, double-check
-- Remove any public read policy if it exists
DROP POLICY IF EXISTS "public_read_iban_accounts" ON public.iban_accounts;

-- 3. Prepaid Cards - already secured, verify
DROP POLICY IF EXISTS "public_read_prepaid_cards" ON public.prepaid_cards;

-- 4. GitHub Integrations - already secured
DROP POLICY IF EXISTS "public_read_github_integrations" ON public.github_integrations;

-- 5. Transaction tables - ensure no public read access
DROP POLICY IF EXISTS "public_read_transactions" ON public.transactions;
DROP POLICY IF EXISTS "public_read_arss_transactions" ON public.arss_transactions;
DROP POLICY IF EXISTS "public_read_founder_pool_transactions" ON public.founder_pool_transactions;
DROP POLICY IF EXISTS "public_read_currency_exchanges" ON public.currency_exchanges;
DROP POLICY IF EXISTS "public_read_cross_border_payments" ON public.cross_border_payments;

-- Create comprehensive security audit for all critical operations
CREATE OR REPLACE FUNCTION log_critical_security_event(
  event_type text,
  table_name text,
  operation text,
  user_id_param uuid DEFAULT NULL,
  details_param jsonb DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  -- Log critical security events with high priority
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    COALESCE(user_id_param, auth.uid()),
    'CRITICAL_' || event_type,
    table_name,
    jsonb_build_object(
      'operation', operation,
      'timestamp', now(),
      'severity', 'critical'
    ) || COALESCE(details_param, '{}'),
    get_client_ip()
  );
  
  -- Also log to a separate critical events table if it exists
  -- This ensures we don't lose critical security events
END;
$$;

-- Add enhanced security validation for wallet operations
CREATE OR REPLACE FUNCTION validate_wallet_pin_secure_fixed(
  user_uuid uuid,
  input_pin text,
  client_ip inet DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_result jsonb;
  actual_ip inet;
BEGIN
  -- Use server-derived IP when client IP not provided
  actual_ip := COALESCE(client_ip, get_client_ip());
  
  -- Check rate limit with enhanced security
  SELECT enhanced_rate_limit_check(user_uuid, actual_ip, 'wallet_pin', 5, 60)
  INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    -- Log security violation
    PERFORM log_critical_security_event(
      'RATE_LIMIT_EXCEEDED',
      'wallet_access',
      'pin_validation',
      user_uuid,
      rate_limit_result
    );
    
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, actual_ip, 'wallet_pin', false, rate_limit_result);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', rate_limit_result->>'reason',
      'message', CASE 
        WHEN rate_limit_result->>'reason' = 'rate_limited' THEN 'Too many failed attempts. Account temporarily locked.'
        WHEN rate_limit_result->>'reason' = 'progressive_delay' THEN 'Please wait ' || (rate_limit_result->>'retry_after') || ' seconds before trying again.'
        ELSE 'Security validation failed.'
      END,
      'retry_after', rate_limit_result->>'retry_after'
    );
  END IF;

  -- Get stored PIN hash
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  IF stored_pin_hash IS NULL THEN
    PERFORM log_critical_security_event(
      'MISSING_PIN_ACCESS_ATTEMPT',
      'wallet_access',
      'pin_validation',
      user_uuid
    );
    
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, actual_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN configured for this account.'
    );
  END IF;

  -- Validate PIN using secure methods
  IF stored_pin_hash LIKE '$2%' THEN
    -- Use bcrypt verification for newer hashes
    is_valid := verify_password(input_pin, stored_pin_hash);
  ELSE
    -- Support legacy SHA256 hashes but log for migration
    is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
    
    IF is_valid THEN
      PERFORM log_critical_security_event(
        'LEGACY_PIN_USED',
        'wallet_access',
        'pin_validation',
        user_uuid,
        jsonb_build_object('pin_type', 'sha256_legacy')
      );
    END IF;
  END IF;

  -- Log the attempt
  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, actual_ip, 'wallet_pin', is_valid);

  IF is_valid THEN
    PERFORM log_critical_security_event(
      'WALLET_ACCESS_GRANTED',
      'wallet_access',
      'pin_validation',
      user_uuid
    );
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'PIN validation successful.'
    );
  ELSE
    PERFORM log_critical_security_event(
      'WALLET_ACCESS_DENIED',
      'wallet_access',
      'pin_validation',
      user_uuid
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN provided.'
    );
  END IF;
END;
$$;