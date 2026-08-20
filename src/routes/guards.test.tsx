import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import type { Session } from '@supabase/supabase-js';

/**
 * Route guards.
 *
 * Three things have to hold and only one of them is obvious:
 *
 *  - no session   -> /auth
 *  - session, no role -> /forbidden
 *  - session with the role -> the page
 *
 * The fourth is the one that shipped broken. `rolesReady` and `roles.length`
 * are different questions. The guard used to wait on the second, so a member
 * with no roles at all — and, worse, any user whose role lookup *failed* — sat
 * on a spinner forever with nothing in the console (F-021). "The lookup has
 * settled" and "the lookup found something" must stay distinct, and the two
 * tests marked F-021 below fail if they are conflated again in either
 * direction.
 */

type AppRole = 'admin' | 'user' | 'moderator' | 'support' | 'legal';

interface FakeAuth {
  session: Session | null;
  ready: boolean;
  rolesReady: boolean;
  roles: AppRole[];
}

let auth: FakeAuth;

vi.mock('@/features/auth/AuthProvider', () => ({
  useAuth: () => ({
    ...auth,
    user: auth.session?.user ?? null,
    isAdmin: auth.roles.includes('admin'),
    hasRole: (role: AppRole) => auth.roles.includes(role),
    signIn: vi.fn(),
    signUp: vi.fn(),
    signOut: vi.fn(),
  }),
}));

import { RequireAuth, RequireRole, RedirectIfAuthed } from './guards';

const SESSION = { user: { id: 'u1', email: 'newbie@ignitehex.local' } } as unknown as Session;

const set = (state: Partial<FakeAuth>) => {
  auth = { session: null, ready: true, rolesReady: true, roles: [], ...state };
};

beforeEach(() => set({}));

/** Mount a guard at /ops with the two redirect targets also mounted, so a
 *  redirect is observable as a rendered destination rather than as an absence. */
function mount(guard: React.ReactNode, at = '/ops') {
  return render(
    <MemoryRouter initialEntries={[at]}>
      <Routes>
        <Route path="/ops" element={guard} />
        <Route path="/ops/deep" element={guard} />
        <Route path="/auth" element={<div>SIGN IN PAGE</div>} />
        <Route path="/forbidden" element={<div>FORBIDDEN PAGE</div>} />
        <Route path="/" element={<div>HOME PAGE</div>} />
      </Routes>
    </MemoryRouter>
  );
}

const PAGE = <div>OPERATIONS CONSOLE</div>;

const shows = (text: string) => expect(screen.queryByText(text)).not.toBeNull();
const hides = (text: string) => expect(screen.queryByText(text)).toBeNull();

/* ------------------------------------------------------------------ */

describe('RequireAuth', () => {
  it('redirects to /auth when there is no session', () => {
    set({ session: null, ready: true });
    mount(<RequireAuth>{PAGE}</RequireAuth>);
    shows('SIGN IN PAGE');
    hides('OPERATIONS CONSOLE');
  });

  it('renders the page when there is a session', () => {
    set({ session: SESSION, ready: true });
    mount(<RequireAuth>{PAGE}</RequireAuth>);
    shows('OPERATIONS CONSOLE');
    hides('SIGN IN PAGE');
  });

  it('shows the spinner while the session lookup is still in flight', () => {
    // Redirecting here bounces an already-signed-in member to the login page on
    // every page reload, before their restored session has arrived.
    set({ session: null, ready: false });
    mount(<RequireAuth>{PAGE}</RequireAuth>);
    shows('Loading');
    hides('SIGN IN PAGE');
    hides('OPERATIONS CONSOLE');
  });

  it('does not wait once ready is true, even with no session', () => {
    set({ session: null, ready: true });
    mount(<RequireAuth>{PAGE}</RequireAuth>);
    hides('Loading');
    shows('SIGN IN PAGE');
  });
});

