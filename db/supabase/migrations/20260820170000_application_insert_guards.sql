-- =====================================================================
-- APPLICATION INSERT GUARDS
--
-- Three tables let an applicant decide the outcome of their own application.
--
-- Each has an INSERT policy of `WITH CHECK (auth.uid() = user_id)` and nothing
-- more. That checks WHOSE row it is and never checks WHAT IS IN IT, so a member
-- may post a row that is already approved, already credited, and already marked
-- payment-verified. Confirmed against a live schema, not inferred:
--
--   POST /rest/v1/seed_str_applications
--     {"status":"approved","credited_amount":500000,
--      "str_shares_credited":500000,"payment_status":"payment_verified"}
--   -> 201, stored exactly as posted
--
-- The reviewer's queue filters on `status = 'pending'`, so such a row is not
-- merely unreviewed — it is INVISIBLE to the person whose job is to catch it.
--
-- private_seed_str_applications has an UPDATE trigger, but its protected list
-- is status / processed_at / processed_by / admin_notes. The money columns are
-- absent, so an applicant may leave `status` at 'pending' and still write:
--
--   PATCH {"credited_amount":777777,"str_shares_credited":777777,
--          "payment_status":"payment_verified"}   -> 200, row updated
--
-- The row then sits in the queue looking untouched while showing the reviewer a
-- figure the applicant wrote for themselves.
--
-- WHY A TRIGGER AND NOT A NARROWER POLICY: a WITH CHECK listing every
-- settlement column would have to be repeated on each table and re-edited every
-- time a column is added, and a policy cannot see OLD on an UPDATE. A BEFORE
-- trigger states the rule once per table and covers both verbs.
--
-- The rule is inverted deliberately: rather than enumerate what a member may
-- not set (which fails open the day someone adds a column), these force every
-- settlement field to its safe value for a non-admin and let everything else
-- through.
-- =====================================================================

-- ---------------------------------------------------------------- seed round
CREATE OR REPLACE FUNCTION public.guard_seed_str_application()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- An application starts as an application. Nothing about its outcome is
    -- the applicant's to state.
    NEW.status              := 'pending';
    NEW.credited_amount     := 0;
    NEW.str_shares_credited := 0;
    NEW.credited_at         := NULL;
    NEW.processed_at        := NULL;
    NEW.processed_by        := NULL;
    NEW.payment_status      := 'awaiting_payment';
    NEW.payment_verified_at := NULL;
    NEW.payment_verified_by := NULL;
    NEW.admin_notes         := NULL;
    NEW.cancelled_at        := NULL;
    NEW.cancelled_by        := NULL;
    NEW.suspended_at        := NULL;
    NEW.suspended_by        := NULL;
  ELSE
    -- On UPDATE every settlement field keeps whatever the reviewer last put
    -- there. A member may still correct their own contact details.
    NEW.status              := OLD.status;
    NEW.credited_amount     := OLD.credited_amount;
    NEW.str_shares_credited := OLD.str_shares_credited;
    NEW.credited_at         := OLD.credited_at;
    NEW.processed_at        := OLD.processed_at;
    NEW.processed_by        := OLD.processed_by;
    NEW.payment_status      := OLD.payment_status;
    NEW.payment_verified_at := OLD.payment_verified_at;
    NEW.payment_verified_by := OLD.payment_verified_by;
    NEW.admin_notes         := OLD.admin_notes;
    NEW.cancelled_at        := OLD.cancelled_at;
    NEW.cancelled_by        := OLD.cancelled_by;
    NEW.suspended_at        := OLD.suspended_at;
    NEW.suspended_by        := OLD.suspended_by;
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_seed_str_application ON public.seed_str_applications;
CREATE TRIGGER guard_seed_str_application
  BEFORE INSERT OR UPDATE ON public.seed_str_applications
  FOR EACH ROW EXECUTE FUNCTION public.guard_seed_str_application();

-- -------------------------------------------------------- private seed round
CREATE OR REPLACE FUNCTION public.guard_private_seed_str_application()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status              := 'pending';
    NEW.credited_amount     := 0;
    NEW.str_shares_credited := 0;
    NEW.credited_at         := NULL;
    NEW.processed_at        := NULL;
    NEW.processed_by        := NULL;
    NEW.payment_status      := 'awaiting_payment';
    NEW.admin_notes         := NULL;
  ELSE
    NEW.status              := OLD.status;
    NEW.credited_amount     := OLD.credited_amount;
    NEW.str_shares_credited := OLD.str_shares_credited;
    NEW.credited_at         := OLD.credited_at;
    NEW.processed_at        := OLD.processed_at;
    NEW.processed_by        := OLD.processed_by;
    NEW.payment_status      := OLD.payment_status;
    NEW.admin_notes         := OLD.admin_notes;
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_private_seed_str_application ON public.private_seed_str_applications;
CREATE TRIGGER guard_private_seed_str_application
  BEFORE INSERT OR UPDATE ON public.private_seed_str_applications
  FOR EACH ROW EXECUTE FUNCTION public.guard_private_seed_str_application();

-- ------------------------------------------------------------ node purchases
CREATE OR REPLACE FUNCTION public.guard_starw_purchase()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $g$
BEGIN
  IF public.is_admin(auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
  ELSE
    NEW.status := OLD.status;
  END IF;

  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS guard_starw_purchase ON public.starw_purchases;
CREATE TRIGGER guard_starw_purchase
  BEFORE INSERT OR UPDATE ON public.starw_purchases
  FOR EACH ROW EXECUTE FUNCTION public.guard_starw_purchase();

-- These are triggers, never called directly. Postgres grants EXECUTE to PUBLIC
-- at creation and this project already carries 269 SECURITY DEFINER functions
-- in production that were never revoked (F-001).
REVOKE ALL ON FUNCTION public.guard_seed_str_application() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_private_seed_str_application() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_starw_purchase() FROM PUBLIC, anon, authenticated;
