# Oronzo — agent guide

A personal fitness system: workout plans are authored in a web app, executed on an iPhone, and
mirrored to an Apple Watch. Single user, personal project, everything on free tiers.

This file is the entry point. It states the stack, the patterns that matter, and the rules that
have already cost real time. Deeper detail lives in `docs/` — see [Reading list](#reading-list).

<!-- Read this before the topic docs. The order is deliberate: the constraints below shape
     everything else, and an agent that skips to the code will re-break something. -->

## Stack

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase — Postgres + Auth + PostgREST + RLS | `supabase/` |
| Web app | Vite + React 19 + TypeScript SPA → Cloudflare Workers | `web/` |
| iOS app | SwiftUI, Swift 6, iOS 26 | `ios/Oronzo/` |
| Watch app | SwiftUI, watchOS 26 | `ios/OronzoWatch/` |
| Shared Swift | Models, flattener, session engine, watch wire format | `ios/OronzoCore/` |
| Ops | Cloudflare Worker on a daily cron | `ops/keepalive/` |

**Plans are authored only in the web app.** The iPhone executes them; the Watch displays them.
That separation is deliberate — building a structured workout on a phone is miserable, and on a
watch worse.

## The one idea that matters

**The iPhone owns session state and is the single source of truth for what you actually did.**
The Watch is a *renderer plus remote*, never an independent app. At session start the phone sends
it the **full flattened interval list with absolute end dates**, so the Watch counts down and
buzzes correctly even when the phone is unreachable or suspended.

There is no per-second message stream, and **there must never be one.** See
`docs/integration-contracts.md` for why this is load-bearing rather than an optimisation choice.

## The one contract: `flatten(plan) -> [Interval]`

```
for block in blocks ordered by position:
  for blockRound in 1...block.rounds:
    for step in steps ordered by position:
      for setIndex in 1...step.sets:
        emit step
        if step.restAfter: emit rest
    if blockRound < block.rounds and block.restBetweenRounds: emit rest
```

It lives in **three places that must change together**:

| Home | File |
|---|---|
| Canonical, and the one with tests | `ios/OronzoCore/Sources/OronzoCore/PlanFlattener.swift` |
| Builder live preview | `web/src/lib/types.ts` — `flattenPlan` |
| Plan persistence | `supabase/migrations/*.sql` — `save_plan` re-encodes the same tree shape |

A step is **always an exercise**; rest is synthetic, never a step. A step's `sets` is its set
count; a block's `rounds` repeats the whole group — different words on purpose. The two rest
mechanisms are deliberately asymmetric: `restAfter` fires after **every** set including the last,
`restBetweenRounds` only **between** rounds. `docs/decisions.md` explains why.

Run the `contract-auditor` agent after changing anything about blocks, steps, sets, rounds, rest,
or the plan/session schema.

## Core patterns

Full detail in `docs/patterns.md`. The short version:

- **The database boundary is snake_case; behaviour is camelCase.** Swift wire structs are named
  in snake_case so decoding needs no `CodingKeys` and cannot drift from the schema. They map to
  camelCase domain types immediately and never escape their file.
- **Hand-written PostgREST select strings** (`PlanRepository.planSelect`, `api.ts` `PLAN_SELECT`)
  are the most fragile code in the repo — a dropped column produces a runtime 400 in an app on a
  device. Keep each on **one line**: PostgREST parses it as a query string.
- **Time is injected, never read from the clock.** The engine takes `now: Date` as a parameter, so
  it is deterministically testable and suspension-safe. `intervalEnd` is an absolute `Date`, never
  a decrementing counter.
- **iOS state is `@MainActor @Observable final class`** (Observation, not Combine). Nonisolated
  delegate callbacks hop with `Task { @MainActor in ... }`.
- **Plans save atomically** through the `save_plan` RPC — never as sequential client calls.

## Commands

```bash
cd ios/OronzoCore && swift test      # 137 tests, no simulator or signing — run this first
cd ios && xcodegen generate          # after editing ios/project.yml or adding files
cd web && npm run dev                # localhost:5173
cd web && npm run build              # tsc -b is what catches stale field references
cd web && npm run lint               # oxlint — 4 pre-existing warnings are expected
cd web && npm run deploy             # build + wrangler deploy
```

`/check` runs the whole verification suite. `/deploy`, `/migration` and `/resign` encode ordering
and traps that are easy to forget — prefer them over doing the thing by hand.

Debug builds accept launch arguments that skip sign-in entirely:

```bash
xcrun simctl launch booted com.lerio.oronzo -demoSession       # a realistic plan
xcrun simctl launch booted com.lerio.oronzo -demoFinish        # 6 seconds, reaches the summary
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -demoSession
```

## Traps

Each of these cost real time. They are not hypothetical.

- **The watch target must be `type: application`, not `application.watchapp2`.** The latter is the
  legacy WatchKit container and declares `PRODUCT_TYPE_HAS_STUB_BINARY`, so the build copies a
  stub binary *and* links a real executable to the same path → `Multiple commands produce`, which
  looks nothing like a product-type problem.
- **`updateApplicationContext` is a single slot.** Whatever is written last is all that survives, so
  a "start" followed by an "update" leaves only the update. That is why `SessionSnapshot` carries
  the plan *and* the position and is re-sent whole on every change. Do not "optimise" this into
  incremental messages.
- **The watch can ask, and must be able to.** `WatchControl.requestState` exists because every way
  a push can go missing is silent — a write that lands before the phone's session activates, a
  snapshot overwritten by a `sessionEnded` from a runner that is no longer the live one, a resume
  that is never handed the context it missed. Without the ask, each of those leaves **"No workout"**
  on the wrist for the rest of the workout, indistinguishable from a phone that never started one.
  When the phone is the thing that is wrong, the watch asking is the only thing that fixes it.
  Re-read `docs/integration-contracts.md` before changing either half.
- **A SwiftUI view's initializer is re-run on every re-render — and what it builds outlives the
  build.** `SessionRunner` constructs its `SessionController` in `@State(initialValue:)`, and the
  view presenting it re-evaluates that expression whenever it redraws, so a workout builds fresh
  controllers repeatedly. Measured on a simulator session: the previous one is **not released
  until the next build replaces it**, so there is always a discarded controller alive. Anything
  with a side effect in `SessionController.init` therefore happens to a copy that SwiftUI is about
  to throw away — binding the watch link from there is what produced a wrist that jumped back to
  the first exercise and then stopped responding while the phone was untouched. Side effects go in
  `onAppear`/`start()`, and anything that can *act* must check it is still the live session
  (`SessionController.pushState`, `PhoneConnectivity.claim`).
- **Adding a field to `Interval` breaks decoding of snapshots already in flight.** `Interval` is
  `Codable` with no defaults and no version field, and the application context persists across
  launches — so a snapshot written by an older build fails to decode and the watch silently shows
  nothing. Add fields only with a default, or accept that the watch needs a fresh send.
- **`PlanCache` is unversioned.** It encodes `Plan`/`Interval` directly to JSON with no version
  key, and `load()` swallows failures via `try?` with no logging. Renaming a Codable property in
  `Models.swift` silently invalidates every existing cache.
- **`.gitignore` needs `.build/`, not `build/`.** Patterns match the exact name, so the `build/`
  line does not cover SwiftPM's directory. This exact mistake committed ~2,300 build files.
- **Migrations are applied by hand**, pasted into the Supabase SQL Editor in filename order. They
  are **append-only**: never edit an applied migration's logic — write a new one. `save_plan` has
  been redefined in six of them, so check the newest definition before changing that function.
- **Free personal team:** provisioning profiles expire every 7 days (the apps stop launching until
  rebuilt from Xcode), HealthKit will not sign, and there are no App Groups. The Watch stays alive
  via `WKExtendedRuntimeSession` with `WKBackgroundModes = [physical-therapy]` — a one-hour cap and
  no Activity ring credit. The iPhone stays alive via `UIBackgroundModes = [audio]` and a silent
  looping tone.
- **Xcode needs an Apple ID signed in and the licence accepted**, or every `xcodebuild` and
  `devicectl` invocation fails with errors that never mention accounts.
- **The Watch must be registered with Xcode** (Devices and Simulators → prepare it), or install
  fails with "integrity could not be verified".

`docs/runbook.md` has the symptom → cause table for all of these.

## Secrets — this repository is public

Never commit the real Supabase URL, publishable key, signing team ID, or personal email. They live
only in gitignored files: `web/.env.local`, `ios/Local.private.xcconfig`, `ops/keepalive/.dev.vars`
(local) and as an encrypted Worker secret (production). Only the `sb_publishable_…` key ever ships
to a client; the `sb_secret_…` key is never used by this project.

**Before every push:** scan the working tree for those four known values and confirm none appear.
Commits use a repo-local author, not the global git identity, and end with the `Co-Authored-By`
line.

A `PreToolUse` guard that automates exactly this is written at `.claude/hooks/secret-scan.sh` but
**is not wired up** — there is no `.claude/settings.json`, so it never runs. Until it is
registered, the scan is manual. See `docs/known-issues.md`.

## Working habits worth keeping

- **`swift test` before claiming the engine works.** The core is testable on macOS in a second, so
  there is no excuse for guessing about flattener or state-machine behaviour.
- **Look at the UI rather than reasoning about it.** Screenshot the web app with headless Chrome —
  arithmetic alone missed real CSS bugs twice on this project (a selector that never matched, a
  placeholder clipped in a narrow field).
- **Verify migration state by probing, not by assumption.** A `400` from PostgREST means a column
  is absent; a `200` means it exists. This caught a migration the user believed had been applied.
- **WatchConnectivity is the flakiest part of the system and it fails silently.** A workout that
  never reached the watch looks exactly like one that never started. `OronzoCore.Log.debug` is
  debug-only and compiles out of release builds — use it rather than `print`.

## Reading list

| Doc | What it answers |
|---|---|
| `docs/patterns.md` | How code is written here — conventions per language, and the boundary rules |
| `docs/integration-contracts.md` | The three-way mirror, the plan/session schema, the Watch wire format |
| `docs/testing-strategy.md` | What is proven where, and what can only be proven on a device |
| `docs/known-issues.md` | Code that looks unintended — confirm before building on it |
| `docs/decisions.md` | Why the system is shaped this way (ADRs, including the forced constraints) |
| `docs/runbook.md` | Operational chores, above all the weekly re-sign |
| `docs/friction-log.md` | Gaps hit while running the skills, and how each was resolved — check before re-litigating |
| `docs/prd/` | Product requirements, with the approved direction and its non-goals. Read the relevant PRD before changing anything user-facing |
| `README.md` | Human-facing overview and first-time setup |
