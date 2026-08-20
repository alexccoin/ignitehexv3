import { QueryClient } from '@tanstack/react-query';

/**
 * One query client for the app.
 *
 * v2 mounted a QueryClientProvider and then used it in exactly one file out of
 * ~1,136 query call sites, so there was no cache and no invalidation - every
 * write was followed by a hand-rolled refetch, or by nothing at all. Here every
 * read goes through react-query and every write invalidates by key.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Financial figures should not be served stale for long.
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      retry: (failureCount, error) => {
        // Authorisation failures will not succeed on retry.
        const code = (error as { code?: string } | null)?.code;
        if (code === 'PGRST301' || code === '42501') return false;
        return failureCount < 2;
      },
      refetchOnWindowFocus: true,
    },
    mutations: { retry: 0 },
  },
});

/** Query keys in one place, so invalidation cannot miss a consumer. */
export const qk = {
  profile: (userId: string) => ['profile', userId] as const,
  roles: (userId: string) => ['roles', userId] as const,
  pools: (userId: string) => ['staking-pools', userId] as const,
  available: (userId: string) => ['available-balances', userId] as const,
  transactions: (userId: string) => ['transactions', userId] as const,
  fiatWallets: (userId: string) => ['fiat-wallets', userId] as const,
  ibans: (userId: string) => ['ibans', userId] as const,
  v2Account: (userId: string) => ['v2-account', userId] as const,
  v2Claims: (userId: string) => ['v2-claims', userId] as const,
  v2Assets: (userId: string) => ['v2-assets', userId] as const,
  v2Connections: (userId: string) => ['v2-connections', userId] as const,
  adminAccounts: (status: string) => ['admin', 'v2-accounts', status] as const,
  adminClaims: (status: string) => ['admin', 'v2-claims', status] as const,
} as const;
