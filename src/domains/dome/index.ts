import { lazy } from 'react';
import { Gem } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * The Dome domain: the member's ownership file.
 *
 * This is the port of the standalone Dome_Dashboard prototype. That prototype
 * was a plain Vite app carrying its own 4,069-line stylesheet and roughly two
 * hundred `dash-*` classes — a fifth design system on top of the four v2 had
 * already accumulated. None of it came across. Every panel here is rebuilt from
 * v3's semantic tokens and the shared primitives in `components/ui`, so the
 * Dome inherits the app's light and dark palettes rather than fighting them.
 *
 * The layout ideas did come across: the round banner, the welcome panel beside
 * a progress track, the tile row, the two-column body with the earnings column
 * on the right, the allocation table, and the modal anatomy of
 * header / summary strip / scrollable body / disclaimer.
 *
 * What did not come across is the prototype's data model, because it did not
 * have one. It hardcoded a single member — the domain `str.ilieslj1`, 31,250
 * shares, $50,000 invested, $93,750 in value, 0.094% of supply, +87.5% versus
 * public — into JSX, so every visitor saw one person's portfolio. Every figure
 * on these two screens is read from the signed-in member's own rows in
 * `safe_purchases`, `private_digital_shares_purchases`, `user_str_shares`,
 * `user_staking_pools`, `crypto_wallets`, `user_wallets`, `fiat_wallets`,
 * `vesting_tokens`, `v2_verified_assets` and `user_messages`, or is replaced by
 * an empty state naming what is missing. See the notes at the top of
 * Overview.tsx and Portfolio.tsx for each panel that was dropped rather than
 * invented.
 *
 * Routes are lazy so the Dome is not in the entry chunk.
 */
export default defineDomain({
  id: 'dome',
  title: 'Dome',
  basePath: '/dome',
  group: 'primary',
  icon: Gem,
  order: 2,
  routes: [
    {
      path: '',
      navLabel: 'Overview',
      end: true,
      component: lazy(() => import('./Overview')),
    },
    {
      path: 'portfolio',
      navLabel: 'Portfolio',
      component: lazy(() => import('./Portfolio')),
    },
  ],
});

export * from './hooks';
