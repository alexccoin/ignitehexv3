import { lazy } from 'react';
import { ShieldAlert } from 'lucide-react';
import { defineDomain } from '@/domains/types';

/**
 * The risk console.
 *
 * Operations answers "what is waiting on an administrator". This domain answers
 * a different question: how much value is the platform carrying, how much of it
 * is backed by a decision somebody actually made, and what is strange about the
 * rest. The two do not overlap — nothing here decides a member request, and
 * nothing there touches a balance.
 *
 * v2 spread this surface over AdminVoucherRiskReview, SuperAdminBalanceAudit,
 * AdminBalanceStatus, AdminMissingAssets and AdminStakingManagement — five
 * pages, three of which wrote balances straight from the browser and one of
 * which (SuperAdminBalanceAudit) did so with no access check whatsoever. Here
 * the whole domain carries `requiresRole: 'admin'`, so the shell will not mount
 * a route or show a nav entry without it, and no screen in this directory
 * contains an access check of its own.
 *
 * Two invariants hold across every route:
 *
 *  - **Reads are read-only sweeps.** The exposure index and the risk radar
 *    touch no data; they page through the asset tables and value what they
 *    find.
 *  - **Writes are blocked by default.** Safe mode is armed unless an
 *    administrator has typed "PUSH TO BALANCES", every balance-affecting
 *    mutation re-checks that inside itself, and each action asks for the phrase
 *    again for that specific button.
 *
 * Routes are lazy so a console nobody opens is not in the entry chunk.
 */
export default defineDomain({
  id: 'admin',
  title: 'Risk console',
  basePath: '/admin',
  group: 'admin',
  requiresRole: 'admin',
  icon: ShieldAlert,
  order: 2,
  routes: [
    {
      path: '',
      navLabel: 'Overview',
      end: true,
      component: lazy(() => import('./Dashboard')),
    },
    {
      path: 'exposure',
      navLabel: 'Exposure',
      component: lazy(() => import('./Exposure')),
    },
    {
      path: 'risk',
      navLabel: 'Risk findings',
      component: lazy(() => import('./Risk')),
    },
    {
      path: 'vouchers',
      navLabel: 'Vouchers',
      component: lazy(() => import('./Vouchers')),
    },
    {
      path: 'corrections',
      navLabel: 'Corrections',
      component: lazy(() => import('./Corrections')),
    },
  ],
});

export * from './hooks';
export * from './lib/platformExposure';
export * from './lib/platformRiskScan';
export * from './lib/safeMode';
export * from './lib/valuation';
export * from './lib/paginate';
