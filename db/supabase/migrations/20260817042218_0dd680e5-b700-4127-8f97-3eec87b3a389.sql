-- ============ V2 ACCOUNT SYSTEM (no data import; user re-confirmation + admin verification) ============

CREATE TABLE public.v2_accounts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'draft',
  email TEXT,
  email_confirmed_at TIMESTAMPTZ,
  full_name TEXT,
  date_of_birth DATE,
  nationality TEXT,
  country_of_residence TEXT,
  address_line1 TEXT,
  address_line2 TEXT,
  city TEXT,
  postal_code TEXT,
  phone TEXT,
  str_domain TEXT,
  id_document_type TEXT,
  id_document_number TEXT,
  investor_classification TEXT,
  source_of_funds TEXT,
  source_of_wealth TEXT,
  pep_status BOOLEAN NOT NULL DEFAULT false,
  sanctions_declaration BOOLEAN NOT NULL DEFAULT false,
  tax_residency TEXT,
  tax_identification_number TEXT,
  risk_acknowledged BOOLEAN NOT NULL DEFAULT false,
  mica_terms_accepted BOOLEAN NOT NULL DEFAULT false,
  mica_terms_version TEXT,
  assets_declared_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID,
  review_notes TEXT,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT v2_accounts_status_chk CHECK (status IN ('draft','submitted','under_review','approved','rejected','suspended','closed'))
);

GRANT SELECT, INSERT, UPDATE ON public.v2_accounts TO authenticated;
GRANT ALL ON public.v2_accounts TO service_role;
ALTER TABLE public.v2_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v2_accounts own select" ON public.v2_accounts FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "v2_accounts own insert" ON public.v2_accounts FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'draft');
CREATE POLICY "v2_accounts own update" ON public.v2_accounts FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status IN ('draft','rejected'))
  WITH CHECK (user_id = auth.uid() AND status IN ('draft','submitted'));
CREATE POLICY "v2_accounts admin update" ON public.v2_accounts FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- Block users from self-approving / tampering with review fields
CREATE OR REPLACE FUNCTION public.v2_accounts_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    NEW.reviewed_at := OLD.reviewed_at;
    NEW.reviewed_by := OLD.reviewed_by;
    NEW.review_notes := OLD.review_notes;
    NEW.rejection_reason := OLD.rejection_reason;
    NEW.email_confirmed_at := OLD.email_confirmed_at;
    IF NEW.status NOT IN ('draft','submitted') THEN
      RAISE EXCEPTION 'Only administrators can set account status to %', NEW.status;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER v2_accounts_guard_trg BEFORE UPDATE ON public.v2_accounts
  FOR EACH ROW EXECUTE FUNCTION public.v2_accounts_guard();

-- ============ ASSET DECLARATIONS (user claims, admin verifies) ============
CREATE TABLE public.v2_asset_claims (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES public.v2_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  category TEXT NOT NULL,
  asset_symbol TEXT NOT NULL,
  asset_label TEXT,
  claimed_amount NUMERIC NOT NULL DEFAULT 0,
  verified_amount NUMERIC,
  reference TEXT,
  evidence_url TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID,
  review_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT v2_asset_claims_category_chk CHECK (category IN ('token','fiat','str_domain','node','banking','card','equity','other')),
  CONSTRAINT v2_asset_claims_status_chk CHECK (status IN ('pending','approved','rejected'))
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.v2_asset_claims TO authenticated;
GRANT ALL ON public.v2_asset_claims TO service_role;
ALTER TABLE public.v2_asset_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v2_claims select" ON public.v2_asset_claims FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "v2_claims insert" ON public.v2_asset_claims FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'pending' AND verified_amount IS NULL);
CREATE POLICY "v2_claims own update" ON public.v2_asset_claims FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending')
  WITH CHECK (user_id = auth.uid() AND status = 'pending');
CREATE POLICY "v2_claims own delete" ON public.v2_asset_claims FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');
CREATE POLICY "v2_claims admin update" ON public.v2_asset_claims FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

CREATE OR REPLACE FUNCTION public.v2_asset_claims_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    NEW.verified_amount := OLD.verified_amount;
    NEW.status := OLD.status;
    NEW.reviewed_at := OLD.reviewed_at;
    NEW.reviewed_by := OLD.reviewed_by;
    NEW.review_notes := OLD.review_notes;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER v2_asset_claims_guard_trg BEFORE UPDATE ON public.v2_asset_claims
  FOR EACH ROW EXECUTE FUNCTION public.v2_asset_claims_guard();

-- ============ VERIFIED ASSET LEDGER (admin/service only writes) ============
CREATE TABLE public.v2_verified_assets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES public.v2_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  claim_id UUID REFERENCES public.v2_asset_claims(id) ON DELETE SET NULL,
  category TEXT NOT NULL,
  asset_symbol TEXT NOT NULL,
  asset_label TEXT,
  amount NUMERIC NOT NULL DEFAULT 0,
  reference TEXT,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.v2_verified_assets TO authenticated;
GRANT ALL ON public.v2_verified_assets TO service_role;
ALTER TABLE public.v2_verified_assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v2_verified select" ON public.v2_verified_assets FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "v2_verified admin all" ON public.v2_verified_assets FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- ============ SERVICE CONNECTIONS ============
CREATE TABLE public.v2_service_connections (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES public.v2_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  service TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'not_connected',
  external_reference TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  requested_at TIMESTAMPTZ,
  connected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, service),
  CONSTRAINT v2_service_chk CHECK (service IN ('str_domains','str_dome','ccoin_finance','ccoin_bank','offshore_banking','onshore_banking')),
  CONSTRAINT v2_service_status_chk CHECK (status IN ('not_connected','requested','pending_review','connected','rejected','suspended'))
);

