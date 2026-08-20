import { AlertTriangle, CheckCircle2, XCircle } from 'lucide-react';
import { useMyMigration, effectiveAmount } from '@/domains/migration/hooks';

/**
 * What a migrated member sees on every page until their account is decided.
 *
 * This banner exists because the alternative is worse: a member signs in,
 * sees zeroes everywhere, and concludes the platform lost their money. Saying
 * plainly that the figures were found, are held, and are waiting on a review
 * is the difference between a queue and an outage.
 *
 * It states the claimed figures rather than hiding them, and is explicit that
 * they are not yet spendable — a number shown without that caveat would be
 * read as a balance, and these are not balances.
 */
export function QuarantineBanner() {
  const { data } = useMyMigration();
  if (!data) return null;

  const { account, balances } = data;
  if (account.state === 'approved') return null;

  if (account.state === 'rejected') {
    return (
      <div className="mb-6 flex items-start gap-3 rounded-lg border border-danger/30 bg-danger/5 p-4">
        <XCircle className="mt-0.5 size-5 shrink-0 text-danger" />
        <div className="space-y-1 text-sm">
          <p className="font-medium">Your imported balances were not approved.</p>
          <p className="text-muted-foreground">
            {account.review_notes
              ? `Reason given: ${account.review_notes}`
              : 'No reason was recorded. Contact support and quote your account email.'}
          </p>
        </div>
      </div>
    );
  }

  const held = balances.filter((b) => effectiveAmount(b) > 0);

  return (
    <div className="mb-6 flex items-start gap-3 rounded-lg border border-warning/30 bg-warning/5 p-4">
      <AlertTriangle className="mt-0.5 size-5 shrink-0 text-warning" />
      <div className="min-w-0 space-y-2 text-sm">
        <p className="font-medium">
          Your account was brought across from the previous platform. Your balances are held for review.
        </p>
        {held.length > 0 ? (
          <>
            <p className="text-muted-foreground">
              These figures were found on your old account. They are not spendable yet, and they may change:
              every one is being checked before it is credited.
            </p>
            <ul className="flex flex-wrap gap-x-4 gap-y-1 font-mono text-xs">
              {held.map((b) => (
                <li key={b.id} className="text-muted-foreground">
                  <span className="text-foreground">
                    {effectiveAmount(b).toLocaleString(undefined, { maximumFractionDigits: 8 })}
                  </span>{' '}
                  {b.asset}
                  {b.bucket !== 'liquid' && ` (${b.bucket})`}
                </li>
              ))}
            </ul>
          </>
        ) : (
          <p className="text-muted-foreground">
            No balances were found on your old account. If you expected some, contact support before making
            any deposit.
          </p>
        )}
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <CheckCircle2 className="size-3.5" />
          You can use the rest of the platform normally while this is reviewed.
        </p>
      </div>
    </div>
  );
}
