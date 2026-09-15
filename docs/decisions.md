# Decisions

Why Oronzo is built the way it is. Several of these are forced by a constraint rather than
chosen, and are marked as such — those are the ones that will bite you if you change them.

## The four pieces

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase — Postgres + Auth + PostgREST + RLS | `supabase/` |
| Web app | Vite + React + TypeScript SPA, Cloudflare Workers | `web/` |
| iOS app | SwiftUI, iOS 26 | `ios/Oronzo/` |
| Watch app | SwiftUI, watchOS 26 | `ios/OronzoWatch/` |

**Plans are authored only in the web app.** The iPhone executes them; the Watch displays
them. That separation is deliberate: building a structured workout on a phone is miserable,
and building one on a watch is worse.

## The one idea that matters

The iPhone owns session state — it is the single source of truth for what you actually did.
But at session start it sends the Watch the **full flattened interval list with absolute end
dates**, so the Watch renders an always-accurate countdown and fires its own haptics without
a per-second message stream. It keeps working when the phone is briefly unreachable or
suspended, which is what makes the free-tier constraints survivable rather than crippling.

## Workout model: a step is an exercise, and rest is synthetic

A plan is an ordered list of **blocks**, each repeating its ordered list of **steps**
`rounds` times. A step is always an **exercise** — timed (auto-advance) or rep-based (tap to
advance). A step is never a rest.

Rest is not a kind of step. It is emitted from two places, and only ever in the *execution*
stream, as an interval:

- `step.rest_after_seconds` — after **each** set of that exercise, including the last
- `block.rest_between_rounds_seconds` — only **between** a block's rounds

**Sets and rounds are different words on purpose.** A step's `sets` is that exercise's set
count; a block's `rounds` repeats the whole group.

- *4×8 bench press with 90 s between sets* → one block, one step with `sets = 4` and
  `rest_after_seconds = 90`. No wrapper block: the set count belongs to the exercise.
- *Circuit of 4 exercises × 3 rounds, 20 s between* → one block, `rounds = 3`, four steps
  each with `rest_after_seconds = 20`.

**The asymmetry is deliberate:** `rest_after_seconds` fires even after the final set of a
step (usually what you want — it doubles as the rest before the next one), whereas
`rest_between_rounds_seconds` fires only *between* rounds. Making both fire would produce
double rests that are painful to debug in the editor.

Two things were tried and removed, rather than merely hidden:

- **Standalone rest steps** (`plan_steps.kind = 'rest'`, dropped in `0006`). Once rest lived
  on the step and the block, a rest step had nothing left to express.
- **Plan and step notes** (dropped in `0008`). Step notes were still editable in the builder
  but iOS decoded and discarded them, so guidance like "per side" never reached a workout.
  Half-supporting a field is worse than not having it.

`session_steps.actual_reps` and `actual_weight_kg` went the same way in `0008`: the engine
could record them but nothing ever called `record(reps:weightKg:)`, so every logged session
stored nulls. `actual_duration_seconds` and `status` stay — the engine genuinely populates
both.

Not supported: EMOM/AMRAP/time-capped work, which needs a *variable* rest (whatever is left
in the minute). Adding it means a new interval concept, not a new column.

## Constraints from a free Apple personal team

These are not preferences. A paid account ($99/yr) lifts every one of them.

| Constraint | Consequence |
|---|---|
| **No HealthKit** (signing fails on a personal team) | No `HKWorkoutSession`. The Watch stays alive via `WKExtendedRuntimeSession` with `WKBackgroundModes = [physical-therapy]` — a 1-hour cap, and **workouts do not close your Activity rings**. |
| **No App Groups** | No shared container between iPhone and Watch. All data moves over WatchConnectivity. |
| **No TestFlight** | Install from Xcode only. |
| **Profiles expire every 7 days** | Re-run from Xcode weekly. See `runbook.md`. |
| Max 3 devices per platform | The Watch must be registered with Xcode, or its bundle signs unsigned and install fails with "integrity could not be verified". |

`physical-therapy` is a slightly awkward category for strength work — Apple intends it for
range-of-motion exercise. It is the longest-lived extended runtime available to us that
allows background execution, so it is what we use.

## Xcode project generation

`ios/project.yml` is the source of truth; the `.xcodeproj` is generated and gitignored.

**The watch target must be `type: application` + `platform: watchOS`.** Not
`application.watchapp2`. That type is the *legacy* WatchKit container and declares
`PRODUCT_TYPE_HAS_STUB_BINARY = YES`, so the build copies a stub binary **and** links a real
executable to the same path, failing with `Multiple commands produce`. XcodeGen does not
infer the correct type from `platform: watchOS`, and the symptom looks nothing like a
product-type problem.

## Secrets

Only the `sb_publishable_…` key ever reaches a client. It carries no privileges of its own —
row-level security protects every table, and `anon` is granted nothing. The `sb_secret_…`
key is never used by this project.

The Supabase URL and key live in `web/.env.local` (gitignored); only placeholders are
committed. On iOS they live in `ios/Local.private.xcconfig` (gitignored, and included
*optionally* by the committed `ios/Local.xcconfig` so a fresh clone still builds). The
signing team ID sits in the same file, for the same reason — this repository is public.
