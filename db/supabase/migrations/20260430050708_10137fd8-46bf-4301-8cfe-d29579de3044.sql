-- Fix privilege escalation: remove seed_str_admin from is_admin().
-- seed_str_admin is a scoped role, not a full system admin. Its legitimate
-- scoped access is already granted via dedicated has_role(...,'seed_str_admin')
-- policies on user_str_shares, seed_str_applications, seed_str_audit_log,
-- ipo_listing_requests, private_seed_str_audit_log, etc.
--
-- Including it in is_admin() previously granted it unrestricted access to
-- highly sensitive tables (user_profiles wallet_recovery_words/wallet_pin_hash/
-- two_factor_secret, domain_wallets private_key_encrypted, iban_accounts,
-- crypto_wallets, fiat_wallets, admin_recovery_backups, etc.) gated by is_admin().

CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF check_user_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = check_user_id
      AND role = 'admin'::app_role
  );
END;
$function$;

-- Dedicated scoped helper for seed_str_admin operations.
CREATE OR REPLACE FUNCTION public.is_seed_str_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF check_user_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = check_user_id
      AND role = 'seed_str_admin'::app_role
  );
END;
$function$;

-- Lock down execution: only authenticated users may call these helpers
-- (they only return information about the caller's own role context).
REVOKE EXECUTE ON FUNCTION public.is_admin(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_seed_str_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_seed_str_admin(uuid) TO authenticated, service_role;