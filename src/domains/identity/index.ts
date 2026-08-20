import { lazy } from 'react';
import { Fingerprint } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * MULTILOGIN — the identity domain.
 *
 * IgniteHeX is the identity provider for a family of properties: str.domains,
 * strdome.com, ccoin.finance and CCoin Bank. A member signs in here, once, and
 * every other property is reached through a *link* from that one identity —
 * `v2_service_connections`, one row per (member, service), hanging off the
 * member's `v2_accounts` record.
 *
 * What this domain deliberately does not contain:
 *
 *  - a second sign-in form. There is one identity and one password, and it is
 *    the one that got the member here.
 *  - any external credential. `str_domain_connections.api_key` exists and RLS
 *    hands it to the owning member's browser; no query in this domain selects
 *    it. See DOMAIN_LINK_COLS in hooks.ts and F-020 in docs/FINDINGS.md.
 *  - any path from the browser to `connected`. A member may raise a request;
 *    the database refuses them the grant. Verified, not assumed.
 *
 * Routes are lazy, so a member who never opens this screen does not download
 * the review console.
 */
export default defineDomain({
  id: 'identity',
  title: 'Connected accounts',
  basePath: '/identity',
  group: 'primary',
  icon: Fingerprint,
  order: 4,
  routes: [
    {
      path: '',
      navLabel: 'Properties',
      end: true,
      component: lazy(() => import('./Connections')),
    },
    {
      path: 'activity',
      navLabel: 'Activity',
      component: lazy(() => import('./Activity')),
    },
    {
      path: 'admin',
      navLabel: 'Review queue',
      requiresRole: 'admin',
      component: lazy(() => import('./Review')),
    },
  ],
});

export * from './hooks';
export * from './properties';
