import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { useAuth } from './AuthProvider';
import { Button } from '@/components/ui/button';
import { Input, Field } from '@/components/ui/input';
import { isLocal, supabase } from '@/lib/supabase';

export default function SignIn() {
  const { signIn, signUp } = useAuth();
  const [mode, setMode] = useState<'in' | 'up'>('in');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [migrating, setMigrating] = useState(false);

  /**
   * Members arriving from the legacy platform do not have an account here yet.
   * Rather than making them notice that and pick a different button, a failed
   * sign-in falls through to the migration path, which asks the legacy project
   * whether these credentials are valid and, if so, creates the account.
   *
   * Order matters: local FIRST. Once a member has migrated, every later sign-in
   * is an ordinary local one and never touches the legacy system again.
   *
   * Returns true when the caller should retry the local sign-in.
   */
  async function tryMigrate(mail: string, pass: string): Promise<boolean> {
    setMigrating(true);
    try {
      const { data, error: fnErr } = await supabase.functions.invoke('migrate-login', {
        body: { email: mail, password: pass },
      });
      if (fnErr || !data?.migrated) return false;
      toast.success(
        data.quarantined_balances > 0
          ? `Welcome back. ${data.quarantined_balances} balances were imported and are held for review.`
          : 'Welcome back. Your account has been migrated.'
      );
      return true;
    } catch {
      // A migration failure must not replace the original sign-in error with a
      // more confusing one — the member's problem is still "I cannot get in".
      return false;
    } finally {
      setMigrating(false);
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const mail = email.trim();
    try {
      if (mode === 'in') {
        try {
          await signIn(mail, password);
        } catch (first) {
          if (!(await tryMigrate(mail, password))) throw first;
          await signIn(mail, password);
        }
      } else {
        await signUp(mail, password, fullName.trim());
        toast.success('Account created. Check your email to confirm it.');
      }
    } catch (err) {
      // Surfaced inline as well as via toast: the message is the only clue the
      // user gets about why they cannot get in.
      setError(err instanceof Error ? err.message : 'Something went wrong');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-background px-4 py-10">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <div className="brand-gradient mx-auto flex size-11 items-center justify-center rounded-xl text-base font-bold text-white">
            iX
          </div>
          <h1 className="text-xl font-semibold">
            {mode === 'in' ? 'Sign in to IgniteHeX' : 'Create your account'}
          </h1>
          <p className="text-sm text-muted-foreground">
            {mode === 'in'
              ? 'Digital asset banking on SourceLess.'
              : 'You will confirm your identity after signing up.'}
          </p>
        </div>

        <form onSubmit={onSubmit} className="panel space-y-4 p-5">
          {mode === 'up' && (
            <Field label="Full name" htmlFor="name">
              <Input
                id="name"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                autoComplete="name"
                required
              />
            </Field>
          )}

          <Field label="Email" htmlFor="email">
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
              required
            />
          </Field>

          <Field
            label="Password"
            htmlFor="password"
            hint={mode === 'up' ? 'At least 8 characters.' : undefined}
            error={error ?? undefined}
          >
            <Input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete={mode === 'in' ? 'current-password' : 'new-password'}
              minLength={8}
              required
              aria-invalid={!!error}
            />
          </Field>

          <Button type="submit" className="w-full" disabled={busy}>
            {migrating
              ? 'Checking your existing account…'
              : busy
                ? 'Working…'
                : mode === 'in'
                  ? 'Sign in'
                  : 'Create account'}
          </Button>

          {mode === 'in' && (
            <p className="text-center text-xs text-muted-foreground">
              Already have an IgniteHeX account? Sign in with the same email and
              password — it will be brought across on your first visit.
            </p>
          )}

          <button
            type="button"
            className="w-full text-center text-sm text-muted-foreground hover:text-foreground"
            onClick={() => {
              setMode((m) => (m === 'in' ? 'up' : 'in'));
              setError(null);
            }}
          >
            {mode === 'in' ? 'Need an account? Sign up' : 'Already have an account? Sign in'}
          </button>
        </form>

        {isLocal && (
          <p className="text-center text-xs text-muted-foreground">
            Local environment — seeded accounts use the password{' '}
            <code className="font-mono">LocalDev123!</code>
          </p>
        )}
      </div>
    </div>
  );
}
