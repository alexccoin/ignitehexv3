CREATE TABLE IF NOT EXISTS public.v2_admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,
  entity_id uuid,
  account_id uuid,
  user_id uuid,
  action text NOT NULL,
  from_status text,
  to_status text,
  notes text,
  actor_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.v2_admin_actions TO authenticated;
GRANT ALL ON public.v2_admin_actions TO service_role;

ALTER TABLE public.v2_admin_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view v2 admin actions" ON public.v2_admin_actions;
CREATE POLICY "Admins can view v2 admin actions"
ON public.v2_admin_actions FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Members can view own v2 history" ON public.v2_admin_actions;
CREATE POLICY "Members can view own v2 history"
ON public.v2_admin_actions FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS v2_admin_actions_account_idx ON public.v2_admin_actions (account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS v2_admin_actions_entity_idx ON public.v2_admin_actions (entity_type, entity_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.v2_log_account_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.v2_admin_actions (entity_type, entity_id, account_id, user_id, action, to_status, actor_id, after_data)
    VALUES ('account', NEW.id, NEW.id, NEW.user_id, 'account_created', NEW.status, auth.uid(), to_jsonb(NEW));
    RETURN NEW;
  END IF;

  INSERT INTO public.v2_admin_actions (entity_type, entity_id, account_id, user_id, action, from_status, to_status, notes, actor_id, before_data, after_data)
  VALUES (
    'account', NEW.id, NEW.id, NEW.user_id,
    CASE WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'account_status_change' ELSE 'account_updated' END,
    OLD.status, NEW.status, NEW.review_notes, auth.uid(), to_jsonb(OLD), to_jsonb(NEW)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS v2_accounts_history ON public.v2_accounts;
CREATE TRIGGER v2_accounts_history
AFTER INSERT OR UPDATE ON public.v2_accounts
FOR EACH ROW EXECUTE FUNCTION public.v2_log_account_history();

CREATE OR REPLACE FUNCTION public.v2_log_claim_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.v2_admin_actions (entity_type, entity_id, account_id, user_id, action, to_status, notes, actor_id, after_data)
    VALUES ('asset_claim', NEW.id, NEW.account_id, NEW.user_id, 'claim_submitted', NEW.status, NEW.notes, auth.uid(), to_jsonb(NEW));
    RETURN NEW;
  END IF;

  INSERT INTO public.v2_admin_actions (entity_type, entity_id, account_id, user_id, action, from_status, to_status, notes, actor_id, before_data, after_data)
  VALUES (
    'asset_claim', NEW.id, NEW.account_id, NEW.user_id,
    CASE WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'claim_' || NEW.status ELSE 'claim_updated' END,
    OLD.status, NEW.status, NEW.review_notes, auth.uid(), to_jsonb(OLD), to_jsonb(NEW)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS v2_asset_claims_history ON public.v2_asset_claims;
CREATE TRIGGER v2_asset_claims_history
AFTER INSERT OR UPDATE ON public.v2_asset_claims
FOR EACH ROW EXECUTE FUNCTION public.v2_log_claim_history();