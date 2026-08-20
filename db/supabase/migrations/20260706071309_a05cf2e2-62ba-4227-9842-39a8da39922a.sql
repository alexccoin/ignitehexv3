
-- 1. Add account lifecycle columns to user_profiles
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz,
  ADD COLUMN IF NOT EXISTS suspension_reason text,
  ADD COLUMN IF NOT EXISTS closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS closure_reason text,
  ADD COLUMN IF NOT EXISTS profile_update_status text NOT NULL DEFAULT 'not_submitted';

-- allowed values: active | suspended | closed
-- profile_update_status: not_submitted | pending_review | approved | rejected

-- 2. Create user_profiles_updated
CREATE TABLE IF NOT EXISTS public.user_profiles_updated (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,

  -- Profile snapshot
  full_name text,
  email_address text,
  address text,
  city text,
  country text,
  postal_code text,
  str_domain_owned text,
  bsc_wallet_address text,
  btc_wallet_address text,
  str_wallet_address text,
  change_reason text,

  -- MiCA: investor classification
  investor_classification text,          -- retail | professional | eligible_counterparty

  -- MiCA: source of funds & wealth
  source_of_funds text,
  source_of_wealth text,
  expected_monthly_volume_eur numeric,

  -- MiCA: risk acknowledgement & suitability
  risk_acknowledged boolean NOT NULL DEFAULT false,
  crypto_experience_level text,          -- none | beginner | intermediate | advanced
  suitability_answers jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- MiCA: PEP / sanctions / tax residency
  is_pep boolean NOT NULL DEFAULT false,
  sanctions_declaration boolean NOT NULL DEFAULT false,
  tax_residency_country text,
  tax_identification_number text,

  -- MiCA legal terms acceptance
  mica_terms_accepted boolean NOT NULL DEFAULT false,
  mica_terms_version text,
  mica_terms_accepted_at timestamptz,

  -- Submission / review state
  submission_status text NOT NULL DEFAULT 'pending_review', -- pending_review | approved | rejected
  otp_verified boolean NOT NULL DEFAULT false,
  reviewed_by uuid,
  reviewed_at timestamptz,
  admin_notes text,
  rejection_reason text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_updated_user ON public.user_profiles_updated(user_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_updated_status ON public.user_profiles_updated(submission_status);

-- 3. Grants
GRANT SELECT, INSERT, UPDATE ON public.user_profiles_updated TO authenticated;
GRANT ALL ON public.user_profiles_updated TO service_role;

-- 4. RLS
ALTER TABLE public.user_profiles_updated ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own updated profile submissions" ON public.user_profiles_updated;
CREATE POLICY "Users view own updated profile submissions"
ON public.user_profiles_updated
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Users insert own updated profile submission" ON public.user_profiles_updated;
CREATE POLICY "Users insert own updated profile submission"
ON public.user_profiles_updated
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users update own pending submission" ON public.user_profiles_updated;
CREATE POLICY "Users update own pending submission"
ON public.user_profiles_updated
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND submission_status = 'pending_review')
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage all updated profile submissions" ON public.user_profiles_updated;
CREATE POLICY "Admins manage all updated profile submissions"
ON public.user_profiles_updated
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- 5. updated_at trigger
CREATE OR REPLACE FUNCTION public.set_updated_at_generic()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_profiles_updated_set_updated_at ON public.user_profiles_updated;
CREATE TRIGGER trg_user_profiles_updated_set_updated_at
BEFORE UPDATE ON public.user_profiles_updated
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_generic();

-- 6. Admin action RPC: approve / reject / suspend / close
CREATE OR REPLACE FUNCTION public.admin_review_updated_profile(
  _submission_id uuid,
  _action text,               -- approve | reject | suspend | close
  _notes text DEFAULT NULL,
  _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _admin uuid := auth.uid();
  _sub public.user_profiles_updated%ROWTYPE;
BEGIN
  IF NOT public.has_role(_admin, 'admin') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _sub FROM public.user_profiles_updated WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission_not_found';
  END IF;

  IF _action = 'approve' THEN
    UPDATE public.user_profiles
    SET
      full_name          = COALESCE(_sub.full_name, full_name),
      email_address      = COALESCE(_sub.email_address, email_address),
      address            = COALESCE(_sub.address, address),
      city               = COALESCE(_sub.city, city),
      country            = COALESCE(_sub.country, country),
      postal_code        = COALESCE(_sub.postal_code, postal_code),
      str_domain_owned   = COALESCE(_sub.str_domain_owned, str_domain_owned),
      bsc_wallet_address = COALESCE(_sub.bsc_wallet_address, bsc_wallet_address),
      btc_wallet_address = COALESCE(_sub.btc_wallet_address, btc_wallet_address),
      str_wallet_address = COALESCE(_sub.str_wallet_address, str_wallet_address),
      account_status = 'active',
      profile_update_status = 'approved',
      updated_at = now()
    WHERE user_id = _sub.user_id;

    UPDATE public.user_profiles_updated
    SET submission_status = 'approved', reviewed_by = _admin, reviewed_at = now(), admin_notes = _notes
    WHERE id = _submission_id;

  ELSIF _action = 'reject' THEN
    UPDATE public.user_profiles_updated
    SET submission_status = 'rejected', reviewed_by = _admin, reviewed_at = now(),
        admin_notes = _notes, rejection_reason = _reason
    WHERE id = _submission_id;

    UPDATE public.user_profiles
    SET profile_update_status = 'rejected', updated_at = now()
    WHERE user_id = _sub.user_id;

  ELSIF _action = 'suspend' THEN
    UPDATE public.user_profiles
    SET account_status = 'suspended', suspended_at = now(), suspension_reason = _reason, updated_at = now()
    WHERE user_id = _sub.user_id;

    UPDATE public.user_profiles_updated
    SET admin_notes = COALESCE(_notes, admin_notes), reviewed_by = _admin, reviewed_at = now()
    WHERE id = _submission_id;

  ELSIF _action = 'close' THEN
    UPDATE public.user_profiles
    SET account_status = 'closed', closed_at = now(), closure_reason = _reason, updated_at = now()
    WHERE user_id = _sub.user_id;

    UPDATE public.user_profiles_updated
    SET admin_notes = COALESCE(_notes, admin_notes), reviewed_by = _admin, reviewed_at = now()
    WHERE id = _submission_id;

  ELSE
    RAISE EXCEPTION 'invalid_action: %', _action;
  END IF;

  RETURN jsonb_build_object('success', true, 'action', _action);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_review_updated_profile(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_review_updated_profile(uuid, text, text, text) TO authenticated;
