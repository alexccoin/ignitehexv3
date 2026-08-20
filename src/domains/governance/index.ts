import { lazy } from 'react';
import { Vote } from 'lucide-react';
import { defineDomain } from '@/domains/types';

/**
 * Governance.
 *
 * v2 spread this over four unrelated top-level routes (/governance, /arx-club,
 * /arx-application and a nested <Routes> inside ArxClub) with two different
 * layouts and two different access checks. Here it is one domain with three
 * routes, and the shell decides the layout and the guarding.
 *
 * No requiresRole on the domain or its routes: these screens serve applicants,
 * members and the board at once, and RLS already decides which rows each of
 * them sees. v2's ArxClub instead read user_roles in the page and rendered an
 * "Access Restricted" wall, which locked applicants out of the one screen that
 * would have told them where their application stood.
 */
export default defineDomain({
  id: 'governance',
  title: 'Governance',
  basePath: '/governance',
  group: 'community',
  icon: Vote,
  order: 1,
  routes: [
    {
      path: '',
      navLabel: 'Proposals',
      end: true,
      component: lazy(() => import('./Proposals')),
    },
    {
      path: 'arx',
      navLabel: 'ARX Club',
      component: lazy(() => import('./ArxClub')),
    },
    {
      path: 'treasury',
      navLabel: 'Treasury',
      component: lazy(() => import('./Treasury')),
    },
  ],
});
