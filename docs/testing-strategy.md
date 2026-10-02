# Testing strategy

## Where the tests are

**All 263 tests live in `ios/OronzoCore/Tests/OronzoCoreTests/`.** Nothing else in the repository
has a single automated test — not the iOS app target, not the watch app, not the web app.

```bash
cd ios/OronzoCore && swift test     # ~1 second, no simulator, no signing, no device
```

| File | Tests | Covers |
|---|---|---|
| `PlanFlattenerTests.swift` | 43 | The flattening contract — sets, rounds, two-sided exercises, all three synthetic intervals, naming, formatting |
| `SessionScreenTests.swift` | 45 | The presentation model both screens draw from — state words, `LAST`, what a rep interval shows |
| `ExecutionEngineTests.swift` | 31 | The session state machine — start/tick/pause/resume/advance/goBack/finish/abandon/snapshot |
| `HealthOwedLedgerTests.swift` | 21 | The Health retry policy — when a workout may be offered again, when the app stops, and the climbing version that keeps a second attempt from becoming a second workout |
| `SessionRecordTests.swift` | 18 | The written-down session — the disk format, decode tolerance, what a restore refuses, and that a stale anchor cannot rewind |
| `PlanSummaryTests.swift` | 16 | What the plan summary says about a plan, including the spoken meta line |
| `LinkTests.swift` | 13 | The phone↔watch wire format — the control vocabulary, a whole snapshot, decode tolerance, and the version handshake |
| `SessionScheduleTests.swift` | 13 | When a surface may next wake — the rule that replaced polling, and the wake counts that prove it |
| `LoadAdjustmentTests.swift` | 11 | The runner's load arrows — what a nudge is, and which interval it may be applied to |
| `DesignTokenTests.swift` | 11 | The token scale — every role resolves, on both surfaces |
| `HapticLanguageTests.swift` | 10 | Which transitions earn a cue, and which stay silent |
| `WatchProjectionTests.swift` | 8 | Walking the interval list forward from an absolute anchor |
| `RecordableWorkoutTests.swift` | 8 | Whether a session is worth recording, and its payload — a pure function, so only the write itself needs the phone |
| `SessionClearTests.swift` | 8 | When the phone may clear the watch's screen — the guard that must not read "no session in memory" as "no session" |
| `AskScheduleTests.swift` | 6 | That the watch's recovery stays bounded — four attempts, never closer than five seconds |

This is possible because `OronzoCore` is a **plain SwiftPM package** rather than a folder of shared
sources inside the app target. That decision is stated in `ios/project.yml`: *"so that it can be
unit-tested on macOS with `swift test` — no simulator, no signing."* It is the reason the trickiest
logic in the project is provable in a second, and it is worth protecting.

## Why the engine is testable at all

**Time is injected, never read from the clock.** Every engine and projection entry point takes
`now: Date` as a parameter (`start(at:)`, `tick(now:)`, `pause(at:)`, `resume(at:)`,
`advance(at:)`, `project(intervals:from:end:now:)`). There is no clock abstraction, no protocol,
no mock — tests just pass a fixed `Date`.

That single decision is what makes the suspension behaviour testable rather than guessed at. The
canonical example is `testSuspensionAcrossSeveralIntervalsCoalescesIntoOneEvent`: it advances
`now` by five minutes across three timed intervals and asserts **one** `.advanced(from:to:)`, not
three. That is the property that keeps a pocketed phone from emitting a burst of stale events.

Two other testable-by-construction choices worth preserving:

- `ExecutionEngine` is a `Sendable` **value type** with `mutating` methods returning
  `[EngineEvent]`. State transitions are observable as a return value, so tests assert on events
  rather than on side effects.
- The engine holds no reference to `Date()`, so identical inputs always produce identical outputs.

## What this suite does *not* prove

Be explicit about this rather than implying coverage that does not exist:

- **Anything touching a device.** Signing, WatchConnectivity, haptics, the extended runtime
  session, the audio keep-alive, and the **HealthKit write** cannot be tested here at all. If a
  change touches `ios/Oronzo/Session/` or `ios/OronzoWatch/`, say plainly that a device run is
  still needed. The HealthKit *decisions* are the deliberate exception, and are exactly why they
  live in `OronzoCore`: `RecordableWorkout` (whether a session is worth recording) and
  `HealthOwedEntry` (whether an unconfirmed one may be offered again, and with which version) are
  pure functions covered by their tests — so only the write itself needs the phone. **The one
  thing that cannot be proven from a desk is that a retry does not duplicate**: that a second save
  under the same sync identifier and a greater version leaves one workout is Apple's documented
  behaviour, not something this repository has observed. (Signing the entitlement
  *can* be checked from a desk — `codesign -d --entitlements` on a device build — and was.)
- **Every SwiftUI view.** No view has a test. `SessionRunner`, `PlanEditor`, `PlanListView` and
  friends are verified by looking at them.
