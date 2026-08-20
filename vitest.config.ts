import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react-swc';
import path from 'path';

/**
 * Test configuration.
 *
 * Separate from vite.config.ts so the dev/build config carries no test-only
 * settings, and so `defineConfig` here is the one from `vitest/config` that
 * actually types the `test` block.
 *
 * happy-dom rather than jsdom: `src/lib/supabase.ts` touches `localStorage` at
 * module scope, so anything that transitively imports it needs a DOM even in a
 * "unit" test. Most tests mock that module out, but the environment has to
 * exist for the ones that do not.
 *
 * There is deliberately no coverage threshold. Coverage on this codebase is a
 * number, not a safety property: the tests here are chosen because a specific
 * defect class has actually shipped (see docs/FINDINGS.md F-015, F-021, F-035),
 * and a threshold would pull effort towards files where nothing has ever gone
 * wrong.
 */
export default defineConfig({
  plugins: [react()],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, './src') } },
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    // The env vars src/lib/supabase.ts demands. Set here rather than read from
    // .env.local so the suite is hermetic: no test may reach a real stack, and
    // a developer without a .env.local can still run it. The URL is invalid on
    // purpose — a request that escapes a mock should fail loudly.
    env: {
      VITE_SUPABASE_URL: 'http://localhost:1/never-reached',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'test-anon-key',
    },
  },
});
