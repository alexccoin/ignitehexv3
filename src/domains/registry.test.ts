import { describe, it, expect, vi } from 'vitest';

/**
 * Nav derivation.
 *
 * The property under test is one sentence: a member must never be offered a
 * link that 403s. It is asserted twice — once on the logic with fixtures, and
 * once as an invariant over the REAL registry, which is the version that keeps
 * holding as domains are added. A fixture-only test passes forever while
 * somebody adds a guarded route with a navLabel to a domain nobody thought
 * about.
 *
 * The mirror property matters just as much: an admin must still be offered the
 * links they can use. A filter that hides everything satisfies "no 403 links"
 * perfectly and makes the console unreachable.
 */

// The domain index modules re-export their hooks, which import the supabase
// client. Nothing here touches it; the mock keeps the registry a pure import.
vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: () => ({ select: () => ({ eq: () => Promise.resolve({ data: [], error: null }) }) }),
    rpc: () => Promise.resolve({ data: null, error: null }),
    functions: { invoke: () => Promise.resolve({ data: null, error: null }) },
    auth: { getSession: () => Promise.resolve({ data: { session: null } }) },
    channel: () => ({ on: () => ({ subscribe: () => ({}) }) }),
  },
  isLocal: true,
}));

import { DOMAINS, NAV_GROUPS, domainsForGroup, navSubRoutes } from './registry';
import type { DomainModule, AppRole } from './types';

/** A caller holding exactly these roles. */
const withRoles =
  (...roles: AppRole[]) =>
  (role: AppRole) =>
    roles.includes(role);

/** A plain signed-in member: the `user` role and nothing else. */
const member = withRoles('user');
const admin = withRoles('user', 'admin');

const ALL_ROLES: AppRole[] = [
  'admin',
  'user',
  'moderator',
  'support',
  'legal',
  'marketing',
  'arx',
  'seed_str_admin',
];

/* ------------------------------------------------------------------ */
/* domainsForGroup                                                     */
/* ------------------------------------------------------------------ */

describe('domainsForGroup', () => {
  it('offers a member no domain they cannot enter, in any group', () => {
    for (const { id: group } of NAV_GROUPS) {
      for (const domain of domainsForGroup(group, member)) {
        expect(domain.requiresRole, `${group}/${domain.id} is offered to a member`).toBeUndefined();
      }
    }
  });

  it('offers a member nothing at all in the Administration group', () => {
    const visible = domainsForGroup('admin', member);
    expect(visible.map((d) => d.id)).toEqual([]);
  });

  it('offers an admin the Administration group', () => {
    // The mirror of the test above. A filter that hides everything would pass
    // the first one and make the platform unadministrable.
    const visible = domainsForGroup('admin', admin);
    expect(visible.length).toBeGreaterThan(0);
    expect(visible.map((d) => d.id)).toContain('operations');
  });

  it('returns each domain in exactly the group it declared', () => {
    for (const { id: group } of NAV_GROUPS) {
      for (const d of domainsForGroup(group, () => true)) {
        expect(d.group).toBe(group);
      }
    }
  });

  it('shows every domain to a caller holding every role, and no domain twice', () => {
    const seen = NAV_GROUPS.flatMap(({ id }) => domainsForGroup(id, () => true)).map((d) => d.id);
    expect(new Set(seen).size).toBe(seen.length);
    expect(new Set(seen)).toEqual(new Set(DOMAINS.map((d) => d.id)));
  });

  it('orders by the declared order, with undeclared last', () => {
    const ordered = domainsForGroup('admin', () => true).map((d) => d.order ?? 99);
    expect(ordered).toEqual([...ordered].sort((a, b) => a - b));
  });

  it('asks about the role the domain declared, not a hardcoded one', () => {
    const asked: string[] = [];
    domainsForGroup('admin', (r) => {
      asked.push(r);
      return true;
    });
    for (const d of DOMAINS.filter((d) => d.group === 'admin' && d.requiresRole)) {
      expect(asked).toContain(d.requiresRole);
    }
  });
});

/* ------------------------------------------------------------------ */
/* navSubRoutes                                                        */
/* ------------------------------------------------------------------ */

