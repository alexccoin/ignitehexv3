
-- ============================================================================
-- FIX 1: Prevent privilege escalation via profiles.role self-update
-- ============================================================================
-- Replace the broad UPDATE policy with one that disallows changing role
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;

CREATE POLICY "Users can update their own profile"
ON public.profiles
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id
  AND role = (SELECT p.role FROM public.profiles p WHERE p.user_id = auth.uid())
);

-- Defense-in-depth: trigger blocks role changes by non-admins (covers SECURITY DEFINER paths too)
CREATE OR REPLACE FUNCTION public.prevent_profile_role_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
      RAISE EXCEPTION 'Changing profile role is not allowed';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_profile_role_self_update ON public.profiles;
CREATE TRIGGER trg_prevent_profile_role_self_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.prevent_profile_role_self_update();

-- ============================================================================
-- FIX 2: Repair broken admin policies on private_str_ipo_purchases
-- ============================================================================
DROP POLICY IF EXISTS "Admins can view all ipo purchases" ON public.private_str_ipo_purchases;
DROP POLICY IF EXISTS "Admins can update all ipo purchases" ON public.private_str_ipo_purchases;

CREATE POLICY "Admins can view all ipo purchases"
ON public.private_str_ipo_purchases
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update all ipo purchases"
ON public.private_str_ipo_purchases
FOR UPDATE
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- ============================================================================
-- FIX 3: Restrict guardian_margin_settings SELECT to admins only
-- ============================================================================
DROP POLICY IF EXISTS "Guardian users can view margin settings" ON public.guardian_margin_settings;

CREATE POLICY "Admins can view margin settings"
ON public.guardian_margin_settings
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- ============================================================================
-- FIX 4: Realtime channel authorization
-- ============================================================================
-- Restrict realtime.messages subscriptions: by default, deny; allow only when
-- topic is scoped to the authenticated user's id, or for admins.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
             WHERE n.nspname='realtime' AND c.relname='messages') THEN
    -- REPAIR: realtime.messages is owned by the realtime role on a local
    -- stack, so altering it aborts the migration. Hosted Supabase grants
    -- ownership, so this applies unchanged in a deployed project.
    IF NOT pg_catalog.pg_has_role(
             current_user,
             (SELECT relowner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname='realtime' AND c.relname='messages'),
             'USAGE') THEN
      RAISE NOTICE 'skipping realtime.messages RLS: not owner';
      RETURN;
    END IF;

    EXECUTE 'ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "authenticated_user_scoped_topics" ON realtime.messages';
    EXECUTE $p$
      CREATE POLICY "authenticated_user_scoped_topics"
      ON realtime.messages
      FOR SELECT
      TO authenticated
      USING (
        -- Allow topics that contain the user's UID (e.g. "user_staking_pools:<uid>")
        realtime.topic() LIKE '%' || auth.uid()::text || '%'
        -- Or admins (full visibility)
        OR public.has_role(auth.uid(), 'admin'::app_role)
        -- Or public chat room channel
        OR realtime.topic() = 'chat_messages:public'
      )
    $p$;
  END IF;
END $$;
