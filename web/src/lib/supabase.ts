import { createClient } from '@supabase/supabase-js';

/**
 * The `sb_publishable_…` key is designed to be shipped to clients — it carries no
 * privileges of its own. Every table is protected by row-level security, so a signed-out
 * request can read and write nothing. The `sb_secret_…` key must never appear here.
 */
const url = import.meta.env.VITE_SUPABASE_URL;
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !publishableKey) {
  throw new Error(
    'Missing VITE_SUPABASE_URL and/or VITE_SUPABASE_PUBLISHABLE_KEY. ' +
      'Copy web/.env.example to web/.env.local and fill them in.',
  );
}

export const supabase = createClient(url, publishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});
