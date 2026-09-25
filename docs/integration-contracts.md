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
| Exercise facts the flattener needs | `OronzoCore/Models.swift` (`ExerciseInfo`) | the `Exercise` record itself | `exercises.name`, `exercises.has_two_sides` |
| Plan shape | `OronzoCore/Models.swift` (`Intensity`) | `types.ts` (`Plan`/`PlanBlock`/`PlanStep`, `INTENSITIES`) | `plans`, `plan_blocks`, `plan_steps` |
| Reading a plan | `PlanRepository.swift` select string | `api.ts` `PLAN_SELECT` | the column names themselves |
| Writing a session | `SessionLogger.swift` wire types | — | `sessions`, `session_steps` |

The flattening rule itself is stated in full in `AGENTS.md`. What follows is the field-level and
wire-level detail that the pseudocode does not carry.

## Current schema (post-`0013`)

Migrations are **cumulative and append-only**, so `0001` is not the current shape. This is the
shape as of `0013_step_intensity.sql`; check the newest file before assuming.

```
exercises      id, user_id, slug, name, muscle_group, default_mode,
               default_duration_seconds, default_reps, has_two_sides, notes, created_at, updated_at

plans          id, user_id, name, created_at, updated_at
plan_blocks    id, plan_id, position, name, rounds, rest_between_rounds_seconds, created_at, updated_at
plan_steps     id, block_id, exercise_id NOT NULL, position, label, sets, mode,
               duration_seconds, reps, target_weight_kg, rest_after_seconds,
               intensity, created_at, updated_at

sessions       id, user_id, plan_id, plan_name, started_at, finished_at, status,
               total_duration_seconds, notes, created_at, updated_at
session_steps  id, session_id, position, set_index, block_round, block_name, kind,
               exercise_id, exercise_name, planned_mode, planned_duration_seconds,
               planned_reps, planned_weight_kg, actual_duration_seconds, status, created_at
```

`plan_steps.intensity` (`0013`) is the one column whose **values** are a closed set — `low`,
`medium` or `hard`, enforced by a check constraint on the same three words `Intensity` and
`INTENSITIES` declare. It is nullable, and it rides to the screens as an *optional* field on
`Interval`: an older snapshot decodes without it and a nil one is omitted from the JSON entirely,
which is what `docs/decisions.md` records as the rule for adding anything to that type.

One column changed meaning with `0012`: `session_steps.exercise_name` is now the *interval's*
name, so a two-sided exercise logs two rows per set as `Reverse Lunge (left)` and `Reverse Lunge
(right)`, sharing a `set_index`. Nothing groups or joins on it, and the alternative — stripping
the side before logging — would lose which side the row was. It is a display string, deliberately.

Columns that **no longer exist**, and must not reappear in a select string or a model:
`plan_steps.kind` and `plan_steps.notes` (dropped in `0006`/`0008`), `plans.notes` (`0008`),
`plan_steps.reps_max` / `target_weight_max_kg` (`0004`), `session_steps.actual_reps` /
`actual_weight_kg` (`0008`), `session_steps.round_index` (renamed `set_index` in `0005`), `exercises.equipment` (`0011`).

`exercises` is in this list for the first time because the flattener reads two of its columns —
`name` and `has_two_sides` — which is why the phone's exercise fetch is a hand-written select
string and not a `select('*')`. **The iOS app is the only surface that reads a named column set**,
so it is the only one a missing column can `400`:

```
GET /rest/v1/exercises?select=id,name,has_two_sides
```

The side suffix the flattener writes is spelled `"… (left)"` / `"… (right)"` in both mirrors —
`PlanFlattener.sideSuffixes` and `sideSuffixes` in `types.ts` — and it goes into `Interval.name`,
never into `PlanFlattener.name(for:)`, which the plan detail screen uses to list a plan as
authored. A two-sided exercise therefore doubles an interval stream and *not* a step list, and
`PlanSummary`'s rep estimate reads the same `sideSuffixes` rather than its own copy of the rule.

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
enum WatchControl  { case next, previous, togglePause, requestState, finish }  // watch → phone

struct SessionSnapshot { planName, intervals: [Interval], startedAt, state: SessionState }
struct SessionState    { currentIndex, isPaused, isFinished, intervalEnd: Date?,
                         remainingWhenPaused: TimeInterval?, finishedAt: Date? }
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

### The watch asks

`requestState` is the one control the phone answers itself rather than forwarding to the session,
because it has to be answerable when **no session is running** — which is exactly when the watch
asks. The reply is `PhoneConnectivity.answer()`: the live session's `currentMessage`, or
`.sessionEnded` when there is none.

It exists because the phone used to speak only when its own state changed, so anything the watch
missed stayed missed. There is no error anywhere in that path: a write that landed before the
phone's `WCSession` finished activating, a snapshot overwritten by a `sessionEnded` from a runner
that was no longer the live one, a resume from a wrist-drop suspension that was never handed the
context it missed — all of them leave the wrist on "No workout", which looks exactly like a phone
that never started a workout. The ask is what turns each of those from a permanently wrong screen
into a sub-second recovery.

The watch asks on becoming active and when activation completes — the two moments it can be *sure*
it is awake, since a cold launch does not necessarily produce a `scenePhase` change. When the
phone is out of range it only queues the ask if there is nothing on screen to lose; otherwise the
phone's own push, or the stored context on the next wake, already covers it. **One message per
wrist raise, not a stream** — the prohibition in `docs/decisions.md` is on per-second traffic.

### Transport

| Direction | Primary | Also |
|---|---|---|
| Phone → Watch | `updateApplicationContext` (always) | `sendMessage` only if `isReachable`, to make a reachable watch update instantly |
| Watch → Phone | `sendMessage` if `isReachable` | `transferUserInfo` otherwise — "Queued for when the phone is next awake, rather than dropped" |

`SessionController.pushState(force:)` dedupes against `lastPushedState` so the 10 Hz engine tick
does not spam the context; forces are used at start. `PhoneConnectivity.answer()` deliberately
does **not** dedupe — what the watch asks for is the state *now*, built on demand from the live
session rather than from a remembered snapshot.

**Only the session holding the link may speak to the watch.** `SessionController` claims the link
on `start` and resigns on `teardown`; `PhoneConnectivity.claim` refuses if another session already
holds it, `resign` refuses unless that controller is still the one holding it, and
`SessionController.pushState` refuses unless it holds the link. The reference is weak, so a
controller released without a `teardown` cannot leave the link believing a workout is still
running.

None of that is defensive padding — each refusal is a reported failure. `SessionRunner` builds its
controller in `@State(initialValue:)`, which SwiftUI re-evaluates on every re-render of the view
presenting it, and the previous copy is not released until the next one replaces it. So a workout
always has a discarded controller alive, and if it can reach the link at all it will answer the
watch from its own empty engine: the wrist jumps to the first exercise (`advance` passes its
`!isFinished` check on an idle engine, does nothing, and pushes an index-0 snapshot anyway) and
then appears dead (the next press pushes the identical state, which `pushState`'s dedupe
swallows). The phone is untouched throughout, because it is rendering the controller that is
actually installed. Verified on a paired simulator, including the built/released interleaving.

Two guards exist purely because the application context has no expiry:

- `PhoneConnectivity.clearIfIdle()` — a phone force-quit mid-workout would otherwise leave the
  watch showing a session that no longer exists. `PhoneConnectivity.answer()` on activation is the
  same truth sent on a hook that always runs, including a cold launch.
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
