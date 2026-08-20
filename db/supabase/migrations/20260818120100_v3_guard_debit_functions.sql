-- Wire the ownership assertion into the debit functions.
--
-- 20260818120000 added public.assert_caller_owns and revoked anon, but the
-- debit functions themselves still accepted an arbitrary p_user_id from an
-- authenticated caller. Both are SECURITY DEFINER, so without an explicit check
-- any signed-in session could debit any other account.
--
-- The existing bodies are correct - they lock the row FOR UPDATE and debit
-- atomically - so rather than restate them here (and risk transcribing them
-- wrongly), the assertion is spliced in after the opening BEGIN of whatever is
-- currently installed. Re-running is safe: a body that already contains the
-- call is skipped.

DO $splice$
DECLARE
  r record;
  new_body text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.proname,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_function_result(p.oid) AS result,
           p.prosrc
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('debit_staking_pool_balance', 'debit_fiat_wallet')
  LOOP
    IF position('assert_caller_owns' in r.prosrc) > 0 THEN
      RAISE NOTICE '% already guarded', r.proname;
      CONTINUE;
    END IF;

    new_body := regexp_replace(
      r.prosrc,
      '(^|\n)BEGIN',
      E'\\1BEGIN\n  PERFORM public.assert_caller_owns(p_user_id);',
      ''
    );

    EXECUTE format(
      'CREATE OR REPLACE FUNCTION public.%I(%s) RETURNS %s LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %L',
      r.proname, r.args, r.result, new_body
    );

    RAISE NOTICE 'guarded %', r.proname;
  END LOOP;
END
$splice$;
