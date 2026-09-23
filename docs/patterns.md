# Patterns

How code is written in this repository. These are the conventions the existing code follows —
follow them rather than inventing a parallel style. Where the code currently *diverges* from the
convention, that is noted and tracked in `known-issues.md` rather than silently copied.

## The boundary rule

**Postgres is snake_case. Everywhere else is camelCase.** The conversion happens exactly once, at
the edge of each data-access file, and never leaks inward.

Swift wire structs are deliberately named in snake_case so the synthesised `Codable` decoder
matches the PostgREST payload with no `CodingKeys` — stated once in the file that owns it
(`ios/Oronzo/Backend/PlanRepository.swift:6-9`):

> *"These deliberately mirror the PostgREST payload — snake_case property names and all — so that
> decoding needs no CodingKeys and cannot silently drift from the schema. They are mapped to
> OronzoCore domain types immediately and never escape this file."*

```swift
private struct StepRow: Decodable {          // snake_case, mirrors the columns
    let exercise_id: UUID?
    let target_weight_kg: Double?
    let duration_seconds: Int?
}
// → toDomain(), in the same file:
PlanStep(
    exerciseID: step.exercise_id,            // camelCase domain type
    targetWeightKg: step.target_weight_kg,
    duration: step.duration_seconds.map(TimeInterval.init),  // Int seconds → TimeInterval, here only
)
```

Wire types are `private`, suffixed `Row` for reads and `New<Table>` for inserts (`NewSession`,
`NewStep`), and mirror SQL table names. There is **no `CodingKeys` anywhere** in the codebase —
if you find yourself needing one, the wire struct is misnamed.

TypeScript follows the same split: `PlanStep.exercise_id` is snake_case because it mirrors the
column, while `flattenPlan` and `estimatePlanDuration` are camelCase because they are behaviour.

## Data access

One thin layer per client, and views never reach past it.

```
Swift:  View → @Observable Store → Repository/Logger struct → Backend.client
Web:    Route component → lib/api.ts → supabase client
```

- `ios/Oronzo/Backend/Backend.swift` — `enum` namespace holding the lazily-built
  `SupabaseClient`. Lazily, so an unconfigured build still launches and shows
  `ConfigurationView` instead of hitting a `preconditionFailure`.
- `PlanRepository` — network **reads**. `SessionLogger` — network **writes**.
- `web/src/lib/api.ts` — every Supabase call for the SPA. No route or component imports
  `supabase` directly.

**Read ordering is normalised client-side.** PostgREST does not guarantee embed order, so both
clients sort blocks and steps by `position` after fetching (`PlanRepository.swift:52,59`,
`api.ts` `toPlan`). The live preview's `normalize()` re-indexes `position` from array order after
every mutation, because positions must be contiguous per parent.

**Defensive coercion at the boundary.** A malformed row degrades rather than throwing:
`max(1, block.rounds)`, `StepMode(rawValue: step.mode ?? "reps") ?? .reps`.

**Writes go through `save_plan`.** A plan save touches 1 + N + M rows; doing it as sequential
client calls risks a half-saved plan. The RPC replaces the whole block/step tree, so **every save
mints new block and step UUIDs** — never cache them across a save.

**Each select string must stay on one line.** PostgREST parses it as a query string, so embedded
newlines break it. Both `PlanRepository.planSelect` and `api.ts` `PLAN_SELECT` carry this comment.

## Error handling

**Swift — catching into a `String?` on the store, rendered inline.** There is no shared error type
and no `Result` anywhere. Only the three data-layer functions throw; the house style is:

```swift
// ios/Oronzo/Backend/PlanStore.swift:44-47
} catch {
    // Keep whatever the cache gave us; a stale plan list beats an empty screen.
    self.error = error.localizedDescription
}
```

