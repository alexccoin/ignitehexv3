import { lazy } from 'react';
import { Landmark } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The banking domain: CCoin Bank, IBANs, cards and settlement.
 *
 * In v2 this surface was seven top-level pages wired by hand into a 400-line
 * router, each doing its own auth check — CCoinBank.tsx alone read the session,
 * looked up the admin role and decided whether to render the product or a
 * marketing page, all inside the component. Here the module declares its routes
 * and the shell guards them; the admin queue is unreachable without the role
 * because the route says so, not because a page remembered to check.
 *
 * Every route is lazy. v2 imported all of these statically, so a visitor who
 * never applied for a bank account still downloaded the approvals console.
 */
export const bankingDomain = defineDomain({
  id: 'banking',
  title: 'Banking',
  basePath: '/banking',
  group: 'finance',
  icon: Landmark,
  order: 3,
  routes: [
    {
      path: '',
      component: lazy(() => import('./BankOverview')),
      navLabel: 'Bank',
      end: true,
    },
    {
      path: 'accounts',
      component: lazy(() => import('./Accounts')),
      navLabel: 'Accounts',
    },
    {
      path: 'cards',
      component: lazy(() => import('./Cards')),
      navLabel: 'Cards',
    },
    {
      path: 'transfers',
      component: lazy(() => import('./Transfers')),
      navLabel: 'Transfers',
    },
    {
      path: 'apply',
      component: lazy(() => import('./Apply')),
      navLabel: 'Apply',
    },
    {
      path: 'admin',
      component: lazy(() => import('./Admin')),
      navLabel: 'Approvals',
      requiresRole: 'admin',
    },
  ],
});

export default bankingDomain;
