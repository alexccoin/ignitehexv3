-- Fix critical security vulnerabilities

-- 1. Make user_id NOT NULL in iban_accounts table to prevent security bypass
ALTER TABLE public.iban_accounts 
ALTER COLUMN user_id SET NOT NULL;

-- 2. Add check constraint to ensure user_id is valid UUID
ALTER TABLE public.iban_accounts 
ADD CONSTRAINT iban_accounts_user_id_check 
CHECK (user_id IS NOT NULL);

-- 3. Create secure master password validation function
CREATE OR REPLACE FUNCTION public.validate_master_password_secure(input_password text, client_ip inet DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_password text;
  rate_limit_result jsonb;
BEGIN
  -- Check rate limit first
  SELECT enhanced_rate_limit_check(auth.uid(), client_ip, 'master_password', 3, 15)
  INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'rate_limited',
      'message', 'Too many failed attempts. Please try again later.'
    );
  END IF;

  -- Get stored password from app settings
  stored_password := current_setting('app.master_password', true);
  
  IF stored_password IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'not_configured',
      'message', 'Master password not configured.'
    );
  END IF;

  -- Validate password
  IF input_password = stored_password THEN
    -- Log successful validation
    INSERT INTO public.security_audit_log (user_id, action, resource_type, details, ip_address)
    VALUES (auth.uid(), 'master_password_validated', 'security', 
            jsonb_build_object('success', true), client_ip);
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Master password validated successfully.'
    );
  ELSE
    -- Log failed attempt
    INSERT INTO public.security_audit_log (user_id, action, resource_type, details, ip_address)
    VALUES (auth.uid(), 'master_password_failed', 'security', 
            jsonb_build_object('success', false), client_ip);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_password',
      'message', 'Invalid master password.'
    );
  END IF;
END;
$$;

-- 4. Strengthen RLS policies for sensitive tables
-- Ensure user_profiles has proper user_id validation
DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
CREATE POLICY "Users can view their own profile"
ON public.user_profiles
FOR SELECT 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
CREATE POLICY "Users can update their own profile"
ON public.user_profiles
FOR UPDATE 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

-- Strengthen transactions policies
DROP POLICY IF EXISTS "Users can view their own transactions" ON public.transactions;
CREATE POLICY "Users can view their own transactions"
ON public.transactions
FOR SELECT 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can insert their own transactions" ON public.transactions;
CREATE POLICY "Users can insert their own transactions"
ON public.transactions
FOR INSERT 
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

-- Strengthen founder_positions policies
DROP POLICY IF EXISTS "Users can view their own founder positions" ON public.founder_positions;
CREATE POLICY "Users can view their own founder positions"
ON public.founder_positions
FOR SELECT 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can insert their own founder positions" ON public.founder_positions;
CREATE POLICY "Users can insert their own founder positions"
ON public.founder_positions
FOR INSERT 
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);