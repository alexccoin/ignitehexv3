-- =====================================================================
-- F-034 -- the exposure sweep silently reads 9 of 108 rows.
--
-- ================================================================
-- FIRST, THE QUESTION F-034 LEFT OPEN: DOES PRODUCTION HAVE THE GAP
-- ================================================================
--
-- F-034 said: "Not established: whether production has an admin SELECT policy
-- on user_staking_pools. Settle it by running the pg_policies query against
-- production before trusting any number on /admin."
--
-- Run read-only against lhkkfrpgbkjfcrodjslf, 2026-08-19:
--
--     tablename           policyname                       cmd     qual
--     ------------------  -------------------------------  ------  ---------------------
--     user_staking_pools  Admins can view all staking      SELECT  is_admin(auth.uid())
--                           pools
--     user_staking_pools  Users can view their own         SELECT  auth.uid() = user_id
--                           staking pools
--     user_staking_pools  Admins can insert staking pools  INSERT  -
--     user_staking_pools  Admins can update all staking    UPDATE  is_admin(auth.uid())
--                           pools
--     user_staking_pools  Admins can delete staking pools  DELETE  is_admin(auth.uid())
--
-- PRODUCTION HAS THE ADMIN SELECT POLICY. The 9-of-108 short read is a
-- local-stack artefact: the recovered schema kept "Users can view their own
-- staking pools" and "Admins can delete staking pools" and lost the three
-- admin read/write policies. So production's staking figures on /admin are
-- NOT short, and F-034's worst case does not hold for that table.
--
-- ================================================================
-- BUT PRODUCTION IS SHORT ON FOUR OTHER TABLES THE SAME SWEEP READS
-- ================================================================
--
-- The same query, widened to all 30 tables buildExposureIndex and
-- runPlatformRiskScan read. Four have RLS enabled, a "view your own" SELECT
-- policy, and no admin read policy of any kind -- in PRODUCTION:
--
--     arss_token_purchases   SELECT auth.uid() = user_id                  (only)
--     crypto_orders          SELECT auth.uid() = user_id                  (only)
--                            ... and "Admins can update all orders" UPDATE
--                                is_admin(auth.uid()) -- an administrator may
--                                UPDATE rows they are not permitted to SELECT
--     user_wallets           SELECT auth.uid() = user_id                  (only)
--     withdrawal_requests    SELECT auth.uid() = user_id                  (only)
--
-- user_wallets is the ARSS balance table the exposure sweep reads for crypto
-- exposure, and withdrawal_requests is a risk-scan input. So the answer to
-- "is every figure on /admin in production also short" is: not for staking,
-- yes for those four, and nobody could tell because the sweep does not report
-- coverage. That is the actual defect, and it is the one fixed below.
--
-- Those four are NOT given admin read policies here. Two reasons. Adding a
-- policy locally that production does not have makes the local stack more
-- permissive than production, which is the failure mode F-018 records and is
-- worse than useless for testing authorisation. And widening read access to
-- four member-facing tables is a decision about who may see what, not a
-- repair -- it is recorded as a finding and left for that decision.
--
-- ================================================================
-- WHAT THIS MIGRATION DOES
-- ================================================================
--
--   1. Restores the admin SELECT policy on user_staking_pools, worded exactly
--      as production words it, so local stops being stricter than production
--      on the one table where it was.
--
--   2. Adds admin_sweep_row_counts(text[]), a SECURITY DEFINER count the
--      sweep can measure itself against. RLS returns an empty set rather than
--      an error, so an RLS-shortened read and an empty table are the same
--      observation from the client. They stop being the same observation once
--      the client can ask a question RLS does not filter.
--
-- The missing policy was never the whole defect. A sweep that cannot tell
-- "no rows" from "not allowed to see rows" would have hidden this one and
-- will hide the next one; the counts function is the part that generalises.
--
-- NOT APPLIED TO PRODUCTION.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. The policy production has and the recovered schema lost.
--
-- SELECT only. Production also carries "Admins can insert staking pools" and
-- "Admins can update all staking pools"; neither is recreated here, because
-- neither is needed to make the sweep read correctly and adding a write path
-- as a side effect of fixing a read is how privilege widens by accident.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can view all staking pools" ON public.user_staking_pools;
CREATE POLICY "Admins can view all staking pools"
  ON public.user_staking_pools
  FOR SELECT
  USING (public.is_admin(auth.uid()));


