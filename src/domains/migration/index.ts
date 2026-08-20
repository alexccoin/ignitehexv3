import { lazy } from 'react';
import { ArrowLeftRight } from 'lucide-react';
import { defineDomain } from '../types';

/**
 * MIGRATION — the review console for accounts carried over from the legacy
 * platform.
 *
 * Admin-only, and deliberately not shown to members. A migrating member does
 * not need a screen in the navigation: what they need is to know their figures
 * are held, which the quarantine banner tells them on every page. Adding a nav
 * entry would put a permanent item in front of every migrated member for a
 * state that is temporary by design.
 */
export default defineDomain({
  id: 'migration',
  title: 'Migration review',
  basePath: '/migration',
  group: 'admin',
  icon: ArrowLeftRight,
  requiresRole: 'admin',
  order: 3,
  routes: [
    {
      path: '',
      end: true,
      component: lazy(() => import('./Review')),
    },
  ],
});

export * from './hooks';
