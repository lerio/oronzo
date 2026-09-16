# UI Design Spec 0001 — states, accessibility and copy

**Implements:** [Spec 0001](../spec/0001-ui-polish.md) · [PRD 0001](../prd/0001-ui-polish-iphone-watch.md)
**Status:** awaiting sign-off (gate before `implementation-planner`)
**Covers:** behaviour, states, accessibility and **actual copy** — not pixel-level visuals.

---

## 1. What already exists (checked before inventing anything)

Following the rule to reuse before adding.

**Reusable — keep these, do not reinvent:**

| Existing | Where | Reuse as |
|---|---|---|
| `MeasurementFormat.clock(remaining:)` | `OronzoCore/Models.swift` | The clock text. Already rounds **up**, so it only reads 0:00 when time is genuinely over. |
| `MeasurementFormat.reps` / `.weight` | same | Rep and load text. |
| `Interval.contextLabel` | same | "Set 2 of 4" / "Round 1 of 3" / block name — the existing precedence is correct, keep it. |
| `PlanFlattener.restLabel` = `"Break"` | `PlanFlattener.swift` | The rest interval's name. |
| Runtime notes | `WatchRuntime.describe` | "Approaching the one-hour limit", "Paused by the watch (low power)", "Another app took over" — already good copy. |
| Save status copy | `SessionRunner.saveStatus` | "Not saved — …" and "Try again". |
| Watch idle copy | `WatchSessionView.idle` | "No workout" / "Start a plan on your iPhone". |
| Semantic colour role names | `web/src/styles.css` | `background` `surface` `text` `muted` `accent` `danger` `good`. **The Swift vocabulary adopts these same role names**, so the web can consume the vocabulary later rather than forking it. |

**No Swift design layer exists** — verified. Every size, colour and spacing in the iPhone and Watch apps is a hardcoded literal (e.g. the Watch clock is `.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit()`). That layer is what this spec creates.

**Explicitly new** (named, not improvised):

1. The `OronzoCore` token layer — colour roles, type roles, spacing steps (Spec 0001 §1).
2. An `AccentColor` asset catalogue on the Watch target — without it `.tint`/`Color.accentColor` do not resolve to a colour (`docs/known-issues.md`, and the existing code comment says so).
3. **A state word element.** No equivalent exists today; state is currently carried by *dimming the clock* when resting, which is colour-only signalling and fails metric 1.
4. The Live Activity UI.

---

## 2. The shared vocabulary

Defined once in `OronzoCore`, consumed by the iPhone app, the Watch app and the Lock Screen extension. Metric 3 counts these; the counts below are the budget.

### Colour roles — 8

`background` · `surface` · `text` · `muted` · `accent` · `rest` · `danger` · `good`

Two rules, both of which exist to make legibility structural rather than per-screen:

- **Subordination is carried by size and weight, never by dimming, for anything the user needs.**
  `muted` is reserved for chrome that can be lost without consequence (non-prominent control
  glyphs). Everything essential — the state word, the primary element, the exercise name, the
  next-up line — uses `text`. This is what makes the sunlight requirement in Spec §5 hold: a
  mid-tone is what dies on a bright screen, so nothing essential is allowed to be one.
- **`accent` and `rest` must differ in perceived luminance, not only in hue.** Verified by
  converting both to greyscale: if they read as the same tone, the choice is wrong. This makes the
  two states survive a dimmed always-on display and colour-blindness *simultaneously*, with the
  state word as the primary and unambiguous signal.

### Type roles — 4

| Role | What it is | Scales with Dynamic Type? |
|---|---|---|
| `primary` | The clock or the rep count. The single biggest thing on the surface. | **No, above a threshold** |
| `title` | The exercise name | Yes |
| `label` | The state word, and the context line ("Set 2 of 4") | Yes |
| `caption` | The next-up line, and chrome | Yes |

### Spacing steps — 4

`tight` (within a line group) · `snug` (between related lines) · `roomy` (between groups) · `edge`
(the screen margin). Four is the budget; a fifth is a design failure, not a need.

