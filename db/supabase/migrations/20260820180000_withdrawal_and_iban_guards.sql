-- =====================================================================
-- WITHDRAWAL AND IBAN GUARDS
--
-- Two tables where the member's own policy is the only policy.
--
-- 1. withdrawal_requests
--
--    SELECT  (auth.uid() = user_id)
--    UPDATE  (auth.uid() = user_id)
--    INSERT  own row
--
--    There is no admin policy of any kind. Two consequences, both verified:
--
--      * A member may UPDATE their own row, and nothing restricts which
--        columns — so they can set status = 'approved' themselves.
--      * An administrator SELECTing the table gets zero rows. Not an error:
--        RLS returns an empty set, so the operations console shows an empty
--        queue and nobody learns that requests exist.
--
--    Together those mean a withdrawal can be raised and approved by the person
--    receiving it, and the operator never sees it happen. This is the same
--    class as F-039 (admin read policies missing on four tables); the
--    self-approval half is worse than the reporting half.
--
--    The production table is currently EMPTY, so this closes an unused door
--    rather than an active loss. That is the good time to close it.
--
-- 2. iban_accounts
--
--    INSERT  ((auth.uid() = user_id) AND (auth.uid() IS NOT NULL))
--
--    Checks whose row it is; never checks what is in it. `balance` is a column
--    on this table, so a member may insert an account carrying a balance they
--    chose. A balance must arrive from a posting, never from an INSERT.
-- =====================================================================

-- --------------------------------------------------------- withdrawal_requests
-- Members keep their own view and may still raise a request. What they lose is
-- the ability to decide it.
DROP POLICY IF EXISTS "Users can update their own withdrawal requests" ON public.withdrawal_requests;

-- A member may still edit a request that has NOT been decided — to correct a
-- destination or amount, or to cancel. The status they may write is restricted
-- to the two that are theirs to choose.
DROP POLICY IF EXISTS withdrawal_requests_own_update ON public.withdrawal_requests;
CREATE POLICY withdrawal_requests_own_update ON public.withdrawal_requests
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id AND status = 'pending')
  WITH CHECK (auth.uid() = user_id AND status IN ('pending', 'cancelled'));

-- The operator has to be able to see the queue before they can work it.
DROP POLICY IF EXISTS withdrawal_requests_admin_select ON public.withdrawal_requests;
CREATE POLICY withdrawal_requests_admin_select ON public.withdrawal_requests
  FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS withdrawal_requests_admin_update ON public.withdrawal_requests;
CREATE POLICY withdrawal_requests_admin_update ON public.withdrawal_requests
  FOR UPDATE TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- Belt and braces: a policy states who may write, a trigger states what. If a
-- later migration widens the policy again, this still holds.
CREATE OR REPLACE FUNCTION public.guard_withdrawal_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  -- Columns are named against the ACTUAL table, which is a founder-position BTC
  -- withdrawal: there is no `amount` and no `processed_by`. plpgsql binds field
  -- names at run time, so a wrong name here applies cleanly as a migration and
  -- then fails on the first insert — which is exactly what happened while this
  -- was being written, and why it is tested against a real row below.
  IF TG_OP = 'INSERT' THEN
    NEW.status           := 'pending';
    NEW.processed_at     := NULL;
    -- A member must not arrive claiming their payout is already on chain.
    NEW.transaction_hash := NULL;
  ELSIF NEW.status NOT IN ('pending', 'cancelled') THEN
    RAISE EXCEPTION 'Only an administrator may set a withdrawal to %', NEW.status
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_withdrawal_request ON public.withdrawal_requests;
CREATE TRIGGER guard_withdrawal_request
  BEFORE INSERT OR UPDATE ON public.withdrawal_requests
  FOR EACH ROW EXECUTE FUNCTION public.guard_withdrawal_request();

REVOKE ALL ON FUNCTION public.guard_withdrawal_request() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- iban_accounts
-- A balance is the result of a posting. It is never something a row arrives
-- carrying, and least of all on a row the account holder wrote.
CREATE OR REPLACE FUNCTION public.guard_iban_account()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.balance := 0;
    NEW.status  := coalesce(NEW.status, 'pending');
  ELSE
    NEW.balance := OLD.balance;
    NEW.status  := OLD.status;
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_iban_account ON public.iban_accounts;
CREATE TRIGGER guard_iban_account
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION public.guard_iban_account();

REVOKE ALL ON FUNCTION public.guard_iban_account() FROM PUBLIC, anon, authenticated;
