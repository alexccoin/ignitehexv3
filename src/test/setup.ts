import { afterEach, expect } from 'vitest';
import { cleanup } from '@testing-library/react';

/**
 * Global test setup.
 *
 * Unmount between tests. @testing-library/react only auto-cleans when it can
 * see a global `afterEach` at import time, and relying on that is how one test
 * ends up asserting against the previous test's DOM.
 */
afterEach(() => {
  cleanup();
});

/**
 * A matcher for the defect class this suite exists for.
 *
 * "Never a fallback" appears three times in the brief — a failed price feed, a
 * failed balance lookup, a missing amount. In every case the wrong answer is a
 * plausible number, and `toBeNull()` alone passes just as happily against a
 * function that has been quietly changed to return 0 in some other branch. This
 * asserts the distinction the code cares about: null means "not known", and 0
 * means "known to be zero".
 */
expect.extend({
  toBeUnknownNotZero(received: unknown) {
    const pass = received === null;
    return {
      pass,
      message: () =>
        pass
          ? 'expected a number, but the value was null (unknown)'
          : `expected null (unknown), got ${JSON.stringify(received)} — a number here is ` +
            'indistinguishable from a real balance or price',
    };
  },
});

/**
 * The type parameter list has to match vitest's own declaration byte for byte
 * or the merge is not a merge: `@vitest/expect` declares
 * `interface Matchers<T = any>`, and `<T = unknown>` here fails the whole
 * typecheck with
 *
 *   error TS2428: All declarations of 'Matchers' must have identical type
 *   parameters.
 *
 * The `any` is vitest's, not a choice made here, which is why it is disabled
 * on this line rather than argued with.
 */
declare module 'vitest' {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  interface Matchers<T = any> {
    toBeUnknownNotZero: () => T;
  }
}
