-- post_entries: the invariants that stop money being created.
--
-- Runs as `postgres`, which is a service identity as far as post_entries is
-- concerned (jwt role empty, login role postgres). That is correct HERE and
-- only here: these are tests of the ledger's arithmetic, not of who may reach
-- it. Authorisation is tested in 02_function_authorization.mjs over a real
-- member JWT, because a psql session proves nothing about a browser caller.
--
-- The whole file is one transaction ending in ROLLBACK, so it can run against a
-- stack with real data as often as you like and leave nothing behind.
--
-- Each assertion catches the expected exception into a flag rather than letting
-- it escape, then raises its own if the expected failure did not happen. A test
-- that only checks "it threw" would pass on a typo in a column name, so the
-- SQLSTATE is checked too.

BEGIN;

DO $$
DECLARE
  v_a        uuid;
  v_b        uuid;
  v_ref      text;
  v_res      jsonb;
  v_ok       boolean;
  v_state    text;
  v_msg      text;
  v_a_before bigint;
  v_b_before bigint;
  v_a_after  bigint;
  v_b_after  bigint;
  v_journals bigint;
  v_entries  bigint;
  v_net      text;
BEGIN
  SELECT id INTO v_a FROM auth.users WHERE email = 'investor1@ignitehex.local';
  SELECT id INTO v_b FROM auth.users WHERE email = 'newbie@ignitehex.local';
  IF v_a IS NULL OR v_b IS NULL THEN
    RAISE EXCEPTION 'FIXTURE MISSING: seed the stack first (npm run db:seed in hex-ignite-nexus)';
  END IF;

  -- Resolve both accounts up front so the opening-balance machinery runs
  -- before anything is measured, and the deltas below are the batch's alone.
  PERFORM public.ledger_resolve_account(v_a, 'STR', 'liquid');
  PERFORM public.ledger_resolve_account(v_b, 'STR', 'liquid');
  PERFORM public.ledger_resolve_account(v_a, 'CCOS', 'liquid');

  SELECT balance INTO v_a_before FROM public.ledger_account
   WHERE user_id = v_a AND asset = 'STR' AND bucket = 'liquid';
  SELECT balance INTO v_b_before FROM public.ledger_account
   WHERE user_id = v_b AND asset = 'STR' AND bucket = 'liquid';
  SELECT count(*) INTO v_journals FROM public.ledger_journal;

  RAISE NOTICE 'opening: A=% B=% journals=%', v_a_before, v_b_before, v_journals;

  ------------------------------------------------------------------ 1
  -- A batch whose signed amounts do not sum to zero is rejected.
  -- This is the credit with no named source: 100 appears, nothing is debited.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 100),
        jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -60)
      ),
      'test-unbalanced-' || gen_random_uuid()::text,
      'unbalanced batch must be rejected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: an unbalanced batch (+100/-60 STR) was ACCEPTED. 40 STR was created from nothing.';
  END IF;
  IF v_state <> '23514' THEN
    RAISE EXCEPTION 'unbalanced batch was rejected, but with SQLSTATE % (%) rather than 23514', v_state, v_msg;
  END IF;
  RAISE NOTICE '1. unbalanced batch rejected: %', left(v_msg, 90);

  ------------------------------------------------------------------ 2
  -- Zero-sum is PER ASSET, not across the batch. +100 STR and -100 CCOS sums
  -- to zero if you add the raw numbers, and adding STR to CCOS is the same
  -- defect the wallet tiles keep growing (F-015): a figure with no unit.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_b, 'asset', 'STR',  'bucket', 'liquid', 'amount', 100),
        jsonb_build_object('user_id', v_a, 'asset', 'CCOS', 'bucket', 'liquid', 'amount', -100)
      ),
      'test-crossasset-' || gen_random_uuid()::text,
      'a cross-asset batch does not balance');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: +100 STR balanced against -100 CCOS was ACCEPTED. The ledger is adding two different units.';
  END IF;
  IF v_state <> '23514' THEN
    RAISE EXCEPTION 'cross-asset batch rejected with SQLSTATE % rather than 23514: %', v_state, v_msg;
  END IF;
  RAISE NOTICE '2. cross-asset batch rejected: %', left(v_msg, 90);

  ------------------------------------------------------------------ 3
  -- Nothing above was written. A rejected batch must leave no journal behind,
  -- or the reference is burned and the retry looks idempotent.
  IF (SELECT count(*) FROM public.ledger_journal) <> v_journals THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a rejected batch left % journal row(s) behind',
      (SELECT count(*) FROM public.ledger_journal) - v_journals;
  END IF;
  RAISE NOTICE '3. rejected batches wrote no journal rows';

  ------------------------------------------------------------------ 4
  -- A balanced batch applies, and moves exactly what it said.
  v_ref := 'test-balanced-' || gen_random_uuid()::text;
  v_res := public.post_entries(
    jsonb_build_array(
      jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -100),
      jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 100)
    ),
    v_ref, 'balanced transfer');

  IF (v_res->>'applied')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'a balanced batch was not applied: %', v_res;
  END IF;

  SELECT balance INTO v_a_after FROM public.ledger_account
   WHERE user_id = v_a AND asset = 'STR' AND bucket = 'liquid';
  SELECT balance INTO v_b_after FROM public.ledger_account
   WHERE user_id = v_b AND asset = 'STR' AND bucket = 'liquid';

  IF v_a_after <> v_a_before - 100 OR v_b_after <> v_b_before + 100 THEN
    RAISE EXCEPTION 'balances moved wrongly: A % -> % (wanted %), B % -> % (wanted %)',
      v_a_before, v_a_after, v_a_before - 100, v_b_before, v_b_after, v_b_before + 100;
  END IF;
  RAISE NOTICE '4. balanced batch applied: A %->%, B %->%', v_a_before, v_a_after, v_b_before, v_b_after;

  ------------------------------------------------------------------ 5
  -- The same reference posted twice is idempotent: it reports so, changes
  -- nothing, and writes no second set of entries. A retried request after a
  -- dropped connection must not pay twice.
  SELECT count(*) INTO v_entries FROM public.ledger_entry;

  v_res := public.post_entries(
    jsonb_build_array(
      jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -100),
      jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 100)
    ),
    v_ref, 'balanced transfer');

  IF (v_res->>'idempotent')::boolean IS NOT TRUE OR (v_res->>'applied')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: reposting reference % was not reported idempotent: %', v_ref, v_res;
  END IF;
  IF (SELECT count(*) FROM public.ledger_entry) <> v_entries THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a repeated reference wrote % more ledger entries',
      (SELECT count(*) FROM public.ledger_entry) - v_entries;
  END IF;
  IF (SELECT balance FROM public.ledger_account
       WHERE user_id = v_b AND asset = 'STR' AND bucket = 'liquid') <> v_b_after THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a repeated reference moved the balance a second time';
  END IF;
  RAISE NOTICE '5. repeat of reference % was idempotent, balances unchanged', left(v_ref, 24);

  ------------------------------------------------------------------ 6
  -- Idempotency is keyed on the reference, so an identical batch under a NEW
  -- reference must apply. Otherwise "idempotent" would just mean "deduplicated
  -- by content", and two genuine identical transfers would silently become one.
  v_res := public.post_entries(
    jsonb_build_array(
      jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -100),
      jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 100)
    ),
    'test-second-' || gen_random_uuid()::text, 'the same transfer again, deliberately');

  IF (v_res->>'applied')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: an identical batch under a new reference was refused: %', v_res;
  END IF;
  IF (SELECT balance FROM public.ledger_account
       WHERE user_id = v_b AND asset = 'STR' AND bucket = 'liquid') <> v_b_after + 100 THEN
    RAISE EXCEPTION 'the second genuine transfer did not move the balance';
  END IF;
  RAISE NOTICE '6. an identical batch under a new reference applied normally';

  ------------------------------------------------------------------ 7
  -- A reference is required. Without one there is no idempotency key at all.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -1),
        jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 1)
      ), '   ', 'no reference');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a batch with a blank reference was accepted; it has no idempotency key';
  END IF;
  RAISE NOTICE '7. blank reference rejected (%): %', v_state, left(v_msg, 70);

  ------------------------------------------------------------------ 8
  -- Amounts are integers in the asset's minor units. A fractional amount has
  -- to be rounded, and a rounded credit is a mint.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid', 'amount', -0.5),
        jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 0.5)
      ),
      'test-fractional-' || gen_random_uuid()::text, 'fractional minor units');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a fractional minor-unit amount was accepted';
  END IF;
  RAISE NOTICE '8. fractional amount rejected (%): %', v_state, left(v_msg, 70);

  ------------------------------------------------------------------ 9
  -- A single leg cannot balance. Two legs is the floor.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid', 'amount', 100)
      ),
      'test-oneleg-' || gen_random_uuid()::text, 'one leg');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a one-leg batch was accepted — a credit with no counterparty';
  END IF;
  RAISE NOTICE '9. single-leg batch rejected (%)', v_state;

  ------------------------------------------------------------------ 10
  -- A member account cannot go negative. Only system accounts carry
  -- allow_negative, and that is what makes the ledger's negative side finite
  -- and named rather than an overdraft anywhere.
  v_ok := false;
  BEGIN
    v_res := public.post_entries(
      jsonb_build_array(
        jsonb_build_object('user_id', v_b, 'asset', 'STR', 'bucket', 'liquid',
                           'amount', -(v_b_after + 100 + 1)),
        jsonb_build_object('user_id', v_a, 'asset', 'STR', 'bucket', 'liquid',
                           'amount',  (v_b_after + 100 + 1))
      ),
      'test-overdraft-' || gen_random_uuid()::text, 'spend more than is held');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: a member account was allowed to go negative';
  END IF;
  IF v_state <> '23514' THEN
    RAISE EXCEPTION 'overdraft rejected with SQLSTATE % rather than 23514: %', v_state, v_msg;
  END IF;
  RAISE NOTICE '10. overdraft rejected: %', left(v_msg, 80);

  ------------------------------------------------------------------ 11
  -- Conservation, over the whole ledger and not just this batch: every asset's
  -- entries sum to zero. If this ever fails, value was created somewhere and
  -- the per-batch check above was bypassed.
  SELECT string_agg(format('%s=%s', asset, net), ', ' ORDER BY asset) INTO v_net
    FROM (SELECT asset, sum(amount) AS net FROM public.ledger_entry
           GROUP BY asset HAVING sum(amount) <> 0) x;
  IF v_net IS NOT NULL THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: the ledger does not balance overall: [%]', v_net;
  END IF;
  RAISE NOTICE '11. every asset in ledger_entry sums to zero across the whole ledger';

  ------------------------------------------------------------------ 12
  -- ledger_account.balance is the sum of that account's entries. The balance
  -- column is a cache; a drift between the two means someone wrote the cache
  -- directly.
  SELECT string_agg(format('%s/%s/%s cached=%s entries=%s', user_id, asset, bucket, balance, entries), '; ')
    INTO v_net
    FROM (
      SELECT a.user_id, a.asset, a.bucket, a.balance,
             coalesce((SELECT sum(e.amount) FROM public.ledger_entry e WHERE e.account_id = a.id), 0) AS entries
        FROM public.ledger_account a
    ) x
   WHERE balance <> entries;
  IF v_net IS NOT NULL THEN
    RAISE EXCEPTION 'INVARIANT BROKEN: ledger_account.balance disagrees with its entries: %', left(v_net, 300);
  END IF;
  RAISE NOTICE '12. every ledger_account.balance equals the sum of its entries';

  RAISE NOTICE 'all post_entries invariants held';
END $$;

ROLLBACK;
