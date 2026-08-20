import { Navigate, Outlet, useLocation } from 'react-router-dom';
import type { ReactNode } from 'react';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

type AppRole = Database['public']['Enums']['app_role'];

/**
 * Route guards.
 *
 * v2 had none: every route was mounted unconditionally and each page was
 * expected to redirect itself, which 25 pages did not do and 8 admin pages did
 * without any role check. Authorisation is enforced by RLS on the server either
 * way, but the UI should not render an admin console to someone who cannot use
 * it, and it certainly should not depend on each new page remembering to guard
 * itself. Guarding is done once, here, at the routing layer.
 */

function FullPageSpinner() {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-background">
      <div className="size-6 animate-spin rounded-full border-2 border-border border-t-primary" />
      <span className="sr-only">Loading</span>
    </div>
  );
}

/** Requires a session. Remembers where the user was headed. */
export function RequireAuth({ children }: { children?: ReactNode }) {
  const { session, ready } = useAuth();
  const location = useLocation();

  // Waiting for the initial session lookup. Redirecting here would bounce a
  // signed-in user to the login page on every reload.
  if (!ready) return <FullPageSpinner />;

  if (!session) {
    return <Navigate to="/auth" replace state={{ from: location.pathname + location.search }} />;
  }

  return <>{children ?? <Outlet />}</>;
}

/** Requires a session and a specific role. Defaults to admin. */
export function RequireRole({
  role = 'admin',
  children,
}: {
  role?: AppRole;
  children?: ReactNode;
}) {
  const { session, ready, rolesReady, hasRole } = useAuth();
  const location = useLocation();

  if (!ready) return <FullPageSpinner />;
  if (!session) {
    return <Navigate to="/auth" replace state={{ from: location.pathname + location.search }} />;
  }

  // Wait for the role lookup to settle, not for it to be non-empty. Keying on
  // `roles.length === 0` meant a member with no roles — or a lookup that
  // failed — sat on a spinner indefinitely with nothing in the console.
  if (!rolesReady) return <FullPageSpinner />;

  if (!hasRole(role)) return <Navigate to="/forbidden" replace />;

  return <>{children ?? <Outlet />}</>;
}

/** Sends an already-signed-in visitor away from the login page. */
export function RedirectIfAuthed({ children }: { children: ReactNode }) {
  const { session, ready } = useAuth();
  const location = useLocation() as { state?: { from?: string } };

  if (!ready) return <FullPageSpinner />;
  if (session) return <Navigate to={location.state?.from ?? '/'} replace />;

  return <>{children}</>;
}
