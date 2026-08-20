import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';

/**
 * The accounts tables — one component test, chosen rather than written for
 * every page.
 *
 * It earns its place because three separate things can only be observed here,
 * in rendered output:
 *
 *  1. Loading, error and empty are three states, not one. v2's tables rendered
 *     an empty table body for all three, so a failed request and an account
 *     with no wallets looked identical, and neither offered a retry.
 *  2. `maskIban` is called on the way to the screen. A unit test proves the
 *     function masks; only a render proves nothing routes around it — including
 *     the `aria-label` on the row action, which is text a screen reader speaks
 *     and which a naive fix would build from the raw IBAN.
 *  3. The `***ENCRYPTED***` sentinel does not reach the DOM. v2 printed it
 *     literally into the copy button and the share dialog.
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
const loading = <T,>(): QueryState<T> => ({
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
});
const failed = <T,>(message: string): QueryState<T> => ({
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error(message),
  refetch: vi.fn(),
});

let fiatWallets: QueryState<unknown[]>;
let ibanAccounts: QueryState<unknown[]>;
let heldTransfers: QueryState<unknown[]>;
let ibanRequests: QueryState<unknown[]>;

const mutation = () => ({ mutate: vi.fn(), isPending: false, variables: undefined });

vi.mock('./hooks', () => ({
  useFiatWallets: () => fiatWallets,
  useIbanAccounts: () => ibanAccounts,
  useHeldTransfers: () => heldTransfers,
  useIbanRequests: () => ibanRequests,
  useLinkIbanToPool: () => mutation(),
  useRefundHeldTransfer: () => mutation(),
  useRequestIbanAccount: () => mutation(),
  IBAN_CURRENCIES: [{ currency: 'EUR', country: 'BG', label: 'Euro · issued in Bulgaria' }],
  IBAN_ACCOUNT_TYPES: ['personal', 'business'],
}));

vi.mock('@/features/auth/AuthProvider', () => ({
  useAuth: () => ({ user: { id: 'u-1', email: 'member@example.test', user_metadata: {} } }),
}));

import WalletAccounts from './Accounts';

const IBAN = 'IE29AIBK93115212345678';

const ibanRow = (over: Record<string, unknown> = {}) => ({
  id: 'iban-1',
  iban: IBAN,
  bic: 'AIBKIE2D',
  currency: 'EUR',
  balance: 18_500,
  status: 'active',
  account_type: 'personal_current',
  account_holder: 'Lars Mwangi',
  country_code: 'IE',
  is_data_encrypted: false,
  created_at: '2026-01-05T10:00:00Z',
  ...over,
});

const walletRow = (over: Record<string, unknown> = {}) => ({
  id: 'w-1',
  currency: 'EUR',
  balance: 18_500,
  available_balance: 18_000,
  held_balance: 500,
  updated_at: '2026-08-19T10:00:00Z',
  ...over,
});

/** The card a section's heading belongs to, so assertions do not accidentally
 *  read the neighbouring table. */
const card = (heading: string) => {
  const el = screen.getByText(heading).closest('.panel');
  if (!el) throw new Error(`no card for ${heading}`);
  return el as HTMLElement;
};

/** The <table> inside a named card, so a card's explanatory footnotes are not
 *  mistaken for rendered data. */
const table = (heading: string) => within(card(heading)).getByRole('table');

beforeEach(() => {
  fiatWallets = idle([]);
  ibanAccounts = idle([]);
  heldTransfers = idle([]);
  ibanRequests = idle([]);
});

/* ------------------------------------------------------------------ */
/* Three states, kept apart                                            */
/* ------------------------------------------------------------------ */

