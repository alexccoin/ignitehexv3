import { useEffect, useState, type ReactNode } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { BadgeCheck, LayoutDashboard, LogOut, Menu, Moon, Sun, X } from 'lucide-react';
import { useAuth } from '@/features/auth/AuthProvider';
import { useTheme } from '@/features/theme';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { isLocal } from '@/lib/supabase';
import { cn } from '@/lib/utils';
import { NAV_GROUPS, domainsForGroup, navSubRoutes } from '@/domains/registry';
import { QuarantineBanner } from './QuarantineBanner';
import type { DomainModule } from '@/domains/types';

/**
 * The application shell.
 *
 * Navigation is derived from the domain registry rather than maintained by
 * hand. v2 kept two sidebar components that had drifted apart — one showed
 * admin+moderator entries, the other admin+seed_str_admin — and four of its nav
 * links pointed at paths that had no route, landing users on NotFound. Here a
 * nav entry exists because a domain declared a route with a navLabel, so the
 * two cannot disagree.
 */

function navItemClass({ isActive }: { isActive: boolean }) {
  return cn(
    'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
    isActive
      ? 'bg-primary/10 text-primary'
      : 'text-muted-foreground hover:bg-elevated hover:text-foreground'
  );
}

/** A domain and, when it is the active one, its sub-routes. */
function DomainNav({ domain, onNavigate }: { domain: DomainModule; onNavigate: () => void }) {
  const location = useLocation();
  const { hasRole } = useAuth();
  const Icon = domain.icon;
  const active = location.pathname === domain.basePath || location.pathname.startsWith(domain.basePath + '/');
  // A sub-route the caller cannot enter must not appear in the nav. Filtering
  // on navLabel alone offered members a link that answered 403 — it went
  // unnoticed until support became the first domain to mix guarded and
  // unguarded routes under one basePath. The rule itself lives in the registry
  // beside domainsForGroup, so the two halves of the nav filter cannot drift.
  const subRoutes = navSubRoutes(domain, hasRole);

  return (
    <div>
      <NavLink to={domain.basePath} end onClick={onNavigate} className={navItemClass}>
        <Icon className="size-4 shrink-0" />
        {domain.title}
      </NavLink>

      {/* Sub-routes only appear for the domain you are in, so the sidebar stays
          short instead of listing every screen in the platform at once. */}
      {active && subRoutes.length > 1 && (
        <div className="ml-4 mt-1 space-y-0.5 border-l border-border pl-3">
          {subRoutes.map((r) => (
            <NavLink
              key={r.path}
              to={r.path === '' ? domain.basePath : domain.basePath + '/' + r.path}
              end={r.end}
              onClick={onNavigate}
              className={({ isActive }) =>
                cn(
                  'block rounded-md px-2 py-1.5 text-sm transition-colors',
                  isActive ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
                )
              }
            >
              {r.navLabel}
            </NavLink>
          ))}
        </div>
      )}
    </div>
  );
}

export function AppShell() {
  const { user, hasRole, signOut } = useAuth();
  const { theme, toggle } = useTheme();
  const [open, setOpen] = useState(false);
  const location = useLocation();

  // Close the mobile drawer whenever the route changes, otherwise it stays open
  // over the page the user just navigated to.
  useEffect(() => setOpen(false), [location.pathname]);

  const initials = ((user?.user_metadata?.full_name as string | undefined) ?? user?.email ?? '?')
    .split(/[\s@.]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((s) => s[0]?.toUpperCase())
    .join('');

  const close = () => setOpen(false);

  const sidebar = (
    <div className="flex h-full flex-col gap-1 p-3">
      <div className="flex items-center gap-2.5 px-2 py-3">
        <div className="brand-gradient flex size-8 items-center justify-center rounded-lg text-sm font-bold text-white">
          iX
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold leading-tight">IgniteHeX</p>
          <p className="truncate text-xs text-muted-foreground">SourceLess</p>
        </div>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto">
        <NavLink to="/" end onClick={close} className={navItemClass}>
          <LayoutDashboard className="size-4 shrink-0" />
          Overview
        </NavLink>
        <NavLink to="/account" onClick={close} className={navItemClass}>
          <BadgeCheck className="size-4 shrink-0" />
          Account
        </NavLink>

        {NAV_GROUPS.map((group) => {
          const domains = domainsForGroup(group.id, hasRole);
          if (domains.length === 0) return null;
          return (
            <div key={group.id} className="space-y-1">
              {group.label && (
                <p className="px-3 pb-1 pt-4 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  {group.label}
                </p>
              )}
              {domains.map((d) => (
                <DomainNav key={d.id} domain={d} onNavigate={close} />
              ))}
            </div>
          );
        })}
      </nav>

      <div className="space-y-3 border-t border-border pt-3">
        {isLocal && (
          <Badge tone="warning" className="w-full justify-center">
            Local environment
          </Badge>
        )}
        <div className="flex items-center gap-2.5 px-2">
          <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-elevated text-xs font-semibold">
            {initials}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">
              {(user?.user_metadata?.full_name as string | undefined) ?? 'Member'}
            </p>
            <p className="truncate text-xs text-muted-foreground">{user?.email}</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="ghost" size="sm" className="flex-1" onClick={toggle}>
            {theme === 'dark' ? <Sun /> : <Moon />}
            {theme === 'dark' ? 'Light' : 'Dark'}
          </Button>
          <Button variant="ghost" size="sm" className="flex-1" onClick={() => void signOut()}>
            <LogOut />
            Sign out
          </Button>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-dvh bg-background">
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 border-r border-border bg-surface lg:block">
        {sidebar}
      </aside>

      {open && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <button className="absolute inset-0 bg-overlay/60" onClick={close} aria-label="Close navigation" />
          <aside className="absolute inset-y-0 left-0 w-72 border-r border-border bg-surface">
            <button
              className="absolute right-3 top-3 rounded-md p-1.5 text-muted-foreground hover:bg-elevated"
              onClick={close}
              aria-label="Close navigation"
            >
              <X className="size-4" />
            </button>
            {sidebar}
          </aside>
        </div>
      )}

      <div className="lg:pl-64">
        <header className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-border bg-background/80 px-4 backdrop-blur lg:px-8">
          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            onClick={() => setOpen(true)}
            aria-label="Open navigation"
          >
            <Menu />
          </Button>
          <div className="flex-1" />
        </header>

        <main className="mx-auto w-full max-w-7xl px-4 py-6 lg:px-8">
          {/* Shown on every page while a migrated account is under review, so a
              member never has to go looking for why their balances read zero. */}
          <QuarantineBanner />
          <Outlet />
        </main>
      </div>
    </div>
  );
}

/** Page title block. Every page opens with one, so headings stay consistent. */
export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        {description && <p className="text-sm text-muted-foreground">{description}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