describe('navSubRoutes', () => {
  const fixture: DomainModule = {
    id: 'fixture',
    title: 'Fixture',
    basePath: '/fixture',
    group: 'primary',
    icon: () => null,
    routes: [
      { path: '', navLabel: 'Mine', end: true, component: null as never },
      { path: 'ticket/:id', component: null as never }, // no navLabel: not a link
      { path: 'help', navLabel: 'Answers', component: null as never },
      { path: 'queue', navLabel: 'Staff queue', requiresRole: 'admin', component: null as never },
    ],
  };

  it('excludes a sub-route whose role the caller lacks', () => {
    const labels = navSubRoutes(fixture, member).map((r) => r.navLabel);
    expect(labels).toEqual(['Mine', 'Answers']);
    expect(labels).not.toContain('Staff queue');
  });

  it('includes it for a caller who holds the role', () => {
    const labels = navSubRoutes(fixture, admin).map((r) => r.navLabel);
    expect(labels).toEqual(['Mine', 'Answers', 'Staff queue']);
  });

  it('excludes a route with no navLabel even when the caller may enter it', () => {
    // A link to the literal path "ticket/:id" is v2's dead nav link.
    expect(navSubRoutes(fixture, admin).map((r) => r.path)).not.toContain('ticket/:id');
  });

  it('asks about the role the route declared', () => {
    const asked: string[] = [];
    navSubRoutes(fixture, (r) => {
      asked.push(r);
      return false;
    });
    expect(asked).toEqual(['admin']);
  });
});

/* ------------------------------------------------------------------ */
/* The invariant, over the real registry                               */
/* ------------------------------------------------------------------ */

describe('the real registry: no offered link may 403', () => {
  /** Every nav link a caller with these roles would be shown, with the guard
   *  that DomainRoutes will actually apply to its destination. */
  const offered = (hasRole: (r: AppRole) => boolean) =>
    NAV_GROUPS.flatMap(({ id }) => domainsForGroup(id, hasRole)).flatMap((domain) =>
      navSubRoutes(domain, hasRole).map((route) => ({
        to: route.path === '' ? domain.basePath : `${domain.basePath}/${route.path}`,
        // DomainRoutes.tsx wraps the whole domain in RequireRole when the
        // domain declares one, and each route in its own when the route does.
        // A link 403s if the caller fails EITHER.
        guards: [domain.requiresRole, route.requiresRole].filter(Boolean) as AppRole[],
      }))
    );

  it('a member is offered nothing that RequireRole would refuse', () => {
    for (const link of offered(member)) {
      expect(link.guards, `member was offered ${link.to}`).toEqual([]);
    }
  });

  it('specifically, a member is not offered the staff support queue', () => {
    // The concrete case the shell's own comment records. Naming it means the
    // test still says something if the general invariant is ever relaxed.
    const support = DOMAINS.find((d) => d.id === 'support');
    expect(support, 'the support domain has gone missing').toBeDefined();
    expect(navSubRoutes(support!, member).map((r) => r.path)).not.toContain('queue');
    expect(navSubRoutes(support!, admin).map((r) => r.path)).toContain('queue');
  });

  it('holds for every single role, not just member and admin', () => {
    for (const role of ALL_ROLES) {
      for (const link of offered(withRoles('user', role))) {
        for (const guard of link.guards) {
          expect(['user', role], `${role} was offered ${link.to}`).toContain(guard);
        }
      }
    }
  });

  it('offers a member at least something — the filter is not just "hide all"', () => {
    const links = offered(member);
    expect(links.length).toBeGreaterThan(0);
    expect(links.map((l) => l.to)).toContain('/support');
  });

  it('offers an admin strictly more than a member', () => {
    const memberLinks = new Set(offered(member).map((l) => l.to));
    const adminLinks = new Set(offered(admin).map((l) => l.to));
    for (const link of memberLinks) expect(adminLinks).toContain(link);
    expect(adminLinks.size).toBeGreaterThan(memberLinks.size);
  });

  it('every offered link resolves to a declared route — no dead links', () => {
    // v2 shipped four nav entries pointing at paths with no route, landing the
    // user on NotFound. Here the link is built from the route, so this asserts
    // the construction rather than a hand-maintained list.
    const declared = new Set(
      DOMAINS.flatMap((d) => d.routes.map((r) => (r.path === '' ? d.basePath : `${d.basePath}/${r.path}`)))
    );
    for (const link of offered(() => true)) {
      expect(declared, `${link.to} has no route`).toContain(link.to);
    }
  });

  it('no offered link contains a route parameter placeholder', () => {
    for (const link of offered(() => true)) {
      expect(link.to, `${link.to} is a link to a pattern, not a page`).not.toContain(':');
    }
  });

  it('every domain declares a basePath, a group and at least one route', () => {
    for (const d of DOMAINS) {
      expect(d.basePath, d.id).toMatch(/^\//);
      expect(NAV_GROUPS.map((g) => g.id), d.id).toContain(d.group);
      expect(d.routes.length, d.id).toBeGreaterThan(0);
    }
  });

  it('no two domains share a basePath or an id', () => {
    // Two domains on one basePath means one of them is unreachable, and the id
    // is the react-query key namespace — a collision crosses two domains' caches.
    const paths = DOMAINS.map((d) => d.basePath);
    const ids = DOMAINS.map((d) => d.id);
    expect(new Set(paths).size, paths.join(',')).toBe(paths.length);
    expect(new Set(ids).size, ids.join(',')).toBe(ids.length);
  });
});
