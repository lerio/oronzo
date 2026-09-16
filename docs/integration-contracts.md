# Integration contracts

The same domain model is written **three times, in three languages, and nothing enforces that
they agree.** A change in one and not the others is the single most likely way this codebase
breaks, and it breaks *quietly* — the web preview flattens differently from the engine, so a
workout reads one way when you build it and runs another way when you do it.

Read this before changing anything about blocks, steps, sets, rounds, rest, or the plan/session
schema. Then run the `contract-auditor` agent.

## The three mirrors

| Concern | Swift | TypeScript | SQL |
|---|---|---|---|
| Flattening rule | `OronzoCore/PlanFlattener.swift` | `flattenPlan`, `web/src/lib/types.ts` | `save_plan` in `supabase/migrations/` |
| Plan shape | `OronzoCore/Models.swift` | `types.ts` (`Plan`/`PlanBlock`/`PlanStep`) | `plans`, `plan_blocks`, `plan_steps` |
| Reading a plan | `PlanRepository.swift` select string | `api.ts` `PLAN_SELECT` | the column names themselves |
| Writing a session | `SessionLogger.swift` wire types | — | `sessions`, `session_steps` |

The flattening rule itself is stated in full in `AGENTS.md`. What follows is the field-level and
wire-level detail that the pseudocode does not carry.

## Current schema (post-`0008`)

Migrations are **cumulative and append-only**, so `0001` is not the current shape. This is the
shape as of `0008_drop_notes_and_actuals.sql`; check the newest file before assuming.

```
plans          id, user_id, name, created_at, updated_at
plan_blocks    id, plan_id, position, name, rounds, rest_between_rounds_seconds, created_at, updated_at
plan_steps     id, block_id, exercise_id NOT NULL, position, label, sets, mode,
               duration_seconds, reps, target_weight_kg, rest_after_seconds, created_at, updated_at

sessions       id, user_id, plan_id, plan_name, started_at, finished_at, status,
               total_duration_seconds, notes, created_at, updated_at
session_steps  id, session_id, position, set_index, block_round, block_name, kind,
               exercise_id, exercise_name, planned_mode, planned_duration_seconds,
               planned_reps, planned_weight_kg, actual_duration_seconds, status, created_at
```

Columns that **no longer exist**, and must not reappear in a select string or a model:
`plan_steps.kind` and `plan_steps.notes` (dropped in `0006`/`0008`), `plans.notes` (`0008`),
`plan_steps.reps_max` / `target_weight_max_kg` (`0004`), `session_steps.actual_reps` /
`actual_weight_kg` (`0008`), `session_steps.round_index` (renamed `set_index` in `0005`).

`sessions.notes` still exists but nothing reads or writes it — see `known-issues.md`.

### Enforced in the database, not the client

`plan_steps` carries constraints the clients deliberately mirror so failures surface as readable
messages rather than raw Postgres errors:

- `exercise_id` is **NOT NULL** after `0006`. A step is always an exercise.
- `plan_steps_mode_shape`: `mode = 'time'` requires `duration_seconds`; `mode = 'reps'` requires
  `reps`.
- `plan_steps_sets_positive`: `sets >= 1`.
- `session_steps.status` allows `pending | completed | skipped | not_reached`.

`web/src/routes/PlanEditor.tsx` `stepProblem()` mirrors the first three exactly, and is applied
per row plus aggregated to gate the Save button (`"Fix N step(s) before saving"`).

## The `save_plan` payload

