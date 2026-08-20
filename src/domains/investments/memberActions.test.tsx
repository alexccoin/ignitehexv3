import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';

/**
 * The two member actions that write: applying to a seed round, and ordering
 * node licences.
 *
 * A render test rather than a unit test, because the three things that can go
 * wrong here are only observable on screen:
 *
 *  1. The page renders at all. Both screens are lazy routes behind a suspense
 *     boundary, and a throw inside one shows as an empty frame rather than an
 *     error — v3's rule is that a blank frame is a failure, so something has to
 *     assert that words arrive.
 *  2. The submission is visible afterwards. A submit button that posts a row
 *     and then shows nothing is how v2 lost track of what a member had asked
 *     for; both forms have to list the member's own pending rows.
 *  3. The order form survives the empty state. Node ordering used to live
 *     inside the holdings <Async>, whose "you have no nodes" branch renders for
 *     precisely the member who wants to buy one.
 *
 * What is deliberately *not* asserted here is that a member cannot approve
 * their own submission. That is an RLS question, it was checked against a live
 * PostgREST endpoint, and asserting it in a test that mocks the data layer
 * would only prove the mock.
 */

type QueryState<T> = {
  data: T | undefined;
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  refetch: () => void;
};

const idle = <T,>(data: T): QueryState<T> => ({
  data,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
});

const createSeedApplication = vi.fn();
const createStarwOrder = vi.fn();

let commitments: QueryState<unknown[]>;
let starw: QueryState<Record<string, unknown>>;

vi.mock('./hooks', () => ({
  useMyCommitments: () => commitments,
  useMyIpoListingRequests: () => idle([]),
  useCreateIpoListingRequest: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useCreateSeedApplication: () => ({ mutateAsync: createSeedApplication, isPending: false }),
  useStarwHoldings: () => starw,
  useShareHoldings: () => idle({ shares: null, vesting: [] }),
  useFounderPortfolio: () => idle({ hasAccess: false, pools: [], positions: [], transactions: [] }),
  useCreateStarwOrder: () => ({ mutateAsync: createStarwOrder, isPending: false }),
}));

vi.mock('@/features/auth/AuthProvider', () => ({
  useAuth: () => ({ user: { id: 'u-1', email: 'investor1@ignitehex.local' } }),
}));

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

import ApplicationsPage from './ApplicationsPage';
import PositionsPage from './PositionsPage';

beforeEach(() => {
  createSeedApplication.mockReset().mockResolvedValue('new-id');
  createStarwOrder.mockReset().mockResolvedValue('new-id');
  commitments = idle([]);
  starw = idle({ nodes: [], supernodes: [], purchases: [], rewards: [] });
});

/** Fill the four consent boxes the seed form requires. */
function consent() {
  for (const title of [
    'Subscription terms',
    'Non-disclosure',
    'Risk disclosure',
    'Data processing',
  ]) {
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(title) }));
  }
}

