import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Download, Globe, Signal, Smartphone } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input, Field } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { Skeleton } from '@/components/ui/skeleton';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import { shortDate, money } from '@/lib/format';
import { useMyDomains, useStrDomeRequests, useRequestStrDome, type StrDomeRequest } from './hooks';

/**
 * str.dome / eSIM — a utility of owning an STR domain.
 *
 * Ported from the Dome_Dashboard EsimModal, but driven by data rather than the
 * fixed values that prototype carried: the domain, country, package and serial
 * all come from the member's own str_dome_requests row, and the activation card
 * only appears once an administrator has attached the file. The original hard-
 * coded one member's domain and serial into the markup, so every viewer saw the
 * same card.
 */

const PACKAGES = [
  { name: 'STRDOME Starter', price: 29, blurb: '1 GB regional data, 30 days' },
  { name: 'STRDOME Traveller', price: 59, blurb: '5 GB multi-country, 30 days' },
  { name: 'STRDOME Business', price: 119, blurb: '20 GB global, 90 days' },
];

const COUNTRIES = [
  'Romania', 'Germany', 'Netherlands', 'France', 'Italy', 'Spain',
  'United Kingdom', 'Switzerland', 'United States', 'United Arab Emirates',
];

/** The activation card. Only rendered once a file has actually been attached. */
function ActivationCard({ request, domain }: { request: StrDomeRequest; domain: string | null }) {
  const [url, setUrl] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // The file lives in private storage; a signed URL is minted on demand rather
  // than embedding a public link in the page.
  async function reveal() {
    if (!request.esim_file_path) return;
    setBusy(true);
    const { data, error } = await supabase.storage
      .from('str-dome')
      .createSignedUrl(request.esim_file_path, 300);
    setBusy(false);
    if (error || !data?.signedUrl) {
      toast.error(error?.message ?? 'Could not produce a download link.');
      return;
    }
    setUrl(data.signedUrl);
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  }

  const details = [
    ['Network', 'SourceLess NET'],
    ['Domain', domain ? `str.${domain}` : '—'],
    ['Country', request.esim_country ?? '—'],
    ['Package', request.package_name ?? '—'],
    ['Reference', request.id.slice(0, 14).toUpperCase()],
    ['Activated', shortDate(request.reviewed_at)],
  ] as const;

  return (
    <Card className="overflow-hidden">
      <div className="brand-gradient flex items-center justify-between gap-4 p-6">
        <div className="min-w-0">
          <p className="text-xs font-medium uppercase tracking-wide text-white/80">
            SourceLess NET eSIM
          </p>
          <p className="truncate font-display text-2xl font-bold text-white">
            {domain ? `str.${domain}` : 'Activation card'}
          </p>
        </div>
        <Signal className="size-8 shrink-0 text-white/90" aria-hidden="true" />
      </div>

      <CardContent className="space-y-4">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
          {details.map(([k, v]) => (
            <div key={k}>
              <dt className="text-xs uppercase tracking-wide text-muted-foreground">{k}</dt>
              <dd className="truncate font-medium">{v}</dd>
            </div>
          ))}
        </dl>

        {request.esim_file_path ? (
          <Button onClick={() => void reveal()} disabled={busy} className="w-full">
            <Download aria-hidden="true" />
            {busy ? 'Preparing…' : 'Download activation QR'}
          </Button>
        ) : (
          <p className="rounded-md border border-border bg-elevated p-3 text-sm text-muted-foreground">
            Approved. The activation file has not been attached yet — it appears here as soon as
            it is issued.
          </p>
        )}
        {url && (
          <p className="text-xs text-muted-foreground">
            Link is valid for 5 minutes. Re-open this page to mint a new one.
          </p>
        )}
      </CardContent>
    </Card>
  );
}

