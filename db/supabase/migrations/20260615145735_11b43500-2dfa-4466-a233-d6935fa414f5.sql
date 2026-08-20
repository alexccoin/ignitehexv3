
-- Protect security-critical columns on user_profiles from being self-modified.
-- Approach: a BEFORE UPDATE trigger that resets protected fields to their OLD
-- values when the caller is not an admin (or service_role).

CREATE OR REPLACE FUNCTION public.prevent_user_profile_privilege_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin boolean := false;
  is_service boolean := false;
BEGIN
  -- Allow service_role / superuser / internal triggers to bypass.
  BEGIN
    is_service := (current_setting('request.jwt.claim.role', true) = 'service_role')
                  OR (session_user = 'postgres')
                  OR (current_user = 'postgres');
  EXCEPTION WHEN OTHERS THEN
    is_service := false;
  END;

  IF is_service THEN
    RETURN NEW;
  END IF;

  -- Check if caller is an admin via existing has_role() helper.
  BEGIN
    is_admin := public.has_role(auth.uid(), 'admin'::app_role)
                OR public.has_role(auth.uid(), 'seed_str_admin'::app_role);
  EXCEPTION WHEN OTHERS THEN
    is_admin := false;
  END;

  IF is_admin THEN
    RETURN NEW;
  END IF;

  -- Non-admin authenticated user: silently revert protected columns to OLD values.
  NEW.status              := OLD.status;
  NEW.user_status         := OLD.user_status;
  NEW.two_factor_enabled  := OLD.two_factor_enabled;
  NEW.two_factor_secret   := OLD.two_factor_secret;
  NEW.wallet_pin_hash     := OLD.wallet_pin_hash;
  NEW.wallet_recovery_words := OLD.wallet_recovery_words;
  NEW.backup_codes        := OLD.backup_codes;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_user_profile_privilege_escalation ON public.user_profiles;

CREATE TRIGGER trg_prevent_user_profile_privilege_escalation
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.prevent_user_profile_privilege_escalation();
