# Decisions

Why Oronzo is built the way it is. Several of these are forced by a constraint rather than
chosen, and are marked as such — those are the ones that will bite you if you change them.

## The four pieces

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase — Postgres + Auth + PostgREST + RLS | `supabase/` |
| Web app | Vite + React + TypeScript SPA, Cloudflare Pages | `web/` |
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

## Workout model: a step *is* an interval

A plan is an ordered list of **blocks**, each repeating its ordered list of **steps**
`rounds` times. A step is exactly one interval — timed (auto-advance), rep-based (tap to
advance), or an explicit rest.

That single primitive covers every shape without a "sets" concept:

- *3×12 squats with 90 s between sets* → one block, `rounds = 3`,
  `rest_between_rounds_seconds = 90`, one rep step.
- *Circuit of 4 exercises × 3 rounds, 20 s between* → one block, `rounds = 3`, four steps
  each with `rest_after_seconds = 20`.

**The asymmetry is deliberate:** `rest_after_seconds` fires even after the final step of a
round (usually what you want — it doubles as the rest before the next round), whereas
`rest_between_rounds_seconds` fires only *between* rounds. Making both fire would produce
double rests that are painful to debug in the editor.

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
committed. The signing team ID lives in `ios/Signing.xcconfig` (gitignored) for the same
reason — this repo is public.
