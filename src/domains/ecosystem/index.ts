import { lazy } from 'react';
import { Globe } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * ECOSYSTEM — what SourceLess is, drawn from the published overview.
 *
 * Top-level rather than nested under Dome, because it describes the whole
 * ecosystem this platform sits inside, not the STRDOME owners' view of it.
 *
 * The reconciliation route is deliberately a peer of the map, not a footnote
 * inside it: the places where the source document disagrees with itself or with
 * this database are the most useful thing on the screen, and burying them at
 * the bottom of a long page would defeat the purpose.
 */
export default defineDomain({
  id: 'ecosystem',
  title: 'Ecosystem',
  basePath: '/ecosystem',
  group: 'primary',
  icon: Globe,
  order: 3,
  routes: [
    {
      path: '',
      navLabel: 'Map',
      end: true,
      component: lazy(() => import('./Overview')),
    },
    {
      path: 'reconciliation',
      navLabel: 'Reconciliation',
      component: lazy(() => import('./Reconciliation')),
    },
  ],
});

export * from './hooks';
