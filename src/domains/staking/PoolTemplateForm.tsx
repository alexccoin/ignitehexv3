import { useId, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Select } from './components';
import { POOL_TYPES, POOL_TYPE_LABELS } from './constants';
import {
  useUpsertPoolTemplate,
  type EnhancedPoolRow,
  type PoolTemplateInput,
} from './hooks';

/**
 * Publish or amend a pool template.
 *
 * The advertised APR range belongs in the database, so this is the screen that
 * changes it. New templates are created paused — a pool becomes visible to
 * members only once someone resumes it, rather than the moment it is saved with
 * whatever was in the form.
 */

const CURVES = ['linear', 'tiered', 'exponential'] as const;

function toDraft(pool: EnhancedPoolRow | null): PoolTemplateInput {
  return {
    id: pool?.id,
    name: pool?.name ?? '',
    tokenType: pool?.token_type ?? 'str',
    durationMonths: pool?.duration_months ?? 12,
    aprMin: pool?.apr_min ?? 10,
    aprMax: pool?.apr_max ?? 15,
    minStakeAmount: pool?.min_stake_amount ?? null,
    maxStakeAmount: pool?.max_stake_amount ?? null,
    description: pool?.description ?? '',
    theme: '',
    compounding: pool?.compounding ?? false,
    rewardCurve: pool?.reward_curve ?? 'linear',
  };
}

function numberOrNull(value: string): number | null {
  if (value.trim() === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export function PoolTemplateForm({
  editing,
  onDone,
}: {
  editing: EnhancedPoolRow | null;
  onDone: () => void;
}) {
  const ids = useId();
  const [draft, setDraft] = useState<PoolTemplateInput>(() => toDraft(editing));
  const [error, setError] = useState<string | undefined>();
  const upsert = useUpsertPoolTemplate();

  function patch(changes: Partial<PoolTemplateInput>) {
    setDraft((current) => ({ ...current, ...changes }));
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();

    if (!draft.name.trim()) {
      setError('Give the pool a name members will recognise.');
      return;
    }
    if (!draft.theme.trim()) {
      setError('A theme is required — the column is not nullable.');
      return;
    }
    if (draft.aprMin > draft.aprMax) {
      setError('The minimum APR cannot exceed the maximum.');
      return;
    }
    if (draft.durationMonths <= 0) {
      setError('The term must be at least one month.');
      return;
    }
    setError(undefined);

    upsert.mutate(draft, {
      onSuccess: () => {
        toast.success(editing ? 'Pool template updated' : 'Pool template created (paused)');
        onDone();
      },
      onError: (err: Error) =>
        toast.error('Could not save the pool template', { description: err.message }),
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 border-b border-border p-5">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Field label="Name" htmlFor={`${ids}-name`}>
          <Input
            id={`${ids}-name`}
            value={draft.name}
            onChange={(e) => patch({ name: e.target.value })}
            placeholder="Momentum Lock"
          />
        </Field>

        <Field label="Token" htmlFor={`${ids}-token`}>
          <Select
            id={`${ids}-token`}
            value={draft.tokenType}
            onChange={(e) => patch({ tokenType: e.target.value })}
          >
            {POOL_TYPES.map((t) => (
              <option key={t} value={t}>
                {POOL_TYPE_LABELS[t]}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Term (months)" htmlFor={`${ids}-duration`}>
          <Input
            id={`${ids}-duration`}
            type="number"
            min="1"
            step="1"
            value={draft.durationMonths}
            onChange={(e) => patch({ durationMonths: Number(e.target.value) })}
          />
        </Field>

        <Field label="APR minimum (%)" htmlFor={`${ids}-aprmin`}>
          <Input
            id={`${ids}-aprmin`}
            type="number"
            min="0"
            step="0.01"
            value={draft.aprMin}
            onChange={(e) => patch({ aprMin: Number(e.target.value) })}
          />
        </Field>

        <Field label="APR maximum (%)" htmlFor={`${ids}-aprmax`}>
          <Input
            id={`${ids}-aprmax`}
            type="number"
            min="0"
            step="0.01"
            value={draft.aprMax}
            onChange={(e) => patch({ aprMax: Number(e.target.value) })}
          />
        </Field>

        <Field label="Reward curve" htmlFor={`${ids}-curve`}>
          <Select
            id={`${ids}-curve`}
            value={draft.rewardCurve}
            onChange={(e) =>
              patch({ rewardCurve: e.target.value as PoolTemplateInput['rewardCurve'] })
            }
          >
            {CURVES.map((curve) => (
              <option key={curve} value={curve}>
                {curve.charAt(0).toUpperCase() + curve.slice(1)}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Minimum stake" htmlFor={`${ids}-min`} hint="Leave blank for no minimum.">
          <Input
            id={`${ids}-min`}
            type="number"
            min="0"
            step="any"
            value={draft.minStakeAmount ?? ''}
            onChange={(e) => patch({ minStakeAmount: numberOrNull(e.target.value) })}
          />
        </Field>

        <Field label="Maximum stake" htmlFor={`${ids}-max`} hint="Leave blank for no cap.">
          <Input
            id={`${ids}-max`}
            type="number"
            min="0"
            step="any"
            value={draft.maxStakeAmount ?? ''}
            onChange={(e) => patch({ maxStakeAmount: numberOrNull(e.target.value) })}
          />
        </Field>

        <Field label="Theme" htmlFor={`${ids}-theme`} hint="Short label, e.g. “Annual commitment”.">
          <Input
            id={`${ids}-theme`}
            value={draft.theme}
            onChange={(e) => patch({ theme: e.target.value })}
          />
        </Field>
      </div>

      <Field label="Description" htmlFor={`${ids}-description`} error={error}>
        <Input
          id={`${ids}-description`}
          value={draft.description}
          onChange={(e) => patch({ description: e.target.value })}
          placeholder="What this pool is for"
        />
      </Field>

      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={draft.compounding}
          onChange={(e) => patch({ compounding: e.target.checked })}
          className="size-4 rounded border-input accent-primary"
        />
        Rewards compound
      </label>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={upsert.isPending}>
          {upsert.isPending && <Loader2 className="animate-spin" />}
          {editing ? 'Save changes' : 'Create paused pool'}
        </Button>
        <Button type="button" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
