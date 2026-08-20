-- =====================================================================
-- F-032 -- selling tokens changes no on-screen figure.
--
-- F-032 recorded the symptom as "debit_staking_pool_balance debits `balance`,
-- the UI reads `staked_amount`", and left the choice of which column is
-- authoritative open. It is not open. Here is what the two columns mean,
-- measured before anything was changed.
--
-- ================================================================
-- WHAT THE COLUMNS MEAN -- the evidence, in the order it settles it
-- ================================================================
--
-- (1) The credit path writes the SAME quantity into BOTH.
--     credit_voucher_tokens (both overloads) does
--         staked_amount = current_staked + token_amount,
--         balance       = current_balance + token_amount
--     for one redemption of token_amount tokens. One credit, two columns, same
--     number. So they are not two disjoint holdings that add up -- they are two
--     records of one holding.
--
-- (2) Only `balance` then moves.
--     calculate_daily_rewards does
--         rewards_earned = rewards_earned + daily_reward,
--         balance        = balance + daily_reward
--     and never touches staked_amount. debit_staking_pool_balance subtracts
--     from balance and never touches staked_amount. So staked_amount is the
--     frozen principal as first credited, and balance is the live figure.
--
-- (3) The server already says which one is spendable.
--     get_available_balance(p_user_id, p_token_type) is
--         SELECT coalesce(SUM(balance), 0) FROM user_staking_pools ...
--     `balance` IS the available balance. Nothing reads staked_amount to
--     decide whether a member can spend.
--
-- (4) Production agrees, at scale. Read-only against lhkkfrpgbkjfcrodjslf on
--     2026-08-19:
--
--       user_staking_pools: 56,836 rows
--         balance = staked_amount  54,499   (95.9%)
--         balance > staked_amount   1,641   (rewards accrued into balance)
--         balance < staked_amount     696   (spent out of balance)
--         sum(balance) 9,853,625,616.82   sum(staked_amount) 9,420,683,267.24
--
--       And joined against what the vouchers actually credited, per member per
--       token, 4,515 pairs:
--         balance          = credited   1,108
--         staked_amount    = credited   1,534
--         balance + staked = credited     166
--
--     If the two columns were disjoint buckets their SUM would reconcile to
--     the credit. It reconciles 166 times out of 4,515. Each column
--     individually reconciles ten times more often. They are duplicates, and
--     staked_amount is the better-preserved copy precisely because nothing
--     debits it.
--
-- CONCLUSION: `balance` is authoritative for what a member holds.
-- debit_staking_pool_balance debits the RIGHT column. Nothing about the debit
-- target needed changing, and "also debit staked_amount" would have been
-- wrong twice over -- it would assert that selling unstakes principal, and it
-- would preserve the duplication instead of routing around it.
--
-- ================================================================
-- WHAT WAS ACTUALLY BROKEN, AND WHAT THIS MIGRATION DOES
-- ================================================================
--
-- The sell path was a four-step client-side dance (v3
-- domains/marketplace/hooks.ts createTokenListing): insert the listing as
-- pending_escrow, call debit_staking_pool_balance, insert the escrow row,
-- update the listing to active. Four round trips, four separate
-- transactions, and the debit in the middle is a ONE-WAY move -- the value
-- leaves `balance` and lands nowhere. There is no account it went to, so
-- nothing can put it back and nothing can be reconciled against it. v3's own
-- Sell.tsx says so and disables the Cancel button for that reason.
--
-- That is the same asymmetry 20260818160000 was written to close, and the
-- release half of it -- release_marketplace_escrow -- was already built. The
-- lock half was missing. This migration is the missing half:
--
--   marketplace_escrow_lock(p_listing_id uuid) -> jsonb
--
--     one transaction, on post_entries, posting
--         seller / ASSET / liquid  -amount
--         seller / ASSET / held    +amount
--     then writing the marketplace_escrow_balances row and publishing the
--     listing inside that same transaction.
--
-- What this buys, concretely:
--
--   * The value has a destination. `held` is a real ledger account, and
--     ledger_opening_balance already reads its opening balance from the
--     locked escrow rows, so the ledger and the escrow table cannot disagree.
--   * release_marketplace_escrow is now the exact inverse. Cancelling a
--     listing becomes possible for the first time.
--   * Insufficient balance is refused by post_entries under the account lock,
--     with the amount named, instead of by a boolean `false` the caller has to
--     remember to check.
--   * The three partial-failure states the client flow could land in -- draft
--     with no debit, debit with no escrow row, escrow with no publication --
--     are gone. They were not handled defects; they were unreachable-by-
--     construction states that the four-transaction shape made reachable.
--   * Every lock is a journal entry with a reference, a reason and an actor,
--     so a sale is attributable. The old debit left no record anywhere.
--
-- AND THE ON-SCREEN FIGURE. `balance` falls, which is the member's liquid
-- position, and a `held` balance appears. The headline tile on / and /wallet
-- reads staked_amount and does NOT move -- correctly, because nothing was
-- unstaked. The v3 change that goes with this migration adds the escrowed
-- quantity to lib/balances.ts so the sale is visible as liquid -> escrowed,
-- and stops adding staked_amount into the total, which was counting the same
-- tokens twice (see the finding recorded alongside this file).
--
-- NOT APPLIED TO PRODUCTION.
-- =====================================================================


