# Spec 0001 — UI/UX polish, iPhone and Apple Watch

**Implements:** [PRD 0001](../prd/0001-ui-polish-iphone-watch.md) — approved 16 September 2026, amended same day.
**Status:** awaiting approval (gate before `implementation-planner`)
**Confidence:** **medium-high** — see [Confidence](#confidence-and-the-biggest-unknown).

---

## Feasibility, led with

The PRD left eleven questions, four of them feasibility. Q10 was flagged as the one most likely to
change the plan, so it is answered first.

### Q10 — Is a live-tracking Lock Screen surface achievable on a free personal team? **Yes, on the evidence — and it does not need App Groups.**

This was the real risk, because the project's single hardest constraint is *no App Groups*, and
sharing data between an app and its extension is the textbook reason people need them.

Three things resolve it:

1. **App Groups are for sharing *data* between app and extension at runtime. A Live Activity does
   not need to do that.** The app pushes content state through ActivityKit and the system hands it
   to the extension to render. There is no shared container in the path.
2. **The only entitlement a local-only Live Activity needs is none.** `NSSupportsLiveActivities =
   YES` in `Info.plist` is what starts one. Push-based updates need `aps-environment` and
   `com.apple.developer.activity-push-notification`, and **this design uses no push** — updates are
   local, driven by the app's own state changes.
3. **Apple's own Food Truck sample documents Personal Team setup for Live Activities**, instructing
   the developer to select their Personal Team for *both* the app and the widget extension target.
   That is the closest thing to authoritative confirmation that the mechanism is available without
   the $99 account.

**And the fit with this codebase is unusually good.** Oronzo's Watch design already works by sending
*absolute end dates* rather than a per-second stream — `docs/integration-contracts.md` records that
as load-bearing. A Live Activity wants exactly that: the extension renders a system-driven timer from
an absolute end date, so the **countdown** stays correct with no ongoing updates from the app at all.
The app updates only on state *changes*, which is precisely the cadence `SessionController.pushState`
already runs at.

**Corrected after the surface was built and used.** The paragraph above is true of the countdown and
false of the **transition**. The card changes only when the app posts a content update — the system's
timer is display-only and clamps at `0:00` — and while the phone is locked, iOS does not take such an
update from an app whose only background justification is audio playback, which is the only kind this
app has. The card therefore holds the interval it was handed until the app is next in the foreground.
Push-to-update is the supported path and this design deliberately has none, so this is a **known
limitation rather than a defect**: `docs/known-issues.md` §12, and the locked-phone state in
`docs/ui-design/0001-ui-polish.md` §5.

The one target-level cost: a widget extension is a **third target**, with its own bundle identifier
and provisioning profile — so the 7-day free-team expiry now covers three things to re-sign instead
of two. `docs/runbook.md`'s re-sign ritual gains a step, but the ritual already re-signs everything
from one Xcode run.

### The other feasibility questions

| Q | Answer |
|---|---|
| **5 — Dynamic Type & colour-independence vs the chosen directions** | Both achievable, with one named conflict. See below. |
| **6 — A distinctive accent colour on the Watch** | **Yes, and the fix is already known.** The Watch target has no asset catalogue at all (verified: zero `.xcassets` in `ios/`), which is why `.tint` and `Color.accentColor` currently render as a plain fill — the existing code comment says as much. Adding an `AccentColor` asset to the Watch target resolves it. Small, contained. |
| **7 — Sunlight and dim-gym contrast in one system** | **Yes, one system, with a hard rule:** essential information is never carried by a mid-tone. Maximum-contrast foreground on black is the only thing that survives both a bright gym and a dimmed always-on display; mid-greys are what die in sunlight. Metric 5's dimmed trials verify it. |
| **8 — App icon** | **Out of scope for v1.** It affects none of the five metrics. Note the Watch app has no icon assets either, for the same missing-catalogue reason as Q6 — worth a fast follow once the catalogue exists, not worth blocking this pass. |

### Q5 in full — the one real conflict

- **Colour-independence is already solved by the approved direction**, not a compromise. Metric 1
  demands 10/10 on *working vs resting*, which colour alone cannot guarantee. Direction A carries
  state as a **word** ("WORK" / "REST") with colour as redundant reinforcement. That is the correct
  answer anyway, and it means no accessibility carve-out is needed on the Watch.
- **Dynamic Type is where the conflict is.** The primary element in direction A is a *large fixed
  clock* — and unbounded scaling breaks exactly the density that makes A work. The resolution:
  **text scales, the clock does not, above a threshold.** The clock is a fixed-purpose instrument,
  not prose; capping its scale is defensible where capping body text would not be. Every other
  element must scale and reflow, and the layout must be verified at the largest accessibility sizes
  where the clock cap means there is *more* room for everything else, not less.

---

## Behaviour

### What changes

Nothing about what the app *does*. Every change is presentation. The session flow — start, advance,
pause, resume, finish, save — is untouched, and that is a hard constraint, not an aspiration.

Three surfaces gain a designed presentation:

1. **The Watch session screen** — direction A (instrument panel), current interval plus what's next.
2. **The iPhone session runner** — direction B (quiet coach), with the distance requirement.
3. **The iPhone Lock Screen** — a Live Activity, direction A, live-tracking.

And one addition to behaviour, which is genuinely new capability rather than presentation:

4. **A haptic vocabulary** — at most three distinct cues, expressing distinctions that change what
   you do next.

### Edge cases that must be defined

The PRD's metrics imply behaviour at states the current UI has never had to present well. Each of
these needs a defined presentation in `ui-design-spec`:

| State | Why it matters |
|---|---|
| **Rep-based interval, no time remaining** | The primary element cannot be a clock — there is no duration. Today this is a known hole; it must have a designed primary that is not an empty countdown. |
| **Paused** | Must be unmistakable. A paused session and a running one at the same elapsed time look identical if state is carried only by a clock. |
| **Rep interval is *next*** | The Watch shows what's next, but a rep interval has no length. "Next: Bench Press" cannot imply a time. |
| **Session finished** | Three entry points reach this (normal finish, early finish, view dismissed). All must land on the same presentation. |
| **The final interval** | The Watch's projection clamps at 0:00 if the phone vanishes (`docs/known-issues.md`). A Live Activity's system timer has the same edge. Decide what is shown when time runs out but no advance arrives. |
| **Last set of the last exercise** | "What's next" has no answer. Must say so rather than showing a stale or blank value. |
| **Lock Screen while the app is foregrounded** | The runner and the Live Activity are both live. They must not disagree, and the Activity must not duplicate what is already on screen in a distracting way. |
| **Session abandoned from the Watch** | `WatchControl.finish` exists and is handled but is unreachable from the Watch UI (`docs/known-issues.md` §8). If this pass touches Watch controls, decide whether to wire it — otherwise the Lock Screen outlives the session on the phone. |

### Error states

- **Live Activity unavailable** — `ActivityAuthorizationInfo().areActivitiesEnabled` is false
  (user disabled Live Activities for the app, or the system refuses). The session must start and run
  normally; the Lock Screen surface is simply absent. **This is never surfaced as an error** — it is
  an unavailable enhancement, not a failure, and it must not block a workout.
- **Live Activity request fails** — `ActivityError.dataTooLarge`, `.tooManyActivities`,
  `.unsupported`. Swallow into `Log.debug` and continue. Same reasoning as the existing
  WatchConnectivity handling: the workout is the product, the mirror is the courtesy.
- **`ActivityAttributes` size** — hard limit under 4 KB. See the design constraint below.
- **The app is terminated mid-session** — the Live Activity outlives it and will show a stale
  countdown. Must be ended on next launch, mirroring `PhoneConnectivity.clearIfIdle()`'s existing
  phantom-session guard. **The same class of bug the project already fixed once for the Watch.**

---

## Technical approach

Described as the shape of the change, so a reviewer can evaluate it without the diff.

### 1. The shared visual vocabulary lives in `OronzoCore`

This is the central structural decision, and it is what makes metric 3 a guarantee rather than a
discipline.

The iPhone app and the Watch app are separate targets that already share `OronzoCore` — the package
that holds the models, the flattener and the engine, and which `project.yml` justifies as existing
"so that it can be unit-tested on macOS with `swift test`". Design tokens belong there for the same
reason the flattener does: **it is the only place that makes drift between the two surfaces
impossible rather than merely discouraged.**

The alternative — a token file in each app target — reintroduces exactly the mirrored-model problem
`docs/integration-contracts.md` was written to warn about, for values instead of fields.

Concretely: type scale, spacing steps, and colour roles as `OronzoCore` types, consumed by both apps.
The Lock Screen extension consumes them too. Because the vocabulary is then *testable* — `swift test`
can assert the scale contains no one-off values — metric 3 stops depending on anyone remembering.

### 2. The haptic vocabulary is a pure decision table in `OronzoCore`

Two cues exist today: a tap on interval change, a click on each of the final three seconds
(`WatchLink.announce`). The change is to make the *choice* of cue a pure function of
(previous state, new state) — testable on macOS with no Watch, and rendered by the Watch.

This is the same trick the engine already uses for time: **extract the decision, inject the effect.**
The engine takes `now: Date` so it is deterministically testable; the haptic language takes a state
transition and returns a cue, so the *vocabulary* is testable even though the *buzz* is not.

### 3. The Live Activity is a fourth projection of state the app already has

The app already maintains `SessionState` and pushes it whole on every change. The Live Activity is
another consumer of that same state — **not a new state machine, and not a new source of truth.**
The phone remains the single source of truth, exactly as for the Watch.

The `.sessionEnded` mirror of `WatchMessage` has a direct analogue: the Activity must be ended on the
same three paths that currently send it.

### 4. The Lock Screen's content state is deliberately *not* the Watch's snapshot

This is the one place the two mirrors must differ, and a reviewer should understand why:

| | Watch | Lock Screen |
|---|---|---|
| Payload | The **entire** interval list, re-sent whole | Current interval + next, only |
| Why | The application context is a single slot, so partial state can be lost | Hard **4 KB** `ActivityAttributes` limit, and the system renders its own timer |
| Countdown | Watch projects from the absolute end date | **The system** drives the timer from the absolute end date |

Both share the same principle — absolute end dates, no per-second stream — and arrive at it for
different reasons. Sending the whole interval list to a Live Activity would fail on size.

### 5. Contrast is a constraint on the token set, not a per-screen decision

Q7's rule ("essential information is never carried by a mid-tone") is enforced in the vocabulary:
the colour roles available for text are restricted to high-contrast foregrounds, with mid-tones
reserved for genuinely non-essential decoration. That makes sunlight legibility a property of the
palette rather than something each screen has to get right.

---

## Scope

### In scope

The three surfaces above, the shared vocabulary, and the haptic vocabulary.

### Non-goals

Inherited from the PRD and unchanged: **the web plan builder**, all new functionality, any change to
the phone-owns-state premise, anything behind a paid Apple account, and a brand identity. App icon
is out (Q8).

Additionally out of scope for this pass, decided here:

- **The seconds-long screens** (sign-in, plan list, plan detail, session summary). The PRD admitted
  them "if cheap once the above is settled". They are not cheap — each needs its own state and copy
  review — and none affects a metric. **Deferred to a follow-up**, and they should inherit the
  vocabulary rather than co-author it.
- **Fixing `docs/known-issues.md` items** beyond §8's Watch-finish question and the phantom-session
  guard, both of which this pass touches for other reasons. The rest stay open.

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Live Activity does not work on this account after all.** The evidence is Apple's own sample, not a test on *this* device and account. | **High impact, low-ish likelihood** | **A spike is slice 0** — see below. If it fails, slices 1–5 are unaffected and only the Lock Screen surface is dropped. This is why the spike comes first and why the plan does not depend on the answer. |
| The vocabulary in `OronzoCore` leaks presentation into a platform-agnostic package — `UIColor`/`Color` do not exist on Linux, and `OronzoCore` is testable on macOS precisely because it is plain Swift. | Medium | Tokens are expressed as **values** (a scale, RGB components, semantic roles), not as platform colour types. Each app maps them to its own type at the boundary. Preserves `swift test`. |
| The clock-cap decision (Q5) is subtly wrong and the layout breaks at accessibility sizes. | Medium | Verify at the largest Dynamic Type sizes on a device as an explicit QA step, not by reasoning. The project's own habit applies: *look at the UI rather than reasoning about it*. |
| Live Activity update budget is exceeded, causing throttling. | Low | The design minimises updates by construction: the system renders the countdown, so updates happen only on state transitions. |
| A third target complicates the weekly re-sign. | Low | Already a multi-target ritual; document the new target in `docs/runbook.md`. |
| Haptics cannot be verified without a device, so a bad vocabulary ships unnoticed. | Medium | Slice 5 is explicitly device-only and must be run on a real wrist before the slice is called done. |

---

## Validation plan

**Automated** (`swift test` in `OronzoCore`, the existing 56 plus new):

- The haptic decision table: every state transition maps to the intended cue, and no transition
  maps to a cue not in the vocabulary. This is the point of extracting the decision.
- The token set: no one-off values; the scale is exactly as defined. This is metric 3, mechanised.
- The existing 56 tests continue to pass, unchanged. Any change to them is a scope violation.

**Manual, on device** — and this is where most of the real verification lives, because none of the
five metrics can be measured in a simulator:

- The five metrics from the PRD, **baseline first on the current app, then again after each slice**.
  Metric 1 needs a Watch; metric 5 needs an iPhone on a surface at 1–2 metres, three trials with the
  screen dimmed to always-on.
- The haptic vocabulary on a real wrist (slice 5).
- The edge cases table above, walked through deliberately.
- `ActivityAuthorizationInfo` false — verify the session runs normally with the Lock Screen surface
  simply absent.
- The app force-quit mid-session — verify the Activity does not outlive it.

`/check` covers the core tests, the web build and lint, and both app targets building. It proves
nothing about the Watch, the haptics, or the Live Activity — say so plainly rather than implying
otherwise.

---

## Confidence and the biggest unknown

**Confidence: medium-high.** The architectural fit is unusually clean — the app already produces the
absolute-end-date state both new surfaces want, and the haptic vocabulary is a testable extraction
rather than new behaviour. The token placement in `OronzoCore` follows the repo's own established
reasoning rather than inventing a pattern.

**The single biggest unknown: whether a Live Activity actually provisions and runs on this specific
free personal team.** The evidence is strong — Apple's own sample documents Personal Team setup, and
the App Groups obstacle genuinely does not apply to this path — but it is documentation, not a test
on this device and this account. **Nothing in slices 1–5 depends on it.**

**Slice 0 exists to answer it, and is time-boxed:** create the extension target, set
`NSSupportsLiveActivities`, start a trivial Activity, confirm it appears on the Lock Screen. If it
fails, stop and amend the PRD — do not spend further effort on the surface. A negative answer is a
legitimate outcome that reduces scope by one surface, not a failure of the plan.

**Second unknown, unverified and lower impact:** that `OronzoCore` can host design tokens without
ceasing to be plain Swift. It should — tokens as values, not platform types — but it is asserted
here rather than proven, and slice 1 verifies it immediately.
