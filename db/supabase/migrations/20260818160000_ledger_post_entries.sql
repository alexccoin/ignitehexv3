-- =====================================================================
-- The double-entry ledger primitive, and the first two wrappers on it.
--
-- WHY THIS EXISTS
--
--   The database has debit_staking_pool_balance and debit_fiat_wallet and no
--   credit counterpart. Every value transfer in v3 therefore has a working
--   first half and no second half, which is worse than having neither: the
--   escrow path debits a seller's pool and nothing can put the tokens back.
--   The audit's EP1 (1.9B tokens credited from nothing) is the same asymmetry
--   seen from the other side -- a credit with no matching debit.
--
--   The answer is NOT eleven more RPCs. v2 grew 185 ad-hoc money functions and
--   they drifted apart. This is one primitive, post_entries(), that refuses to
--   commit a batch whose signed amounts do not sum to zero per asset. "Credit
--   from nothing" stops being a bug you have to remember not to write and
--   becomes a statement the database will not accept.
--
-- SHAPE
--
--   An account is (user_id, asset, bucket) where bucket is one of
--   liquid / staked / rewards / held. Amounts are signed integers in minor
--   units -- fiat at 2 decimals, tokens at 8 -- fixed per asset in
--   ledger_asset, never per column. The ledger is exact by construction and
--   never sees an IEEE-754 double.
--
--   The ledger does not replace the legacy balance stores yet, it drives them.
--   Every posting projects onto fiat_wallets / user_staking_pools so v3's
--   existing reads stay true. The first time an account is touched its opening
--   balance is read out of the legacy store and recognised against a system
--   equity account in its own journal batch -- so the ledger agrees with the
--   balances that already exist, and the recognition is itself double-entry
--   and attributable.
--
-- SECTIONS
--   1. Prerequisite: restore the unique key on user_staking_pools
--   2. Ledger tables, asset register, system accounts
--   3. Internal helpers (scale conversion, opening balance, projection)
--   4. post_entries -- the primitive
--   5. Wrappers: release_marketplace_escrow, admin_adjust_member_balance
--   6. Privileges
-- =====================================================================


-- =====================================================================
-- 1. PREREQUISITE -- restore the unique key on user_staking_pools
--
-- 20251205142711 dropped both unique constraints, leaving only the primary key
-- on id. Both named the same three columns, so "both" was one key stated
-- twice:
--
--   user_staking_pools_user_id_pool_type_stake_duration_months_key
--       -- 20250720000000:2276
--   user_staking_pools_unique_duration
--       -- 20250929154826:8, restated by 20251001055111 / 055129 / 055449
--
--   UNIQUE (user_id, pool_type, stake_duration_months)
--
-- Without it there is no ON CONFLICT target, so no idempotent upsert, so no
-- credit path that can safely be retried. It is restored under the canonical
-- name.
--
-- NULL stake_duration_months is normalised first: a UNIQUE constraint treats
-- NULLs as distinct, so leaving them would leave a hole in the key wide enough
-- to drive the original defect back through.
--
-- Two keys go in, not one, because a full replay of this history produces
-- duplicates of its own (two groups, both str/12mo, from the backfill INSERTs
-- in the migration set itself):
--
--   user_staking_pools_spot_key   UNIQUE (user_id, pool_type)
--                                 WHERE stake_duration_months = 0
--       Installed unconditionally. This is the ON CONFLICT target the ledger's
--       credit path upserts against, and it is the only one the ledger needs.
--       Duplicate TERM pools cannot block it.
--
--   ..._user_id_pool_type_stake_duration_months_key
--       UNIQUE (user_id, pool_type, stake_duration_months) -- the key
--       20251205142711 dropped. Restored when the data permits.
--
-- When duplicates block the full key the migration does NOT fail and does NOT
-- pick a winner: it writes every group, with all its rows verbatim, into
-- public.staking_pool_duplicate_backlog and raises a WARNING. Merging two
-- pools decides what happens to two apy_rate values, two lock_end_dates and
-- two rewards_earned accruals. v2's fix-user-balance made that call
-- automatically and the audit records the result as "the fixers re-seed the
-- drift they patch". A backlog row is a decision waiting for an owner; a
-- silent merge is the defect.
-- =====================================================================

-- The backlog. What cannot be decided by a migration is recorded as data, so
-- it is queryable, assignable and closable -- not a line in a replay log that
-- scrolls past. Every row here is a merge somebody has to make.
CREATE TABLE IF NOT EXISTS public.staking_pool_duplicate_backlog (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  detected_at           timestamptz NOT NULL DEFAULT now(),
  user_id               uuid    NOT NULL,
  pool_type             text    NOT NULL,
  stake_duration_months numeric,
  row_count             int     NOT NULL,
  rows                  jsonb   NOT NULL,
  blocks                text    NOT NULL,
  resolved_at           timestamptz,
  resolution            text
);

ALTER TABLE public.staking_pool_duplicate_backlog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staking_pool_duplicate_backlog_admin ON public.staking_pool_duplicate_backlog;
CREATE POLICY staking_pool_duplicate_backlog_admin
  ON public.staking_pool_duplicate_backlog FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

DO $prereq$
DECLARE
  v_nulls  bigint;
  v_groups bigint;
  v_dup0   bigint;
