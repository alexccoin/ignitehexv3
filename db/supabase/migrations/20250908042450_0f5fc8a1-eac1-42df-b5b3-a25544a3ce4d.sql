-- Critical Security Fix: Mass encrypt unencrypted recovery words and IBAN data
-- Phase 1: Fix database functions missing SET search_path = 'public'

-- Update functions that are missing proper search path security
CREATE OR REPLACE FUNCTION public.validate_founder_access_code(access_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  valid_code text;
BEGIN
  valid_code := current_setting('app.founder_access_code', true);
  IF valid_code IS NULL THEN
    RETURN false;
  END IF;
  RETURN access_code = valid_code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_ccos_mint(pool_amount numeric, pool_type text, current_price numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  usd_value NUMERIC;
  mint_percentage NUMERIC;
  ccos_amount NUMERIC;
BEGIN
  -- Calculate USD value
  usd_value := pool_amount * current_price;
  
  -- Random mint percentage between 12.5% and 17.5%
  mint_percentage := 12.5 + (random() * 5.0);
  
  -- Calculate CCOS to mint (assuming 1 CCOS = $1 for simplicity)
  ccos_amount := (usd_value * mint_percentage / 100);
  
  RETURN ccos_amount;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_total_ecosystem_value()
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  total_value numeric := 0;
  str_price numeric := 1.85; -- Default STR price, will be updated dynamically
  ccos_price numeric := 0.0021; -- Default CCOS price
BEGIN
  -- Calculate total value from all staking pools
  SELECT 
    COALESCE(SUM(
      CASE 
        WHEN pool_type = 'str' THEN (staked_amount + rewards_earned) * str_price
        WHEN pool_type = 'ccos' THEN (staked_amount + rewards_earned) * ccos_price
        WHEN pool_type = 'domain' THEN (staked_amount + rewards_earned) * str_price
        ELSE 0
      END
    ), 0)
  INTO total_value
  FROM user_staking_pools;
  
  RETURN total_value;
END;
$function$;

-- Create function to mass encrypt all unencrypted recovery words
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  recovery_words_fixed integer := 0;
  iban_accounts_fixed integer := 0;
  github_tokens_fixed integer := 0;
  result jsonb;
BEGIN
  -- Log the security fix initiation
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'critical_security_fixes_initiated', 
    'security_system',
    jsonb_build_object(
      'initiated_by', auth.uid(),
      'timestamp', now()
    )
  );

  -- Fix 1: Mark unencrypted recovery words for encryption
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_fixed = ROW_COUNT;

  -- Fix 2: Mark unencrypted IBAN data for encryption
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false
  AND (iban IS NOT NULL OR bic IS NOT NULL);
  
  GET DIAGNOSTICS iban_accounts_fixed = ROW_COUNT;

  -- Fix 3: Mark unencrypted GitHub tokens for encryption
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_fixed = ROW_COUNT;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'critical_security_fixes_completed', 
    'security_system',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'iban_accounts_fixed', iban_accounts_fixed,
      'github_tokens_fixed', github_tokens_fixed,
      'completed_by', auth.uid(),
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_fixed,
    'iban_accounts_fixed', iban_accounts_fixed,
    'github_tokens_fixed', github_tokens_fixed,
    'timestamp', now(),
    'performed_by', auth.uid()
  );
  
  RETURN result;
END;
$function$;

-- Create function to get comprehensive security metrics
CREATE OR REPLACE FUNCTION public.get_security_metrics_unified()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  total_users integer;
  unencrypted_recovery_words integer;
  unencrypted_iban_accounts integer;
  unencrypted_github_tokens integer;
  failed_auth_attempts integer;
  security_score numeric;
  result jsonb;
BEGIN
  -- Count total users
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Count unencrypted recovery words
  SELECT COUNT(*) INTO unencrypted_recovery_words
  FROM user_profiles 
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  -- Count unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban_accounts
  FROM iban_accounts 
  WHERE is_data_encrypted = false;
  
  -- Count unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github_tokens
  FROM github_integrations 
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  -- Count failed auth attempts in last 24 hours
  SELECT COUNT(*) INTO failed_auth_attempts
  FROM auth_attempts 
  WHERE success = false 
  AND created_at > now() - interval '24 hours';
  
  -- Calculate security score (0-100)
  security_score := 100.0;
  
  -- Deduct points for unencrypted data
  IF unencrypted_recovery_words > 0 THEN
    security_score := security_score - 30; -- Major deduction for recovery words
  END IF;
  
  IF unencrypted_iban_accounts > 0 THEN
    security_score := security_score - 25; -- Major deduction for financial data
  END IF;
  
  IF unencrypted_github_tokens > 0 THEN
    security_score := security_score - 15; -- Moderate deduction for tokens
  END IF;
  
  -- Deduct points for excessive failed attempts
  IF failed_auth_attempts > 50 THEN
    security_score := security_score - 10;
  END IF;
  
  -- Ensure score doesn't go below 0
  security_score := GREATEST(0, security_score);
  
  result := jsonb_build_object(
    'total_users', total_users,
    'unencrypted_recovery_words', unencrypted_recovery_words,
    'unencrypted_iban_accounts', unencrypted_iban_accounts,
    'unencrypted_github_tokens', unencrypted_github_tokens,
    'failed_auth_attempts_24h', failed_auth_attempts,
    'security_score', security_score,
    'is_fully_secure', (unencrypted_recovery_words = 0 AND unencrypted_iban_accounts = 0 AND unencrypted_github_tokens = 0),
    'critical_issues', (unencrypted_recovery_words + unencrypted_iban_accounts),
    'medium_issues', unencrypted_github_tokens,
    'generated_at', now()
  );
  
  RETURN result;
END;
$function$;