- **The entire web app.** There is no test framework in `web/package.json` — no Vitest, no Jest,
  no Playwright, no Testing Library. What exists instead is:
  - `npm run build` — `tsc -b`, which is the half that matters: it catches a reference to a field
    that no longer exists, the most common breakage here given the mirrored model.
  - `npm run lint` — oxlint, with **4 pre-existing warnings** (3 fast-refresh in `auth.tsx`, 1
    `set-state-in-effect` in `ExercisePicker` that is a deliberate after-mount focus). Anything
    beyond those four is new.
- **The hand-written select strings.** `tsc -b` checks the TypeScript type against the *declared*
  type, not against the database. A column dropped from Postgres but still named in `PLAN_SELECT`
  compiles cleanly and 400s at runtime on a device. Only `contract-auditor` or a real request
  catches that.

## The full check suite

`/check` runs everything above plus both app targets, using a **generic** destination (there are
two simulators named "iPhone 17 Pro" on this machine, so a name-based destination is ambiguous):

```bash
cd ios && xcodegen generate
cd ios && xcodebuild build -project Oronzo.xcodeproj -scheme Oronzo \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/oronzo-check CODE_SIGNING_ALLOWED=NO
cd ios && xcodebuild build -project Oronzo.xcodeproj -scheme OronzoWatch \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/oronzo-check-watch CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` keeps this off the signing path entirely, so it works without an Apple
ID, a connected device, or a valid profile.

There is **no CI**. Nothing runs on push.

## Manual verification

Debug builds accept launch arguments that skip sign-in entirely, which is how the runner and the
watch screen get exercised without an account or a network:

```bash
xcrun simctl launch booted com.lerio.oronzo -demoSession
xcrun simctl launch booted com.lerio.oronzo -demoFinish        # 6 seconds, reaches the summary
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -demoSession
```

**`-demoAdjust`** (with `-demoSession`) drives the runner's load arrows for you — a weight nudge,
then the save two seconds later — because there is no way to tap a simulator from a desk: this
machine has no `idb`, no `cliclick`, and no Simulator UI attached to the booted device. It is the
only route to the pending state and the Adjust button, and it is how the layout was checked.

Both are wrapped in `#if DEBUG` and have no entry point in a release build. The demo cannot save
— with no signed-in session, finishing reports "Auth session missing" and offers a retry. That is
the failure path working, not a bug.

**The watch link can be exercised between a paired iPhone and Watch simulator**, which is worth
knowing because it is the only way to watch the protocol move without two devices. Boot the pair,
install both apps, and attach a console to each:

```bash
xcrun simctl install <watch-udid>   /tmp/oronzo-dd/Build/Products/Debug-watchsimulator/OronzoWatch.app
xcrun simctl install <phone-udid>   /tmp/oronzo-dd/Build/Products/Debug-iphonesimulator/Oronzo.app
xcrun simctl launch --console-pty <phone-udid> com.lerio.oronzo -demoSession
xcrun simctl launch --console-pty <watch-udid> com.lerio.oronzo.watchkitapp   # no flag: real link
```

`--console-pty` is what makes `Log.debug` visible; `simctl io <udid> screenshot` is how the result
is checked. What this **cannot** reproduce is the reason the link fails in the first place: a
wrist-drop suspension, an out-of-range phone, and the extended runtime session all need hardware.
Treat it as a way to prove the protocol *works*, never as a way to prove it always will.

Two flaky edges, both worth recognising if a run looks impossible: the watch app can be slow to
install (minutes, occasionally hanging — kill it and retry), and a `terminate` immediately
followed by a `launch` can leave the old process on screen, so what you screenshot is not what
you just started.

For the web app, screenshot it with headless Chrome. Arithmetic alone missed real CSS bugs twice
on this project — a selector that never matched, and a placeholder clipped in a narrow field.

**Dragging a plan is the one thing on this list that nothing here can check.** There is no web
test framework, and a headless screenshot cannot perform an HTML5 drag — the events are the whole
feature, and `swift test` never sees the plans list. So the drag is verified by hand, and the
sequence matters because the order lives in the database rather than in the page. Step 1 is not
optional and comes first for the reason `docs/runbook.md` gives: both clients order by a column
that does not exist until it is applied, so until then the plan list is a `400`.

1. Apply `0015` in the SQL Editor, then read the probe in `docs/runbook.md` — `0015` must be `200`
   where it was `400`.
2. `cd web && npm run build && npm run lint`.
3. `cd web && npm run dev`, drag a row, then **reload** — the order must survive, which is what
   proves the RPC ran rather than the array merely moving on screen.
4. Drag a row and **drop it where it started** — no request should be sent at all.
5. On the phone, **pull to refresh** the plans list. The order is read on fetch, so nothing about
   it is live: there is no push channel, and a phone left showing an old order is a phone that has
   not refetched, not a phone that disagreed.

Step 5 is the only one that proves the feature's actual claim — *"the same order in the iPhone
app"* — and it needs the device. A simulator cannot get past sign-in without an account.

## How to use this when something breaks

**If a workout advances wrongly, prove it in `OronzoCore` first.** The flattener and the state
machine are the parts most likely to be wrong and the cheapest to test. A bug reproduced in a
failing test there is already fixed; the same bug chased through the simulator is an afternoon.
