
-- Guard sensitive columns on user_profile_addendum
CREATE OR REPLACE FUNCTION public.guard_user_profile_addendum_sensitive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow service_role / SECURITY DEFINER context (no auth.uid) and admins
  IF auth.uid() IS NULL OR public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF NEW.kyc_status IS DISTINCT FROM OLD.kyc_status THEN
    RAISE EXCEPTION 'Not allowed to modify kyc_status';
  END IF;
  IF NEW.compliance_flags IS DISTINCT FROM OLD.compliance_flags THEN
    RAISE EXCEPTION 'Not allowed to modify compliance_flags';
  END IF;
  IF NEW.tax_residency_country_code IS DISTINCT FROM OLD.tax_residency_country_code THEN
    RAISE EXCEPTION 'Not allowed to modify tax_residency_country_code';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_user_profile_addendum_sensitive ON public.user_profile_addendum;
CREATE TRIGGER trg_guard_user_profile_addendum_sensitive
BEFORE UPDATE ON public.user_profile_addendum
FOR EACH ROW
EXECUTE FUNCTION public.guard_user_profile_addendum_sensitive();

-- Guard sensitive columns on user_profiles
CREATE OR REPLACE FUNCTION public.guard_user_profiles_sensitive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF NEW.two_factor_secret IS DISTINCT FROM OLD.two_factor_secret THEN
    RAISE EXCEPTION 'Not allowed to modify two_factor_secret directly';
  END IF;
  IF NEW.two_factor_enabled IS DISTINCT FROM OLD.two_factor_enabled THEN
    RAISE EXCEPTION 'Not allowed to modify two_factor_enabled directly';
  END IF;
  IF NEW.wallet_pin_hash IS DISTINCT FROM OLD.wallet_pin_hash THEN
    RAISE EXCEPTION 'Not allowed to modify wallet_pin_hash directly';
  END IF;
  IF NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words THEN
    RAISE EXCEPTION 'Not allowed to modify wallet_recovery_words directly';
  END IF;
  IF NEW.backup_codes IS DISTINCT FROM OLD.backup_codes THEN
    RAISE EXCEPTION 'Not allowed to modify backup_codes directly';
  END IF;
  IF NEW.user_status IS DISTINCT FROM OLD.user_status THEN
    RAISE EXCEPTION 'Not allowed to modify user_status';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Not allowed to modify status';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_user_profiles_sensitive ON public.user_profiles;
CREATE TRIGGER trg_guard_user_profiles_sensitive
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.guard_user_profiles_sensitive();
