
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'arx_voting_records') THEN
    DROP POLICY IF EXISTS "Admins can view all voting records" ON public.arx_voting_records;
    EXECUTE 'CREATE POLICY "Admins can view all voting records" ON public.arx_voting_records FOR SELECT TO authenticated USING (public.is_admin(auth.uid()))';
    DROP POLICY IF EXISTS "Voters can view their own voting records" ON public.arx_voting_records;
    EXECUTE 'CREATE POLICY "Voters can view their own voting records" ON public.arx_voting_records FOR SELECT TO authenticated USING (auth.uid() = voter_id)';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'github_integrations' AND column_name = 'access_token'
  ) THEN
    EXECUTE 'UPDATE public.github_integrations SET access_token = NULL WHERE access_token IS NOT NULL';

    CREATE OR REPLACE FUNCTION public.prevent_plaintext_github_token()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $fn$
    BEGIN
      IF NEW.access_token IS NOT NULL THEN
        NEW.access_token := NULL;
      END IF;
      RETURN NEW;
    END;
    $fn$;

    DROP TRIGGER IF EXISTS trg_prevent_plaintext_github_token ON public.github_integrations;
    CREATE TRIGGER trg_prevent_plaintext_github_token
      BEFORE INSERT OR UPDATE ON public.github_integrations
      FOR EACH ROW EXECUTE FUNCTION public.prevent_plaintext_github_token();
  END IF;
END $$;
