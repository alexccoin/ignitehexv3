-- =====================================================================
-- AIRDROP REGISTRATION GUARD
--
-- The fifth table with the same defect, found after the other four were closed.
--
-- `airdrop_registrations` has a member INSERT policy that checks `user_id` and
-- nothing else, so an applicant may file a registration that is already
-- approved, already flagged as credited, and carrying an amount they chose:
--
--   POST /rest/v1/airdrop_registrations
--     {"status":"approved","tokens_credited":true,"credited_amount":250000}
--   -> 201, stored exactly as posted
--
-- The reason this one was missed in the first pass is worth recording: the
-- table was on the "confirmed ready, has an INSERT policy" list. Having an
-- INSERT policy was treated as the thing to check, when the question that
-- matters is what the policy CONSTRAINS. `WITH CHECK (auth.uid() = user_id)`
-- is present on all five of these tables and permits all five attacks.
--
-- Same shape as 20260820170000: force every settlement field for a non-admin
-- rather than enumerate what they may not touch, so a column added later
-- cannot silently reopen it.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.guard_airdrop_registration()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status          := 'pending';
    NEW.tokens_credited := false;
    NEW.credited_amount := 0;
    NEW.credited_at     := NULL;
    NEW.processed_at    := NULL;
    NEW.processed_by    := NULL;
  ELSE
    NEW.status          := OLD.status;
    NEW.tokens_credited := OLD.tokens_credited;
    NEW.credited_amount := OLD.credited_amount;
    NEW.credited_at     := OLD.credited_at;
    NEW.processed_at    := OLD.processed_at;
    NEW.processed_by    := OLD.processed_by;
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_airdrop_registration ON public.airdrop_registrations;
CREATE TRIGGER guard_airdrop_registration
  BEFORE INSERT OR UPDATE ON public.airdrop_registrations
  FOR EACH ROW EXECUTE FUNCTION public.guard_airdrop_registration();

REVOKE ALL ON FUNCTION public.guard_airdrop_registration() FROM PUBLIC, anon, authenticated;