-- ---------------------------------------------------------------------
-- marketplace_escrow_lock(p_listing_id uuid) -> jsonb
--
-- The counterpart of release_marketplace_escrow(uuid), and deliberately built
-- to the same rules: the wrapper decides WHO may act and WHAT the legs are,
-- and never touches a balance column itself.
--
-- Identity is re-derived from the listing row against auth.uid() through
-- assert_caller_owns. There is no seller_id parameter to forge.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketplace_escrow_lock(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $lock$
DECLARE
  v_listing record;
  v_asset   text;
  v_minor   bigint;
  v_locked  numeric;
  v_result  jsonb;
BEGIN
  IF p_listing_id IS NULL THEN
    RAISE EXCEPTION 'p_listing_id is required' USING ERRCODE = '22023';
  END IF;

  SELECT id, seller_id, asset_type, asset_symbol, amount, status
    INTO v_listing
    FROM public.token_marketplace_listings
   WHERE id = p_listing_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % does not exist', p_listing_id USING ERRCODE = '22023';
  END IF;

  -- Identity, re-derived from the row. A member may lock only their own
  -- listing; an administrator may act for a member; a JWT-less server session
  -- may act unattended. assert_caller_owns is the single place that decides.
  PERFORM public.assert_caller_owns(v_listing.seller_id);

  -- Only an unpublished draft may be locked. Anything already active, sold,
  -- reserved or cancelled has either been locked once already or is a record
  -- that must not acquire new escrow. escrow_error is included because that
  -- state means "debited but the escrow row did not save" under the OLD flow
  -- and is exactly the case an operator needs to be able to complete.
  IF v_listing.status NOT IN ('pending_escrow', 'escrow_error') THEN
    RAISE EXCEPTION 'Listing % is %, and only a pending_escrow or escrow_error draft may be locked',
      p_listing_id, v_listing.status
      USING ERRCODE = '22023';
  END IF;

  IF v_listing.asset_type IS DISTINCT FROM 'token' THEN
    RAISE EXCEPTION 'Listing % is a % listing; only token listings hold pool escrow',
      p_listing_id, coalesce(v_listing.asset_type, 'null')
      USING ERRCODE = '22023';
  END IF;

  IF v_listing.amount IS NULL OR v_listing.amount <= 0 THEN
    RAISE EXCEPTION 'Listing % has no positive amount to lock', p_listing_id
      USING ERRCODE = '22023';
  END IF;

  v_asset := upper(btrim(coalesce(v_listing.asset_symbol, '')));

  IF NOT EXISTS (SELECT 1 FROM public.ledger_asset WHERE asset = v_asset) THEN
    RAISE EXCEPTION 'Asset % is not registered in ledger_asset, so its scale is unknown and it cannot be escrowed exactly',
      coalesce(nullif(v_asset, ''), 'null')
      USING ERRCODE = '22023';
  END IF;

  -- Second lock against a double lock. The status check above is the first;
  -- this one survives a listing whose status was moved by hand.
  SELECT coalesce(sum(amount), 0) INTO v_locked
    FROM public.marketplace_escrow_balances
   WHERE listing_id = p_listing_id AND status = 'locked';

  IF v_locked > 0 THEN
    RAISE EXCEPTION 'Listing % already holds % in locked escrow', p_listing_id, v_locked
      USING ERRCODE = '23505';
  END IF;

  v_minor := public.ledger_minor(v_asset, v_listing.amount);

  IF v_minor <= 0 THEN
    RAISE EXCEPTION 'Listing % rounds to zero minor units of %, and a zero lock is not a sale',
      p_listing_id, v_asset
      USING ERRCODE = '22023';
  END IF;

  -- Delegation marker: this wrapper has asserted identity, so the primitive
  -- may accept the batch even though the session belongs to a member. It is
  -- transaction-local and post_entries consumes it on entry.
  PERFORM set_config('ignitehex.ledger_delegated', 'on', true);

  -- The two legs. They sum to zero, so this is a transfer between two of the
  -- member's own buckets and not a mint. post_entries refuses it under the
  -- account lock if liquid would go negative, which is the balance check --
  -- there is no separate one to forget.
  v_result := public.post_entries(
    jsonb_build_array(
      jsonb_build_object('user_id', v_listing.seller_id, 'asset', v_asset,
                         'bucket', 'liquid', 'amount', (-v_minor)::text),
      jsonb_build_object('user_id', v_listing.seller_id, 'asset', v_asset,
                         'bucket', 'held',   'amount', ( v_minor)::text)),
    'escrow_lock:' || p_listing_id::text,
    format('Marketplace escrow locked for listing %s', p_listing_id));

  -- On a replayed reference post_entries returns applied=false and changes
  -- nothing. The escrow row and the publication must not be written again
  -- either, so both are conditional on the posting having applied.
  IF (v_result->>'applied')::boolean THEN
    INSERT INTO public.marketplace_escrow_balances
      (user_id, listing_id, asset_symbol, amount, status)
    VALUES (v_listing.seller_id, p_listing_id, v_asset, v_listing.amount, 'locked');

    UPDATE public.token_marketplace_listings
       SET status = 'active', updated_at = now()
     WHERE id = p_listing_id;
  END IF;

  RETURN jsonb_build_object(
    'locked',     (v_result->>'applied')::boolean,
    'listing_id', p_listing_id,
    'asset',      v_asset,
    'amount',     v_listing.amount,
    'posting',    v_result);
END
$lock$;


-- ---------------------------------------------------------------------
-- Privileges.
--
-- REVOKE first. Postgres grants EXECUTE to PUBLIC on creation (F-001), so a
-- function is anon-callable the instant it exists unless this is stated.
-- ---------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.marketplace_escrow_lock(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.marketplace_escrow_lock(uuid) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- Close the one-way debit to members.
--
-- debit_staking_pool_balance takes value out of `balance` and gives it to
-- nothing. With marketplace_escrow_lock in place nothing in v3 needs it: the
-- only caller was the sell path this replaces.
--
-- It is NOT dropped, and NOT revoked from service_role: the process-swap edge
-- function calls it (supabase/functions/process-swap/index.ts:173) with the
-- service key, and breaking a swap in order to fix a sale would be trading one
-- defect for another. What changes is that a browser can no longer reach it.
--
-- This NARROWS privilege. It is stated here rather than left implicit because
-- a member who can still call it can still create the exact divergence F-032
-- describes, and then the ledger is authoritative for the sell path only.
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.debit_staking_pool_balance(uuid, text, numeric) FROM authenticated;

COMMENT ON FUNCTION public.marketplace_escrow_lock(uuid) IS
  'F-032: locks a pending_escrow token listing by posting liquid -> held through post_entries, then writes the escrow row and publishes the listing in the same transaction. The exact inverse of release_marketplace_escrow.';

COMMENT ON FUNCTION public.debit_staking_pool_balance(uuid, text, numeric) IS
  'F-032: one-way debit of user_staking_pools.balance with no counterparty. Retained for the process-swap edge function only. Members go through marketplace_escrow_lock, which posts both legs.';
