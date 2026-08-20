import { lazy } from 'react';
import { Wrench } from 'lucide-react';
import { defineDomain } from '@/domains/types';

/**
 * Operations.
 *
 * v2 had 38 pages beginning with "Admin" or "SuperAdmin", mounted
 * unconditionally, each responsible for checking its own access. Eight of them
 * — including SuperAdminBalanceAudit, which rewrote staking balances — checked
 * nothing at all, and the three that did check used three different mechanisms.
 *
 * Here the whole domain carries requiresRole: 'admin'. The shell will not mount
 * a route or show a nav entry without it, and no page in this directory
 * contains an access check of its own, so a new screen cannot be added without
 * one.
 */
export default defineDomain({
  id: 'operations',
  title: 'Operations',
  basePath: '/operations',
  group: 'admin',
  requiresRole: 'admin',
  icon: Wrench,
  order: 1,
  routes: [
    {
      path: '',
      navLabel: 'Overview',
      end: true,
      component: lazy(() => import('./OpsDashboard')),
    },
    {
      path: 'requests',
      navLabel: 'Requests',
      component: lazy(() => import('./Requests')),
    },
    {
      path: 'roles',
      navLabel: 'Roles',
      component: lazy(() => import('./Roles')),
    },
    {
      path: 'support',
      navLabel: 'Support',
      component: lazy(() => import('./Support')),
    },
    {
      path: 'reserves',
      navLabel: 'Reserves',
      component: lazy(() => import('./Reserves')),
    },
  ],
});
