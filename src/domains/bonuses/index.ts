import { lazy } from 'react';
import { Gift } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The bonuses domain: vouchers, the airdrop, referrals and the affiliate
 * programme — everything the platform gives a member rather than sells them.
 *
 * v2 scattered this across nine top-level routes (`/referral-rewards`,
 * `/airdrop`, `/my-vouchers`, `/ccos-voucher-redeem`, `/vanquish-incentive`,
 * `/affiliate-signup`, `/ref/:code`, plus two admin components mounted inside
 * unrelated pages) with no shared model of what a reward was. A member could
 * not see what they had been given without visiting five screens, and the admin
 * surfaces credited balances directly from the browser.
 *
 * Here the four member screens read one ledger, and the single admin screen is
 * role-guarded by the shell and gated by SAFE MODE, which blocks every crediting
 * path until an operator types the release phrase in full.
 *
 * Every route is lazy, so none of this is in the entry chunk.
 */

const Overview = lazy(() => import('./Overview'));
const Vouchers = lazy(() => import('./Vouchers'));
const Referrals = lazy(() => import('./Referrals'));
const Airdrop = lazy(() => import('./Airdrop'));
const Admin = lazy(() => import('./Admin'));

export default defineDomain({
  id: 'bonuses',
  title: 'Rewards',
  basePath: '/rewards',
  group: 'invest',
  icon: Gift,
  order: 3,
  routes: [
    { path: '', component: Overview, navLabel: 'Overview', end: true },
    { path: 'vouchers', component: Vouchers, navLabel: 'Vouchers' },
    { path: 'referrals', component: Referrals, navLabel: 'Referrals' },
    { path: 'airdrop', component: Airdrop, navLabel: 'Airdrop' },
    {
      path: 'admin',
      component: Admin,
      navLabel: 'Review queue',
      requiresRole: 'admin',
    },
  ],
});

export * from './hooks';
export * from './constants';
export { SAFE_MODE_RELEASE_PHRASE, useSafeMode } from './safeMode';
