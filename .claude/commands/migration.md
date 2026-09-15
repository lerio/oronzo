---
description: Scaffold the next Supabase migration, following the append-only rules
argument-hint: [short snake_case name, e.g. add_plan_tags]
---

Create the next migration in `supabase/migrations/`. `$0` is the intended name; if it is empty,
ask for one rather than inventing it.

## Before writing anything

Read, in this order:

1. `ls supabase/migrations/` — take the **highest** number and use the next one. Right now that
   is `0008_drop_notes_and_actuals.sql`, so the new file is `0009_$0.sql`. Zero-padded to four
   digits, matching the existing files.
2. **The newest definition of anything you are about to touch.** `save_plan` has been redefined
   in `0005`, `0006` and `0008`; the *newest* one is the current shape, not the one in `0001`.
   Copy from there, never from memory.
3. `docs/decisions.md` — the "Workout model" section, if the change touches blocks, steps, sets,
   rounds or rest. Several earlier attempts were removed on purpose and are documented as such.

## The rules

- **Append-only.** Never edit an applied migration's logic; it is a record of what already ran on
  the database. A wrong line is corrected by a new migration, not by editing history. (Comments
  are the one exception — a stale comment was corrected in `0005` during the cleanup pass.)
- **Order matters inside the file.** If you are dropping a column that a function writes to,
  redefine the function *first*, then drop. `0008` demonstrates this: `save_plan` is replaced
  above the `alter table` statements, because its body inserts into both columns being removed.
- **Report destructive changes before making them.** `0008` raises a `notice` counting the rows
  whose data is about to be lost. Do the same for anything that discards user data — a migration
  that deletes text silently is one nobody can audit afterwards.
- **Idempotent where practical.** `0002` upserts on `slug` so re-running corrects rather than
  duplicates. Use `drop ... if exists`, `create or replace`, `on conflict do ...`.
- **RLS is not optional.** Every table is scoped to `auth.uid()`, using the `(select auth.uid())`
  form so it evaluates once rather than per row. Seeded exercises are readable by any
  authenticated user and never writable; child tables authorise through an `EXISTS` check
  against their parent.
- **Grants.** A redefined function needs its grant re-stated:
  `grant execute on function public.save_plan(jsonb) to authenticated;` — `create or replace`
  does not preserve it in every case, and the existing files re-issue it every time.
- **Header comment explaining *why*.** These files are read far more often than they are run.
  Say what the change is for and what it forecloses, not what the SQL plainly says.

## After writing it

Do **not** attempt to apply it. Migrations here are applied by hand, pasted into the Supabase SQL
Editor in filename order — there is no `supabase db push` wired up, and the project has no local
Postgres.

Instead:

1. Report the filename and summarise what it does in a few lines.
2. State clearly whether it is destructive, and if so, exactly what is lost.
3. Note any code that must change in the same session — the mirrored model lives in
   `ios/OronzoCore/Sources/OronzoCore/Models.swift`, `web/src/lib/types.ts` and the Swift
   `PlanRepository`/`SessionLogger` row types, and a column change usually means touching all of
   them. A migration applied without the matching code change leaves the app broken against its
   own database.
4. If the change makes the currently-deployed web bundle invalid — e.g. it drops a column that
   bundle still selects — say so, and flag that `npm run deploy` must happen **first**.
