import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';

type AppRole = Database['public']['Enums']['app_role'];

interface AuthState {
  session: Session | null;
  user: User | null;
  roles: AppRole[];
  /** False until the initial session lookup has settled. Guards must wait for
   *  this, otherwise a signed-in user is bounced to the login page on reload. */
  ready: boolean;
  /** True once the role lookup has settled, whether or not it found any. */
  rolesReady: boolean;
  isAdmin: boolean;
  hasRole: (role: AppRole) => boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, fullName: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  /** The user id the loaded roles belong to; null before any lookup settles. */
  const [rolesForUserId, setRolesForUserId] = useState<string | null | undefined>(undefined);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let active = true;

    // onAuthStateChange fires immediately with the restored session, but it can
    // race with the initial getSession on a cold load, so both are handled and
    // the later one wins.
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      if (!active) return;
      setSession(next);
      if (!next) setRoles([]);
    });

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      setSession(data.session);
      setReady(true);
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  // Roles come from user_roles, which is the table the database's own RLS
  // policies check. Reading profiles.role instead would let the two disagree.
  useEffect(() => {
    const userId = session?.user?.id ?? null;
    if (!userId) {
      setRoles([]);
      setRolesForUserId(null);
      return;
    }

    let active = true;
    supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', userId)
      .then(({ data, error }) => {
        if (!active) return;
        if (error) {
          // A failed role lookup must not grant anything — but it must also
          // resolve, or every guarded route spins forever.
          setRoles([]);
          setRolesForUserId(userId);
          return;
        }
        setRoles((data ?? []).map((r) => r.role));
        setRolesForUserId(userId);
      });

    return () => {
      active = false;
    };
  }, [session?.user?.id]);

  const value = useMemo<AuthState>(() => {
    const hasRole = (role: AppRole) => roles.includes(role);
    // Derived, not stored: roles are ready only when they belong to the session
    // currently in hand. A boolean set in an effect lags by one render.
    const rolesReady = rolesForUserId === (session?.user?.id ?? null);
    return {
      session,
      user: session?.user ?? null,
      roles,
      ready,
      rolesReady,
      isAdmin: hasRole('admin'),
      hasRole,
      async signIn(email, password) {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      },
      async signUp(email, password, fullName) {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { full_name: fullName },
            emailRedirectTo: `${window.location.origin}/auth`,
          },
        });
        if (error) throw error;
      },
      async signOut() {
        await supabase.auth.signOut();
        setRoles([]);
      },
    };
  }, [session, roles, ready, rolesForUserId]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
