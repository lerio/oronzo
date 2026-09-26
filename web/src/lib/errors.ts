/**
 * Reading a failure out of a Supabase call.
 *
 * **A PostgREST error is not an `Error`.** `postgrest-js` parses the response body and hands it
 * back exactly as it arrived — `error = JSON.parse(body)` — and only wraps it in a
 * `PostgrestError` on the `shouldThrowOnError` path, which this client does not use
 * (`@supabase/postgrest-js/dist/index.mjs:512-526`). So the value reaching a `catch` is a plain
 * object: `{ code, details, hint, message }`, with `constructor.name === 'Object'`.
 *
 * That is not a detail. `err instanceof Error ? err.message : 'Delete failed'` — the idiom this
 * replaced, in eight places across six files — is **always false** here, so the fallback branch
 * was the only branch ever taken and no Supabase failure in this app ever reported its reason.
 * Deleting an exercise refused by the RESTRICT foreign key read as a bare "Delete failed".
 *
 * Anything reaching these helpers is therefore treated as `unknown` and duck-typed, never
 * `instanceof`-checked.
 */

/**
 * The message from whatever was thrown, or `fallback` when there is nothing usable to show.
 *
 * A real `Error` from a network failure has a `message` too, so this covers both shapes and the
 * call site does not have to care which it got.
 */
export function errorMessage(err: unknown, fallback: string): string {
  if (typeof err === 'object' && err !== null && 'message' in err) {
    const { message } = err as { message?: unknown };
    if (typeof message === 'string' && message.trim() !== '') return message;
  }
  return fallback;
}

/**
 * Postgres's `foreign_key_violation`, which PostgREST reports as **409 Conflict**.
 *
 * Branching on the code rather than on the message text keeps this working whatever language the
 * database reports errors in — the text is Postgres's, not ours.
 */
export function isForeignKeyViolation(err: unknown): boolean {
  return (
    typeof err === 'object' &&
    err !== null &&
    'code' in err &&
    (err as { code?: unknown }).code === '23503'
  );
}
