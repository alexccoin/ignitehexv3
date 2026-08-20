import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { EVM_ADDRESS, PAYOUT_NETWORKS } from './constants';
import { LockedAction } from './shared';
import { useUpdatePayoutAddresses, type AffiliateRow } from './hooks';

/**
 * Where an affiliate's commission is paid.
 *
 * The addresses are the only thing this form touches. v2's equivalent held the
 * whole affiliate row in component state and wrote it back on save, so an edit
 * to a payout address also re-wrote the status and the counters from whatever
 * the browser happened to be holding.
 *
 * Editing is currently shown as unavailable, with the reason on screen. That is
 * not caution: `seed_str_affiliates` has no member UPDATE policy, so the write
 * is filtered to zero rows and PostgREST answers `200 []` with no error —
 * confirmed by PATCHing a real row as its owner and re-reading it unchanged.
 * The form was therefore telling affiliates their payout address had moved when
 * it had not. See the TODO(server) on `useUpdatePayoutAddresses` and F-078.
 *
 * The form itself is left intact below the guard so that adding the policy or
 * the routine makes it live again by flipping one constant.
 */

/**
 * Whether a member may edit their own payout addresses.
 *
 * False until `seed_str_affiliates` gains a member UPDATE policy or a
 * `v2_member_set_affiliate_payout` routine exists. The hook checks the returned
 * rows independently, so flipping this to true cannot resurrect a silent
 * success — it would surface a real error instead.
 */
const MEMBER_MAY_EDIT_PAYOUT_ADDRESSES = false;
export function PayoutAddressForm({ affiliate }: { affiliate: AffiliateRow }) {
  const update = useUpdatePayoutAddresses();

  const [editing, setEditing] = useState(false);
  const [usdtAddress, setUsdtAddress] = useState(affiliate.usdt_address ?? '');
  const [usdtNetwork, setUsdtNetwork] = useState(affiliate.usdt_network ?? PAYOUT_NETWORKS[0]);
  const [usdcAddress, setUsdcAddress] = useState(affiliate.usdc_address ?? '');
  const [usdcNetwork, setUsdcNetwork] = useState(affiliate.usdc_network ?? PAYOUT_NETWORKS[0]);

  const usdtValid = usdtAddress.trim().length === 0 || EVM_ADDRESS.test(usdtAddress.trim());
  const usdcValid = usdcAddress.trim().length === 0 || EVM_ADDRESS.test(usdcAddress.trim());
  const canSave = usdtValid && usdcValid && !update.isPending;

  function reset() {
    setUsdtAddress(affiliate.usdt_address ?? '');
    setUsdtNetwork(affiliate.usdt_network ?? PAYOUT_NETWORKS[0]);
    setUsdcAddress(affiliate.usdc_address ?? '');
    setUsdcNetwork(affiliate.usdc_network ?? PAYOUT_NETWORKS[0]);
    setEditing(false);
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!canSave) return;

    try {
      await update.mutateAsync({
        affiliateId: affiliate.id,
        usdtAddress: usdtAddress.trim() || null,
        usdtNetwork: usdtAddress.trim() ? usdtNetwork : null,
        usdcAddress: usdcAddress.trim() || null,
        usdcNetwork: usdcAddress.trim() ? usdcNetwork : null,
      });
      toast.success('Payout addresses updated.');
      setEditing(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not update the addresses.');
    }
  }

  if (!editing) {
    return (
      <div className="space-y-3 rounded-md border border-border p-4">
        <div className="flex items-start justify-between gap-4">
          <p className="text-sm font-medium">Payout addresses</p>
          {MEMBER_MAY_EDIT_PAYOUT_ADDRESSES && (
            <Button variant="secondary" size="sm" onClick={() => setEditing(true)}>
              Edit
            </Button>
          )}
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-0.5">
            <p className="text-xs uppercase tracking-wide text-muted-foreground">
              USDT{affiliate.usdt_network ? ` · ${affiliate.usdt_network}` : ''}
            </p>
            <p className="break-all font-mono text-xs">{affiliate.usdt_address ?? 'Not set'}</p>
          </div>
          <div className="space-y-0.5">
            <p className="text-xs uppercase tracking-wide text-muted-foreground">
              USDC{affiliate.usdc_network ? ` · ${affiliate.usdc_network}` : ''}
            </p>
            <p className="break-all font-mono text-xs">{affiliate.usdc_address ?? 'Not set'}</p>
          </div>
        </div>

        {!MEMBER_MAY_EDIT_PAYOUT_ADDRESSES && (
          <LockedAction
            className="border-t border-border pt-3"
            label="Edit payout addresses"
            reason="Changing these needs an operator. The database has no policy that lets a member edit their own affiliate payout addresses, so an edit made here would be discarded without an error — raise a support ticket instead."
          />
        )}
      </div>
    );
  }

  return (
    <form className="grid gap-4 rounded-md border border-border p-4 md:grid-cols-2" onSubmit={onSubmit}>
      <p className="text-sm font-medium md:col-span-2">Payout addresses</p>

      <Field
        label="USDT address"
        htmlFor="pf-usdt"
        error={usdtValid ? undefined : 'Enter a valid EVM address (0x…).'}
      >
        <Input
          id="pf-usdt"
          value={usdtAddress}
          onChange={(e) => setUsdtAddress(e.target.value)}
          spellCheck={false}
          className="font-mono text-xs"
        />
      </Field>

      <div className="space-y-1.5">
        <Label htmlFor="pf-usdt-net">USDT network</Label>
        <select
          id="pf-usdt-net"
          value={usdtNetwork}
          onChange={(e) => setUsdtNetwork(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
        >
          {PAYOUT_NETWORKS.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </div>

      <Field
        label="USDC address"
        htmlFor="pf-usdc"
        error={usdcValid ? undefined : 'Enter a valid EVM address (0x…).'}
      >
        <Input
          id="pf-usdc"
          value={usdcAddress}
          onChange={(e) => setUsdcAddress(e.target.value)}
          spellCheck={false}
          className="font-mono text-xs"
        />
      </Field>

      <div className="space-y-1.5">
        <Label htmlFor="pf-usdc-net">USDC network</Label>
        <select
          id="pf-usdc-net"
          value={usdcNetwork}
          onChange={(e) => setUsdcNetwork(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
        >
          {PAYOUT_NETWORKS.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </div>

      <div className="flex gap-2 md:col-span-2">
        <Button type="submit" disabled={!canSave}>
          <Save aria-hidden="true" />
          {update.isPending ? 'Saving…' : 'Save addresses'}
        </Button>
        <Button type="button" variant="ghost" onClick={reset}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
