import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import type { Session } from '@supabase/supabase-js';

/**
 * AuthProvider — where `ready` and `rolesReady` are actually produced.
 *
 * guards.test.tsx asserts what the guards do with these two flags. This file
 * asserts that the provider ever sets them, which is the half F-021 got wrong:
 * a role lookup that ERRORS must still set rolesReady, or every guarded route
 * spins forever and the console stays empty because nothing threw.
 *
 * Two further properties are load-bearing for authorisation and easy to lose in
 * a refactor:
 *  - roles come from `user_roles`, the table the database's own RLS policies
 *    check. Reading `user_profiles.role` instead lets the UI and the server
 *    disagree about who is an admin.
 *  - a failed lookup grants nothing.
 */

type Handler = (event: string, session: Session | null) => void;

type RolesResult = { data: { role: string }[] | null; error: { message: string } | null };

let getSessionResult: { data: { session: Session | null } };
let rolesResult: RolesResult;
let selectedTable: string | null;
let selectedColumns: string | null;
let unsubscribe: ReturnType<typeof vi.fn>;
let authHandler: Handler | undefined;

/** How many role lookups have been issued, and how to hold one open.
 *
 *  Holding it open is what makes the F-021 tests real. The provider settles
 *  rolesReady=true for the signed-out first render and only flips it back to
 *  false once a session arrives, so a test that just waits for "true" can be
 *  satisfied by the state BEFORE the lookup it means to test — which is exactly
 *  how an earlier version of this file stayed green against a reintroduced
 *  F-021. With a deferred lookup the test can assert the in-flight state first,
 *  then release the lookup, and only then ask whether it settled. */
let lookups = 0;
let holdLookup = false;
let releaseLookup: ((result: RolesResult) => void) | null = null;

vi.mock('@/lib/supabase', () => ({
  isLocal: true,
  supabase: {
    auth: {
      onAuthStateChange: (cb: Handler) => {
        authHandler = cb;
        return { data: { subscription: { unsubscribe: unsubscribe } } };
      },
      getSession: () => Promise.resolve(getSessionResult),
      signOut: () => Promise.resolve({ error: null }),
    },
    from: (table: string) => {
      selectedTable = table;
      return {
        select: (columns: string) => {
          selectedColumns = columns;
          return {
            eq: () => {
              lookups++;
              if (!holdLookup) return Promise.resolve(rolesResult);
              return new Promise<RolesResult>((resolve) => {
                releaseLookup = resolve;
              });
            },
          };
        },
      };
    },
  },
}));

import { AuthProvider, useAuth } from './AuthProvider';

const SESSION = {
  user: { id: 'u1', email: 'newbie@ignitehex.local' },
} as unknown as Session;

/** Renders the auth state as text so assertions read like the real question. */
function Probe() {
  const { ready, rolesReady, roles, isAdmin, session } = useAuth();
  return (
    <ul>
      <li data-testid="ready">{String(ready)}</li>
      <li data-testid="rolesReady">{String(rolesReady)}</li>
      <li data-testid="roles">{roles.join(',') || '(none)'}</li>
      <li data-testid="isAdmin">{String(isAdmin)}</li>
      <li data-testid="session">{session ? 'yes' : 'no'}</li>
    </ul>
  );
}

const mount = () =>
  render(
    <AuthProvider>
      <Probe />
    </AuthProvider>
  );

const state = (key: string) => screen.getByTestId(key).textContent;

beforeEach(() => {
  getSessionResult = { data: { session: null } };
  rolesResult = { data: [], error: null };
  selectedTable = null;
  selectedColumns = null;
  unsubscribe = vi.fn();
  authHandler = undefined;
  lookups = 0;
  holdLookup = false;
  releaseLookup = null;
});

/** Mount with a session and wait until the role lookup for THAT session is
 *  actually in flight, so nothing below can be satisfied by the pre-session
 *  state. Returns a function that completes the lookup with the given result. */
async function mountWithLookupInFlight() {
  getSessionResult = { data: { session: SESSION } };
  holdLookup = true;
  mount();

  await waitFor(() => expect(lookups).toBe(1));
  await waitFor(() => expect(releaseLookup).not.toBeNull());
  // In flight: the guard must be spinning, not deciding.
  await waitFor(() => expect(state('rolesReady')).toBe('false'));

  return (result: RolesResult) => releaseLookup!(result);
}

