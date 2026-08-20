import { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Link } from 'react-router-dom';
import { QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'sonner';
import { queryClient } from '@/lib/query';
import { AuthProvider } from '@/features/auth/AuthProvider';
import { ThemeProvider } from '@/features/theme';
import { AppShell } from '@/components/layout/AppShell';
import { RequireAuth, RedirectIfAuthed } from '@/routes/guards';
import { domainRoutes } from '@/routes/DomainRoutes';
import { DOMAINS } from '@/domains/registry';
import { Button } from '@/components/ui/button';

/**
 * Routes are lazy and, apart from the shell's own pages, come from the domain
 * registry. v2 imported all ~140 pages statically at the top of this file,
 * which is why its entry chunk was 5.6MB — every visitor downloaded the entire
 * admin surface to see the sign-in form.
 */
const SignIn = lazy(() => import('@/features/auth/SignIn'));
const Overview = lazy(() => import('@/features/dashboard/Overview'));
const AccountPage = lazy(() => import('@/features/account/AccountPage'));

function Loading() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center">
      <div className="size-6 animate-spin rounded-full border-2 border-border border-t-primary" />
      <span className="sr-only">Loading</span>
    </div>
  );
}

function Message({ code, title, body }: { code: string; title: string; body: string }) {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-4 bg-background px-6 text-center">
      <p className="brand-text text-3xl font-bold">{code}</p>
      <div className="space-y-1">
        <h1 className="text-xl font-semibold">{title}</h1>
        <p className="max-w-sm text-sm text-muted-foreground">{body}</p>
      </div>
      <Button asChild variant="secondary">
        <Link to="/">Back to overview</Link>
      </Button>
    </div>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>
        <BrowserRouter>
          <AuthProvider>
            <Suspense fallback={<Loading />}>
              <Routes>
                <Route
                  path="/auth"
                  element={
                    <RedirectIfAuthed>
                      <SignIn />
                    </RedirectIfAuthed>
                  }
                />

                <Route
                  path="/forbidden"
                  element={
                    <Message
                      code="403"
                      title="Not available to your account"
                      body="This area needs a role your account does not have. If you think that is wrong, contact an administrator."
                    />
                  }
                />

                {/* Everything below requires a session. Guarding happens here,
                    once, rather than in each page. */}
                <Route element={<RequireAuth />}>
                  <Route element={<AppShell />}>
                    <Route index element={<Overview />} />
                    <Route path="account" element={<AccountPage />} />
                    {DOMAINS.map(domainRoutes)}
                  </Route>
                </Route>

                <Route
                  path="*"
                  element={
                    <Message code="404" title="Page not found" body="That page does not exist." />
                  }
                />
              </Routes>
            </Suspense>
            <Toaster position="top-right" richColors closeButton />
          </AuthProvider>
        </BrowserRouter>
      </ThemeProvider>
    </QueryClientProvider>
  );
}