---

## 3. Surface 1 — the Watch session screen (direction A)

### Layout regions, top to bottom

```
STATE WORD          ← WORK / REST / PAUSED / DONE   (new element)
Exercise name       ← title, or promoted "next" during rest
════════ PRIMARY ════════   ← clock, or rep count
Set 2 of 4          ← context
NEXT · Lat Pulldown ← caption, suppressed during rest
      [ controls ]
```

### The one non-obvious decision: rest promotes what's next

During rest the name slot shows **the next exercise**, and the next-up line is **suppressed**.

Showing "Break" as the name is useless — the user already knows they are resting. What they
actually want, mid-rest, is to know what they are resting *toward*, so they can set up. This
reuses the slot rather than adding one, so the layout never changes shape.

### States and copy

| # | State | State word | Name slot | Primary | Context | Next line |
|---|---|---|---|---|---|---|
| 1 | Timed work | `WORK` | exercise name | clock | `contextLabel` | `NEXT · <name>` |
| 2 | Rest | `REST` | **the next exercise** | clock | `contextLabel` | *(suppressed — see above)* |
| 3 | Rep work, no duration | `WORK` | exercise name | `10` over `reps` | `contextLabel` | `NEXT · <name>` |
| 4 | Paused | `PAUSED` | exercise name | **frozen** remaining | `contextLabel` | `NEXT · <name>` |
| 5 | Final interval | `WORK`/`REST` | as above | as above | as above | **`LAST`** |
| 6 | Finished | `DONE` | plan name | total elapsed | — | — |
| 7 | No session | *(none)* | — | `No workout` | `Start a plan on your iPhone` | — |
| 8 | Runtime ended | *(unchanged)* | — | *(unchanged)* | existing `WatchRuntime` note, in `danger` | — |

Notes on the decisions:

- **`LAST`** answers "what's next" when the answer is "nothing". It is shown whenever the current
  interval is the final one in the list. Knowing the last interval is the last one is the single
  most motivating fact the Watch can carry, so it gets the slot rather than a blank.
- **Rep intervals never show a time.** A rep interval has no length, so nothing may imply one —
  neither the primary (reps, not a clock) nor the next-up line (name only, never a duration).
- **`DONE` needs a small protocol addition.** `SessionState.isFinished` exists and is populated by
  `pushState`, but the finish path sends `.sessionEnded` without a final snapshot, so `true` never
  reaches the Watch. Send one final snapshot with `isFinished: true` before `.sessionEnded`. This
  is the only new behaviour in this spec, and it reuses an existing field.
- **`DONE` is brief.** It is cleared when the phone sends `.sessionEnded`, or after the Watch is
  left idle — it must not persist as a stale screen.

### Adaptive behaviour

| Condition | Behaviour |
|---|---|
| 41 mm | `caption` (next-up) is dropped if it would wrap. Primary and title never drop. |
| 45 mm / 49 mm | All regions shown. |
| Always-on, dimmed | The same layout. Because no essential element uses `muted`, nothing essential is lost — this is the design's whole justification for the no-dimming rule. |
| Largest Dynamic Type | `label`, `title` and `caption` grow; `primary` does not. The longer text may wrap to two lines and `caption` may drop. `primary`, `title` and the state word **must remain visible without scrolling** — that is the acceptance test. |

### Accessibility

- **VoiceOver.** The running screen is icon-and-number only, so the primary region needs a
  composed label. Announce as, in this order:
  *"Working. Barbell Bench Press. 42 seconds remaining. Set 2 of 4. Next: Lat Pulldown."* — and
  for a rep interval, *"Working. Barbell Bench Press. 8 reps. Set 2 of 4."* Omitting the time when
  there isn't one is required; announcing a stale or zero time would be a lie.
- **Controls need labels — this is a live gap.** The three controls are icon-only
  (`backward.fill` / `pause.fill` / `forward.fill`) with no `accessibilityLabel`. They must become
  "Previous", "Pause" / "Resume", and "Next". The pause control's label is state-dependent.