-- ---------------------------------------------------------------------
-- 2. admin_sweep_row_counts(text[]) -> (table_name, total_rows)
--
-- The authoritative row count per table, for the tables the platform sweeps.
--
-- SECURITY DEFINER, so it is not filtered by the caller's RLS -- that is the
-- entire point. Identity is re-derived from auth.uid() through is_admin; there
-- is no actor parameter. A server-side session with no JWT is admitted on the
-- F-005/F-030 shape so the sweep can also be run from psql or a worker.
--
-- The table name is never interpolated from caller input. p_tables is
-- INTERSECTED with a fixed allow-list, so an unknown name is dropped rather
-- than counted, and format('%I') quotes what survives. Passing NULL returns
-- every allow-listed table.
--
-- A count is not the data. This returns cardinality only, and only for tables
-- that already exist to be swept, so it tells an administrator how much of a
-- table they are seeing without showing them a row they could not otherwise
-- read.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_sweep_row_counts(p_tables text[] DEFAULT NULL)
RETURNS TABLE(table_name text, total_rows bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $counts$
DECLARE
  -- The union of the tables buildExposureIndex and runPlatformRiskScan read.
  -- A name not on this list is not counted, whoever asks.
  v_allowed constant text[] := ARRAY[
    'arss_token_purchases',
    'ccos_purchases',
    'cross_border_payments',
    'crypto_orders',
    'crypto_wallets',
    'currency_exchanges',
    'domain_marketplace_transactions',
    'fiat_transactions',
    'fiat_wallets',
    'guardian_wallets',
    'iban_accounts',
    'marketplace_escrow_balances',
    'prepaid_cards',
    'private_digital_shares_purchases',
    'private_seed_str_applications',
    'private_str_ipo_purchases',
    'private_str_prelisting_purchases',
    'safe_purchases',
    'seed_str_applications',
    'staking_requests',
    'starw_purchases',
    'supernode_purchases',
    'token_marketplace_listings',
    'token_transfers',
    'user_profiles',
    'user_staking_pools',
    'user_str_shares',
    'user_wallets',
    'vesting_tokens',
    'voucher_redemptions',
    'wallet_transactions',
    'withdrawal_requests'
  ];
  v_jwt_role text;
  v_login    text;
  v_server   boolean;
  v_wanted   text[];
  v_table    text;
  v_count    bigint;
BEGIN
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  -- Read into a variable rather than naming it at the start of a line, which
  -- scripts/repair-migrations.mjs rewrites (F-029 neighbourhood).
  v_login := session_user;

  v_server := v_jwt_role = 'service_role'
              OR (v_jwt_role = '' AND v_login IN ('postgres', 'supabase_admin'));

  IF NOT (v_server OR public.is_admin(auth.uid())) THEN
    RAISE EXCEPTION 'admin_sweep_row_counts is for administrators (caller jwt role %, login role %)',
      coalesce(nullif(v_jwt_role, ''), 'none'), v_login
      USING ERRCODE = '42501';
  END IF;

  IF p_tables IS NULL THEN
    v_wanted := v_allowed;
  ELSE
    SELECT array_agg(x ORDER BY x) INTO v_wanted
      FROM (SELECT DISTINCT unnest(p_tables) AS x) s
     WHERE s.x = ANY (v_allowed);
  END IF;

  IF v_wanted IS NULL THEN
    RETURN;
  END IF;

  FOREACH v_table IN ARRAY v_wanted LOOP
    -- A table on the allow-list that does not exist on this stack is skipped,
    -- not counted as zero. Zero would read as "the sweep saw everything".
    CONTINUE WHEN to_regclass('public.' || quote_ident(v_table)) IS NULL;

    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;

    table_name := v_table;
    total_rows := v_count;
    RETURN NEXT;
  END LOOP;
END
$counts$;


-- ---------------------------------------------------------------------
-- Privileges. REVOKE before GRANT: Postgres grants EXECUTE to PUBLIC at
-- creation, so without this the function is anon-callable (F-001).
--
-- authenticated is granted because the in-body is_admin(auth.uid()) is the
-- real gate and an administrator reaches this from the browser. A member who
-- calls it gets 42501 from the body.
-- ---------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.admin_sweep_row_counts(text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_sweep_row_counts(text[]) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_sweep_row_counts(text[]) IS
  'F-034: authoritative row counts for the tables /admin sweeps, so a client can tell an RLS-shortened read from an empty table. SECURITY DEFINER, gated on is_admin(auth.uid()), table names intersected with a fixed allow-list.';
