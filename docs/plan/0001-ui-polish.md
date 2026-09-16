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

**2. One slice is an unknown, and it gates exactly one other slice.** S1 answers whether a Live
Activity provisions at all on this account. **Nothing except S7 depends on the answer**, which is
why S1 is cheap to run first and cheap to fail.

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

| # | Slice | Depends on | Device? | Gate |
|---|---|---|---|---|
| S1 | Live Activity feasibility spike | — | iPhone | **Blocks S7 only** |
| S2 | Shared vocabulary in `OronzoCore` | — | No | Blocks S3, S5, S7 |
| S3 | Watch session screen | S2 | **Watch** | Highest value |
| S4 | The `DONE` snapshot | S3 | **Watch** | Wire-format risk |
| S5 | iPhone session runner | S2 | iPhone | |
| S6 | Haptic vocabulary | — | **Watch** | Device-only |
| S7 | Lock Screen Live Activity | S1, S2 | iPhone | May not survive S1 |

**Order of execution: P0 → S1 → S2 → S3 → S4 → S5 → S6 → S7.**

S6 has no dependency on any other slice and could run at any point after P0. It is placed last
only because it is device-only — run it in the same device session as S3 or S4's verification
rather than opening a wrist-sized session of its own.

---

### S1 — Live Activity feasibility spike

**Delivers:** an answer. Does a Live Activity provision, start and appear on the Lock Screen on a
free personal team?

**Time-boxed and disposable.** A widget extension target, `NSSupportsLiveActivities`, and a
trivial Activity showing fixed text. No design, no integration, no tests. The code is expected to
be thrown away — S7 rewrites it properly.

**How it is verified:** on the iPhone. Start the Activity, lock the phone, confirm it appears.

**Done when:** either (a) an Activity is visible on the Lock Screen, or (b) it is not, and the
failing step is named. **Both outcomes are done.** (b) means S7 is dropped and the PRD is amended a
second time — which the PRD already anticipates and which costs one surface, not the plan.

**Does not include:** anything reusable. Do not build the real payload here.

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

### S7 — Lock Screen Live Activity

**Delivers:** `UI design §5` — a live-tracking Activity carrying current interval plus next,
system-driven timer, state word, and the ending behaviour on all completion paths.

**Blocked by S1.** If S1 came back negative, this slice does not exist and the PRD is amended
rather than the surface quietly disappearing.

**How it is verified:**
- On an iPhone: **metric 5** and the dimmed always-on trials, which are this surface's acceptance
  test.
- Live Activities disabled (`areActivitiesEnabled == false`): the session must run normally with
  the surface simply absent, and **nothing said about it**. An unavailable enhancement is not an
  error state.
- Force-quit the app mid-session and relaunch: the Activity must not outlive the session as a stale
  countdown — the phantom-session class of bug the project already fixed once for the Watch.
- All completion paths end the Activity.
- Confirm the payload stays under the 4 KB `ActivityAttributes` limit — and keep it to current plus
  next; the interval list must never be sent here.

**Done when:** the surface tracks a real session correctly, survives dimming, and disappears
cleanly on every way a session can end. Plus the documented re-sign step in `docs/runbook.md` for
the new target.

**Watch out for:** sending the whole interval list "for consistency with the Watch". That is
exactly the mistake `docs/integration-contracts.md` warns about in reverse — the Watch sends
everything because the application context is one slot; the Activity must not, because of the size
limit. Same principle, opposite conclusion, and both are deliberate.

---

## Explicitly not in this plan

- **The seconds-long screens** (sign-in, plan list, plan detail, summary chrome) — deferred by the
  spec. They should inherit the vocabulary, not co-author it.
- **Wiring `WatchControl.finish`.** **Decision taken: deferred, not open.** It is *new
  functionality*, and the PRD excludes new functionality from this pass. The design spec flagged
  that `DONE` makes the omission more visible, and it does — but visibility is not a reason to
  expand scope. Note that all Live Activity end paths are phone-triggered, so S7 does not depend
  on it.
- **The web plan builder.** Its own PRD.
- **Fixing other `docs/known-issues.md` items**, except the two this work touches for its own
  reasons: the phantom-session guard (S7) and the missing VoiceOver labels (S3).
- **App icon** — Q8, out of scope.

---

## What could invalidate this plan

| If this happens | Then |
|---|---|
| **S1 fails** | S7 is dropped, the PRD is amended, and the Watch carries the whole no-look burden. Slices S2–S6 are unaffected. |
| **S2's tokens cannot stay plain Swift** | The vocabulary moves to a small separate target or a per-app file, and metric 3 loses its structural guarantee — becoming discipline again. This is the plan's quietest risk and S2 tests it immediately. |
| **S3 fails metric 1** | Direction A is wrong for the Watch. That is worth knowing before S5 and S7 are built on the same vocabulary. |
| **A 7-day profile expiry lands mid-slice** | Re-sign and resume; `/resign` covers it. Budget for it rather than being surprised. |
