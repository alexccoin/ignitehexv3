import { useEffect, useRef, useState } from 'react';
import { ExternalLink, Maximize2, Minimize2, X, AppWindow } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { useEcosystemApps, canFrame, type EcosystemApp } from './ecosystemApps';

/**
 * The ecosystem app launcher.
 *
 * Apps open in a window inside the dashboard, framed from their own origin.
 * Three properties of this component are load-bearing rather than stylistic:
 *
 *  1. **The URL is framed as-is, cross-origin.** No proxy. A proxied app runs on
 *     our origin and can read the Supabase session out of localStorage.
 *
 *  2. **`sandbox` omits `allow-top-navigation`.** Without it a framed app cannot
 *     navigate the whole tab somewhere else, which is the cheap phishing move —
 *     the member believes they are still on IgniteHeX.
 *
 *  3. **`allow` grants almost nothing.** The original passed camera, microphone,
 *     geolocation and payment to every framed app. None of those are needed to
 *     display one, and a permission granted here is granted to whatever that app
 *     later becomes.
 *
 * An app that refuses framing cannot be detected from script — a cross-origin
 * load event fires either way and the document cannot be inspected. So rather
 * than guess, the window always offers "Open in new tab" and says plainly what
 * to do if the panel stays blank.
 */

function AppWindowPanel({ app, onClose }: { app: EcosystemApp; onClose: () => void }) {
  const [full, setFull] = useState(false);
  const [slow, setSlow] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);

  // Escape closes the window; focus moves to the close button on open so the
  // keyboard is not stranded inside a frame we do not control.
  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  // A frame that has not painted after a few seconds is usually one refusing to
  // be framed. We cannot confirm that, so we surface the hint rather than an
  // assertion.
  useEffect(() => {
    const t = window.setTimeout(() => setSlow(true), 4000);
    return () => window.clearTimeout(t);
  }, []);

  return (
    <div
      className={cn(
        'fixed inset-0 z-50 flex flex-col bg-overlay/70 backdrop-blur',
        full ? 'p-0' : 'p-4 lg:p-10'
      )}
      role="dialog"
      aria-modal="true"
      aria-label={`${app.name} application window`}
    >
      <div
        className={cn(
          'mx-auto flex min-h-0 w-full flex-1 flex-col overflow-hidden border border-border bg-surface',
          full ? 'rounded-none' : 'max-w-6xl rounded-xl shadow-2xl'
        )}
      >
        <header className="flex shrink-0 items-center gap-3 border-b border-border px-4 py-2.5">
          <AppWindow className="size-4 shrink-0 text-muted-foreground" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{app.name}</p>
            <p className="truncate font-mono text-xs text-muted-foreground">{new URL(app.url).host}</p>
          </div>
          <Button variant="ghost" size="sm" asChild>
            <a href={app.url} target="_blank" rel="noopener noreferrer">
              <ExternalLink className="size-4" />
              Open in new tab
            </a>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setFull((f) => !f)}
            aria-label={full ? 'Exit fullscreen' : 'Fullscreen'}
          >
            {full ? <Minimize2 className="size-4" /> : <Maximize2 className="size-4" />}
          </Button>
          <Button ref={closeRef} variant="ghost" size="icon" onClick={onClose} aria-label="Close window">
            <X className="size-4" />
          </Button>
        </header>

        <div className="relative min-h-0 flex-1 bg-background">
          <iframe
            title={app.name}
            src={app.url}
            className="absolute inset-0 size-full border-0"
            // allow-same-origin is safe ONLY because canFrame() has already
            // established this URL is cross-origin. Never relax that check.
            // allow-top-navigation is deliberately absent.
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox allow-downloads"
            // Not camera, microphone, geolocation or payment.
            allow="clipboard-write; fullscreen"
            referrerPolicy="strict-origin-when-cross-origin"
            loading="lazy"
          />
          {slow && (
            <div className="pointer-events-none absolute inset-x-0 bottom-0 p-3">
              <div className="pointer-events-auto mx-auto max-w-lg rounded-lg border border-border bg-surface/95 p-3 text-center text-xs text-muted-foreground">
                Still blank? {app.name} may not allow being embedded. Use{' '}
                <a
                  href={app.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary underline underline-offset-2"
                >
                  open in new tab
                </a>
                .
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function Apps() {
  const { data, isLoading, error } = useEcosystemApps();
  const [open, setOpen] = useState<EcosystemApp | null>(null);

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (error) return <ErrorState error={error} />;

  const apps = data ?? [];

  return (
    <>
      <PageHeader
        title="Ecosystem apps"
        description="Open the rest of the SourceLess ecosystem without leaving the dashboard."
      />

      {apps.length === 0 ? (
        <EmptyState
          title="No apps available"
          description="Nothing has been published to the launcher yet, or none are available to your account."
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {apps.map((app) => {
            const framable = app.embeddable && canFrame(app.url);
            return (
              <Card key={app.id} className="flex flex-col">
                <CardHeader className="flex-1">
                  <div className="flex items-start justify-between gap-2">
                    <CardTitle className="text-base">{app.name}</CardTitle>
                    <Badge tone="neutral">{app.category}</Badge>
                  </div>
                  <CardDescription>{app.description}</CardDescription>
                </CardHeader>
                <CardContent className="flex items-center gap-2">
                  {framable ? (
                    <Button size="sm" onClick={() => setOpen(app)}>
                      <AppWindow className="size-4" />
                      Open here
                    </Button>
                  ) : (
                    <Button size="sm" asChild>
                      <a href={app.url} target="_blank" rel="noopener noreferrer">
                        <ExternalLink className="size-4" />
                        Open in new tab
                      </a>
                    </Button>
                  )}
                  {/* Said plainly rather than hidden: a member who expected an
                      in-dashboard window should know why they got a tab. */}
                  {!framable && (
                    <span className="text-xs text-muted-foreground">Does not allow embedding</span>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {open && <AppWindowPanel app={open} onClose={() => setOpen(null)} />}
    </>
  );
}
