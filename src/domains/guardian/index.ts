import { lazy } from 'react';
import { ShieldCheck } from 'lucide-react';
import { defineDomain } from '@/domains/types';

/**
 * Ares Guardian — the custody vault, its reserves and the requests against it.
 *
 * v2 spread this over `AresGuardian`, `ProofOfReserve`, `ClientSettlements`,
 * `LiquidityNodeBTC002`, `AdminAresGuardian` and twenty-two components under
 * `components/guardian/`, and protected all of it with
 * `AresGuardianPasswordGate`: one shared password, typed into a form, checked
 * by an edge function, after which the page set `authenticated = true` in React
 * state and rendered everything. That is not access control — it is a
 * doorbell. Anyone holding the string held the vault, the string could not be
 * revoked per person, and the check lived entirely in the browser.
 *
 * Here the door is `requiresRole`. The shell will not mount a route or show a
 * nav entry without it, so no screen in this directory contains an access check
 * of its own and none can forget one. `admin` is the role every RLS policy on
 * the eight `guardian_*` tables actually names — the member-facing policies are
 * `user_id = auth.uid()` and the operator-facing ones are
 * `has_role(auth.uid(), 'admin')` — so gating on anything else would put people
 * in front of screens the database would then return nothing for. There is no
 * `guardian` app_role to gate on; if guardian membership should become a role
 * of its own, this one line is where it changes.
 *
 * Rows are still decided by RLS underneath, not by the guard: the queries in
 * `hooks.ts` do not filter by `user_id`, because the policies already scope a
 * member to their own wallets and an operator to the whole book.
 *
 * Routes are lazy so the vault is not in the entry chunk.
 */
export default defineDomain({
  id: 'guardian',
  title: 'Ares Guardian',
  basePath: '/guardian',
  group: 'community',
  icon: ShieldCheck,
  order: 2,
  requiresRole: 'admin',
  routes: [
    {
      path: '',
      navLabel: 'Vault',
      end: true,
      component: lazy(() => import('./VaultOverview')),
    },
    {
      path: 'reserves',
      navLabel: 'Proof of reserve',
      component: lazy(() => import('./Reserves')),
    },
    {
      path: 'withdrawals',
      navLabel: 'Withdrawals',
      component: lazy(() => import('./Withdrawals')),
    },
    {
      path: 'alerts',
      navLabel: 'Alerts',
      component: lazy(() => import('./Alerts')),
    },
  ],
});

export * from './hooks';