describe('RequireRole', () => {
  it('renders the page when the user holds the role', () => {
    set({ session: SESSION, ready: true, rolesReady: true, roles: ['user', 'admin'] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('OPERATIONS CONSOLE');
  });

  it('redirects to /forbidden when the session lacks the role', () => {
    set({ session: SESSION, ready: true, rolesReady: true, roles: ['user'] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('FORBIDDEN PAGE');
    hides('OPERATIONS CONSOLE');
  });

  it('redirects to /auth — not /forbidden — when there is no session at all', () => {
    // Sending a signed-out visitor to /forbidden tells them they are not
    // allowed in when what they actually need is to sign in.
    set({ session: null, ready: true, rolesReady: true, roles: [] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('SIGN IN PAGE');
    hides('FORBIDDEN PAGE');
  });

  it('F-021: rolesReady=false shows the spinner', () => {
    set({ session: SESSION, ready: true, rolesReady: false, roles: [] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('Loading');
    hides('FORBIDDEN PAGE');
    hides('OPERATIONS CONSOLE');
  });

  it('F-021: rolesReady=true with roles=[] does NOT spin — it forbids', () => {
    // This is the exact conflation that spun forever. An empty role list is a
    // settled answer: this member has no roles. Waiting for it to become
    // non-empty waits for something that will never happen.
    set({ session: SESSION, ready: true, rolesReady: true, roles: [] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    hides('Loading');
    shows('FORBIDDEN PAGE');
  });

  it('F-021: a settled-but-empty lookup denies rather than grants', () => {
    // The other way of getting this wrong: treating "no roles yet" as
    // permissive so the spinner goes away. That would open every admin console.
    set({ session: SESSION, ready: true, rolesReady: true, roles: [] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    hides('OPERATIONS CONSOLE');
  });

  it('still waits on the session lookup before the role lookup', () => {
    set({ session: null, ready: false, rolesReady: true, roles: [] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('Loading');
    hides('SIGN IN PAGE');
  });

  it('defaults to requiring admin when no role is named', () => {
    // Every call site that forgets the prop must fail closed.
    set({ session: SESSION, ready: true, rolesReady: true, roles: ['user'] });
    mount(<RequireRole>{PAGE}</RequireRole>);
    shows('FORBIDDEN PAGE');
  });

  it('checks the role it was given, not just admin', () => {
    set({ session: SESSION, ready: true, rolesReady: true, roles: ['support'] });
    mount(<RequireRole role="support">{PAGE}</RequireRole>);
    shows('OPERATIONS CONSOLE');

    set({ session: SESSION, ready: true, rolesReady: true, roles: ['support'] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('FORBIDDEN PAGE');
  });

  it('does not let one role stand in for another', () => {
    // 'moderator' is not 'admin'. v2's two sidebars disagreed about exactly
    // this, one offering moderator entries and the other seed_str_admin.
    set({ session: SESSION, ready: true, rolesReady: true, roles: ['moderator'] });
    mount(<RequireRole role="admin">{PAGE}</RequireRole>);
    shows('FORBIDDEN PAGE');
  });
});

describe('RedirectIfAuthed', () => {
  it('renders the sign-in page for a visitor with no session', () => {
    set({ session: null, ready: true });
    render(
      <MemoryRouter initialEntries={['/auth']}>
        <Routes>
          <Route path="/auth" element={<RedirectIfAuthed>{<div>SIGN IN PAGE</div>}</RedirectIfAuthed>} />
          <Route path="/" element={<div>HOME PAGE</div>} />
        </Routes>
      </MemoryRouter>
    );
    shows('SIGN IN PAGE');
  });

  it('sends an already-signed-in visitor home', () => {
    set({ session: SESSION, ready: true });
    render(
      <MemoryRouter initialEntries={['/auth']}>
        <Routes>
          <Route path="/auth" element={<RedirectIfAuthed>{<div>SIGN IN PAGE</div>}</RedirectIfAuthed>} />
          <Route path="/" element={<div>HOME PAGE</div>} />
        </Routes>
      </MemoryRouter>
    );
    shows('HOME PAGE');
    hides('SIGN IN PAGE');
  });

  it('waits rather than flashing the login form during the session lookup', () => {
    set({ session: null, ready: false });
    render(
      <MemoryRouter initialEntries={['/auth']}>
        <Routes>
          <Route path="/auth" element={<RedirectIfAuthed>{<div>SIGN IN PAGE</div>}</RedirectIfAuthed>} />
        </Routes>
      </MemoryRouter>
    );
    shows('Loading');
    hides('SIGN IN PAGE');
  });
});
