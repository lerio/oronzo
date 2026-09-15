# Oronzo

A personal fitness system: workout plans are authored in a web app, executed on an iPhone, and
mirrored to an Apple Watch. Single user, personal project, everything on free tiers.

**Division of labour that shapes everything:** the iPhone owns session state and is the
single source of truth for what you actually did. The Watch is a *renderer plus remote*, never an
independent app — it is sent the full flattened interval list with **absolute end dates**, so it
counts down and buzzes correctly even when the phone is unreachable or suspended. There is no
per-second message stream, and there must never be one.

## Layout

| Path | What |
|---|---|
| `supabase/migrations/` | Schema, RLS, seed data, `save_plan`. **Applied by hand** — see below. |
| `supabase/plans/` | Re-runnable SQL that loads a real workout. User data, not migrations. |
| `web/` | Vite + React + TS SPA → Cloudflare Workers. The only place plans are authored. |
| `ios/OronzoCore/` | SwiftPM package: models, flattener, engine, watch wire format. |
| `ios/Oronzo/` | iOS app — auth, plan cache, session engine, logging. |
| `ios/OronzoWatch/` | watchOS app — countdown, haptics, controls. |
| `ops/keepalive/` | Cloudflare Worker on a daily cron; stops Supabase's free tier pausing. |
| `docs/` | `decisions.md` (why) and `runbook.md` (operational chores). |

## Commands

```bash
cd ios/OronzoCore && swift test      # 56 tests, no simulator or signing needed — run this first
cd ios && xcodegen generate          # after editing ios/project.yml or adding files
cd web && npm run dev                # localhost:5173
cd web && npm run build              # tsc -b is what catches stale field references
cd web && npm run lint               # oxlint
cd web && npm run deploy             # build + wrangler deploy
```

Debug builds accept launch arguments that skip sign-in entirely:

```bash
xcrun simctl launch booted com.lerio.oronzo -demoSession       # a realistic plan
xcrun simctl launch booted com.lerio.oronzo -demoFinish        # 6 seconds, reaches the summary
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -demoSession
```

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

- `ios/OronzoCore/Sources/OronzoCore/PlanFlattener.swift` — canonical, and the one with tests
- `web/src/lib/types.ts` — `flattenPlan`, used by the builder's live preview
- `supabase/migrations/*.sql` — `save_plan` re-encodes the same tree shape

A step is **always an exercise**; rest is synthetic, never a step. A step's `sets` is its set
count; a block's `rounds` repeats the whole group. `docs/decisions.md` explains the asymmetry
between the two rest mechanisms, which is deliberate.

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
- **`.gitignore` needs `.build/`, not `build/`.** Patterns match the exact name, so the `build/`
  line does not cover SwiftPM's directory. This exact mistake committed ~2,300 build files.
- **Migrations are applied by hand**, pasted into the Supabase SQL Editor in filename order. They
  are **append-only**: never edit an applied migration's logic — write a new one. `save_plan` has
  been redefined in six of them, so check the newest definition before changing that function.
- **Free personal team:** provisioning profiles expire every 7 days (the apps stop launching until
  rebuilt from Xcode), HealthKit will not sign, and there are no App Groups. The Watch stays alive
  via `WKExtendedRuntimeSession` with `WKBackgroundModes = [physical-therapy]` — a one-hour cap and
  no Activity ring credit.
- **Xcode needs an Apple ID signed in and the licence accepted**, or every `xcodebuild` and
  `devicectl` invocation fails with errors that never mention accounts.
- **The Watch must be registered with Xcode** (Devices and Simulators → prepare it), or install
  fails with "integrity could not be verified".

## Secrets — this repository is public

Never commit the real Supabase URL, publishable key, signing team ID, or personal email. They live
only in gitignored files: `web/.env.local`, `ios/Local.private.xcconfig`, `ops/keepalive/.dev.vars`
(local) and as an encrypted Worker secret (production). Only the `sb_publishable_…` key ever ships
to a client; the `sb_secret_…` key is never used by this project.

**Before every push:** scan the working tree for those four known values and confirm none appear.
Commits use a repo-local author, not the global git identity, and end with the `Co-Authored-By`
line.

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
