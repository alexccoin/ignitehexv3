import { lazy } from 'react';
import { TrendingUp } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The investments domain: seed rounds, private sales, vouchers, the airdrop,
 * referral rewards, founder positions and node holdings.
 *
 * v2 spread this across roughly two dozen top-level routes, each declared by
 * hand in a 400-line router and each responsible for guarding itself — which
 * the admin screens in this area did not do. Here the domain declares its
 * routes and the roles they need, and the shell wires them up, so the admin
 * queue cannot be reached by typing its path and the nav cannot drift from
 * what is actually mounted.
 *
 * Every route is lazy. v2 imported all of these statically, so a visitor
 * looking at the sign-in form downloaded the entire investment admin surface.
 */

const OfferingsPage = lazy(() => import('./OfferingsPage'));
const ApplicationsPage = lazy(() => import('./ApplicationsPage'));
const VouchersPage = lazy(() => import('./VouchersPage'));
const RewardsPage = lazy(() => import('./RewardsPage'));
const PositionsPage = lazy(() => import('./PositionsPage'));
const AdminPage = lazy(() => import('./AdminPage'));

export default defineDomain({
  id: 'investments',
  title: 'Investments',
  basePath: '/investments',
  group: 'invest',
  icon: TrendingUp,
  order: 2,
  routes: [
    { path: '', component: OfferingsPage, navLabel: 'Offerings', end: true },
    { path: 'applications', component: ApplicationsPage, navLabel: 'My applications' },
    { path: 'vouchers', component: VouchersPage, navLabel: 'Vouchers' },
    { path: 'rewards', component: RewardsPage, navLabel: 'Rewards' },
    { path: 'positions', component: PositionsPage, navLabel: 'Positions' },
    {
      path: 'admin',
      component: AdminPage,
      navLabel: 'Review queue',
      requiresRole: 'admin',
    },
  ],
});

export { ik } from './hooks';
