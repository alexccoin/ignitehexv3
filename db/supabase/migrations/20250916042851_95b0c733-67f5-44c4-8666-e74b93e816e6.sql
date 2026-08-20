-- Update security compliance function to make 2FA optional
CREATE OR REPLACE FUNCTION public.check_user_security_compliance(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  profile_data record;
  compliance_score integer := 0;
  issues text[] := ARRAY[]::text[];
  result jsonb;
BEGIN
  -- Get user profile
  SELECT * INTO profile_data
  FROM user_profiles
  WHERE user_id = check_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'compliant', false,
      'score', 0,
      'issues', ARRAY['no_profile']
    );
  END IF;
  
  -- Check PIN setup (50 points - now required for compliance)
  IF profile_data.wallet_pin_hash IS NOT NULL THEN
    compliance_score := compliance_score + 50;
  ELSE
    issues := array_append(issues, 'no_pin');
  END IF;
  
  -- Check 2FA setup (30 points - now optional, adds to score but not required)
  IF profile_data.two_factor_enabled = true THEN
    compliance_score := compliance_score + 30;
  END IF;
  
  -- Check recovery words encryption (20 points)
  IF profile_data.recovery_words_encrypted = true OR profile_data.wallet_recovery_words IS NULL THEN
    compliance_score := compliance_score + 20;
  ELSE
    issues := array_append(issues, 'unencrypted_recovery_words');
  END IF;
  
  -- User is compliant if they have PIN (minimum 50 points) - 2FA is now optional
  -- This means users need PIN + encrypted recovery words to be compliant
  result := jsonb_build_object(
    'compliant', compliance_score >= 70, -- PIN (50) + Recovery Words (20) = 70
    'score', compliance_score,
    'issues', issues,
    'pin_set', profile_data.wallet_pin_hash IS NOT NULL,
    'two_fa_enabled', COALESCE(profile_data.two_factor_enabled, false),
    'recovery_words_secure', COALESCE(profile_data.recovery_words_encrypted, false),
    'profile_complete', COALESCE(profile_data.wallet_setup_completed, false)
  );
  
  RETURN result;
END;
$$;