describe('AuthProvider', () => {
  it('settles `ready` once the initial session lookup returns, signed out', async () => {
    mount();
    await waitFor(() => expect(state('ready')).toBe('true'));
    expect(state('session')).toBe('no');
  });

  it('settles `ready` and exposes the session when signed in', async () => {
    getSessionResult = { data: { session: SESSION } };
    mount();
    await waitFor(() => expect(state('ready')).toBe('true'));
    expect(state('session')).toBe('yes');
  });

  it('reads roles from user_roles, the table RLS itself checks', async () => {
    getSessionResult = { data: { session: SESSION } };
    rolesResult = { data: [{ role: 'user' }, { role: 'admin' }], error: null };
    mount();

    // Wait on the roles themselves, not on rolesReady: the provider settles
    // rolesReady=true for the signed-out first render, then flips it false while
    // the lookup for the arriving session is in flight. Waiting on the flag
    // alone would assert against the pre-session state.
    await waitFor(() => expect(state('roles')).toBe('user,admin'));
    expect(state('rolesReady')).toBe('true');
    expect(selectedTable).toBe('user_roles');
    expect(selectedColumns).toBe('role');
    expect(state('isAdmin')).toBe('true');
  });

  it('F-021: a role lookup that ERRORS still settles rolesReady', async () => {
    // The defect: rolesReady never became true, RequireRole waited on it, and
    // the member sat on a full-page spinner. Nothing was logged because the
    // error was handled — it just was not resolved.
    const finish = await mountWithLookupInFlight();
    finish({ data: null, error: { message: 'permission denied for table user_roles' } });

    await waitFor(() => expect(state('rolesReady')).toBe('true'), { timeout: 2_000 });
  });

  it('F-021: a role lookup that errors grants nothing', async () => {
    // Settling must not be achieved by assuming a role. Failing open here would
    // turn a transient database error into an admin session.
    const finish = await mountWithLookupInFlight();
    finish({ data: null, error: { message: 'permission denied' } });

    await waitFor(() => expect(state('rolesReady')).toBe('true'));
    expect(state('roles')).toBe('(none)');
    expect(state('isAdmin')).toBe('false');
  });

  it('F-021: a member with genuinely no roles settles empty, it does not hang', async () => {
    const finish = await mountWithLookupInFlight();
    finish({ data: [], error: null });

    await waitFor(() => expect(state('rolesReady')).toBe('true'));
    expect(state('roles')).toBe('(none)');
    expect(state('isAdmin')).toBe('false');
  });

  it('F-021: a lookup that SUCCEEDS settles it too', async () => {
    // The same waiting harness, exercised on the happy path, so a provider that
    // only settles on failure is caught as well.
    const finish = await mountWithLookupInFlight();
    finish({ data: [{ role: 'admin' }], error: null });

    await waitFor(() => expect(state('rolesReady')).toBe('true'));
    expect(state('isAdmin')).toBe('true');
  });

  it('settles rolesReady immediately for a signed-out visitor', async () => {
    // No user id means no lookup to wait for. Leaving it false would spin the
    // guard before the redirect to /auth could happen.
    mount();
    await waitFor(() => expect(state('rolesReady')).toBe('true'));
    expect(state('roles')).toBe('(none)');
  });

  it('drops the roles when the session goes away', async () => {
    getSessionResult = { data: { session: SESSION } };
    rolesResult = { data: [{ role: 'admin' }], error: null };
    mount();
    await waitFor(() => expect(state('isAdmin')).toBe('true'));

    rolesResult = { data: [], error: null };
    authHandler?.('SIGNED_OUT', null);

    await waitFor(() => expect(state('isAdmin')).toBe('false'));
    expect(state('session')).toBe('no');
  });

  it('picks up roles when a session arrives via onAuthStateChange', async () => {
    mount();
    await waitFor(() => expect(state('ready')).toBe('true'));

    rolesResult = { data: [{ role: 'support' }], error: null };
    authHandler?.('SIGNED_IN', SESSION);

    await waitFor(() => expect(state('roles')).toBe('support'));
    expect(state('rolesReady')).toBe('true');
  });

  it('unsubscribes from auth changes on unmount', async () => {
    const view = mount();
    await waitFor(() => expect(state('ready')).toBe('true'));
    view.unmount();
    expect(unsubscribe).toHaveBeenCalled();
  });

  it('throws a useful error when useAuth is called outside the provider', () => {
    // Rendering a guard outside AuthProvider silently returning undefined would
    // read as "no session" and log everybody out.
    const Orphan = () => {
      useAuth();
      return null;
    };
    expect(() => render(<Orphan />)).toThrow(/useAuth must be used inside/);
  });
});