- **Focus order:** state word → name → primary → context → next → controls.
- **No animation carries meaning.** Nothing essential may rely on motion; a transition cue that is
  only visual is unavailable to a user who is not looking, which is the norm here.

---

## 4. Surface 2 — the iPhone session runner (direction B)

### The distance rule, made concrete

The phone sits on a surface and is read from 1–2 metres (PRD metric 5). Therefore:

- `primary` is sized by the **distance requirement, not by the phone's available space**. It is the
  largest element on the screen by a wide margin, and it is not permitted to shrink to make room
  for anything else.
- **Nothing essential is below `label` in size**, and nothing essential is `muted`.
- Where the desire for calm and the distance requirement conflict, **the requirement wins**. In
  practice that means: generous whitespace around a very large primary, not a uniformly small
  screen.

### States and copy

| State | What is shown | Copy |
|---|---|---|
| Running, timed | State word, exercise name, large clock, set context, next up | `WORK` · `NEXT · <name>` |
| Running, rep interval | Rep target as the primary, no clock | `WORK` · `8 reps` |
| Rest | State word, next exercise promoted, clock | `REST` |
| Paused | Frozen clock, and the primary control becomes resume | `PAUSED` · button `Resume` |
| Saving | Unchanged content; the save control reflects progress | `Saving…` |
| Saved | Confirmation does not block the summary | `Saved` |
| **Save failed** | The message sits over the summary, does not replace it | `Not saved — <reason>` · button `Try again` |
| Summary | The existing summary, restyled to the vocabulary | *(existing copy unchanged)* |

The last three reuse `SessionRunner`'s existing `SaveState` copy verbatim. It is already good and
already distinguishes "saving" from "failed" from "saved"; only its presentation changes.

### The both-visible state

The runner and the Live Activity can be on screen at once only in the sense that the Activity lives
on the Lock Screen — they are never literally both visible. They **cannot disagree**, because both
are projections of the same `SessionState` and neither holds state of its own. No reconciliation
logic is needed, and none should be added.

---

## 5. Surface 3 — the Lock Screen Live Activity (direction A, live-tracking)

**Payload constraint:** current interval + next, only. Hard 4 KB `ActivityAttributes` limit — the
interval list is never sent here (Spec §4).

### Lock Screen presentation

| Region | Content | Notes |
|---|---|---|
| State word | `WORK` / `REST` / `PAUSED` | Same vocabulary as the Watch — the two surfaces must not diverge on this word |
| Exercise name | current, or promoted next during rest | Same promotion rule as the Watch |
| Primary | the clock, driven by the **system's own timer** from the absolute end date | Not app-updated. This is what makes it live without a per-second stream. |
| Set context | `Set 2 of 4` | |
| Next-up | `NEXT · <name>`, or `LAST` | Rep intervals show the name only, never a duration |

### States

| State | Behaviour |
|---|---|
| Running | As above. Updates only on state transitions, not per second. |
| Paused | Clock stops and `PAUSED` is shown. The system timer cannot be paused, so the paused state must present the frozen remaining value as static text instead of a running timer. |
| Finished | The Activity is **ended** on the same three paths that send `.sessionEnded` today. |
| **Live Activities unavailable** | `ActivityAuthorizationInfo().areActivitiesEnabled` is false. **Nothing is shown and nothing is said.** The session runs normally. An unavailable enhancement is never an error state. |
| **App terminated mid-session** | The Activity outlives the app and will show a stale countdown. It must be ended on next launch — the same phantom-session class of bug the project already fixed once for the Watch. |

### Dynamic Island

Minimal by design: the state word and the clock only. The exercise name does not fit legibly and is
not worth the compression. This is a deliberate reduction, not an omission.

### Always-on, dimmed

Both the state word and the primary must survive dimming — which they do, by the no-mid-tones rule.
**Metric 5's three dimmed trials are the acceptance test for this surface.**

---