BEGIN
  ---------------------------------------------------------------- NULL fix
  -- A NULL duration is invisible to a UNIQUE constraint, so it is a hole in
  -- the key. Normalise to 0 (the spot pool) only where that cannot itself
  -- create a collision; anything left over is backlog, not a silent overwrite.
  WITH candidate AS (
    SELECT id,
           row_number() OVER (PARTITION BY user_id, pool_type ORDER BY created_at, id) AS rn
      FROM public.user_staking_pools p
     WHERE p.stake_duration_months IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.user_staking_pools o
                        WHERE o.user_id = p.user_id
                          AND o.pool_type = p.pool_type
                          AND o.stake_duration_months = 0)
  )
  UPDATE public.user_staking_pools u
     SET stake_duration_months = 0
    FROM candidate c
   WHERE u.id = c.id AND c.rn = 1;
  GET DIAGNOSTICS v_nulls = ROW_COUNT;
  IF v_nulls > 0 THEN
    RAISE NOTICE 'user_staking_pools: % row(s) with a NULL stake_duration_months normalised to 0 (the spot pool)', v_nulls;
  END IF;

  ------------------------------------------------------------- the backlog
  INSERT INTO public.staking_pool_duplicate_backlog
    (user_id, pool_type, stake_duration_months, row_count, rows, blocks)
  SELECT user_id, pool_type, stake_duration_months, count(*),
         jsonb_agg(to_jsonb(p) ORDER BY p.id),
         'UNIQUE (user_id, pool_type, stake_duration_months) on user_staking_pools'
    FROM public.user_staking_pools p
   GROUP BY user_id, pool_type, stake_duration_months
  HAVING count(*) > 1
     AND NOT EXISTS (
       SELECT 1 FROM public.staking_pool_duplicate_backlog b
        WHERE b.user_id = p.user_id AND b.pool_type = p.pool_type
          AND b.stake_duration_months IS NOT DISTINCT FROM p.stake_duration_months
          AND b.resolved_at IS NULL);

  SELECT count(*) INTO v_groups
    FROM public.staking_pool_duplicate_backlog WHERE resolved_at IS NULL;

  ------------------------------------------------------- the spot-pool key
  -- This one is not optional: it is the ON CONFLICT target the ledger's credit
  -- path upserts against, and without it there is no idempotent credit at all.
  -- It is narrower than the full key -- one spot pool per (user, pool_type) --
  -- so duplicate TERM pools cannot block it.
  SELECT count(*) INTO v_dup0
    FROM (SELECT 1 FROM public.user_staking_pools
           WHERE stake_duration_months = 0
           GROUP BY user_id, pool_type HAVING count(*) > 1) z;

  IF v_dup0 > 0 THEN
    RAISE EXCEPTION
      'Cannot create the spot-pool key: % (user_id, pool_type) pair(s) already hold more than one stake_duration_months = 0 row. The ledger cannot have an idempotent credit path until these are merged; see staking_pool_duplicate_backlog.', v_dup0;
  END IF;

  ------------------------------------------------------------ the full key
  IF v_groups = 0 THEN
    ALTER TABLE public.user_staking_pools
      ALTER COLUMN stake_duration_months SET NOT NULL;
    ALTER TABLE public.user_staking_pools
      DROP CONSTRAINT IF EXISTS user_staking_pools_user_id_pool_type_stake_duration_months_key;
    ALTER TABLE public.user_staking_pools
      ADD CONSTRAINT user_staking_pools_user_id_pool_type_stake_duration_months_key
      UNIQUE (user_id, pool_type, stake_duration_months);
    RAISE NOTICE 'user_staking_pools: no duplicates; full UNIQUE (user_id, pool_type, stake_duration_months) restored';
  ELSE
    -- Deliberately NOT an exception. The full key cannot be installed until a
    -- human merges these, and each merge decides what happens to two apy_rate
    -- values, two lock_end_dates and two rewards_earned accruals. A migration
    -- that picked a winner would be v2's fix-user-balance again -- the audit
    -- records that pattern as "the fixers re-seed the drift they patch". The
    -- rows are now in staking_pool_duplicate_backlog with their full contents.
    RAISE WARNING
      'user_staking_pools: full UNIQUE (user_id, pool_type, stake_duration_months) NOT restored -- % duplicate group(s) recorded in staking_pool_duplicate_backlog, each needs a merge decision. The spot-pool key the ledger requires is installed and unaffected.',
      v_groups;
  END IF;
END
$prereq$;

-- Installed unconditionally: the ledger's idempotent-credit target.
CREATE UNIQUE INDEX IF NOT EXISTS user_staking_pools_spot_key
  ON public.user_staking_pools (user_id, pool_type)
  WHERE stake_duration_months = 0;

ALTER TABLE public.user_staking_pools
  ALTER COLUMN stake_duration_months SET DEFAULT 0;

-- The way out of the backlog. Once the duplicate groups have been merged by a
-- decision and marked resolved, this installs the full key. It is safe to run
-- any number of times and it re-checks the data itself rather than trusting
-- the backlog to be accurate -- the backlog records intent, the table is the
-- fact. Without this, deferring the key would have made it permanent.
CREATE OR REPLACE FUNCTION public.ledger_restore_pool_unique_key()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $restore$
DECLARE
  v_groups bigint;
  v_nulls  bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname = 'user_staking_pools_user_id_pool_type_stake_duration_months_key'
                AND conrelid = 'public.user_staking_pools'::regclass AND contype = 'u') THEN
    RETURN 'already in place';
  END IF;

  SELECT count(*) INTO v_nulls FROM public.user_staking_pools WHERE stake_duration_months IS NULL;
  SELECT count(*) INTO v_groups FROM (
    SELECT 1 FROM public.user_staking_pools
     GROUP BY user_id, pool_type, stake_duration_months HAVING count(*) > 1) d;

  IF v_nulls > 0 OR v_groups > 0 THEN
    RETURN format(
      'not restored: %s duplicate group(s) and %s NULL-duration row(s) remain. Merge them, then call this again.',
      v_groups, v_nulls);
  END IF;

  ALTER TABLE public.user_staking_pools
    ALTER COLUMN stake_duration_months SET NOT NULL;
  ALTER TABLE public.user_staking_pools
    ADD CONSTRAINT user_staking_pools_user_id_pool_type_stake_duration_months_key
    UNIQUE (user_id, pool_type, stake_duration_months);

  RETURN 'restored: UNIQUE (user_id, pool_type, stake_duration_months)';
END
$restore$;


-- =====================================================================
-- 2. LEDGER TABLES
-- =====================================================================

