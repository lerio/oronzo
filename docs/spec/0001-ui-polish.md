# Spec 0001 — UI/UX polish, iPhone and Apple Watch

**Implements:** [PRD 0001](../prd/0001-ui-polish-iphone-watch.md) — approved 16 September 2026, amended same day.
**Status:** awaiting approval (gate before `implementation-planner`)
**Confidence:** **medium-high** — see [Confidence](#confidence-and-the-biggest-unknown).

---

## Feasibility, led with

The PRD left eleven questions, four of them feasibility. Q10 was flagged as the one most likely to
change the plan, so it is answered first.

### Q10 — Is a live-tracking Lock Screen surface achievable on a free personal team? **Yes — and it was then removed anyway.**

Answered: **yes, and it needs no App Groups.** App Groups share *data* between an app and its
extension at runtime, and a local-only Live Activity never does that — the app pushes content state
through ActivityKit and the system hands it to the extension to render. The only thing needed to
start one is `NSSupportsLiveActivities` in `Info.plist`; push-based updates would have needed
`aps-environment`, and this design used no push.

**The surface was built, used, and deleted.** Its countdown was correct, but the card could not
advance while the phone was locked: the system's timer is display-only and clamps at `0:00`, the
handover to the next interval is the app's job, and iOS does not take a content update from an app
whose only background justification is audio playback. That is the one kind this app has, and it is
the same mechanism that makes the pocketed-phone cues work. So for the half of a workout when the
phone was actually in a pocket, the card held whichever interval it had last been handed.

Push-to-update is the supported path and would need a server and a paid account. Rather than carry a
third target — a widget extension with its own bundle identifier and provisioning profile, and
therefore a third thing in the weekly re-sign — for a surface that was right only while the phone was
in your hand, it was removed. `docs/decisions.md` records the decision; `docs/ui-design/0001-ui-polish.md`
§5 records what it used to show.

The lesson worth keeping: **"achievable" and "worth building" are different questions, and this spec
only asked the first one.** The feasibility work was not wasted — the answer was correct — but the
value question was never asked until the thing existed and could be used.

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

Two surfaces gain a designed presentation:

1. **The Watch session screen** — direction A (instrument panel), current interval plus what's next.
2. **The iPhone session runner** — direction B (quiet coach), with the distance requirement.

A third was specified and built — the iPhone Lock Screen as a Live Activity — and was removed after
being used. See Q10 above for why.

And one addition to behaviour, which is genuinely new capability rather than presentation:

3. **A haptic vocabulary** — at most three distinct cues, expressing distinctions that change what
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
| **The final interval** | The Watch's projection clamps at 0:00 if the phone vanishes (`docs/known-issues.md`). Decide what is shown when time runs out but no advance arrives. |
| **Last set of the last exercise** | "What's next" has no answer. Must say so rather than showing a stale or blank value. |
| **Session abandoned from the Watch** | `WatchControl.finish` exists and is handled but is unreachable from the Watch UI (`docs/known-issues.md` §8). If this pass touches Watch controls, decide whether to wire it. |

### Error states

- **The app is terminated mid-session** — the Watch keeps the session it was last handed, so the
  link must clear on the next launch. That is `PhoneConnectivity.clearIfIdle()`, whose
  phantom-session guard is the same class of bug the project fixed once already for the Watch.

The four Live Activity error states that used to be listed here — activities disabled, a refused
request, the 4 KB payload limit, and an Activity outliving a force-quit — went with the surface.

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
Because the vocabulary is then *testable* — `swift test`
can assert the scale contains no one-off values — metric 3 stops depending on anyone remembering.

### 2. The haptic vocabulary is a pure decision table in `OronzoCore`

Two cues exist today: a tap on interval change, a click on each of the final three seconds
(`WatchLink.announce`). The change is to make the *choice* of cue a pure function of
(previous state, new state) — testable on macOS with no Watch, and rendered by the Watch.

This is the same trick the engine already uses for time: **extract the decision, inject the effect.**
The engine takes `now: Date` so it is deterministically testable; the haptic language takes a state
transition and returns a cue, so the *vocabulary* is testable even though the *buzz* is not.

### 3. Both surfaces project the same state, and neither holds any

The app maintains `SessionState` and pushes it whole on every change. The Watch screen and the iPhone
runner are two consumers of that same state — **neither is a new state machine, and neither is a new
source of truth.** The phone remains the single source of truth, exactly as before.

### 4. The payload each surface gets is chosen for its transport

This was the one place the two mirrors had to differ, and a reviewer should understand why — the
reasoning outlives the surface it was written for:

| | Watch | Lock Screen *(removed)* |
|---|---|---|
| Payload | The **entire** interval list, re-sent whole | Current interval + next, only |
| Why | The application context is a single slot, so partial state can be lost | Hard **4 KB** `ActivityAttributes` limit, and the system renders its own timer |

Both shared the same principle — absolute end dates, no per-second stream — and arrived at it for
different reasons. The same principle, opposite conclusions, both deliberate: **the payload follows
the transport's constraint, not the other surface's shape.** That is worth keeping in mind for
whatever is added next.

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
| The vocabulary in `OronzoCore` leaks presentation into a platform-agnostic package — `UIColor`/`Color` do not exist on Linux, and `OronzoCore` is testable on macOS precisely because it is plain Swift. | Medium | Tokens are expressed as **values** (a scale, RGB components, semantic roles), not as platform colour types. Each app maps them to its own type at the boundary. Preserves `swift test`. |
| The clock-cap decision (Q5) is subtly wrong and the layout breaks at accessibility sizes. | Medium | Verify at the largest Dynamic Type sizes on a device as an explicit QA step, not by reasoning. The project's own habit applies: *look at the UI rather than reasoning about it*. |
| Haptics cannot be verified without a device, so a bad vocabulary ships unnoticed. | Medium | Slice 5 is explicitly device-only and must be run on a real wrist before the slice is called done. |
| **A surface can be feasible and still not worth having.** This one was built, used, and removed — Q10. | — | Not mitigable by a spec. It is the reason the PRD's non-goals list exists, and the reason a surface should be asked what it is *for* before it is asked whether it is possible. |

---

## Validation plan

**Automated** (`swift test` in `OronzoCore`, the existing suite plus new):

- The haptic decision table: every state transition maps to the intended cue, and no transition
  maps to a cue not in the vocabulary. This is the point of extracting the decision.
- The token set: no one-off values; the scale is exactly as defined. This is metric 3, mechanised.
- The existing tests continue to pass, unchanged. Any change to them is a scope violation.

**Manual, on device** — and this is where most of the real verification lives, because none of the
five metrics can be measured in a simulator:

- The five metrics from the PRD, **baseline first on the current app, then again after each slice**.
  Metric 1 needs a Watch; metric 5 needs an iPhone on a surface at 1–2 metres, three trials with the
  screen dimmed to always-on.
- The haptic vocabulary on a real wrist (slice 5).
- The edge cases table above, walked through deliberately.
- The app force-quit mid-session — verify the Watch is cleared on the next launch rather than
  holding a session that no longer exists.

`/check` covers the core tests, the web build and lint, and both app targets building. It proves
nothing about the Watch, the haptics, or the extended runtime session — say so plainly rather than
implying otherwise.

---

## Confidence, and what the biggest unknown turned out to be

**Confidence in the two surviving surfaces: high, and borne out.** The Watch screen and the runner
were built and are in daily use. The token and haptic extractions behaved as designed.

**The biggest unknown was the wrong one.** This spec spent its risk budget on the question *can we*
— whether a Live Activity would provision and run on a free personal team — and answered it
correctly. The question it never asked was *should we*, and that is the one that decided the
outcome: the surface could not track a locked phone (`docs/known-issues.md` §12 before its removal),
which is most of a workout, and it cost a third target to do it.

**A follow-up workstream should invert that.** For any surface whose value is not obvious from the
design, the spike should answer "what does this get you that the surface you already have does not"
*before* the feasibility work, because feasibility is the easier question and it is the one that
feels like progress. Q10 is a worked example: a correct answer, cheaply obtained, that bought
nothing.

**Second unknown, unverified and lower impact:** that `OronzoCore` can host design tokens without
ceasing to be plain Swift. It should — tokens as values, not platform types — but it is asserted
here rather than proven, and slice 1 verifies it immediately.