export default function Esim() {
  const { user } = useAuth();
  const domains = useMyDomains();
  const requests = useStrDomeRequests();
  const submit = useRequestStrDome();

  const [pkg, setPkg] = useState(PACKAGES[0].name);
  const [country, setCountry] = useState('');
  const [username, setUsername] = useState('');
  const [deliveryEmail, setDeliveryEmail] = useState('');
  const [toWallet, setToWallet] = useState(false);

  const owned = domains.data ?? [];
  const rows = requests.data ?? [];
  const active = rows.find((r) => r.status === 'approved');
  const primaryDomain = owned.find((d) => d.is_main_domain)?.domain_name ?? owned[0]?.domain_name ?? null;

  // The eSIM is a utility of domain ownership — without a domain there is
  // nothing to bind it to, so the form is not offered.
  const eligible = owned.length > 0;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const chosen = PACKAGES.find((p) => p.name === pkg);
    if (!chosen) return;

    try {
      await submit.mutateAsync({
        username: username.trim() || primaryDomain || '',
        packageName: chosen.name,
        priceUsd: chosen.price,
        country,
        accountEmail: user?.email ?? '',
        deliveryEmail,
        deliverToWallet: toWallet,
      });
      toast.success('Request submitted for review.');
      setCountry('');
      setUsername('');
      setDeliveryEmail('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the request');
    }
  }

  if (requests.isLoading || domains.isLoading) {
    return (
      <>
        <PageHeader title="str.dome eSIM" />
        <Skeleton className="h-64 w-full" />
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="str.dome eSIM"
        description="Mobile connectivity bound to your STR domain."
        actions={
          <Badge tone={eligible ? 'primary' : 'neutral'}>
            {owned.length} domain{owned.length === 1 ? '' : 's'} owned
          </Badge>
        }
      />

      {requests.isError ? (
        <Card>
          <ErrorState error={requests.error} onRetry={() => void requests.refetch()} />
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-2">
          {active ? (
            <ActivationCard request={active} domain={active.str_dome_username ?? primaryDomain} />
          ) : (
            <Card>
              <CardHeader>
                <div>
                  <CardTitle>Request an eSIM</CardTitle>
                  <CardDescription>
                    An administrator reviews the request and issues the activation card.
                  </CardDescription>
                </div>
              </CardHeader>
              <CardContent>
                {!eligible ? (
                  <EmptyState
                    icon={<Globe className="size-5" />}
                    title="An STR domain is required"
                    description="The eSIM is bound to a domain you own. Request or buy one first, then come back."
                  />
                ) : (
                  <form onSubmit={onSubmit} className="space-y-4">
                    <Field label="Package" htmlFor="pkg">
                      <select
                        id="pkg"
                        value={pkg}
                        onChange={(e) => setPkg(e.target.value)}
                        className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                      >
                        {PACKAGES.map((p) => (
                          <option key={p.name} value={p.name}>
                            {p.name} — {money(p.price, 'USD')} · {p.blurb}
                          </option>
                        ))}
                      </select>
                    </Field>

                    <Field label="Country" htmlFor="country">
                      <select
                        id="country"
                        value={country}
                        onChange={(e) => setCountry(e.target.value)}
                        required
                        className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                      >
                        <option value="">Choose a country…</option>
                        {COUNTRIES.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </select>
                    </Field>

                    <Field
                      label="Bind to domain"
                      htmlFor="username"
                      hint={primaryDomain ? `Defaults to str.${primaryDomain}` : undefined}
                    >
                      <select
                        id="username"
                        value={username || primaryDomain || ''}
                        onChange={(e) => setUsername(e.target.value)}
                        className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                      >
                        {owned.map((d) => (
                          <option key={d.id} value={d.domain_name}>
                            str.{d.domain_name}
                          </option>
                        ))}
                      </select>
                    </Field>

                    <Field label="Delivery email" htmlFor="delivery" hint="Where the card is sent.">
                      <Input
                        id="delivery"
                        type="email"
                        value={deliveryEmail}
                        onChange={(e) => setDeliveryEmail(e.target.value)}
                        placeholder={user?.email ?? ''}
                      />
                    </Field>

                    <label className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={toWallet}
                        onChange={(e) => setToWallet(e.target.checked)}
                        className="size-4 rounded border-input"
                      />
                      Also deliver to my wallet
                    </label>

                    <Button type="submit" disabled={submit.isPending} className="w-full">
                      <Smartphone aria-hidden="true" />
                      {submit.isPending ? 'Submitting…' : 'Request eSIM'}
                    </Button>
                  </form>
                )}
              </CardContent>
            </Card>
          )}

          <Card>
            <CardHeader>
              <CardTitle>Request history</CardTitle>
            </CardHeader>
            <CardContent className="pt-3">
              {rows.length === 0 ? (
                <EmptyState title="No requests yet" />
              ) : (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Package</TH>
                        <TH>Country</TH>
                        <TH>Domain</TH>
                        <TH>Status</TH>
                        <TH>Requested</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((r) => (
                        <TR key={r.id}>
                          <TD className="font-medium">{r.package_name ?? '—'}</TD>
                          <TD className="text-muted-foreground">{r.esim_country ?? '—'}</TD>
                          <TD className="text-muted-foreground">
                            {r.str_dome_username ? `str.${r.str_dome_username}` : '—'}
                          </TD>
                          <TD>
                            <StatusBadge status={r.status} />
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(r.created_at)}</TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
