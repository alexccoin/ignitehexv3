
-- 1) Strict admin function (admin role only, excludes seed_str_admin)
CREATE OR REPLACE FUNCTION public.is_strict_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN check_user_id IS NULL THEN false
    ELSE EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = check_user_id
        AND role = 'admin'::app_role
    )
  END;
$$;

REVOKE ALL ON FUNCTION public.is_strict_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_strict_admin(uuid) TO authenticated, service_role;

-- 2) Tighten policies on highly sensitive tables to strict admin only
-- admin_recovery_backups
DROP POLICY IF EXISTS "Admins can create recovery backups" ON public.admin_recovery_backups;
DROP POLICY IF EXISTS "Admins can view all recovery backups" ON public.admin_recovery_backups;
CREATE POLICY "Strict admins can create recovery backups"
  ON public.admin_recovery_backups FOR INSERT TO authenticated
  WITH CHECK (public.is_strict_admin(auth.uid()));
CREATE POLICY "Strict admins can view all recovery backups"
  ON public.admin_recovery_backups FOR SELECT TO authenticated
  USING (public.is_strict_admin(auth.uid()));

-- backup_metadata
DROP POLICY IF EXISTS "Admin users can manage backup metadata" ON public.backup_metadata;
CREATE POLICY "Strict admins manage backup metadata"
  ON public.backup_metadata FOR ALL TO authenticated
  USING (public.is_strict_admin(auth.uid()))
  WITH CHECK (public.is_strict_admin(auth.uid()));

-- domain_wallets (private_key_encrypted)
DROP POLICY IF EXISTS "Admins can create domain wallets" ON public.domain_wallets;
DROP POLICY IF EXISTS "Admins can update domain wallets" ON public.domain_wallets;
DROP POLICY IF EXISTS "Admins can view all domain wallets" ON public.domain_wallets;
CREATE POLICY "Strict admins can create domain wallets"
  ON public.domain_wallets FOR INSERT TO authenticated
  WITH CHECK (public.is_strict_admin(auth.uid()));
CREATE POLICY "Strict admins can update domain wallets"
  ON public.domain_wallets FOR UPDATE TO authenticated
  USING (public.is_strict_admin(auth.uid()))
  WITH CHECK (public.is_strict_admin(auth.uid()));
CREATE POLICY "Strict admins can view all domain wallets"
  ON public.domain_wallets FOR SELECT TO authenticated
  USING (public.is_strict_admin(auth.uid()));

-- guardian_recovery_keys
DROP POLICY IF EXISTS "Admins can view all recovery keys" ON public.guardian_recovery_keys;
CREATE POLICY "Strict admins can view all recovery keys"
  ON public.guardian_recovery_keys FOR SELECT TO authenticated
  USING (public.is_strict_admin(auth.uid()));

-- iban_accounts (replace is_admin with strict admin)
DROP POLICY IF EXISTS "Admins can insert IBAN accounts" ON public.iban_accounts;
DROP POLICY IF EXISTS "Admins can view all IBAN accounts" ON public.iban_accounts;
DROP POLICY IF EXISTS "Strict admin manage IBAN accounts" ON public.iban_accounts;
CREATE POLICY "Strict admins manage IBAN accounts"
  ON public.iban_accounts FOR ALL TO authenticated
  USING (public.is_strict_admin(auth.uid()))
  WITH CHECK (public.is_strict_admin(auth.uid()));

-- user_wallet_security (recovery words, 2FA, PIN hashes)
DROP POLICY IF EXISTS "Wallet security - admin only management" ON public.user_wallet_security;
CREATE POLICY "Strict admins manage wallet security"
  ON public.user_wallet_security FOR ALL TO authenticated
  USING (public.is_strict_admin(auth.uid()))
  WITH CHECK (public.is_strict_admin(auth.uid()));

-- 3) user_profiles: revoke column-level SELECT/UPDATE on highly sensitive credential fields
-- so no RLS policy (admin or otherwise) can return them through PostgREST.
-- service_role keeps full access for SECURITY DEFINER / edge functions.
REVOKE SELECT (
  wallet_recovery_words,
  wallet_pin_hash,
  two_factor_secret,
  backup_codes,
  recovery_words_encrypted,
  recovery_words_iv
) ON public.user_profiles FROM authenticated, anon;

REVOKE UPDATE (
  wallet_recovery_words,
  wallet_pin_hash,
  two_factor_secret,
  backup_codes
) ON public.user_profiles FROM authenticated, anon;