describe('seed application form', () => {
  it('renders the round, and does not submit until the amount and consents are valid', async () => {
    render(<ApplicationsPage />);

    expect(screen.getByRole('heading', { name: 'Apply to a round' })).toBeTruthy();

    const submit = screen.getByRole('button', { name: /Submit application/ });
    expect((submit as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(screen.getByLabelText('Full name', { selector: '#seed-name' }), {
      target: { value: 'Investor One' },
    });
    // Below the tier floor: still refused.
    fireEvent.change(screen.getByLabelText(/Amount \(USD\)/), { target: { value: '500' } });
    consent();
    expect((submit as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(screen.getByLabelText(/Amount \(USD\)/), { target: { value: '25000' } });
    expect((submit as HTMLButtonElement).disabled).toBe(false);

    fireEvent.click(submit);
    await vi.waitFor(() => expect(createSeedApplication).toHaveBeenCalledTimes(1));

    // The share and STR figures must be the same conversion the read path uses.
    expect(createSeedApplication.mock.calls[0][0]).toMatchObject({
      round: 'seed_str',
      amountUsd: 25000,
      tier: 'retail_tier1',
      termsAccepted: true,
    });
  });

  it('asks for an address and a signature only on the private round', () => {
    render(<ApplicationsPage />);
    expect(screen.queryByLabelText('Street address')).toBeNull();

    fireEvent.click(screen.getByRole('radio', { name: 'Private STR seed round' }));
    expect(screen.getByLabelText('Street address')).toBeTruthy();
    expect(screen.getByLabelText('Signature - first name')).toBeTruthy();
  });

  it('shows the member their own pending application', () => {
    commitments = idle([
      {
        id: 'a-1',
        kind: 'seed_str',
        offering: 'STR seed round (retail_tier1)',
        status: 'pending',
        paymentStatus: 'awaiting_payment',
        amountUsd: 25000,
        quantity: 5000,
        quantityUnit: 'shares',
        createdAt: '2026-08-20T07:40:00.000Z',
        paymentDeadline: null,
      },
    ]);
    render(<ApplicationsPage />);

    const awaiting = screen.getByRole('heading', { name: 'Applications awaiting a decision' })
      .parentElement as HTMLElement;
    expect(within(awaiting).getByText('STR seed round (retail_tier1)')).toBeTruthy();
    expect(within(awaiting).getAllByText(/pending/i).length).toBeGreaterThan(0);
  });
});

describe('node order form', () => {
  it('is reachable by a member who holds no nodes at all', () => {
    render(<PositionsPage />);
    expect(screen.getByRole('heading', { name: 'Order node licences' })).toBeTruthy();
    expect(screen.getByRole('button', { name: /Order nodes/ })).toBeTruthy();
  });

  it('prices the order from the published USD price and submits no crypto amount', async () => {
    render(<PositionsPage />);

    fireEvent.change(screen.getByLabelText('Full name', { selector: '#node-name' }), {
      target: { value: 'Investor One' },
    });
    fireEvent.change(screen.getByLabelText(/^Nodes/), { target: { value: '3' } });

    expect(screen.getByText(/US\$39,000\.00 at US\$13,000\.00 per node/)).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: /Order nodes/ }));
    await vi.waitFor(() => expect(createStarwOrder).toHaveBeenCalledTimes(1));

    expect(createStarwOrder.mock.calls[0][0]).toEqual({
      nodeCount: 3,
      fullName: 'Investor One',
      emailAddress: 'investor1@ignitehex.local',
      strDomain: null,
      walletAddress: null,
      paymentMethod: 'btc',
    });
  });

  it('refuses an order larger than the node numbers the database permits', () => {
    render(<PositionsPage />);
    fireEvent.change(screen.getByLabelText('Full name', { selector: '#node-name' }), {
      target: { value: 'Investor One' },
    });
    fireEvent.change(screen.getByLabelText(/^Nodes/), { target: { value: '101' } });

    expect((screen.getByRole('button', { name: /Order nodes/ }) as HTMLButtonElement).disabled).toBe(
      true
    );
    expect(screen.getByText(/Between 1 and 100 whole nodes/)).toBeTruthy();
  });

  it('shows the member their own pending order', () => {
    starw = idle({
      nodes: [],
      supernodes: [],
      purchases: [
        {
          id: 'o-1',
          node_count: 3,
          total_cost: 39000,
          status: 'pending',
          stage: 0,
          arss_bonus: '3,000 ARSS',
          created_at: '2026-08-20T07:40:00.000Z',
          processed_at: null,
        },
      ],
      rewards: [],
    });
    render(<PositionsPage />);

    const awaiting = screen.getByRole('heading', { name: 'Orders awaiting a decision' })
      .parentElement as HTMLElement;
    expect(within(awaiting).getByText('3 nodes')).toBeTruthy();
    expect(within(awaiting).getAllByText(/pending/i).length).toBeGreaterThan(0);
  });
});
