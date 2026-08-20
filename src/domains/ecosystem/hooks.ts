import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';

/**
 * The SourceLess ecosystem, read from the database rather than written into a
 * component.
 *
 * Everything here traces to the published 127-page "SourceLess Ecosystem
 * Overview". Each row carries the page it came from, which is the whole point:
 * a screen that describes an ecosystem is worthless if nobody can check where a
 * claim came from, and this platform already has fifteen disagreeing sources
 * for its APY schedule to prove it.
 *
 * The unusual part is `useDiscrepancies`. The overview contradicts itself in
 * several places and contradicts this database in others, and those conflicts
 * are stored and rendered rather than quietly resolved. Picking a winner would
 * mean inventing authority the source document does not give us.
 */

type Tables = Database['public']['Tables'];

export type EcosystemSection = Pick<Tables['ecosystem_section']['Row'], 'id' | 'ordinal' | 'title' | 'subtitle'>;
export type EcosystemComponent = Pick<
  Tables['ecosystem_component']['Row'],
  'id' | 'section_id' | 'ordinal' | 'name' | 'summary' | 'status' | 'status_note' | 'url' | 'source_page'
>;
export type EcosystemToken = Pick<
  Tables['ecosystem_token']['Row'],
  'symbol' | 'ordinal' | 'name' | 'role' | 'in_overview' | 'source_page'
>;
export type Discrepancy = Pick<
  Tables['ecosystem_discrepancy']['Row'],
  'id' | 'ordinal' | 'kind' | 'severity' | 'subject' | 'says_a' | 'says_b' | 'note' | 'source_page'
>;

export type ComponentStatus = 'live' | 'beta' | 'testing' | 'rnd' | 'planned' | 'unstated';

const SECTION_COLS = 'id, ordinal, title, subtitle';
const COMPONENT_COLS =
  'id, section_id, ordinal, name, summary, status, status_note, url, source_page';
const TOKEN_COLS = 'symbol, ordinal, name, role, in_overview, source_page';
const DISCREPANCY_COLS = 'id, ordinal, kind, severity, subject, says_a, says_b, note, source_page';

/** Sections and their components, in the overview's own order. */
export function useEcosystem() {
  return useQuery({
    queryKey: ['ecosystem', 'map'],
    queryFn: async (): Promise<{ sections: EcosystemSection[]; components: EcosystemComponent[] }> => {
      const [sections, components] = await Promise.all([
        supabase.from('ecosystem_section').select(SECTION_COLS).order('ordinal'),
        supabase.from('ecosystem_component').select(COMPONENT_COLS).order('ordinal'),
      ]);
      if (sections.error) throw new Error(sections.error.message);
      if (components.error) throw new Error(components.error.message);
      return { sections: sections.data ?? [], components: components.data ?? [] };
    },
  });
}

export function useEcosystemTokens() {
  return useQuery({
    queryKey: ['ecosystem', 'tokens'],
    queryFn: async (): Promise<EcosystemToken[]> => {
      const { data, error } = await supabase.from('ecosystem_token').select(TOKEN_COLS).order('ordinal');
      if (error) throw new Error(error.message);
      return data ?? [];
    },
  });
}

export function useDiscrepancies() {
  return useQuery({
    queryKey: ['ecosystem', 'discrepancies'],
    queryFn: async (): Promise<Discrepancy[]> => {
      const { data, error } = await supabase
        .from('ecosystem_discrepancy')
        .select(DISCREPANCY_COLS)
        .order('ordinal');
      if (error) throw new Error(error.message);
      return data ?? [];
    },
  });
}

/**
 * What this deployment can actually verify, as opposed to what the overview
 * asserts.
 *
 * The overview shows a live block explorer with 14M+ blocks and a 0.4s block
 * time. This reads the chain row this platform actually holds. If they
 * disagree, the page says so — that is the difference between a description and
 * a status board.
 */
export function useChainStatus() {
  return useQuery({
    queryKey: ['ecosystem', 'chain'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ledger_anchor_chain')
        .select('chain_id, name, enabled, rpc_url, explorer_url')
        .maybeSingle();
      // A missing row is a legitimate answer here — it means this deployment
      // has no chain configured at all — so it is not an error.
      if (error) return null;
      return data;
    },
  });
}

/** The ledger assets this deployment carries, for reconciling against the overview. */
export function useLedgerAssets() {
  return useQuery({
    queryKey: ['ecosystem', 'ledger-assets'],
    queryFn: async (): Promise<string[]> => {
      const { data, error } = await supabase.from('ledger_asset').select('asset').order('asset');
      if (error) return [];
      return (data ?? []).map((r) => r.asset);
    },
  });
}
