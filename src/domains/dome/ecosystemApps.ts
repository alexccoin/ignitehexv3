import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';

/**
 * The ecosystem app launcher's data, and the one safety rule it turns on.
 *
 * Apps are opened by framing their real URL cross-origin under a restrictive
 * sandbox. The reference implementation instead proxied every app through the
 * dashboard's own origin, which put third-party JavaScript on the same origin
 * as the Supabase session token. See the migration 20260820140000 for why that
 * is not repeated here.
 *
 * `canFrame` below is what makes the sandbox meaningful, so it lives beside the
 * data rather than inside a component where a refactor could drop it.
 */

type Row = Database['public']['Tables']['ecosystem_apps']['Row'];

export type EcosystemApp = Pick<
  Row,
  'id' | 'slug' | 'name' | 'description' | 'url' | 'icon' | 'category' | 'embeddable' | 'sort_order'
>;

const APP_COLS = 'id, slug, name, description, url, icon, category, embeddable, sort_order';

/**
 * Whether this URL may be put in a sandboxed iframe.
 *
 * The sandbox we use is `allow-scripts allow-same-origin`. For CROSS-origin
 * content that pair is safe: the frame keeps its own origin, which is what lets
 * the app log in and use its own storage, and it still cannot read ours.
 *
 * For SAME-origin content the same pair is an escape hatch — the frame gets our
 * origin *and* scripts, so it can reach into this document, read localStorage
 * and take the session. So a same-origin URL is refused outright rather than
 * framed with a weaker sandbox, because a weaker sandbox breaks every real app
 * and the temptation would be to widen it again later.
 *
 * Anything that is not parseable, not https, or not cross-origin opens in a new
 * tab instead.
 *
 * `selfOrigin` is injectable ONLY so the same-origin rule can be tested. The
 * test environment serves over http, so a test that relied on the real
 * `window.location.origin` could never construct a same-origin *https* URL —
 * every such case would be refused by the protocol check above and the origin
 * comparison would go unexercised. That version of this test passed with the
 * origin check deleted, which is the failure mode this parameter exists to
 * remove. Production callers pass nothing.
 */
export function canFrame(rawUrl: string, selfOrigin?: string): boolean {
  let u: URL;
  try {
    u = new URL(rawUrl);
  } catch {
    return false;
  }
  if (u.protocol !== 'https:') return false;

  // Resolved rather than hardcoded: this must hold on localhost, on the Netlify
  // URL and on any future domain without an edit.
  const origin =
    selfOrigin ?? (typeof window !== 'undefined' ? window.location.origin : undefined);
  if (origin && u.origin === origin) return false;
  return true;
}

/** The apps this member may open. RLS decides which rows come back. */
export function useEcosystemApps() {
  return useQuery({
    queryKey: ['dome', 'ecosystem-apps'],
    queryFn: async (): Promise<EcosystemApp[]> => {
      const { data, error } = await supabase
        .from('ecosystem_apps')
        .select(APP_COLS)
        .order('sort_order')
        .order('name');
      if (error) throw error;
      return data ?? [];
    },
  });
}
