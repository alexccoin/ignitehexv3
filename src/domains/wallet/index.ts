import { lazy } from 'react';
import { Wallet } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The wallet domain.
 *
 * v2 spread this surface over `WalletPage`, `IbanManagement`, `DomeWallet` and
 * eighteen components under `components/wallet/`, each fetching its own copy of
 * the same balances and each disagreeing about what a balance was. Here the
 * four screens share one set of hooks, one balance definition and one activity
 * ledger, and the shell mounts them from this declaration rather than from a
 * hand-maintained router.
 *
 * Routes are lazy so the wallet is not in the entry chunk.
 */
export default defineDomain({
  id: 'wallet',
  title: 'Wallet',
  basePath: '/wallet',
  icon: Wallet,
  group: 'finance',
  order: 1,
  routes: [
    {
      path: '',
      navLabel: 'Overview',
      end: true,
      component: lazy(() => import('./Overview')),
    },
    {
      path: 'transfers',
      navLabel: 'Transfers',
      component: lazy(() => import('./Transfers')),
    },
    {
      path: 'activity',
      navLabel: 'Activity',
      component: lazy(() => import('./Activity')),
    },
    {
      path: 'accounts',
      navLabel: 'Accounts',
      component: lazy(() => import('./Accounts')),
    },
  ],
});

export * from './hooks';
export * from './ledger';
