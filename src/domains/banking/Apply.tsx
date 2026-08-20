import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { CheckCircle2, FileSignature, Loader2, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { ErrorState } from '@/components/ui/states';
import { useAuth } from '@/features/auth/AuthProvider';
import { shortDate } from '@/lib/format';
import { useBankApplication, useSubmitBankApplication } from './hooks';
import { SelectInput } from './shared';

const AGREEMENTS = [
  {
    id: 'gdpr',
    title: 'Data processing (GDPR)',
    body: 'Your identity, address and account data are processed to open and operate the account, retained for the statutory period, and encrypted at rest. You may request access, correction or erasure at any time.',
  },
  {
    id: 'terms',
    title: 'Terms of service',
    body: 'Accounts are operated in accordance with applicable law. Fee schedules are available on request and may change with 30 days notice. Accounts may be suspended for breach of these terms.',
  },
  {
    id: 'nda',
    title: 'Non-disclosure',
    body: 'Account structures, settlement rails and pricing shared with you are confidential and are not to be disclosed to third parties without written consent.',
  },
] as const;

type AgreementId = (typeof AGREEMENTS)[number]['id'];

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default function Apply() {
  const { user } = useAuth();
  const existing = useBankApplication();
  const submit = useSubmitBankApplication();

  const [accountType, setAccountType] = useState<'individual' | 'business'>('individual');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [companyNumber, setCompanyNumber] = useState('');
  const [signature, setSignature] = useState('');
  const [accepted, setAccepted] = useState<Record<AgreementId, boolean>>({
    gdpr: false,
    terms: false,
    nda: false,
  });
  const [touched, setTouched] = useState<Record<string, boolean>>({});

  // Prefill from the session so the applicant is not retyping what we know.
  useEffect(() => {
    if (!user) return;
    setFullName((current) => current || (user.user_metadata?.full_name ?? ''));
    setEmail((current) => current || (user.email ?? ''));
  }, [user]);

  const errors = useMemo(() => {
    const next: Record<string, string> = {};
    if (fullName.trim().length < 2) next.fullName = 'Enter your full legal name.';
    if (!EMAIL_RE.test(email.trim())) next.email = 'Enter a valid email address.';
    if (accountType === 'business' && companyName.trim().length < 2) {
      next.companyName = 'Enter the registered company name.';
    }
    if (signature.trim().toLowerCase() !== fullName.trim().toLowerCase() || !signature.trim()) {
      next.signature = 'Your signature must match your full name exactly.';
    }
    return next;
  }, [fullName, email, accountType, companyName, signature]);

  const allAccepted = AGREEMENTS.every((a) => accepted[a.id]);
  const canSubmit = Object.keys(errors).length === 0 && allAccepted && !submit.isPending;

  async function onSubmit() {
    setTouched({ fullName: true, email: true, companyName: true, signature: true });
    if (!canSubmit) {
      toast.error('Check the highlighted fields and accept all three agreements.');
      return;
    }

    try {
      await submit.mutateAsync({
        fullName: fullName.trim(),
        email: email.trim(),
        signatureFullName: signature.trim(),
        accountType,
        companyName: companyName.trim(),
        companyRegistrationNumber: companyNumber.trim(),
      });
      toast.success('Application submitted. You will be notified once it is reviewed.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the application');
    }
  }

  return (
    <>
      <PageHeader
        title="Apply for CCoin Bank"
        description="One application opens EUR, CHF and GBP accounts, a network card and settlement."
      />

      {existing.isLoading ? (
        <Skeleton className="h-64 w-full" />
      ) : existing.isError ? (
        <ErrorState error={existing.error} onRetry={() => void existing.refetch()} />
      ) : existing.data ? (
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <FileSignature className="size-5 text-primary" />
                Your application
              </CardTitle>
              <CardDescription>
                Submitted {shortDate(existing.data.created_at)}
                {existing.data.processed_at
                  ? ' · decided ' + shortDate(existing.data.processed_at)
                  : ' · awaiting review'}
              </CardDescription>
            </div>
            <StatusBadge status={existing.data.status} />
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-lg border border-border p-3">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">Applicant</p>
                <p className="mt-1 font-medium">{existing.data.full_name}</p>
                <p className="text-xs text-muted-foreground">{existing.data.email}</p>
              </div>
              <div className="rounded-lg border border-border p-3">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">
                  Account type
                </p>
                <p className="mt-1 font-medium capitalize">
                  {existing.data.account_type ?? 'individual'}
                </p>
              </div>
            </div>

            {existing.data.admin_notes && (
              <div className="rounded-lg border border-border p-3">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">
                  Reviewer notes
                </p>
                <p className="mt-1 text-sm">{existing.data.admin_notes}</p>
              </div>
            )}

            {existing.data.status === 'approved' && (
              <Button asChild>
                <Link to="/banking">Open CCoin Bank</Link>
              </Button>
            )}
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-3">
          <div className="space-y-6 lg:col-span-2">
            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Applicant</CardTitle>
                  <CardDescription>
                    These details are checked against your verified identity.
                  </CardDescription>
                </div>
              </CardHeader>
              <CardContent className="grid gap-4 sm:grid-cols-2">
                <Field label="Account type" htmlFor="account-type">
                  <SelectInput
                    id="account-type"
                    value={accountType}
                    onChange={(e) => setAccountType(e.target.value as 'individual' | 'business')}
                  >
                    <option value="individual">Individual</option>
                    <option value="business">Business</option>
                  </SelectInput>
                </Field>

                <Field
                  label="Full legal name"
                  htmlFor="full-name"
                  error={touched.fullName ? errors.fullName : undefined}
                >
                  <Input
                    id="full-name"
                    value={fullName}
                    aria-invalid={touched.fullName && !!errors.fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    onBlur={() => setTouched((t) => ({ ...t, fullName: true }))}
                  />
                </Field>

                <Field
                  label="Email"
                  htmlFor="email"
                  error={touched.email ? errors.email : undefined}
                >
                  <Input
                    id="email"
                    type="email"
                    value={email}
                    aria-invalid={touched.email && !!errors.email}
                    onChange={(e) => setEmail(e.target.value)}
                    onBlur={() => setTouched((t) => ({ ...t, email: true }))}
                  />
                </Field>

                {accountType === 'business' && (
                  <>
                    <Field
                      label="Registered company name"
                      htmlFor="company-name"
                      error={touched.companyName ? errors.companyName : undefined}
                    >
                      <Input
                        id="company-name"
                        value={companyName}
                        aria-invalid={touched.companyName && !!errors.companyName}
                        onChange={(e) => setCompanyName(e.target.value)}
                        onBlur={() => setTouched((t) => ({ ...t, companyName: true }))}
                      />
                    </Field>
                    <Field label="Company registration number" htmlFor="company-number">
                      <Input
                        id="company-number"
                        value={companyNumber}
                        onChange={(e) => setCompanyNumber(e.target.value)}
                      />
                    </Field>
                  </>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Agreements</CardTitle>
                  <CardDescription>All three are required to open an account.</CardDescription>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                {AGREEMENTS.map((agreement) => (
                  <label
                    key={agreement.id}
                    htmlFor={'agree-' + agreement.id}
                    className="flex cursor-pointer gap-3 rounded-lg border border-border p-3 transition-colors hover:bg-elevated"
                  >
                    <input
                      id={'agree-' + agreement.id}
                      type="checkbox"
                      className="mt-0.5 size-4 shrink-0 rounded border-border accent-primary"
                      checked={accepted[agreement.id]}
                      onChange={(e) =>
                        setAccepted((prev) => ({ ...prev, [agreement.id]: e.target.checked }))
                      }
                    />
                    <span>
                      <span className="block text-sm font-medium">{agreement.title}</span>
                      <span className="mt-1 block text-xs text-muted-foreground">
                        {agreement.body}
                      </span>
                    </span>
                  </label>
                ))}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Signature</CardTitle>
                  <CardDescription>
                    Type your full name exactly as entered above. This is recorded with the date as
                    your electronic signature.
                  </CardDescription>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <Field
                  label="Signed by"
                  htmlFor="signature"
                  error={touched.signature ? errors.signature : undefined}
                  hint={!errors.signature ? 'Matches your full name.' : undefined}
                >
                  <Input
                    id="signature"
                    value={signature}
                    aria-invalid={touched.signature && !!errors.signature}
                    onChange={(e) => setSignature(e.target.value)}
                    onBlur={() => setTouched((t) => ({ ...t, signature: true }))}
                  />
                </Field>

                <Button onClick={() => void onSubmit()} disabled={!canSubmit}>
                  {submit.isPending ? <Loader2 className="animate-spin" /> : <CheckCircle2 />}
                  Submit application
                </Button>
              </CardContent>
            </Card>
          </div>

          <Card className="h-fit">
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="flex items-center gap-2">
                  <ShieldCheck className="size-4 text-primary" />
                  What happens next
                </CardTitle>
              </div>
            </CardHeader>
            <CardContent className="space-y-3 text-sm text-muted-foreground">
              {[
                ['1. Review', 'An administrator checks the application against your verified identity.'],
                ['2. Provisioning', 'On approval, EUR, CHF and GBP IBANs and fiat wallets are created server-side.'],
                ['3. Cards', 'A CCoin network card can then be issued against an STR domain you hold.'],
              ].map(([step, body]) => (
                <div key={step}>
                  <p className="font-medium text-foreground">{step}</p>
                  <p className="mt-0.5">{body}</p>
                </div>
              ))}
              <div className="rounded-lg border border-border p-3 text-xs">
                <Label className="text-xs">Note</Label>
                <p className="mt-1">
                  Nothing on this page opens an account or moves money. It records a request; every
                  balance is created by the approval function.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