## 6. Haptic vocabulary

Behaviour, not visuals, but it belongs with the state definitions because it is the same
vocabulary expressed through a different channel.

| Transition | Cue | Why it earns a distinct feel |
|---|---|---|
| Work → rest | one firm tap | You can stop. |
| Rest → work | **two** firm taps | You must start. The only cue that changes what you do *right now*. |
| Any → finished | a short rising pattern | The payoff, and the one moment you want to notice. |
| Final 3 seconds | one soft click per second | Existing behaviour, unchanged. |

**The bar for a fourth cue:** does this distinction change what you do next? Everything else is
noise, and the vocabulary is deliberately capped at three distinct feels plus the existing
countdown clicks.

The decision is a **pure function of (previous state, new state)**, so it is testable on macOS with
no Watch. Only the feel itself needs a wrist.

---

## 7. Cross-surface consistency rules

1. **One vocabulary, three surfaces.** The state words are identical everywhere. A user must never
   have to learn two words for the same state.
2. **The state word is never omitted**, on any surface, in any state. It is the colour-independent
   signal that metric 1 and metric 5 both depend on.
3. **Rep intervals never imply a duration**, anywhere.
4. **No surface invents a state the others lack.** If `DONE` is worth showing on the Watch, the
   Live Activity ends rather than showing a third treatment — the asymmetry is deliberate and is
   noted rather than smoothed over.

---

## 8. Copy reference

Every user-facing string this spec introduces or fixes. Existing strings marked *(kept)*.

| Context | String |
|---|---|
| Watch, timed work | `WORK` |
| Watch / Lock Screen, rest | `REST` |
| Watch / Lock Screen / runner, paused | `PAUSED` |
| Watch, finished | `DONE` |
| Watch / Lock Screen, final interval | `LAST` |
| Watch / Lock Screen, next-up prefix | `NEXT · ` |
| Watch, rep unit | `reps` |
| Watch, idle | `No workout` *(kept)* |
| Watch, idle hint | `Start a plan on your iPhone` *(kept)* |
| Watch controls, VoiceOver | `Previous` · `Pause` / `Resume` · `Next` |
| Runner, resume control | `Resume` |
| Runner, saving | `Saving…` |
| Runner, saved | `Saved` |
| Runner, save failed | `Not saved — <reason>` *(kept)* |
| Runner, retry | `Try again` *(kept)* |
| Rest interval name | `Break` *(kept, from `PlanFlattener.restLabel`)* |

**No string is left to implementation time.** If an implementer needs a string not in this table,
that is a gap in this spec.

---

## 9. Out of scope for this spec

- **Pixel-level visuals** — final type sizes in points, exact colour values, corner radii. Those are
  implementation decisions made against the roles above, verified by looking at the UI.
- The web plan builder, app icon, and the seconds-long screens (sign-in, plan list, plan detail,
  summary chrome) — all deferred elsewhere.
- Fixing `docs/known-issues.md` items, except the two this spec touches: the unroutable
  `WatchControl.finish` (see below) and the phantom-session guard.

**One open question this spec raises and does not settle:** the Watch has no way to end a session
(`WatchControl.finish` is handled by the phone but unreachable from the Watch UI —
`docs/known-issues.md` §8). The haptic and state work here makes the omission more visible, because
`DONE` can now only ever be reached from the phone. **Decide whether to wire it in this pass or
explicitly defer it** — but note that if it stays unwired, a session abandoned on the phone leaves
the Live Activity needing to end on a path the Watch cannot trigger.

---

## 10. Gate

Sign-off required before `implementation-planner` runs. The two things most worth a reviewer's
judgement:

1. **Rest promoting "what's next" into the name slot** — a genuine design decision, not an obvious
   one, and it changes what the rest screen looks like.
2. **The `DONE` protocol addition** — the only new behaviour in an otherwise presentation-only
   pass. It is one snapshot sent on an existing field, but it does touch the wire format, which
   `docs/integration-contracts.md` treats as the most fragile part of the system.
