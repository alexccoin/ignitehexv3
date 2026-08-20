import { lazy } from 'react';
import { Coins } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The staking domain.
 *
 * v2 spread this surface over five hand-registered routes in a 400-line router
 * — `/staking`, `/staking-history`, `/staking-withdrawals`,
 * `/admin-staking-management`, `/admin-staking-distribution` — and the two
 * admin screens were mounted with no role check at all, each page being trusted
 * to redirect itself. Here the domain declares `requiresRole: 'admin'` on the
 * management route and the shell enforces it, so the guard cannot be forgotten.
 *
 * Every route is lazy: an admin console is not part of what a member downloads.
 */

const StakingPositions = lazy(() => import('./StakingPositions'));
const StakingHistory = lazy(() => import('./StakingHistory'));
const StakingWithdrawals = lazy(() => import('./StakingWithdrawals'));
const StakingManage = lazy(() => import('./StakingManage'));

export const stakingDomain = defineDomain({
  id: 'staking',
  title: 'Staking',
  basePath: '/staking',
  group: 'finance',
  icon: Coins,
  order: 2,
  routes: [
    {
      path: '',
      component: StakingPositions,
      navLabel: 'Positions',
      end: true,
    },
    {
      path: 'history',
      component: StakingHistory,
      navLabel: 'History',
    },
    {
      path: 'withdrawals',
      component: StakingWithdrawals,
      navLabel: 'Withdrawals',
    },
    {
      path: 'manage',
      component: StakingManage,
      navLabel: 'Pool management',
      requiresRole: 'admin',
    },
  ],
});

export default stakingDomain;

export * from './hooks';
export * from './constants';