-- The asset register. Scale is fixed per ASSET, not per column: the audit's
-- B7/R8 finding is 842 bare `numeric` declarations and three incompatible unit
-- conventions in code. One row here is the only place a scale is stated.
CREATE TABLE IF NOT EXISTS public.ledger_asset (
  asset        text PRIMARY KEY,
  kind         text NOT NULL CHECK (kind IN ('fiat','token')),
  scale        int  NOT NULL CHECK (scale BETWEEN 0 AND 18),
  legacy_store text NOT NULL CHECK (legacy_store IN ('fiat_wallets','user_staking_pools')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.ledger_asset (asset, kind, scale, legacy_store) VALUES
  ('EUR',        'fiat',  2, 'fiat_wallets'),
  ('USD',        'fiat',  2, 'fiat_wallets'),
  ('GBP',        'fiat',  2, 'fiat_wallets'),
  ('CHF',        'fiat',  2, 'fiat_wallets'),
  ('STR',        'token', 8, 'user_staking_pools'),
  ('CCOS',       'token', 8, 'user_staking_pools'),
  ('DOMAIN',     'token', 8, 'user_staking_pools'),
  ('ARSS',       'token', 8, 'user_staking_pools'),
  ('WSTR',       'token', 8, 'user_staking_pools'),
  ('ESTR',       'token', 8, 'user_staking_pools'),
  ('STR_STABLE', 'token', 8, 'user_staking_pools')
ON CONFLICT (asset) DO NOTHING;

-- Named platform accounts. Every one of these may go negative, and that is the
-- point: a negative system account is a visible, reconcilable statement that
-- value entered or left the member side. It is the opposite of a silent mint.
--
-- The AUTHORITY for this mapping is the two functions below, not the table.
-- The table carries the human-readable description and nothing load-bearing,
-- because scripts/seed-local.mjs --reset truncates every table in public that
-- has a user_id column -- this one included. If the mapping lived only here, a
-- reseed would silently reclassify the treasury as a member account.
CREATE TABLE IF NOT EXISTS public.ledger_system (
  code        text PRIMARY KEY,
  user_id     uuid NOT NULL UNIQUE,
  description text NOT NULL
);

INSERT INTO public.ledger_system (code, user_id, description) VALUES
  ('opening_equity',     '00000000-0000-0000-0000-00000000e001',
   'Counterparty for balances recognised out of the legacy stores when an account is first opened'),
  ('treasury',           '00000000-0000-0000-0000-00000000e002',
   'Platform treasury: the funding side of any operator credit to a member'),
  ('corrections',        '00000000-0000-0000-0000-00000000e003',
   'Counterparty for operator corrections and write-offs, so a correction can never be a mint'),
  ('marketplace_escrow', '00000000-0000-0000-0000-00000000e004',
   'Platform escrow control account for marketplace listings')
ON CONFLICT (code) DO NOTHING;

-- The mapping, as code. Truncating a table cannot change what these return.
CREATE OR REPLACE FUNCTION public.ledger_system_user(p_code text)
RETURNS uuid LANGUAGE sql IMMUTABLE AS $sysu$
  SELECT CASE lower(btrim(p_code))
           WHEN 'opening_equity'     THEN '00000000-0000-0000-0000-00000000e001'
           WHEN 'treasury'           THEN '00000000-0000-0000-0000-00000000e002'
           WHEN 'corrections'        THEN '00000000-0000-0000-0000-00000000e003'
           WHEN 'marketplace_escrow' THEN '00000000-0000-0000-0000-00000000e004'
         END::uuid
$sysu$;

CREATE OR REPLACE FUNCTION public.ledger_is_system(p_user_id uuid)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $syst$
  SELECT p_user_id IN ('00000000-0000-0000-0000-00000000e001'::uuid,
                       '00000000-0000-0000-0000-00000000e002'::uuid,
                       '00000000-0000-0000-0000-00000000e003'::uuid,
                       '00000000-0000-0000-0000-00000000e004'::uuid)
$syst$;

-- One row per (user, asset, bucket). This is the ledger's own balance; the
-- legacy stores are projections of it from here on.
CREATE TABLE IF NOT EXISTS public.ledger_account (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid    NOT NULL,
  asset          text    NOT NULL REFERENCES public.ledger_asset(asset),
  bucket         text    NOT NULL CHECK (bucket IN ('liquid','staked','rewards','held')),
  balance        bigint  NOT NULL DEFAULT 0,
  allow_negative boolean NOT NULL DEFAULT false,
  opened_at      timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ledger_account_unique UNIQUE (user_id, asset, bucket),
  CONSTRAINT ledger_account_sign   CHECK (allow_negative OR balance >= 0)
);

CREATE INDEX IF NOT EXISTS idx_ledger_account_user ON public.ledger_account (user_id);

-- One immutable row per batch. `reference` is the idempotency key: posting the
-- same reference twice is a no-op, not a double credit. v2's airdrop path had
-- no such key and credited twice on retry.
CREATE TABLE IF NOT EXISTS public.ledger_journal (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference   text NOT NULL,
  reason      text NOT NULL,
  posted_by   uuid,
  posted_role text NOT NULL,
  entry_count int  NOT NULL,
  posted_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ledger_journal_reference_key UNIQUE (reference)
);

-- One immutable row per leg, carrying the balance the account reached.
CREATE TABLE IF NOT EXISTS public.ledger_entry (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_id    uuid   NOT NULL REFERENCES public.ledger_journal(id) ON DELETE RESTRICT,
  account_id    uuid   NOT NULL REFERENCES public.ledger_account(id) ON DELETE RESTRICT,
  asset         text   NOT NULL REFERENCES public.ledger_asset(asset),
  amount        bigint NOT NULL CHECK (amount <> 0),
  balance_after bigint NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ledger_entry_journal ON public.ledger_entry (journal_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entry_account ON public.ledger_entry (account_id, created_at DESC);

-- Immutability is enforced by the database, not by convention. An audit trail
-- a later UPDATE can rewrite is not an audit trail.
CREATE OR REPLACE FUNCTION public.ledger_reject_mutation()
RETURNS trigger LANGUAGE plpgsql AS $reject$
BEGIN
  RAISE EXCEPTION '% is append-only; % is not permitted', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END
$reject$;

DROP TRIGGER IF EXISTS ledger_journal_immutable ON public.ledger_journal;
CREATE TRIGGER ledger_journal_immutable
  BEFORE UPDATE OR DELETE ON public.ledger_journal
  FOR EACH ROW EXECUTE FUNCTION public.ledger_reject_mutation();

DROP TRIGGER IF EXISTS ledger_entry_immutable ON public.ledger_entry;
CREATE TRIGGER ledger_entry_immutable
  BEFORE UPDATE OR DELETE ON public.ledger_entry
  FOR EACH ROW EXECUTE FUNCTION public.ledger_reject_mutation();

-- RLS, not GRANT, is the boundary on these tables.
--
-- rebuild-local.mjs ends with GRANT ALL ON ALL TABLES IN SCHEMA public TO
-- anon, authenticated, service_role, which overwrites any table-level REVOKE a
-- migration performs. The REVOKEs in section 6 are still stated (they are
-- correct against production, where nothing sweeps them away), but the
-- load-bearing control is that no INSERT/UPDATE/DELETE policy exists on any
-- ledger table. A SECURITY DEFINER function owned by the table owner bypasses
-- RLS; nothing else can write here at all.
ALTER TABLE public.ledger_asset   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_system  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_account ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entry   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ledger_asset_read    ON public.ledger_asset;
DROP POLICY IF EXISTS ledger_system_read   ON public.ledger_system;
DROP POLICY IF EXISTS ledger_account_own   ON public.ledger_account;
DROP POLICY IF EXISTS ledger_account_admin ON public.ledger_account;
DROP POLICY IF EXISTS ledger_journal_admin ON public.ledger_journal;
DROP POLICY IF EXISTS ledger_entry_own     ON public.ledger_entry;
DROP POLICY IF EXISTS ledger_entry_admin   ON public.ledger_entry;

CREATE POLICY ledger_asset_read    ON public.ledger_asset   FOR SELECT TO authenticated USING (true);
CREATE POLICY ledger_system_read   ON public.ledger_system  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY ledger_account_own   ON public.ledger_account FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY ledger_account_admin ON public.ledger_account FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY ledger_journal_admin ON public.ledger_journal FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY ledger_entry_own     ON public.ledger_entry   FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.ledger_account a
                  WHERE a.id = ledger_entry.account_id AND a.user_id = auth.uid()));
CREATE POLICY ledger_entry_admin   ON public.ledger_entry   FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

DO $legs$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                  WHERE n.nspname = 'public' AND t.typname = 'ledger_leg') THEN
    CREATE TYPE public.ledger_leg AS (user_id uuid, asset text, bucket text, amount bigint);
  END IF;
END
$legs$;


-- =====================================================================
-- 3. INTERNAL HELPERS
--
-- None of these are callable by anyone, including service_role. post_entries
-- and the wrappers reach them because a SECURITY DEFINER function runs as its
-- owner, and the owner owns these too.
-- =====================================================================

-- numeric (legacy store) -> bigint minor units. Fails closed on anything that
-- does not fit the asset's scale exactly. It never rounds: a rounded credit
-- mints or burns the remainder, and the audit has enough of both.
CREATE OR REPLACE FUNCTION public.ledger_minor(p_asset text, p_amount numeric)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $minor$
DECLARE
  v_scale int;
  v_shift numeric;
BEGIN
  SELECT scale INTO v_scale FROM public.ledger_asset WHERE asset = upper(p_asset);
  IF v_scale IS NULL THEN
    RAISE EXCEPTION 'Unknown ledger asset %', p_asset USING ERRCODE = '22023';
  END IF;
  v_shift := coalesce(p_amount, 0) * power(10::numeric, v_scale);
  IF v_shift <> trunc(v_shift) THEN
    RAISE EXCEPTION 'Amount % of % carries more precision than the asset scale (%) permits',
      p_amount, upper(p_asset), v_scale USING ERRCODE = '22003';
  END IF;
  RETURN v_shift::bigint;
END
$minor$;

-- bigint minor units -> numeric for the legacy store. Exact: numeric is exact.
CREATE OR REPLACE FUNCTION public.ledger_major(p_asset text, p_minor bigint)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $major$
DECLARE v_scale int;
BEGIN
  SELECT scale INTO v_scale FROM public.ledger_asset WHERE asset = upper(p_asset);
  IF v_scale IS NULL THEN
    RAISE EXCEPTION 'Unknown ledger asset %', p_asset USING ERRCODE = '22023';
  END IF;
  -- trim_scale keeps the trailing zeros of the division out of the legacy
  -- numeric columns. The value is unchanged; numeric is exact either way.
  RETURN trim_scale(coalesce(p_minor, 0)::numeric / power(10::numeric, v_scale));
END
$major$;

-- What the legacy store already says this account holds, in minor units. Read
-- exactly once, when the account is first opened.
CREATE OR REPLACE FUNCTION public.ledger_opening_balance(p_user_id uuid, p_asset text, p_bucket text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $open$
DECLARE
  v_kind  text;
  v_asset text := upper(p_asset);
  v_major numeric := 0;
BEGIN
  SELECT kind INTO v_kind FROM public.ledger_asset WHERE asset = v_asset;

  IF v_kind = 'fiat' THEN
    SELECT CASE p_bucket WHEN 'liquid' THEN available_balance
                         WHEN 'held'   THEN held_balance END
      INTO v_major
      FROM public.fiat_wallets
     WHERE user_id = p_user_id AND currency = v_asset;

  ELSIF p_bucket = 'held' THEN
    -- Token escrow has never lived in a pool column; it lives as locked rows
    -- in marketplace_escrow_balances. That total is the opening balance.
    SELECT sum(amount) INTO v_major
      FROM public.marketplace_escrow_balances
     WHERE user_id = p_user_id
       AND upper(asset_symbol) = v_asset
       AND status = 'locked';

  ELSE
    SELECT CASE p_bucket WHEN 'liquid'  THEN sum(balance)
                         WHEN 'staked'  THEN sum(staked_amount)
                         WHEN 'rewards' THEN sum(rewards_earned) END
      INTO v_major
      FROM public.user_staking_pools
     WHERE user_id = p_user_id AND pool_type = lower(v_asset);
  END IF;

  RETURN public.ledger_minor(v_asset, coalesce(v_major, 0));
END
$open$;

-- Push a signed minor-unit delta out to the legacy store v3 reads.
--
-- The token side is asymmetric, deliberately, and it has to be: a ledger
-- account is one balance per (user, asset, bucket), while user_staking_pools
-- spreads the same holding over one row per lock duration. The ledger account
-- opens at the SUM across those rows, so the projection must be able to reach
-- all of them:
--   credit -> the canonical spot pool (stake_duration_months = 0), created on
--             demand through the unique key restored in section 1;
--   debit  -> drained across the member's pools of that type, shortest lock
--             first, so a debit reaches tokens legacy paths parked in a term
--             pool instead of failing against an empty spot pool.
-- A credit followed by a debit of the same amount is therefore exact, and a
-- debit the ledger says is affordable is always affordable in the legacy
-- store too.
CREATE OR REPLACE FUNCTION public.ledger_apply_projection(
  p_user_id uuid, p_asset text, p_bucket text, p_delta_minor bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $proj$
DECLARE
  v_asset     text := upper(p_asset);
  v_kind      text;
  v_col       text;
  v_delta     numeric;
  v_remaining numeric;
  v_take      numeric;
  v_pool_id   uuid;
  v_wallet_id uuid;
  v_avail     numeric;
  v_held      numeric;
  r           record;
BEGIN
  IF p_delta_minor = 0 THEN RETURN; END IF;

  -- System accounts have no legacy store. They exist only in the ledger.
  IF public.ledger_is_system(p_user_id) THEN
    RETURN;
  END IF;

  SELECT kind INTO v_kind FROM public.ledger_asset WHERE asset = v_asset;
  v_delta := public.ledger_major(v_asset, p_delta_minor);

  ------------------------------------------------------------------ fiat
  IF v_kind = 'fiat' THEN
    INSERT INTO public.fiat_wallets (user_id, currency, balance, available_balance, held_balance)
    VALUES (p_user_id, v_asset, 0, 0, 0)
    ON CONFLICT (user_id, currency) DO NOTHING;

    SELECT id INTO v_wallet_id FROM public.fiat_wallets
     WHERE user_id = p_user_id AND currency = v_asset FOR UPDATE;

    IF p_bucket = 'liquid' THEN
      UPDATE public.fiat_wallets
         SET available_balance = available_balance + v_delta,
             balance           = available_balance + v_delta + held_balance,
             updated_at        = now()
       WHERE id = v_wallet_id
      RETURNING available_balance, held_balance INTO v_avail, v_held;

    ELSIF p_bucket = 'held' THEN
      UPDATE public.fiat_wallets
         SET held_balance = held_balance + v_delta,
             balance      = available_balance + held_balance + v_delta,
             updated_at   = now()
       WHERE id = v_wallet_id
      RETURNING available_balance, held_balance INTO v_avail, v_held;

    ELSE
      RAISE EXCEPTION 'Bucket % is not defined for the fiat asset %', p_bucket, v_asset
        USING ERRCODE = '22023';
    END IF;

    IF v_avail < 0 OR v_held < 0 THEN
      RAISE EXCEPTION 'fiat_wallets for % % would go negative (available=%, held=%)',
        p_user_id, v_asset, v_avail, v_held USING ERRCODE = '23514';
    END IF;
    RETURN;
  END IF;

  ------------------------------------------------------------ token held
  -- Escrow is a row in marketplace_escrow_balances, not a pool column. The
  -- ledger carries the balance; the wrapper that releases it flips the row.
  IF p_bucket = 'held' THEN
    RETURN;
  END IF;

  ------------------------------------------------------------ token pools
  -- The column is chosen from a closed set, never from caller input.
  v_col := CASE p_bucket WHEN 'liquid'  THEN 'balance'
                         WHEN 'staked'  THEN 'staked_amount'
                         WHEN 'rewards' THEN 'rewards_earned' END;

  ------------------------------------------------------- token, debit
  IF v_delta < 0 THEN
    v_remaining := -v_delta;
    FOR r IN EXECUTE format(
      'SELECT id, coalesce(%1$I, 0) AS amt
         FROM public.user_staking_pools
        WHERE user_id = $1 AND pool_type = $2 AND coalesce(%1$I, 0) > 0
        ORDER BY stake_duration_months, created_at, id
        FOR UPDATE', v_col)
      USING p_user_id, lower(v_asset)
    LOOP
      v_take := least(v_remaining, r.amt);
      EXECUTE format(
        'UPDATE public.user_staking_pools SET %1$I = %1$I - $1, updated_at = now() WHERE id = $2', v_col)
        USING v_take, r.id;
      v_remaining := v_remaining - v_take;
      EXIT WHEN v_remaining <= 0;
    END LOOP;

    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'user_staking_pools.% is % short of the % % debit for %',
        v_col, v_remaining, -v_delta, v_asset, p_user_id USING ERRCODE = '23514';
    END IF;
    RETURN;
  END IF;

  ------------------------------------------------------ token, credit
  -- Credits land on the canonical spot pool. This is the ON CONFLICT target
  -- the restored unique key exists to provide.
  INSERT INTO public.user_staking_pools
    (user_id, pool_type, stake_duration_months, balance, staked_amount, rewards_earned, status, apy_rate)
  VALUES (p_user_id, lower(v_asset), 0, 0, 0, 0, 'active', 0)
  ON CONFLICT (user_id, pool_type) WHERE stake_duration_months = 0 DO NOTHING;

  SELECT id INTO v_pool_id
    FROM public.user_staking_pools
   WHERE user_id = p_user_id AND pool_type = lower(v_asset) AND stake_duration_months = 0
   FOR UPDATE;

  EXECUTE format(
    'UPDATE public.user_staking_pools SET %1$I = coalesce(%1$I, 0) + $1, updated_at = now() WHERE id = $2', v_col)
    USING v_delta, v_pool_id;
END
$proj$;

-- Find or open a ledger account. Opening one recognises whatever the legacy
-- store already holds, as its own balanced journal batch against
-- opening_equity, so the ledger agrees with reality from its first posting and
-- the recognition is itself attributable.
CREATE OR REPLACE FUNCTION public.ledger_resolve_account(p_user_id uuid, p_asset text, p_bucket text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $resolve$
DECLARE
  v_asset    text := upper(btrim(p_asset));
  v_kind     text;
  v_id       uuid;
  v_equity   uuid;
  v_system   boolean;
  v_opening  bigint := 0;
  v_journal  uuid;
  v_eq_after bigint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Every entry must name a user_id' USING ERRCODE = '22023';
  END IF;

  SELECT kind INTO v_kind FROM public.ledger_asset WHERE asset = v_asset;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Unknown ledger asset %', p_asset USING ERRCODE = '22023';
  END IF;
  IF p_bucket NOT IN ('liquid','staked','rewards','held') THEN
    RAISE EXCEPTION 'Unknown bucket % (expected liquid, staked, rewards or held)', p_bucket
      USING ERRCODE = '22023';
  END IF;
  IF v_kind = 'fiat' AND p_bucket IN ('staked','rewards') THEN
    RAISE EXCEPTION 'Bucket % is not defined for the fiat asset %', p_bucket, v_asset
      USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_id FROM public.ledger_account
   WHERE user_id = p_user_id AND asset = v_asset AND bucket = p_bucket;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  v_system := public.ledger_is_system(p_user_id);
  IF NOT v_system THEN
    v_opening := public.ledger_opening_balance(p_user_id, v_asset, p_bucket);
  END IF;

  INSERT INTO public.ledger_account (user_id, asset, bucket, balance, allow_negative)
  VALUES (p_user_id, v_asset, p_bucket, 0, v_system)
  ON CONFLICT ON CONSTRAINT ledger_account_unique DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    -- Lost the race; the winner's opening balance stands.
    SELECT id INTO v_id FROM public.ledger_account
     WHERE user_id = p_user_id AND asset = v_asset AND bucket = p_bucket;
    RETURN v_id;
  END IF;

  IF v_opening <> 0 THEN
    -- opening_equity is a system account, so this call cannot recurse further.
    v_equity := public.ledger_resolve_account(
      public.ledger_system_user('opening_equity'), v_asset, p_bucket);

    INSERT INTO public.ledger_journal (reference, reason, posted_by, posted_role, entry_count)
    VALUES ('opening:' || v_id::text,
            format('Opening balance for %s/%s recognised from the legacy store', v_asset, p_bucket),
            auth.uid(), session_user, 2)
    RETURNING id INTO v_journal;

    UPDATE public.ledger_account SET balance = balance + v_opening, updated_at = now()
     WHERE id = v_id;
    UPDATE public.ledger_account SET balance = balance - v_opening, updated_at = now()
     WHERE id = v_equity
    RETURNING balance INTO v_eq_after;

    INSERT INTO public.ledger_entry (journal_id, account_id, asset, amount, balance_after) VALUES
      (v_journal, v_id,     v_asset,  v_opening, v_opening),
      (v_journal, v_equity, v_asset, -v_opening, v_eq_after);
  END IF;

  RETURN v_id;
END
$resolve$;


-- =====================================================================
-- 4. post_entries -- THE PRIMITIVE
--
--   post_entries(p_entries jsonb, p_reference text, p_reason text) -> jsonb
--
-- p_entries is an array of legs, each naming nothing but an account and a
-- signed amount:
--
--   [ {"user_id":"<uuid>","asset":"STR","bucket":"liquid","amount":"-500000000"},
--     {"user_id":"<uuid>","asset":"STR","bucket":"held",  "amount": "500000000"} ]
--
-- amount is an integer in the asset's minor units. Non-integral amounts are
-- rejected, not rounded.
--
-- Invariants, in the order they are enforced:
--   1. The caller is service_role (or the owner, which is how the SECURITY
--      DEFINER wrappers reach it). A member cannot post entries.
--   2. p_reference is unique. A second post of the same reference returns the
--      first journal and changes nothing.
--   3. Signed amounts sum to zero PER ASSET. This is the whole defence: a
--      credit with no matching debit is not a bug to be caught in review, it
--      is a batch the database refuses.
--   4. Accounts are locked FOR UPDATE in ascending id order -- the same
--      deterministic-lock discipline as debit_staking_pool_balance.
--   5. No member account may go negative. Only named system accounts may.
--   6. One journal row per batch, one entry row per leg, both immutable.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.post_entries(p_entries jsonb, p_reference text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $post$
DECLARE
  v_ref       text := btrim(coalesce(p_reference, ''));
  v_journal   uuid;
  v_existing  uuid;
  v_legs      public.ledger_leg[];
  v_ids       uuid[] := '{}';
  v_leg       public.ledger_leg;
  v_bad       text;
  v_before    bigint;
  v_after     bigint;
  v_neg       boolean;
  v_out       jsonb := '[]'::jsonb;
  i           int;
  v_jwt_role  text;
  v_delegated boolean;
BEGIN
  -- (1) Not member-callable.
  --
  -- The EXECUTE grant in section 6 is the primary control and it is sufficient.
  -- This is the second lock, because rebuild-local.mjs has swept revoked
  -- functions back open before now and a re-granted post_entries would be the
  -- worst possible thing to hand a browser.
  --
  -- Note what CANNOT be used here: `current_user` is the OWNER inside a
  -- SECURITY DEFINER function, so it reads 'postgres' no matter who called.
  -- What survives is the JWT role PostgREST puts in the GUC, and the login
  -- role, which is 'authenticator' for every browser session and 'postgres' or
  -- 'service_role' for a server one.
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  -- A wrapper marks its own delegation, transaction-locally and single-use.
  v_delegated := coalesce(current_setting('ignitehex.ledger_delegated', true), 'off') = 'on';
  PERFORM set_config('ignitehex.ledger_delegated', 'off', true);

  IF NOT v_delegated
     AND ( v_jwt_role NOT IN ('', 'service_role')
        OR session_user NOT IN ('postgres', 'supabase_admin', 'service_role') ) THEN
    RAISE EXCEPTION 'post_entries is a service-role primitive (caller jwt role %, login role %). Member operations must go through a wrapper that asserts identity.',
      coalesce(nullif(v_jwt_role, ''), 'none'), session_user
      USING ERRCODE = '42501';
  END IF;

  IF v_ref = '' THEN
    RAISE EXCEPTION 'p_reference is required: it is the idempotency key' USING ERRCODE = '22023';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'p_reason is required: every balance change must be attributable' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) < 2 THEN
    RAISE EXCEPTION 'p_entries must be an array of at least two legs' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) e
     WHERE e->>'user_id' IS NULL OR e->>'asset' IS NULL
        OR e->>'bucket'  IS NULL OR e->>'amount' IS NULL
  ) THEN
    RAISE EXCEPTION 'Every entry needs user_id, asset, bucket and amount' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) e
     WHERE (e->>'amount')::numeric <> trunc((e->>'amount')::numeric)
  ) THEN
    RAISE EXCEPTION 'Amounts are integers in the asset''s minor units; a fractional amount would have to be rounded, and a rounded credit is a mint'
      USING ERRCODE = '22003';
  END IF;

  -- (2) Idempotency. ON CONFLICT DO NOTHING also serialises two concurrent
  -- posts of the same reference: the loser blocks, then sees zero rows.
  INSERT INTO public.ledger_journal (reference, reason, posted_by, posted_role, entry_count)
  VALUES (v_ref, btrim(p_reason), auth.uid(), session_user, jsonb_array_length(p_entries))
  ON CONFLICT ON CONSTRAINT ledger_journal_reference_key DO NOTHING
  RETURNING id INTO v_journal;

  IF v_journal IS NULL THEN
    SELECT id INTO v_existing FROM public.ledger_journal WHERE reference = v_ref;
    RETURN jsonb_build_object(
      'applied',   false,
      'idempotent', true,
      'reference', v_ref,
      'journal_id', v_existing,
      'note', 'This reference has already been posted; nothing was changed.');
  END IF;

  -- (3) Zero-sum per asset.
  SELECT string_agg(format('%s=%s', asset, net), ', ' ORDER BY asset) INTO v_bad
    FROM (
      SELECT upper(btrim(e->>'asset')) AS asset, sum((e->>'amount')::bigint) AS net
        FROM jsonb_array_elements(p_entries) e
       GROUP BY 1
      HAVING sum((e->>'amount')::bigint) <> 0
    ) x;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Unbalanced batch rejected: signed amounts must sum to zero per asset, but the net residual is [%]. Every credit needs a named account the value came out of.', v_bad
      USING ERRCODE = '23514';
  END IF;

  -- Net the legs per account so each account is locked and written once.
  SELECT array_agg(ROW(user_id, asset, bucket, amount)::public.ledger_leg
                   ORDER BY user_id, asset, bucket)
    INTO v_legs
    FROM (
      SELECT (e->>'user_id')::uuid       AS user_id,
             upper(btrim(e->>'asset'))   AS asset,
             lower(btrim(e->>'bucket'))  AS bucket,
             sum((e->>'amount')::bigint) AS amount
        FROM jsonb_array_elements(p_entries) e
       GROUP BY 1, 2, 3
      HAVING sum((e->>'amount')::bigint) <> 0
    ) s;

  IF v_legs IS NULL OR array_length(v_legs, 1) IS NULL THEN
    RAISE EXCEPTION 'Batch has no net effect: every leg cancels against another on the same account'
      USING ERRCODE = '22023';
  END IF;

  -- Resolve accounts in the same deterministic order the legs are sorted in.
  FOREACH v_leg IN ARRAY v_legs LOOP
    v_ids := v_ids || public.ledger_resolve_account(v_leg.user_id, v_leg.asset, v_leg.bucket);
  END LOOP;

  -- (4) Lock every touched account, ascending id. Two batches over the same
  -- accounts therefore always take them in the same order.
  PERFORM 1 FROM public.ledger_account
   WHERE id = ANY (v_ids) ORDER BY id FOR UPDATE;

  -- (5)+(6) Guard the sign under the lock, apply, project, record.
  FOR i IN 1 .. array_length(v_legs, 1) LOOP
    v_leg := v_legs[i];

    SELECT balance, allow_negative INTO v_before, v_neg
      FROM public.ledger_account WHERE id = v_ids[i];

    IF v_before + v_leg.amount < 0 AND NOT v_neg THEN
      RAISE EXCEPTION 'Insufficient balance: %/%/% holds % minor units and the batch would take it to %',
        v_leg.user_id, v_leg.asset, v_leg.bucket, v_before, v_before + v_leg.amount
        USING ERRCODE = '23514';
    END IF;

    UPDATE public.ledger_account
       SET balance = balance + v_leg.amount, updated_at = now()
     WHERE id = v_ids[i]
    RETURNING balance INTO v_after;

    PERFORM public.ledger_apply_projection(v_leg.user_id, v_leg.asset, v_leg.bucket, v_leg.amount);

    INSERT INTO public.ledger_entry (journal_id, account_id, asset, amount, balance_after)
    VALUES (v_journal, v_ids[i], v_leg.asset, v_leg.amount, v_after);

    v_out := v_out || jsonb_build_object(
      'user_id', v_leg.user_id, 'asset', v_leg.asset, 'bucket', v_leg.bucket,
      'amount', v_leg.amount, 'balance_after', v_after,
      'balance_after_major', public.ledger_major(v_leg.asset, v_after));
  END LOOP;

  RETURN jsonb_build_object(
    'applied',   true,
    'idempotent', false,
    'reference', v_ref,
    'journal_id', v_journal,
    'entries',   v_out);
END
$post$;


-- =====================================================================
-- 5. WRAPPERS
--
-- Thin by design. A wrapper decides WHO may act and WHAT the legs are; it
-- never touches a balance column itself. Everything that moves money goes
-- through post_entries, so the zero-sum rule cannot be routed around.
-- =====================================================================

-- release_marketplace_escrow(p_listing_id uuid) -> jsonb
--
-- The v2 defect this closes: the sell path debits the seller's pool through
-- debit_staking_pool_balance and writes a locked escrow row, and there is no
-- credit counterpart -- so cancelling a listing released the escrow row while
-- the tokens stayed gone. v3's Sell.tsx:320-330 says so in as many words and
-- disables the control.
--
-- Here both legs are one statement: the member's held balance falls and their
-- liquid balance rises by the same amount, and the escrow row is only marked
-- released inside the same transaction that posted them.
CREATE OR REPLACE FUNCTION public.release_marketplace_escrow(p_listing_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $rel$
DECLARE
  v_listing record;
  r         record;
  v_entries jsonb := '[]'::jsonb;
  v_minor   bigint;
  v_count   int := 0;
  v_result  jsonb;
BEGIN
  IF p_listing_id IS NULL THEN
    RAISE EXCEPTION 'p_listing_id is required' USING ERRCODE = '22023';
  END IF;

  SELECT id, seller_id, status INTO v_listing
    FROM public.token_marketplace_listings
   WHERE id = p_listing_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % does not exist', p_listing_id USING ERRCODE = '22023';
  END IF;

  -- Identity is re-derived here, from the row, against auth.uid(). Nothing the
  -- caller sent is trusted to say whose escrow this is.
  PERFORM public.assert_caller_owns(v_listing.seller_id);

  FOR r IN
    SELECT id, user_id, upper(asset_symbol) AS asset, amount
      FROM public.marketplace_escrow_balances
     WHERE listing_id = p_listing_id AND status = 'locked'
     ORDER BY id
     FOR UPDATE
  LOOP
    v_minor := public.ledger_minor(r.asset, r.amount);
    v_entries := v_entries
      || jsonb_build_object('user_id', r.user_id, 'asset', r.asset,
                            'bucket', 'held',   'amount', (-v_minor)::text)
      || jsonb_build_object('user_id', r.user_id, 'asset', r.asset,
                            'bucket', 'liquid', 'amount', ( v_minor)::text);
    v_count := v_count + 1;
  END LOOP;

  IF v_count = 0 THEN
    RETURN jsonb_build_object('released', false, 'listing_id', p_listing_id,
                              'reason', 'No locked escrow rows for this listing.');
  END IF;

  -- Delegation marker: this wrapper has asserted identity, so the primitive
  -- may accept the batch even though the session belongs to a member. It is
  -- transaction-local and post_entries consumes it on entry.
  PERFORM set_config('ignitehex.ledger_delegated', 'on', true);

  v_result := public.post_entries(
    v_entries,
    'escrow_release:' || p_listing_id::text,
    format('Marketplace escrow released for listing %s', p_listing_id));

  IF (v_result->>'applied')::boolean THEN
    UPDATE public.marketplace_escrow_balances
       SET status = 'released', released_at = now()
     WHERE listing_id = p_listing_id AND status = 'locked';

    UPDATE public.token_marketplace_listings
       SET status = 'cancelled', updated_at = now()
     WHERE id = p_listing_id
       AND status IN ('active','pending_escrow','escrow_error','reserved');
  END IF;

  RETURN jsonb_build_object('released', (v_result->>'applied')::boolean,
                            'listing_id', p_listing_id,
                            'posting', v_result);
END
$rel$;


-- admin_adjust_member_balance(...) -> jsonb
--
-- The credit path. Group A's "credit or adjust a member balance"
-- (banking/Admin.tsx:465), and the direct answer to the audit's EP1: an
-- operator cannot credit an account without naming the platform account the
-- value came out of. The counterparty is neither optional nor defaulted.
--
-- p_amount_minor is signed: positive credits the member, negative debits them.
CREATE OR REPLACE FUNCTION public.admin_adjust_member_balance(
  p_user_id      uuid,
  p_asset        text,
  p_bucket       text,
  p_amount_minor bigint,
  p_counterparty text,
  p_reference    text,
  p_reason       text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $adj$
DECLARE
  v_actor uuid := auth.uid();
  v_cp    uuid;
  v_code  text := lower(btrim(coalesce(p_counterparty, '')));
BEGIN
  -- Identity re-derived from the token. There is no admin_user_id parameter to
  -- forge, which is the defect the audit records in v2's approval routines.
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may adjust a member balance'
      USING ERRCODE = '42501';
  END IF;

  IF p_amount_minor IS NULL OR p_amount_minor = 0 THEN
    RAISE EXCEPTION 'p_amount_minor must be a non-zero signed integer in minor units'
      USING ERRCODE = '22023';
  END IF;
  IF public.ledger_is_system(p_user_id) THEN
    RAISE EXCEPTION 'p_user_id names a platform account, not a member' USING ERRCODE = '22023';
  END IF;

  -- Whitelist, not lookup: opening_equity and marketplace_escrow are not
  -- fundable by an operator, and a typo must not resolve to anything.
  v_cp := CASE WHEN v_code IN ('treasury','corrections')
               THEN public.ledger_system_user(v_code) END;
  IF v_cp IS NULL THEN
    RAISE EXCEPTION 'p_counterparty must be treasury or corrections; a credit with no funding account is a mint'
      USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('ignitehex.ledger_delegated', 'on', true);

  RETURN public.post_entries(
    jsonb_build_array(
      jsonb_build_object('user_id', p_user_id, 'asset', p_asset, 'bucket', p_bucket,
                         'amount', p_amount_minor::text),
      jsonb_build_object('user_id', v_cp, 'asset', p_asset,
                         'bucket', CASE WHEN upper(btrim(p_asset)) IN ('EUR','USD','GBP','CHF')
                                        THEN 'liquid' ELSE p_bucket END,
                         'amount', (-p_amount_minor)::text)),
    p_reference,
    format('%s [operator %s, counterparty %s]', p_reason, v_actor, v_code));
END
$adj$;


-- =====================================================================
-- 6. PRIVILEGES
--
-- A new function defaults to EXECUTE for PUBLIC. Every one of these is revoked
-- first and granted second, and nothing below widens a privilege that already
-- existed.
-- =====================================================================

-- Internal. Not callable by anybody, including service_role: post_entries and
-- the wrappers reach them as the owner.
REVOKE ALL ON FUNCTION public.ledger_reject_mutation()                          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_system_user(text)                          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_is_system(uuid)                            FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_minor(text, numeric)                       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_major(text, bigint)                        FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_opening_balance(uuid, text, text)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_apply_projection(uuid, text, text, bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_resolve_account(uuid, text, text)          FROM PUBLIC, anon, authenticated, service_role;

-- The primitive. service_role only; members reach it through a wrapper.
REVOKE ALL     ON FUNCTION public.post_entries(jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.post_entries(jsonb, text, text) TO service_role;

-- Operator maintenance: installs the deferred key once the backlog is cleared.
REVOKE ALL     ON FUNCTION public.ledger_restore_pool_unique_key() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_restore_pool_unique_key() TO service_role;

-- Wrappers. Member- and operator-facing; each asserts identity in its body.
REVOKE ALL     ON FUNCTION public.release_marketplace_escrow(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.release_marketplace_escrow(uuid) TO authenticated, service_role;

REVOKE ALL     ON FUNCTION public.admin_adjust_member_balance(uuid, text, text, bigint, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_adjust_member_balance(uuid, text, text, bigint, text, text, text) TO authenticated, service_role;

-- Tables: read-only where readable at all, and only through RLS.
REVOKE ALL ON TABLE public.ledger_asset, public.ledger_system, public.ledger_account,
                    public.ledger_journal, public.ledger_entry,
                    public.staking_pool_duplicate_backlog
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ledger_asset, public.ledger_system, public.ledger_account,
                      public.ledger_journal, public.ledger_entry,
                      public.staking_pool_duplicate_backlog
  TO authenticated, service_role;


-- Fail the migration rather than ship a hole.
DO $verify$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(format('%s -> %s', p.oid::regprocedure, r.rolname), ', ')
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
   WHERE n.nspname = 'public'
     AND p.proname IN ('post_entries','ledger_resolve_account','ledger_apply_projection',
                       'ledger_opening_balance','ledger_minor','ledger_major',
                       'ledger_reject_mutation','ledger_system_user','ledger_is_system')
     AND has_function_privilege(r.rolname, p.oid, 'EXECUTE');

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'ledger internals are still reachable by a browser role: %', v_bad;
  END IF;

  -- The spot-pool key is a hard requirement: no key, no idempotent credit.
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE c.relname = 'user_staking_pools_spot_key' AND i.indisunique
  ) THEN
    RAISE EXCEPTION 'user_staking_pools_spot_key is missing: post_entries has no ON CONFLICT target';
  END IF;

  RAISE NOTICE 'ledger: post_entries + 2 wrappers installed; internals closed to anon and authenticated';

  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname = 'user_staking_pools_user_id_pool_type_stake_duration_months_key'
                AND conrelid = 'public.user_staking_pools'::regclass AND contype = 'u') THEN
    RAISE NOTICE 'ledger: full UNIQUE (user_id, pool_type, stake_duration_months) is in place';
  ELSE
    RAISE WARNING 'ledger: full UNIQUE (user_id, pool_type, stake_duration_months) is NOT in place -- % group(s) open in staking_pool_duplicate_backlog',
      (SELECT count(*) FROM public.staking_pool_duplicate_backlog WHERE resolved_at IS NULL);
  END IF;
END
$verify$;