/**
 * F-059 — the cold-load race.
 *
 * The F-021 fix set `rolesReady` inside an effect. Effects run after render, so
 * a cold load produced one render with the session already in hand, `roles`
 * still empty, and `rolesReady` still `true` left over from the signed-out
 * pass. `RequireRole` decided in that render and sent every admin to
 * `/forbidden`. Clicking a link in-app never reproduced it, which is why the
 * F-021 fix passed review — so these tests must observe EVERY render, not the
 * settled state.
 *
 * The other tests in this file use `waitFor`, which only ever sees states that
 * survive long enough to be polled; a one-render flash slips straight through.
 * Hence the recording probe below.
 */
describe('AuthProvider · cold load (F-059)', () => {
  /** Every render's auth state, in order. A transient frame cannot hide here. */
  let frames: { session: boolean; rolesReady: boolean; roles: string }[] = [];

  function RecordingProbe() {
    const { rolesReady, roles, session } = useAuth();
    frames.push({ session: !!session, rolesReady, roles: roles.join(',') });
    return <li data-testid="rolesReady">{String(rolesReady)}</li>;
  }

  const mountRecording = () =>
    render(
      <AuthProvider>
        <RecordingProbe />
      </AuthProvider>
    );

  beforeEach(() => {
    frames = [];
  });

  it('never reports ready-with-no-roles while a session is present but unresolved', async () => {
    // The member HAS a role. So any frame claiming "session present, roles
    // ready, roles empty" is the bug — it cannot be a legitimate end state.
    getSessionResult = { data: { session: SESSION } };
    holdLookup = true;
    mountRecording();

    await waitFor(() => expect(releaseLookup).not.toBeNull());
    releaseLookup!({ data: [{ role: 'admin' }], error: null });
    await waitFor(() => expect(state('rolesReady')).toBe('true'));

    const bad = frames.filter((f) => f.session && f.rolesReady && f.roles === '');
    expect(
      bad,
      `RequireRole would have redirected to /forbidden in ${bad.length} render(s)`
    ).toEqual([]);
  });

  it('never reports ready-with-no-roles when the session arrives after mount', async () => {
    // The other entry path: signed out first, then SIGNED_IN. Here the
    // signed-out branch legitimately settles rolesReady=true with no roles, so
    // only frames from after the session appears may be judged.
    holdLookup = true;
    mountRecording();
    await waitFor(() => expect(state('rolesReady')).toBe('true'));

    const beforeSession = frames.length;
    authHandler?.('SIGNED_IN', SESSION);

    await waitFor(() => expect(releaseLookup).not.toBeNull());
    releaseLookup!({ data: [{ role: 'admin' }], error: null });
    await waitFor(() => expect(state('rolesReady')).toBe('true'));

    const bad = frames
      .slice(beforeSession)
      .filter((f) => f.session && f.rolesReady && f.roles === '');
    expect(bad).toEqual([]);
  });

  it('does not carry the previous user\'s roles across a user switch', async () => {
    // Same class of bug, different trigger: if readiness is stored rather than
    // derived, user B is briefly ready with user A's roles.
    getSessionResult = { data: { session: SESSION } };
    rolesResult = { data: [{ role: 'admin' }], error: null };
    mountRecording();
    await waitFor(() => expect(state('rolesReady')).toBe('true'));

    const OTHER = { user: { id: 'u2', email: 'member@ignitehex.local' } } as unknown as Session;
    holdLookup = true;
    const at = frames.length;
    authHandler?.('SIGNED_IN', OTHER);

    await waitFor(() => expect(releaseLookup).not.toBeNull());
    const leaked = frames.slice(at).filter((f) => f.rolesReady && f.roles === 'admin');
    releaseLookup!({ data: [], error: null });

    expect(leaked, 'user u2 was briefly treated as admin').toEqual([]);
  });
});
