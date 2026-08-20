import type { DomainModule } from './types';

import wallet from './wallet';
import staking from './staking';
import banking from './banking';
import marketplace from './marketplace';
import investments from './investments';
import governance from './governance';
import operations from './operations';
import dome from './dome';
import guardian from './guardian';
import bonuses from './bonuses';
import admin from './admin';
import support from './support';
import identity from './identity';
import migration from './migration';
import ecosystem from './ecosystem';

/**
 * Every product domain in the platform.
 *
 * This list is the only place a domain is switched on. The router mounts its
 * routes, the sidebar builds its nav, and the guards apply its role
 * requirements — all derived from the module itself, so the three can never
 * disagree. Adding a domain is one import and one array entry.
 *
 * v2 declared ~140 routes by hand in App.tsx and maintained the nav separately
 * in two sidebar components that had already drifted apart: one offered
 * admin+moderator entries, the other admin+seed_str_admin, and four nav links
 * pointed at paths with no route at all.
 */
export const DOMAINS: DomainModule[] = [
  wallet,
  staking,
  banking,
  marketplace,
  investments,
  governance,
  operations,
  dome,
  guardian,
  bonuses,
  admin,
  support,
  identity,
  migration,
  ecosystem,
];

export const NAV_GROUPS: { id: DomainModule['group']; label: string }[] = [
  { id: 'primary', label: '' },
  { id: 'finance', label: 'Finance' },
  { id: 'invest', label: 'Invest' },
  { id: 'community', label: 'Community' },
  { id: 'admin', label: 'Administration' },
];

/** What the nav needs to know about the caller. */
export type HasRole = (role: NonNullable<DomainModule['requiresRole']>) => boolean;

/** Domains in a group, ordered, filtered to what this user may see. */
export function domainsForGroup(
  group: DomainModule['group'],
  hasRole: HasRole
): DomainModule[] {
  return DOMAINS.filter((d) => d.group === group)
    .filter((d) => !d.requiresRole || hasRole(d.requiresRole))
    .sort((a, b) => (a.order ?? 99) - (b.order ?? 99));
}

/**
 * The sub-routes of one domain that this user may both see and enter.
 *
 * Two conditions, and dropping either one produces a real defect:
 *
 *  - `navLabel` — a route without one has no link text. `support`'s
 *    `ticket/:id` is the case in point: a nav entry for it would have to link
 *    to the literal path "ticket/:id", which is v2's dead-nav-link bug.
 *  - `requiresRole` — the shell filtered on `navLabel` alone, so a member
 *    browsing /support was offered a "Staff queue" link that answered 403.
 *    `support` is the first domain to mix guarded and unguarded routes under
 *    one basePath, which is why nothing had hit it before.
 *
 * It lives here rather than inside AppShell so the rule is testable on its own
 * and so a second nav component cannot reimplement it differently — which is
 * exactly how v2's two sidebars came to disagree.
 */
export function navSubRoutes(domain: DomainModule, hasRole: HasRole): DomainModule['routes'] {
  return domain.routes.filter((r) => r.navLabel && (!r.requiresRole || hasRole(r.requiresRole)));
}