The **only** way a plan is written. Defined in six migrations; the newest is in `0008`. It is a
whole-tree replace: it upserts `plans` by id (raising `42501` if the row is not the caller's),
then `delete from plan_blocks where plan_id = …` and re-inserts every block and step.

```jsonc
{
  "id": "<uuid or null>",          // null → server generates
  "name": "…",
  "blocks": [{
    "name": …, "rounds": 3, "rest_between_rounds_seconds": …,
    "steps": [{
      "exercise_id": "<uuid>", "label": …, "sets": 4, "mode": "reps",
      "duration_seconds": …, "reps": 8, "target_weight_kg": …,
      "rest_after_seconds": …
    }]
  }]
}
```

Three things about this that surprise people:

- **`position` is ignored.** The web sends it; the RPC overwrites it from its own loop counters
  (`v_block_pos`, `v_step_pos`). Array order *is* position order. Don't add position handling
  server-side.
- **Every save mints new block and step UUIDs**, because the tree is deleted and re-inserted.
  Never hold a `plan_steps.id` across a save. (The `id?` fields on `PlanBlock`/`PlanStep` in
  `types.ts` are therefore vestigial on the web path.)
- **Empty strings are coerced to NULL** throughout (`nullif(v_step->>'label', '')`), so `''` never
  round-trips. The web sends `null` for absent values, matching.

`save_plan` is `security invoker` with `set search_path = public`, so RLS still applies to every
statement inside it. A redefined function needs its grant re-stated —
`grant execute on function public.save_plan(jsonb) to authenticated;` — which is why every
migration that redefines it repeats the line.

## The Watch wire format

The whole phone↔watch vocabulary is one file: `ios/OronzoCore/Sources/OronzoCore/Link.swift`.

```swift
enum WatchMessage  { case session(SessionSnapshot), sessionEnded }   // phone → watch
enum WatchControl  { case next, previous, togglePause, finish }      // watch → phone

struct SessionSnapshot { planName, intervals: [Interval], startedAt, state: SessionState }
struct SessionState    { currentIndex, isPaused, isFinished, intervalEnd: Date?,
                         remainingWhenPaused: TimeInterval? }
```

**`SessionSnapshot` is always complete, and that is not a style choice.** The application context
is a *single slot* — whatever is written last is all that survives. Sending a "start" and then an
"update" back to back leaves only the update, so a watch app that was asleep at that moment wakes
to a position with no plan in it and sits showing "no workout" while the phone believes it has
been told everything. Sending the plan every time costs a few kilobytes and removes that entire
class of bug. **Do not optimise this into incremental messages.**

**`intervalEnd` is an absolute `Date`, never a countdown.** That is what lets the watch stay
correct across a suspension with no further traffic. A rep interval has *no* end date, which is
how the watch knows to stop walking the list and wait to be told.

### Transport

| Direction | Primary | Also |
|---|---|---|
| Phone → Watch | `updateApplicationContext` (always) | `sendMessage` only if `isReachable`, to make a reachable watch update instantly |
| Watch → Phone | `sendMessage` if `isReachable` | `transferUserInfo` otherwise — "Queued for when the phone is next awake, rather than dropped" |

`SessionController.pushState(force:)` dedupes against `lastPushedState` so the 10 Hz engine tick
does not spam the context; forces are used at start.

Two guards exist purely because the application context has no expiry:

- `PhoneConnectivity.clearIfIdle()` — a phone force-quit mid-workout would otherwise leave the
  watch showing a session that no longer exists.
- `WatchLink.refreshFromContext()` — with the wrist down the watch is suspended, and a suspended
  app is *not* woken by WatchConnectivity. Raising the wrist **resumes** it rather than
  re-activating, so `activationDidComplete` does not fire again. This is the fix that made the
  watch see workouts at all.

### Projection

`WatchProjection.project(intervals:from:end:now:)` walks forward from the phone's anchor while
`now >= boundary`, adding each next interval's duration, and **stops dead at a rep interval**
(it has no length, so nothing can be assumed about when it finishes). The watch re-renders on a
0.25 s `TimelineView` and fires its own haptics from the same projection — "a buzz is exactly what
you need when you are not looking at either screen."

## Changing the model safely

1. Change the SQL first if the shape changes — and remember migrations are append-only, applied by
   hand, in filename order.
2. Update all three: `Models.swift`, `types.ts`, and the newest `save_plan`.
3. Update both hand-written select strings. A column dropped from the database but still named in
   a select string produces a **runtime 400 in an app on a device** — `tsc -b` cannot catch it.
4. If the change makes the currently-deployed web bundle invalid, **deploy before migrating** —
   the deployed bundle is what breaks, not the new build. `/deploy` exists to make you answer this
   question before shipping.
5. Run `swift test`, then the `contract-auditor` agent.
