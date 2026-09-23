# Implementation plan 0001 — UI/UX polish

**Implements:** [Spec 0001](../spec/0001-ui-polish.md) · [UI design 0001](../ui-design/0001-ui-polish.md) · [PRD 0001](../prd/0001-ui-polish-iphone-watch.md)
**Status:** awaiting approval (gate before any `implement` run).

**Rules for this plan.** One slice per PR. Never start slice *n+1* while slice *n* is unreviewed —
errors compound, and a small mistake in a foundation slice gets expensive once three surfaces are
built on it. Each slice below is independently shippable: it can be implemented, reviewed and
merged without depending on any later slice ever happening.

---

## The two things that shape sequencing

**1. Verification is device-bound, and that is the real bottleneck.** Only **S2** can be verified
entirely on macOS with `swift test`. Every other slice needs a physical iPhone, a physical Watch,
or both. The free personal team adds a wrinkle: provisioning profiles expire every 7 days, and a
device session that lands badly can be interrupted by a re-sign.

**So: batch device runs deliberately.** S3 and S6 in particular both want a Watch on a wrist, and
there is no reason they should be two separate sessions.

**2. One slice was an unknown, and it gated exactly one other slice.** S1 answered whether a Live
Activity provisions at all on this account, and **nothing except S7 depended on the answer** — which
is why S1 was cheap to run first and cheap to fail. The answer came back yes, S7 was built on it, and
S7 was then removed anyway. The spike was not the mistake; asking only whether it *could* work, and
never whether it *should*, was.

---

## Prerequisite — P0: Baseline measurement

**Not a slice. Produces no PR.** Listed first because it is worthless if done late.

**Owner: the user.** This cannot be done by an agent — it is a person running a workout and timing
himself. Everything downstream claims an *improvement*, and without this there is nothing to
improve on.

| Metric | How | Record |
|---|---|---|
| 1 — 3-second glance (Watch) | 10 trials, unassisted, on the current app | Correct count per sub-question |
| 2 — No-look transitions | One full session; count phone pickups to check state | A number |
| 5 — Distance read (iPhone) | Phone on a surface, 1–2 m, 10 trials, 3 dimmed | Correct count on (a) and (b) |

Metrics 3 and 4 are count-and-squint exercises done from the current UI, and can be done at a desk
in a few minutes — no session required.

**Done when:** the five numbers are written down somewhere durable. **Blocked by:** nothing.
**Blocks:** the *claim* of improvement in every later slice — but not the work itself.

---

## The slices

| # | Slice | Depends on | Device? | Outcome |
|---|---|---|---|---|
| S1 | Live Activity feasibility spike | — | iPhone | Done — the answer was yes |
| S2 | Shared vocabulary in `OronzoCore` | — | No | Done |
| S3 | Watch session screen | S2 | **Watch** | Done |
| S4 | The `DONE` snapshot | S3 | **Watch** | Done |
| S5 | iPhone session runner | S2 | iPhone | Done |
| S6 | Haptic vocabulary | — | **Watch** | Done, device-verified |
| S7 | Lock Screen Live Activity | S1, S2 | iPhone | **Built, used, removed** |

**Executed in order: P0 → S1 → S2 → S3 → S4 → S5 → S6 → S7.** Every slice but the last shipped and
is in daily use; S7 shipped too, and was then deleted once it had been used enough to judge. Its
removal is recorded in `docs/decisions.md`, and the reasoning that held up is under S1 and S7 below.

---

### S1 — Live Activity feasibility spike — *done*

**Delivered:** the answer. Yes — a Live Activity provisions, starts and appears on the Lock Screen
on a free personal team, with no App Groups and no entitlement beyond `NSSupportsLiveActivities`.

**Kept because the finding outlived the surface:** `ActivityAttributes` types may live in
`OronzoCore`, but they must be guarded on **`os(iOS)`, not on `canImport(ActivityKit)`** — the module
imports fine on macOS while `ActivityAttributes` itself is unavailable there, so `canImport` compiles
the guard and then fails on the symbol. That rule now lives in `docs/patterns.md`, where it stands on
its own; its example file was deleted with the surface.

**Time-boxed and disposable, and it was.** The target plumbing is what S7 built on; the spike's own
view code was replaced wholesale, as planned.

---

### S2 — Shared vocabulary in `OronzoCore`

**Delivers:** the colour, type and spacing roles of `UI design §2` as `OronzoCore` values, plus the
per-app mapping into each platform's colour type. No surface consumes them yet.

**Why this is shippable alone:** it is the thing that makes metric 3 a guarantee instead of a
discipline, and it is verifiable on macOS by `swift test` — the only slice in this plan that is.
A reviewer can judge the *scale itself* here, cheaply, before three surfaces are built on it.