GRANT SELECT, INSERT, UPDATE ON public.v2_service_connections TO authenticated;
GRANT ALL ON public.v2_service_connections TO service_role;
ALTER TABLE public.v2_service_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v2_conn select" ON public.v2_service_connections FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "v2_conn insert" ON public.v2_service_connections FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status IN ('not_connected','requested'));
CREATE POLICY "v2_conn own update" ON public.v2_service_connections FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status IN ('not_connected','rejected'))
  WITH CHECK (user_id = auth.uid() AND status IN ('not_connected','requested'));
CREATE POLICY "v2_conn admin update" ON public.v2_service_connections FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

CREATE OR REPLACE FUNCTION public.v2_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;

CREATE TRIGGER v2_conn_touch BEFORE UPDATE ON public.v2_service_connections
  FOR EACH ROW EXECUTE FUNCTION public.v2_touch_updated_at();
CREATE TRIGGER v2_verified_touch BEFORE UPDATE ON public.v2_verified_assets
  FOR EACH ROW EXECUTE FUNCTION public.v2_touch_updated_at();

CREATE INDEX v2_accounts_status_idx ON public.v2_accounts(status);
CREATE INDEX v2_claims_status_idx ON public.v2_asset_claims(status);
CREATE INDEX v2_claims_user_idx ON public.v2_asset_claims(user_id);
CREATE INDEX v2_verified_user_idx ON public.v2_verified_assets(user_id);
CREATE INDEX v2_conn_user_idx ON public.v2_service_connections(user_id);

-- ============ ADMIN: approve a claim and post it to the verified ledger ============
CREATE OR REPLACE FUNCTION public.v2_review_asset_claim(
  p_claim_id UUID,
  p_approve BOOLEAN,
  p_verified_amount NUMERIC DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_claim public.v2_asset_claims%ROWTYPE; v_amount NUMERIC;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT * INTO v_claim FROM public.v2_asset_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Claim not found'); END IF;

  IF p_approve THEN
    v_amount := COALESCE(p_verified_amount, v_claim.claimed_amount);
    UPDATE public.v2_asset_claims
      SET status='approved', verified_amount=v_amount, reviewed_at=now(), reviewed_by=auth.uid(), review_notes=p_notes
      WHERE id = p_claim_id;

    DELETE FROM public.v2_verified_assets WHERE claim_id = p_claim_id;
    INSERT INTO public.v2_verified_assets(account_id, user_id, claim_id, category, asset_symbol, asset_label, amount, reference, verified_by)
    VALUES (v_claim.account_id, v_claim.user_id, v_claim.id, v_claim.category, v_claim.asset_symbol, v_claim.asset_label, v_amount, v_claim.reference, auth.uid());
  ELSE
    UPDATE public.v2_asset_claims
      SET status='rejected', verified_amount=NULL, reviewed_at=now(), reviewed_by=auth.uid(), review_notes=p_notes
      WHERE id = p_claim_id;
    DELETE FROM public.v2_verified_assets WHERE claim_id = p_claim_id;
  END IF;

  RETURN jsonb_build_object('success', true);
END; $$;

-- ============ ADMIN: set account status ============
CREATE OR REPLACE FUNCTION public.v2_review_account(
  p_account_id UUID,
  p_status TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;
  IF p_status NOT IN ('under_review','approved','rejected','suspended','closed') THEN
    RAISE EXCEPTION 'Invalid status %', p_status;
  END IF;

  UPDATE public.v2_accounts
    SET status = p_status,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        review_notes = p_notes,
        rejection_reason = CASE WHEN p_status = 'rejected' THEN p_notes ELSE rejection_reason END
    WHERE id = p_account_id;

  RETURN jsonb_build_object('success', true);
END; $$;