describe('the cash wallets table renders three distinct states', () => {
  it('loading: skeletons, and neither the empty message nor an error', () => {
    fiatWallets = loading();
    render(<WalletAccounts />);

    expect(screen.queryByText('No cash wallets')).toBeNull();
    expect(screen.queryByText('Could not load this')).toBeNull();
    expect(within(card('Cash wallets')).queryByRole('table')).toBeNull();
    expect(card('Cash wallets').querySelectorAll('.animate-shimmer').length).toBeGreaterThan(0);
  });

  it('error: says so, offers a retry, and does NOT say the account is empty', () => {
    // This is the state v2 could not express. A member whose request failed was
    // told they had no wallets, which on a banking screen is alarming and wrong.
    fiatWallets = failed('permission denied for table fiat_wallets');
    render(<WalletAccounts />);

    expect(screen.getByText('Could not load this')).toBeDefined();
    expect(screen.getByText('permission denied for table fiat_wallets')).toBeDefined();
    expect(screen.getByRole('button', { name: 'Try again' })).toBeDefined();
    expect(screen.queryByText('No cash wallets')).toBeNull();
  });

  it('empty: says the account has none, and does not claim a failure', () => {
    fiatWallets = idle([]);
    render(<WalletAccounts />);

    expect(screen.getByText('No cash wallets')).toBeDefined();
    expect(screen.queryByText('Could not load this')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Try again' })).toBeNull();
  });

  it('rows: the table, with each figure in its own currency', () => {
    fiatWallets = idle([
      walletRow(),
      walletRow({ id: 'w-2', currency: 'USD', balance: 1_000, available_balance: 1_000, held_balance: 0 }),
    ]);
    render(<WalletAccounts />);

    const wallets = table('Cash wallets');
    expect(within(wallets).getByText('EUR')).toBeDefined();
    expect(within(wallets).getByText('USD')).toBeDefined();
    // Two currencies, two figures. Never one added-up number — the fiat form of
    // the cross-token sum in balances.ts (F-015).
    expect(wallets.textContent).toContain('18,500.00');
    expect(wallets.textContent).toContain('1,000.00');
    expect(wallets.textContent).not.toContain('19,500.00');
  });

  it('shows a zero held balance as an em dash, and a real one as a figure', () => {
    fiatWallets = idle([walletRow({ held_balance: 0 })]);
    const { unmount } = render(<WalletAccounts />);
    expect(table('Cash wallets').textContent).toContain('—');
    unmount();

    fiatWallets = idle([walletRow({ held_balance: 500 })]);
    render(<WalletAccounts />);
    expect(table('Cash wallets').textContent).toContain('500.00');
  });

  it('the error state names the failure rather than showing a bare message', () => {
    fiatWallets = failed('JWT expired');
    render(<WalletAccounts />);
    expect(screen.getByText('JWT expired')).toBeDefined();
  });
});

describe('the bank accounts table renders three distinct states', () => {
  it('loading shows skeletons, not "No bank accounts"', () => {
    ibanAccounts = loading();
    render(<WalletAccounts />);
    expect(screen.queryByText('No bank accounts')).toBeNull();
  });

  it('error is distinguishable from empty', () => {
    ibanAccounts = failed('relation "iban_accounts" does not exist');
    render(<WalletAccounts />);
    expect(screen.getByText('relation "iban_accounts" does not exist')).toBeDefined();
    expect(screen.queryByText('No bank accounts')).toBeNull();
  });

  it('empty says an IBAN is issued after review', () => {
    ibanAccounts = idle([]);
    render(<WalletAccounts />);
    expect(screen.getByText('No bank accounts')).toBeDefined();
  });
});

/* ------------------------------------------------------------------ */
/* The IBAN never reaches the DOM in full                              */
/* ------------------------------------------------------------------ */

describe('rendered IBANs', () => {
  it('never puts a full IBAN anywhere in the document', () => {
    ibanAccounts = idle([ibanRow()]);
    render(<WalletAccounts />);

    // Not in the visible text...
    expect(document.body.textContent).not.toContain(IBAN);
    // ...and not in any attribute either. The row action's aria-label is built
    // from the IBAN, and a screen reader reads it aloud.
    expect(document.body.innerHTML).not.toContain(IBAN);
  });

  it('shows the masked form, so the member can still tell which account it is', () => {
    ibanAccounts = idle([ibanRow()]);
    render(<WalletAccounts />);
    expect(screen.getByText('IE29 •••• 5678')).toBeDefined();
  });

  it('masks the IBAN in the row action\'s accessible name too', () => {
    ibanAccounts = idle([ibanRow()]);
    render(<WalletAccounts />);

    const action = screen.getByRole('button', {
      name: /Route incoming funds on .* to your main pool/,
    });
    expect(action.getAttribute('aria-label')).toContain('IE29 •••• 5678');
    expect(action.getAttribute('aria-label')).not.toContain(IBAN);
  });

  it('does not render the ***ENCRYPTED*** sentinel', () => {
    // v2 printed it literally into the copy button and the share dialog.
    ibanAccounts = idle([
      ibanRow({ iban: '***ENCRYPTED***', bic: '***ENCRYPTED***', is_data_encrypted: true }),
    ]);
    render(<WalletAccounts />);

    // Scoped to the table: the card's own footnote quotes the sentinel while
    // explaining the v2 defect, and that prose is not rendered account data.
    const rows = table('Bank accounts');
    expect(rows.textContent).not.toContain('***ENCRYPTED***');
    expect(within(rows).getAllByText('Encrypted').length).toBeGreaterThan(0);
    expect(within(rows).getByText(/BIC encrypted/)).toBeDefined();
  });

  it('masks every row when there are several accounts', () => {
    const second = 'DE89370400440532013000';
    ibanAccounts = idle([ibanRow(), ibanRow({ id: 'iban-2', iban: second, currency: 'EUR' })]);
    render(<WalletAccounts />);

    expect(document.body.innerHTML).not.toContain(IBAN);
    expect(document.body.innerHTML).not.toContain(second);
    expect(screen.getByText('DE89 •••• 3000')).toBeDefined();
  });
});

/* ------------------------------------------------------------------ */
/* Held transfers                                                      */
/* ------------------------------------------------------------------ */

describe('held transfers', () => {
  it('the card is absent entirely when nothing is held', () => {
    // An empty "funds we are holding from you" card is its own kind of alarming.
    heldTransfers = idle([]);
    render(<WalletAccounts />);
    expect(screen.queryByText('Held by the treasury')).toBeNull();
  });

  it('the card appears when a transfer is held', () => {
    heldTransfers = idle([
      {
        id: 'h-1',
        tx_id: 'tx-1',
        to_identifier: 'someone@example.com',
        currency: 'EUR',
        amount: 250,
        fee: 1,
        status: 'held',
        held_until: '2026-08-25T00:00:00Z',
        transfer_type: 'fiat',
        created_at: '2026-08-19T09:00:00Z',
      },
    ]);
    render(<WalletAccounts />);
    expect(document.body.textContent).toContain('250.00');
  });

  it('the card still appears — rather than vanishing — when the query fails', () => {
    // The early return is on "loaded and empty". A failure must not be mistaken
    // for "nothing is held": that is the one state a member most needs told.
    heldTransfers = failed('timeout');
    render(<WalletAccounts />);
    expect(screen.getByText('timeout')).toBeDefined();
  });
});
