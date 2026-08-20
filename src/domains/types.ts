import type { ComponentType, LazyExoticComponent } from 'react';
import type { Database } from '@/lib/database.types';

export type AppRole = Database['public']['Enums']['app_role'];

/**
 * The contract every product domain implements.
 *
 * v2 had no such contract: ~140 routes were declared by hand in one file, each
 * page invented its own layout, its own auth check and its own data access.
 * Adding a screen meant touching a 400-line router and hoping you remembered
 * the guard. Here a domain is a self-contained module that declares what it
 * needs, and the shell wires it up — so a domain cannot forget to be guarded,
 * and the nav cannot drift from the routes.
 */
export interface DomainRoute {
  /** Path relative to the domain's basePath. Use '' for the domain index. */
  path: string;
  component: LazyExoticComponent<ComponentType<unknown>>;
  /** Omit for any signed-in member; set to require a role. */
  requiresRole?: AppRole;
  /** Shown in the nav. Omit to route without a nav entry. */
  navLabel?: string;
  /** Exact-match the path for nav highlighting. */
  end?: boolean;
}

export interface DomainModule {
  /** Stable id, also used as the query-key namespace. */
  id: string;
  title: string;
  /** Mounted at this path; routes are nested beneath it. */
  basePath: string;
  icon: ComponentType<{ className?: string }>;
  /** Which nav group this appears under. */
  group: 'primary' | 'finance' | 'invest' | 'community' | 'admin';
  /** Hide the whole domain unless the user holds this role. */
  requiresRole?: AppRole;
  routes: DomainRoute[];
  /** Order within the group; lower is higher. */
  order?: number;
}

/** Narrow a value to a DomainModule at registration time. */
export function defineDomain(module: DomainModule): DomainModule {
  return module;
}
