import { lazy } from 'react';
import { Store } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The marketplace domain: STR domain and token listings, the seller flow, STR
 * domain management and the merchant portal.
 *
 * Every route is code-split. v2 imported all ~140 pages statically, so a
 * visitor downloaded the merchant portal to look at a domain listing.
 *
 * A note on what this module deliberately does not do. Migration
 * 20260509121934 revoked user-level writes on `user_staking_pools` and added
 * atomic, service-role RPCs to replace them; v2 called none of them and kept
 * doing read-modify-write from the browser, which RLS silently discarded. The
 * only balance-moving call in this domain is `marketplace_escrow_lock`, used
 * once, when tokens go into escrow; it posts both legs of the transfer through
 * the ledger primitive (F-032). Every other money action — releasing
 * escrow, settling a token sale, accepting a bid, POS charges, IBAN issuance,
 * outbound transfers — is rendered disabled with the reason on screen and a
 * TODO naming the server function it needs. See Sell.tsx, Browse.tsx,
 * Merchant.tsx and Activity.tsx.
 */
export default defineDomain({
  id: 'marketplace',
  title: 'Marketplace',
  basePath: '/marketplace',
  group: 'invest',
  icon: Store,
  order: 1,
  routes: [
    {
      path: '',
      end: true,
      navLabel: 'Browse',
      component: lazy(() => import('./Browse')),
    },
    {
      path: 'sell',
      navLabel: 'Sell',
      component: lazy(() => import('./Sell')),
    },
    {
      path: 'domains',
      navLabel: 'STR domains',
      component: lazy(() => import('./Domains')),
    },
    {
      path: 'esim',
      navLabel: 'str.dome eSIM',
      component: lazy(() => import('./Esim')),
    },
    {
      path: 'merchant',
      navLabel: 'Merchant',
      component: lazy(() => import('./Merchant')),
    },
    {
      path: 'activity',
      navLabel: 'Activity',
      component: lazy(() => import('./Activity')),
    },
  ],
});
