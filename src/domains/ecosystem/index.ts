import { lazy } from 'react';
import { Globe } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * ECOSYSTEM — what SourceLess is, drawn from the published overview.
 *
 * Top-level rather than nested under Dome, because it describes the whole
 * ecosystem this platform sits inside, not the STRDOME owners' view of it.
 *
 * The reconciliation surface — every point where the overview disagrees with
 * itself or with this database, with the verdicts and the probe evidence — is
 * built and its data is loaded, but it is NOT routed. Re-enabling it is one
 * entry in the array below; the component, the hook and the tables are all
 * still here and still current.
 *
 * Nothing about the map depends on it. The chain panel makes its own statement
 * from this deployment's own configuration rather than deferring to that page.
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
      end: true,
      component: lazy(() => import('./Overview')),
    },
  ],
});

export * from './hooks';