**How it is verified:**
- New `swift test` cases asserting the type scale, colour set and spacing scale are exactly the
  defined sizes — no one-off values, no extras. **This is metric 3, mechanised.**
- A test that the two state colours differ in perceived luminance (converted to greyscale), which
  is the rule that makes them survive dimming and colour-blindness.
- The existing 56 tests still pass unchanged.

**Done when:** the tests above exist and pass, and the tokens are plain Swift values with no
platform colour type in `OronzoCore`. **Confirms one unverified assumption from the spec:** that
tokens-as-values keep the package buildable and testable on macOS.

**Does not include:** any view change. Nothing looks different after this slice, which is expected
and is the point — the scale is reviewed before it is used.

**No asset catalogue is needed.** Q6 asked whether a distinctive accent is achievable on the Watch
given it has no `.xcassets`. With tokens as explicit colours, an asset catalogue is only required
if *system-tinted* chrome must match — and none of these three surfaces uses any. This resolves Q6
by removing the need rather than by adding a resource.

---

### S3 — Watch session screen

**Delivers:** `UI design §3` in full — the state word, the layout regions, the rest-promotes-next
rule, `LAST`, the rep-interval primary, and the accessibility fixes. This is direction A.

**This is the hardest slice and the one where the work succeeds or fails.** Metrics 1, 2 and 4 all
land here. Done early, on purpose.

**How it is verified:**
- On a Watch: metric 1 (10 trials, unassisted), and metric 4 (squint test at arm's length).
- The adaptive table walked deliberately: 41 mm, 45/49 mm, dimmed always-on, and the largest
  Dynamic Type size — where the acceptance test is that `primary`, `title` and the state word are
  all still visible without scrolling.
- VoiceOver: the composed announcement, and the three control labels that are missing today.
  Verify the rep-interval case *omits* the time rather than announcing a stale one.
- `swift test` unchanged.

**Done when:** the states in `UI design §3` all render as specified, metric 1 is re-measured against
P0's baseline, and the VoiceOver controls have labels.

**Does not include:** the `DONE` state (S4), haptics (S6), or any change to the iPhone app.

**Watch out for:** the existing screen signals rest by *dimming the clock*. That must be replaced by
the state word, not supplemented — dimming is the colour-only signalling the design rejects.

---

### S4 — The `DONE` snapshot

**Delivers:** the Watch showing `DONE` with total elapsed time when a session finishes. One final
`SessionSnapshot` with `isFinished: true` sent before `.sessionEnded`.

**Why it is its own slice, despite being small:** it is the **only new behaviour** in an otherwise
presentation-only body of work, and it changes the **wire format**, which
`docs/integration-contracts.md` calls the most fragile part of the system. Isolating it means a
mistake here fails one small review instead of taking the Watch screen down with it.

**How it is verified:**
- On a Watch: complete a session with `-demoFinish` (6 seconds) and confirm `DONE` appears with a
  sensible elapsed time, then clears.
- All three completion paths: normal finish, early finish, and view dismissed. **All three must
  reach `DONE`**, and `DONE` must not persist as a stale screen.
- `swift test` unchanged.

**Done when:** `DONE` appears on every completion path and clears correctly, and an older snapshot
still decodes — `Interval` carries no version field, so confirm the added state does not break a
snapshot already sitting in the application context (`docs/known-issues.md`).

**Does not include:** any summary or history work — that is the phone's, and deferred.

---

### S5 — iPhone session runner

**Delivers:** `UI design §4` — direction B with the distance rule made real: the primary sized by
the 1–2 m requirement and not permitted to shrink for anything else, generous whitespace, the
existing save-status copy retained.

**How it is verified:**
- On an iPhone: **metric 5** — 1–2 m, 10 trials, including 3 with the screen dimmed. This is the
  whole point of the slice; if it fails, the design failed.
- Metric 4 on the runner.
- The save path by hand: saving, saved, and a forced failure, confirming the error sits *over* the
  summary rather than replacing it.

**Done when:** metric 5 is re-measured against P0's baseline and meets the PRD target (10/10 on
working-vs-resting, 8/10 on roughly-how-long).

**Does not include:** the summary screen's own restyling — deferred with the seconds-long screens.

**Watch out for:** the temptation to make it *calm* at the cost of distance legibility. The
requirement outranks the direction where they conflict; that is stated in the PRD and this is where
it gets tested.

---

### S6 — Haptic vocabulary

**Delivers:** `UI design §6` — three distinct feels plus the existing countdown clicks, as a **pure
function of (previous state, new state)** in `OronzoCore`, with the Watch rendering whatever cue it
returns.

**How it is verified:**
- `swift test`, on macOS: every state transition maps to the intended cue, no transition maps to a
  cue outside the vocabulary, and the vocabulary contains exactly three distinct feels. **The point
  of extracting the decision is that the vocabulary is testable even though the buzz is not.**
