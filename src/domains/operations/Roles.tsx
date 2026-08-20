import { useState } from 'react';
import { toast } from 'sonner';
import { KeyRound, Lock, ShieldCheck, UserMinus, UserPlus } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input, Label } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { relativeTime, shortDate } from '@/lib/format';
import { useGrantRole, useMyRoles, useRoleAudit, type AppRole } from './hooks';

/**
 * Roles the `assign-role` function will grant. `user` is not among them: it is
 * the baseline every account already has and the function rejects it.
 */
const GRANTABLE: Array<{ role: AppRole; label: string; note: string }> = [
  { role: 'admin', label: 'Administrator', note: 'Full operations access, including this page.' },
  { role: 'moderator', label: 'Moderator', note: 'Community moderation.' },
  { role: 'support', label: 'Support', note: 'Reads and answers member requests.' },
  { role: 'marketing', label: 'Marketing', note: 'Campaigns and announcements.' },
  { role: 'legal', label: 'Legal', note: 'Compliance and legal review.' },
  { role: 'arx', label: 'ARX member', note: 'ARX Club governance portal.' },
  { role: 'seed_str_admin', label: 'Seed STR admin', note: 'Seed STR administration.' },
];

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function GrantForm() {
  const grant = useGrantRole();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<AppRole>('support');

  const emailOk = EMAIL.test(email.trim());
  const canSubmit = emailOk && !grant.isPending;
  const selected = GRANTABLE.find((entry) => entry.role === role);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;
    try {
      const message = await grant.mutateAsync({ email, role });
      toast.success(message);
      setEmail('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not grant the role');
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            <UserPlus className="size-5 text-primary" />
            Grant a role
          </CardTitle>
          <CardDescription>
            The member is looked up by the email on their profile. If no account matches, nothing is
            written.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent>
        <form className="max-w-lg space-y-4" onSubmit={submit}>
          <Field
            label="Member email"
            htmlFor="grant-email"
            error={email.trim() && !emailOk ? 'Enter a valid email address.' : undefined}
          >
            <Input
              id="grant-email"
              type="email"
              autoComplete="off"
              value={email}
              aria-invalid={!!email.trim() && !emailOk}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="member@example.com"
            />
          </Field>

          <div className="space-y-1.5">
            <Label htmlFor="grant-role">Role</Label>
            <select
              id="grant-role"
              value={role}
              onChange={(e) => setRole(e.target.value as AppRole)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm transition-colors"
            >
              {GRANTABLE.map((entry) => (
                <option key={entry.role} value={entry.role}>
                  {entry.label}
                </option>
              ))}
            </select>
            {selected && <p className="text-xs text-muted-foreground">{selected.note}</p>}
          </div>

          <Button type="submit" disabled={!canSubmit}>
            {grant.isPending ? 'Granting…' : 'Grant role'}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

export default function Roles() {
  const myRoles = useMyRoles();
  const audit = useRoleAudit();

  return (
    <>
      <PageHeader
        title="Roles"
        description="Who holds which role, and how a role is granted."
      />

      <Card className="mb-6">
        <CardContent className="flex items-start gap-3 py-4">
          <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" />
          <div className="space-y-1 text-sm text-muted-foreground">
            <p className="font-medium text-foreground">Role changes are made on the server.</p>
            <p>
              Every grant goes through the <code className="font-mono text-xs">assign-role</code>{' '}
              function, which re-checks that the caller is an administrator before it writes. The
              browser has no write access to the role table at all, and can only read its own rows.
            </p>
          </div>
        </CardContent>
      </Card>

      <div className="mb-6 grid gap-6 lg:grid-cols-2 lg:items-start">
        <GrantForm />

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <UserMinus className="size-5 text-muted-foreground" />
                Revoke a role
              </CardTitle>
              <CardDescription>Not available from this console.</CardDescription>
            </div>
            <Badge tone="warning">
              <Lock className="size-3" />
              Disabled
            </Badge>
          </CardHeader>
          <CardContent className="space-y-3 text-sm text-muted-foreground">
            <p>
              There is no server function that revokes a role. v2 revoked by deleting from the role
              table straight from the browser, which is precisely the write that made a grant
              worthless: anyone who could reach the admin page could remove another administrator,
              or keep their own access after it was withdrawn.
            </p>
            <p>
              Rather than reproduce that, revocation is left out until a{' '}
              <code className="font-mono text-xs">revoke-role</code> function exists to authorise and
              log it the same way the grant is. Until then, revoke through the database.
            </p>
            <Button variant="secondary" size="sm" disabled aria-disabled="true">
              <UserMinus />
              Revoke role
            </Button>
          </CardContent>
        </Card>
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Your roles</CardTitle>
            <CardDescription>
              The role table is readable only for your own account, so this console cannot list who
              else holds a role.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {myRoles.isLoading ? (
            <Skeleton className="h-10 w-64" />
          ) : myRoles.isError ? (
            <ErrorState error={myRoles.error} onRetry={() => void myRoles.refetch()} />
          ) : (myRoles.data ?? []).length === 0 ? (
            <EmptyState title="No roles" description="Your account holds no elevated role." />
          ) : (
            <div className="flex flex-wrap gap-2">
              {(myRoles.data ?? []).map((entry) => (
                <Badge key={entry.id} tone="primary">
                  <KeyRound className="size-3" />
                  {entry.role}
                  {entry.created_at && (
                    <span className="text-muted-foreground">since {shortDate(entry.created_at)}</span>
                  )}
                </Badge>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Role change log</CardTitle>
            <CardDescription>Entries the security log holds against the role table.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {audit.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-24 w-full" />
            </div>
          ) : audit.isError ? (
            <ErrorState error={audit.error} onRetry={() => void audit.refetch()} />
          ) : (audit.data ?? []).length === 0 ? (
            <EmptyState
              title="Nothing logged"
              description="No role change has been written to the security log."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Action</TH>
                    <TH>Subject</TH>
                    <TH>Actor</TH>
                    <TH>When</TH>
                  </TR>
                </THead>
                <TBody>
                  {(audit.data ?? []).map((entry) => (
                    <TR key={entry.id}>
                      <TD className="font-medium">{entry.action}</TD>
                      <TD className="font-mono text-xs text-muted-foreground">
                        {entry.resource_id ?? '—'}
                      </TD>
                      <TD className="font-mono text-xs text-muted-foreground">{entry.user_id ?? '—'}</TD>
                      <TD className="text-muted-foreground">{relativeTime(entry.created_at)}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>
    </>
  );
}
