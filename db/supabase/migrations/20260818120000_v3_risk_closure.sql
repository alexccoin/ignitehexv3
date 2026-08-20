-- V3 risk closure.
--
-- Concludes the high-risk items carried over from the v1/v2 audit. Each section
-- states the exposure it closes and how it was verified.
--
-- Nothing here changes application behaviour for a caller that was already
-- using these paths legitimately: the fixes remove authority that no legitimate
-- caller needed in the first place.

-- ===========================================================================
-- 1. EP1 - close the phantom-stake mint path
-- ===========================================================================
-- public.distribute_enhanced_rewards is SECURITY DEFINER, takes an arbitrary
-- user_id_param and amount, inserts a stake with no balance check and no debit,
-- and carried PUBLIC EXECUTE (proacl "=X/postgres"). Any authenticated user -
-- and anon - could mint a staking position of any size for any account. The
-- audit attributes 1.9B+ tokens staked from nothing to this entrypoint,
-- including a single 1,000,000,000 CCOS position.
--
-- Reward distribution is a scheduled, server-side job. It never needs to be
-- reachable from a browser session.

REVOKE ALL ON FUNCTION public.distribute_enhanced_rewards(uuid, text, numeric, integer, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.distribute_enhanced_rewards(uuid, text, numeric, integer, numeric) FROM anon;
REVOKE ALL ON FUNCTION public.distribute_enhanced_rewards(uuid, text, numeric, integer, numeric) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.distribute_enhanced_rewards(uuid, text, numeric, integer, numeric) TO service_role;

-- ===========================================================================
-- 2. Debit functions must verify the caller owns the account
-- ===========================================================================
-- debit_staking_pool_balance and debit_fiat_wallet are SECURITY DEFINER and
-- accept p_user_id as a parameter, but were granted to anon and authenticated
-- with no check tying p_user_id to the caller. Any session could therefore
-- debit any other account's balance.
--
-- The row locking and atomicity in these functions is correct and is kept; only
-- the authorisation gap is closed. A caller with no JWT (auth.uid() IS NULL) is
-- a trusted server-side context - the service role or a cron job - and is still
-- allowed through, which is how the reward and settlement jobs keep working.

CREATE OR REPLACE FUNCTION public.assert_caller_owns(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No JWT: server-side context (service_role, pg_cron). Allowed.
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  IF auth.uid() = p_user_id THEN
    RETURN;
  END IF;

  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  RAISE EXCEPTION 'Not authorised to act on another account'
    USING ERRCODE = '42501';
END;
$$;

REVOKE ALL ON FUNCTION public.assert_caller_owns(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_caller_owns(uuid) TO authenticated, service_role;

-- anon has no business moving money at all.
REVOKE ALL ON FUNCTION public.debit_staking_pool_balance(uuid, text, numeric) FROM anon;
REVOKE ALL ON FUNCTION public.debit_fiat_wallet(uuid, text, numeric) FROM anon;

-- ===========================================================================
-- 3. two_factor_enabled must not be client-assertable
-- ===========================================================================
-- prevent_user_profile_security_field_writes blocks direct writes to
-- wallet_pin_hash, wallet_recovery_words, two_factor_secret and backup_codes -
-- but not two_factor_enabled. v2's MandatorySecuritySetup.tsx set that column
-- directly after merely displaying a TOTP secret, with a comment conceding the
-- code was never verified. A user could therefore mark themselves as 2FA
-- protected without ever holding a working authenticator.
--
-- The column is added to the protected set. The verified path
-- (functions.invoke('verify-totp')) runs with the service role and is
-- unaffected.

CREATE OR REPLACE FUNCTION public.prevent_user_profile_security_field_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Server-side contexts bypass: no JWT means service_role or a scheduled job.
  IF auth.uid() IS NULL OR public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.wallet_pin_hash       := OLD.wallet_pin_hash;
    NEW.wallet_recovery_words := OLD.wallet_recovery_words;
    NEW.two_factor_secret     := OLD.two_factor_secret;
    NEW.backup_codes          := OLD.backup_codes;
    -- Added: enabling 2FA is a claim about a verification that only the
    -- server can have performed.
    NEW.two_factor_enabled    := OLD.two_factor_enabled;
  END IF;

  RETURN NEW;
END;
$$;

-- ===========================================================================
-- 4. Role grants stay server-side
-- ===========================================================================
-- v2 inserted into and deleted from user_roles directly from the browser
-- (ArxRoleManager, AdminRoleAssignment). user_roles is now RLS-locked to
-- read-own-only, so those writes fail; this makes the intent explicit and
-- ensures no stray grant survives.

REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM anon, authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
