import { Route } from 'react-router-dom';
import type { DomainModule } from '@/domains/types';
import { RequireRole } from './guards';

/**
 * Turn a domain module into mounted routes.
 *
 * Role requirements are applied here from the declaration, so a route is
 * guarded because it said it needed a role — not because someone remembered to
 * add a check inside the page. v2 relied on the latter and 8 admin pages had no
 * check at all.
 *
 * Returns an array of <Route> elements rather than a component, because
 * react-router only accepts Route elements as children of <Routes>.
 */
export function domainRoutes(domain: DomainModule) {
  const children = domain.routes.map((route) => {
    const element = <route.component />;

    // A role on the individual route wraps just that route. A role on the whole
    // domain is applied once, around all of them, below.
    const guarded = route.requiresRole ? (
      <RequireRole role={route.requiresRole}>{element}</RequireRole>
    ) : (
      element
    );

    return route.path === '' ? (
      <Route key={domain.id + ':index'} index element={guarded} />
    ) : (
      <Route key={domain.id + ':' + route.path} path={route.path} element={guarded} />
    );
  });

  return (
    <Route
      key={domain.id}
      path={domain.basePath.replace(/^\//, '')}
      element={domain.requiresRole ? <RequireRole role={domain.requiresRole} /> : undefined}
    >
      {children}
    </Route>
  );
}
