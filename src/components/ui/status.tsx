import { Badge } from './badge';

/** One mapping from a domain status string to a visual tone, so the same status
 *  never appears green on one screen and grey on another. */
const TONES: Record<string, 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info'> = {
  approved: 'success',
  connected: 'success',
  active: 'success',
  completed: 'success',
  verified: 'success',
  submitted: 'info',
  pending: 'warning',
  pending_review: 'warning',
  under_review: 'warning',
  requested: 'warning',
  draft: 'neutral',
  not_connected: 'neutral',
  rejected: 'danger',
  suspended: 'danger',
  closed: 'danger',
  failed: 'danger',
};

const LABELS: Record<string, string> = {
  under_review: 'Under review',
  pending_review: 'Pending review',
  not_connected: 'Not connected',
};

export function StatusBadge({ status }: { status: string | null | undefined }) {
  const key = (status ?? 'unknown').toLowerCase();
  const label = LABELS[key] ?? key.charAt(0).toUpperCase() + key.slice(1);
  return <Badge tone={TONES[key] ?? 'neutral'}>{label}</Badge>;
}
