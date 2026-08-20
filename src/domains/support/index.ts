import { lazy } from 'react';
import { LifeBuoy } from 'lucide-react';
import { defineDomain } from '@/domains/types';

/**
 * Support.
 *
 * v2 had no support domain. What it had was a floating help widget on the
 * dashboard, a "report a problem" form in the profile screen, a third form in
 * banking, and an admin console at AdminSupportTickets that wrote
 * member_support_tickets directly while a second console decided the same rows
 * through the RPC. A member who sent something had nowhere to see what had
 * become of it, which made "did you get my message?" the most common thing the
 * platform was asked.
 *
 * Here the member side and the staff side are one domain with one set of hooks,
 * because they are two views of the same rows and the commonest support bug is
 * the two views disagreeing.
 *
 * The domain itself carries no `requiresRole` — every signed-in member needs
 * the first three routes. Only `queue` is guarded, and it is guarded here in
 * the declaration rather than inside the page, so the screen cannot be reached
 * by a member who types the URL and cannot forget to check.
 *
 * A caution for whoever wires this into the registry: `DomainNav` in
 * AppShell.tsx builds its sub-route links from `route.navLabel` alone and does
 * not consult `route.requiresRole`, so a member browsing /support will see a
 * "Staff queue" link that sends them to /forbidden. This is the first domain to
 * mix guarded and unguarded routes, so nothing has hit it before. The fix is
 * one predicate in the shell, not a missing navLabel here.
 */
export default defineDomain({
  id: 'support',
  title: 'Support',
  basePath: '/support',
  group: 'primary',
  icon: LifeBuoy,
  order: 3,
  routes: [
    {
      path: '',
      navLabel: 'My tickets',
      end: true,
      component: lazy(() => import('./MyTickets')),
    },
    {
      // No navLabel: a nav entry for this would have to link to the literal
      // path "ticket/:id", which is the dead-nav-link bug AppShell's own
      // comment records from v2. It is reached from the ticket list.
      path: 'ticket/:id',
      component: lazy(() => import('./TicketDetail')),
    },
    {
      path: 'help',
      navLabel: 'Answers',
      component: lazy(() => import('./Help')),
    },
    {
      path: 'queue',
      navLabel: 'Staff queue',
      requiresRole: 'admin',
      component: lazy(() => import('./Queue')),
    },
  ],
});

export * from './hooks';
