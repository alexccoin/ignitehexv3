import { createClient } from '@supabase/supabase-js';
import type { Database } from './database.types';

/**
 * Supabase client.
 *
 * Both values come from the environment so the same build can run against a
 * local stack or a hosted project. There is deliberately no hardcoded fallback:
 * a missing variable should fail loudly at startup rather than silently point a
 * local session at production data.
 */
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_PUBLISHABLE_KEY. Copy .env.example to .env.local.'
  );
}

export const supabase = createClient<Database>(url, key, {
  auth: { storage: localStorage, persistSession: true, autoRefreshToken: true },
});

export const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost)/.test(url);
