-- =====================================================================
-- ECOSYSTEM APPS — the in-dashboard application launcher.
--
-- Backs the STRDOME owners-dashboard app window. Each row is an application
-- elsewhere in the ecosystem that a member can open without leaving IgniteHeX.
--
-- WHAT THIS DELIBERATELY IS NOT: a proxy. The reference implementation this is
-- ported from routed every app through a server-side `/proxy?url=` endpoint and
-- rendered it inside an iframe on the dashboard's OWN origin. Three consequences
-- followed from that, and all three are the reason this table stores a plain URL
-- and nothing else:
--
--   1. `/proxy?url=` accepts an arbitrary URL and fetches it server-side. That
--      is a server-side request forgery primitive — on a cloud host it reaches
--      the instance metadata endpoint and anything else the server can route to.
--
--   2. A page served through that proxy runs as the dashboard's own origin, so
--      its JavaScript can read the dashboard's localStorage — where the Supabase
--      session token lives. One compromised ecosystem app would be account
--      takeover for every member who opened it.
--
--   3. It was framed with `allow="camera; microphone; geolocation; payment; …"`
--      and no sandbox, so that same code held the member's devices too.
--
-- Here the client frames the real, cross-origin URL directly under a restrictive
-- sandbox. `embeddable` records whether an app actually permits framing, because
-- many send X-Frame-Options: DENY — which is very likely why the proxy existed.
-- An app that will not frame is opened in a new tab instead, which is a smaller
-- loss than the alternative.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ecosystem_apps (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text,
  -- Stored as given and validated on the client against our own origin before
  -- framing. A same-origin URL under `allow-scripts allow-same-origin` escapes
  -- the sandbox, so that combination must never be reachable.
  url         text NOT NULL CHECK (url ~ '^https://'),
  icon        text,
  category    text NOT NULL DEFAULT 'general',
  -- FALSE means the app refuses to be framed (X-Frame-Options / CSP
  -- frame-ancestors) and must be opened in a new tab.
  embeddable  boolean NOT NULL DEFAULT true,
  -- NULL means every signed-in member may open it.
  requires_role public.app_role,
  sort_order  integer NOT NULL DEFAULT 100,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ecosystem_apps_active_idx ON public.ecosystem_apps (active, sort_order);

ALTER TABLE public.ecosystem_apps ENABLE ROW LEVEL SECURITY;

-- Members read the active apps they are entitled to. The role check is here as
-- well as in the UI because the UI only decides what to *offer*.
DROP POLICY IF EXISTS ecosystem_apps_select ON public.ecosystem_apps;
CREATE POLICY ecosystem_apps_select ON public.ecosystem_apps
  FOR SELECT TO authenticated
  USING (
    active
    AND (
      requires_role IS NULL
      OR EXISTS (SELECT 1 FROM public.user_roles r
                  WHERE r.user_id = auth.uid() AND r.role = ecosystem_apps.requires_role)
    )
  );

-- Admins see everything, including inactive rows they are about to publish.
DROP POLICY IF EXISTS ecosystem_apps_select_admin ON public.ecosystem_apps;
CREATE POLICY ecosystem_apps_select_admin ON public.ecosystem_apps
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- No INSERT/UPDATE/DELETE policy: writes go through the functions below, which
-- assert the caller themselves.

-- =====================================================================
-- Administration
-- =====================================================================
CREATE OR REPLACE FUNCTION public.upsert_ecosystem_app(
  p_slug text, p_name text, p_url text,
  p_description text DEFAULT NULL, p_icon text DEFAULT NULL,
  p_category text DEFAULT 'general', p_embeddable boolean DEFAULT true,
  p_requires_role public.app_role DEFAULT NULL,
  p_sort_order integer DEFAULT 100, p_active boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $ua$
DECLARE v_actor uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may manage ecosystem apps' USING ERRCODE = '42501';
  END IF;
  -- Enforced here as well as by the CHECK: an app reached over http:// would be
  -- framed inside an https page and its traffic is readable in transit.
  IF p_url !~ '^https://' THEN
    RAISE EXCEPTION 'An ecosystem app URL must be https' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.ecosystem_apps
    (slug, name, url, description, icon, category, embeddable, requires_role, sort_order, active)
  VALUES (p_slug, p_name, p_url, p_description, p_icon, p_category,
          p_embeddable, p_requires_role, p_sort_order, p_active)
  ON CONFLICT (slug) DO UPDATE
    SET name = EXCLUDED.name, url = EXCLUDED.url, description = EXCLUDED.description,
        icon = EXCLUDED.icon, category = EXCLUDED.category, embeddable = EXCLUDED.embeddable,
        requires_role = EXCLUDED.requires_role, sort_order = EXCLUDED.sort_order,
        active = EXCLUDED.active, updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id);
END $ua$;

REVOKE ALL ON FUNCTION public.upsert_ecosystem_app(text, text, text, text, text, text, boolean, public.app_role, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_ecosystem_app(text, text, text, text, text, text, boolean, public.app_role, integer, boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_ecosystem_app_active(p_slug text, p_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $sa$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may manage ecosystem apps' USING ERRCODE = '42501';
  END IF;
  UPDATE public.ecosystem_apps SET active = p_active, updated_at = now() WHERE slug = p_slug;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such ecosystem app' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('ok', true);
END $sa$;

REVOKE ALL ON FUNCTION public.set_ecosystem_app_active(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_ecosystem_app_active(text, boolean) TO authenticated, service_role;

-- =====================================================================
-- The known ecosystem. `embeddable` starts FALSE for everything: an app is
-- marked framable only once someone has confirmed it actually frames, rather
-- than assuming it does and showing members an empty window.
-- =====================================================================
INSERT INTO public.ecosystem_apps (slug, name, url, description, category, embeddable, sort_order)
VALUES
  ('strdome-shop', 'STRDOME Shop', 'https://shop.strdome.com',
   'Packages, upgrades and merchandise for domain holders.', 'commerce', false, 10),
  ('str-domains', 'str.domains', 'https://str.domains',
   'The registry that issues str.name identifiers.', 'identity', false, 20),
  ('strdome', 'strdome.com', 'https://strdome.com',
   'Connectivity and eSIM delivery for domain holders.', 'connectivity', false, 30),
  ('ccoin-finance', 'ccoin.finance', 'https://ccoin.finance',
   'The CCoin markets front end.', 'finance', false, 40),
  ('strtalk', 'STR Talk', 'https://strtalk.net',
   'Ecosystem messaging.', 'social', false, 50)
ON CONFLICT (slug) DO NOTHING;