- On a Watch: the feels themselves. **Device-only — this cannot be verified in a simulator**, and
  the slice is not done until it has been felt on a wrist.

**Done when:** the decision table is covered by tests, and the three cues have been run on a real
Watch and are distinguishable *without looking*.

**Does not include:** a fourth cue. The bar is "does this distinction change what you do next" — if
a cue cannot clear it, it does not ship.

---

### S7 — Lock Screen Live Activity — *built, then removed*

**Delivered** `UI design §5` in full: a live-tracking Activity carrying the current interval plus
the next, a system-driven timer, and the ending behaviour on every completion path. It met its own
"done when" — it tracked a real session, survived dimming, and disappeared cleanly however the
session ended. The payload stayed far under the 4 KB ceiling (`SessionActivityTests` pinned that,
including the worst-case plan).

**Then it was deleted, because meeting the bar was not the same as being worth it.** The card could
not advance while the phone was locked: the system's timer is display-only and clamps at `0:00`, the
handover to the next interval is the app's job, and iOS does not take a content update from an app
whose only background justification is audio playback — which is the only kind this app has, and the
same mechanism that makes the pocketed-phone cues work. So for most of a workout, on a phone
deliberately left on a surface a metre away, the card held whichever interval it had last been
handed. Push-to-update is the supported path and would need a server and a paid account.

**What the verification list above missed** is the one thing that would have caught it: *use it for
a real workout with the phone in a pocket.* Every item on the list passes with the phone in your
hand, and every item on it passes with the phone locked. The list tested the surface; it never
tested the situation the surface was for.

**Watch out for — and this one held up.** Sending the whole interval list "for consistency with the
Watch" is the mistake `docs/integration-contracts.md` warns about in reverse: the Watch sends
everything because the application context is one slot, the Activity must not because of the size
limit. Same principle, opposite conclusion, both deliberate. That reasoning survived the surface and
is recorded in `docs/spec/0001-ui-polish.md` §4 for whatever is added next.

---

## Explicitly not in this plan

- **The seconds-long screens** (sign-in, plan list, plan detail, summary chrome) — deferred by the
  spec. They should inherit the vocabulary, not co-author it.
- **Wiring `WatchControl.finish`.** **Decision taken: deferred, not open.** It is *new
  functionality*, and the PRD excludes new functionality from this pass. The design spec flagged
  that `DONE` makes the omission more visible, and it does — but visibility is not a reason to
  expand scope. It was deferred once on that reasoning and is still deferred; it is now the only
  remaining asymmetry, since the Lock Screen surface is gone (see `docs/known-issues.md` §8).
- **The web plan builder.** Its own PRD.
- **Fixing other `docs/known-issues.md` items**, except the two this work touched for its own
  reasons: the phantom-session guard and the missing VoiceOver labels (S3). The phantom guard
  outlived the surface that motivated it and is now `PhoneConnectivity.clearIfIdle()`.
- **App icon** — Q8, out of scope.

---

## What could invalidate this plan

Borne out, in the end: none of the risks below materialised, and the surface the plan spent most of
its attention on was the one that did not survive. Kept as the shape of the reasoning rather than as
a live warning.

| If this happens | Then |
|---|---|
| **S1 fails** | S7 is dropped, the PRD is amended, and the Watch carries the whole no-look burden. Slices S2–S6 are unaffected. **Did not happen** — S1 passed. |
| **S2's tokens cannot stay plain Swift** | The vocabulary moves to a small separate target or a per-app file, and metric 3 loses its structural guarantee — becoming discipline again. **Did not happen**; the tokens stayed plain values in `OronzoCore`. |
| **S3 fails metric 1** | Direction A is wrong for the Watch. **Did not happen.** |
| **A 7-day profile expiry lands mid-slice** | Re-sign and resume; `/resign` covers it. **Happened repeatedly, handled each time by `/resign`.** |

---

## Discovery from S1 — kept, because the rule outlived its example

Recorded here rather than in the PR, because a PR description scrolls away. Its subject file is gone;
the rule is not, and it lives on in `docs/patterns.md`.

**ActivityKit types may live in `OronzoCore`, but they must be guarded on `os(iOS)` — *not* on
`canImport(ActivityKit)`.** The module imports fine on macOS; it is `ActivityAttributes` itself that
is marked unavailable there. So `canImport` compiles the guard and then fails on the symbol, which is
a confusing error in a package that is otherwise plain Swift.

`#if os(iOS)` is correct and sufficient: it keeps the type out of the macOS build — so `swift test`
still runs — and out of the Watch target.

The general form is worth keeping: **`OronzoCore` can host platform-framework-shaped things, and the
guard is what makes that safe.** The design tokens made the same choice from the other direction —
plain values, no platform types at all — and both approaches were in service of the same thing:
`swift test` running the whole engine on macOS in a second.