The type information is destroyed at the catch site, so no view can branch on the *kind* of
failure. Each view then chooses its own treatment: inline red text (`SignInView`), a
non-blocking banner over stale content (`PlanListView`), or a message plus a "Try again" button
(`SessionRunner`'s private `SaveState` enum — the closest thing to a phase enum, and not reused).

**Web — hand-rolled per route, and currently inconsistent.** Typically
`if (loading) … if (error) …`, but `Plans`/`History` replace the whole screen while `Exercises`
renders the error above a still-visible list. New code should keep the list visible and put the
error inline; see `known-issues.md`.

**Deliberately swallowed, and this is fine:** sign-out failure (state moves to `.signedOut`
regardless), session-restore failure (just means "no keychain session"), and every
WatchConnectivity failure (debug log only — see below). Don't "fix" these into user-facing errors
without a reason.

**The one place silence is by design and dangerous:** `Log.debug` compiles out of release builds
entirely. A failed watch delivery is therefore *completely silent in production*. That is the
reason `Log.debug` exists rather than `print` — a workout that never reached the watch looks
exactly like one that never started.

## Concurrency and state

**`@MainActor @Observable final class`** (the Observation framework). There are **zero**
occurrences of `ObservableObject`, `@Published`, `@StateObject` or `@ObservedObject` — don't
introduce Combine.

- App-scoped stores are created once and injected: `.environment(auth)`, read with
  `@Environment(AuthStore.self)`.
- Per-view models are `@State private var`.
- Mutation is always `private(set) var` plus methods. Views never write state directly.
- UI reads **computed proxies** into the domain object rather than duplicating state
  (`SessionController.current` forwards to `engine.current`).

**Swift 6 language mode is on**, which is what forces the discipline. Every `WCSessionDelegate` /
`WKExtendedRuntimeSessionDelegate` callback is `nonisolated` and hops with
`Task { @MainActor in ... }`, because `[String: Any]` is not `Sendable` — pull the `Data` out
first. `ISO8601DateFormatter` was rejected for the same reason (non-Sendable class in a static).

**async/await throughout.** No completion handlers, no `DispatchQueue`, no Combine. The only
primitives in use are `async let` for parallel fetches and a `Task` + `Task.sleep` loop per surface
for scheduled work — always stored in a property and cancelled explicitly.

**`OronzoCore` may hold platform-framework-shaped things, and the guard is what makes that safe.**
`#if os(iOS)` rather than `canImport(ActivityKit)`: the module imports fine on macOS while the symbol
inside it is unavailable there, so `canImport` compiles the guard and then fails on the type — a
confusing error in a package that is otherwise plain Swift. The rule outlived the file that taught it.
The design tokens made the same call from the other direction — plain values, no platform types at
all — so both that and this exist to keep one property: **`swift test` runs the whole engine on macOS
in a second.**

**Scheduled, not polled.** A loop never asks the clock whether something has happened; it sleeps
until the instant something *will*. `OronzoCore.SessionSchedule` computes that instant from the
session's absolute dates, and it is a pure function so `swift test` can prove it. Both surfaces rest
entirely on this: the watch used to wake four times a second for the whole workout and the phone ten
times, and neither needed to — a minute-long interval has four instants at which anything can
happen. `SessionScheduleTests` counts the wakes a session costs, so a regression to polling fails
the suite rather than the battery. The display cadences (`TimelineView`) are separate from this and
are stated where they are set.

**Web has no state library.** `useState` + `useEffect`, one `Plan` object per editor, nested
arrays, and a single `mutate()` funnel that runs `normalize()` on every change.

## Naming

| Kind | Convention |
|---|---|
| Files | One primary type, named exactly after it. `Backend/`, `Session/`, `Views/` group by role. |
| Role suffixes | `-Store` (UI state), `-Repository` (read), `-Logger` (write), `-Controller`, `-View`, `-Runtime`, `-Link` |
| Methods | Verb-first, no `get`. `fetch*` = network, `load` = cache-then-network, `refresh` = network only, `restore` = keychain, `save`/`persist` = write |
| Booleans | Read as assertions: `isRunning`, `hasActiveSession`, `advancesAutomatically` |
| Callbacks | `on<Event>` — `var onControl: (@MainActor (WatchControl) -> Void)?` |
| Web components | PascalCase filename for components (`routes/`, `components/`); lowercase for modules of functions/types (`lib/`) |

`src/auth.tsx` is the one file that breaks the web casing rule — it is lowercase but exports a
component *and* functions. Don't add more like it.

**Comments explain *why*, and cite authority** — a doc, a milestone, or a past incident. There are
zero `TODO`/`FIXME` markers in the iOS tree; don't add the first one, write the reason instead.

## Styling

One global stylesheet, `web/src/styles.css`, imported once. No CSS modules, no Tailwind, no
CSS-in-JS.

- Colours go through custom properties in `:root`, with a full dark-mode override under
  `@media (prefers-color-scheme: dark)`. Use the variables; do not hardcode a colour.
- Naming is block-element with hyphens plus a **second compound class** for state
  (`.tab.active`, `.step-row.invalid`) — not BEM `--` modifiers.
- A small set of shared utilities (`.muted`, `.small`, `.error`, `.centered`) is used across
  routes.

**Two live gotchas.** The numeric field widths depend on source *order*: `.inline-field input`
sets a 72px fallback and `.step-row input` overrides it 180 lines later at equal specificity, so
the fallback only works because explicit `w-digits-*` classes outrank both. Reordering those
blocks silently breaks the numeric columns. And the file still contains selectors left over from
the `<select>` → `ExercisePicker` swap (`.step-row > input`, and `.step-row select` which now only
matches the mode dropdown) that no longer match anything.
