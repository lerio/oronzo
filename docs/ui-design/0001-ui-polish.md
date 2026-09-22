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
3. **A state word element.** No equivalent existed before; state was carried by *dimming the clock* when resting, which is colour-only signalling and fails metric 1. It is now drawn only for the states the exercise name cannot express — see §7.1.
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
  two states survive a dimmed always-on display and colour-blindness *simultaneously*. Note that
  since `WORK`/`REST` stopped being drawn (see §7), the `rest` role currently has no on-screen
  consumer — the rule is kept because the role is still part of the vocabulary and `reinforcement`
  still resolves it.

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
STATE WORD              ← DONE only   (new element; paused blinks instead)
Interval name           ← the exercise, or `Break`
   [ ‹ ]  PRIMARY  [ › ]   ← the step controls flank the clock, which is the pause control
Target load             ← `20 kg`, or an empty line
Set 2 of 4              ← context
NEXT · Lat Pulldown     ← caption, present in every running state
```

### The controls flank the primary

Prev and next sit either side of the clock or rep count, and **tapping the primary pauses and
resumes**. There is no separate controls row, which is the vertical space a 41 mm screen notices
most.

Whether the primary is tappable is `SessionScreen.allowsPause`, not this view's judgement: a rep
set has no clock to stop, so it is inert there — and it stays live while the session is *already*
paused, which is what keeps a session paused on a rest and then stepped onto a rep set
recoverable. That case used to be the pause button's job.

The buttons are sized independently of the primary and the primary takes `maxWidth: .infinity`, so
the controls hold their positions as the primary goes from `62:30` to `8`. Controls that move
between intervals are controls you have to look for.

### The decision that changed: each slot means what it says

The name slot is the interval you are in and the next-up line is the interval after it — a rest
included, so `Break` leads the next-up line before every set that has one.

**This reverses the original "rest promotes what's next" rule.** That rule had the name slot show
the *upcoming exercise* during rest, and suppressed the next-up line so the two would not repeat
the same word. Two changes retired it:

- **Removing the `REST` badge** (see §7) left the promotion with nothing to stand against. A rest
  screen showed the *next* exercise's name and said nowhere that you were resting.
- **The suppression made the next-up line vanish mid-rest.** A line present on every work screen
  disappeared at exactly the moment the name slot stopped meaning what it usually means, which
  reads as a glitch rather than as information.

Naming the rest fixes both: it puts a real word back on the rest screen, and the next-up line has
something other than itself to carry, so it never has to be suppressed. Both slots keep one
meaning each, in every state.

### States and copy

| # | State | State word badge | Name slot | Primary | Context | Next line |
|---|---|---|---|---|---|---|
| 1 | Timed work | *(none)* | exercise name | clock | `contextLabel` | `NEXT · <name or Break>` |
| 2 | Rest | *(none)* | `Break` | clock | `contextLabel` | `NEXT · <the exercise it is for>` |
| 3 | Rep work, no duration | *(none)* | exercise name | `10x` | `contextLabel` | `NEXT · <name or Break>` |
| 4 | Paused | *(none — the timer blinks)* | exercise name | **frozen** remaining, blinking | `contextLabel` | `NEXT · <name>` |
| 5 | Final interval | *(none)* | as above | as above | as above | **`LAST`** |
| 6 | Finished | `DONE` | plan name | total elapsed | — | — |
| 7 | No session | *(none)* | — | `No workout` | `Start a plan on your iPhone` | — |
| 8 | Runtime ended | *(unchanged)* | — | *(unchanged)* | existing `WatchRuntime` note, in `danger` | — |

Notes on the decisions:

- **Paused is carried by the blinking timer, not by a word.** A badge is a line that appears and
  pushes the title and the clock down as it does, and this screen has spent a pass removing exactly
  that movement. The rule is `PausedTimerBlink` in `OronzoCore`: **a pure function of the clock**,
  so the two surfaces cannot blink out of step, cannot keep blinking after a resume, and cannot be
  caught half-faded coming back from a wrist-drop suspension — which a `repeatForever` animation
  can, and did. Visible for the first half of each second, hidden for the second.
  The cost is that the paused state now rests on **motion** on the watch, where nothing else
  signals it; see §7.2.
- **The target load sits under the primary, not under the name.** "8x at 20 kg" is one figure, and
  a load drawn above the number reads as part of the title. It is `label`-sized — a step up from
  the `caption` it used to be on the phone — because a load is a number you act on rather than
  chrome you read past. Like the name and the weight line before it, **the row is always
  present**: a rest and an unweighted exercise have no load, and an empty row is cheaper than a
  primary that moves. The phone draws it outside the timer's `TimelineView` so it does not blink,
  and both surfaces hide it from VoiceOver — which is why `SessionScreen.weight` exists and why the
  composed announcement carries it, in the position it is drawn.
- **The word is drawn only where the name cannot say it** — `DONE` alone now. `WORK` and `REST`
  are the ordinary flow of a session, and the name slot already distinguishes them; a badge
  restating it is a line of chrome above every interval, which a 41 mm screen feels most.
  The rule lives in `SessionScreen.StateWord.showsBadge` and all three surfaces read it, so they
  still cannot diverge on this word. **The word is still spoken by VoiceOver in every state**,
  these two included: speech costs no layout, and a listener who joins mid-interval has no colour
  and no position to infer the state from.
- **`LAST`** answers "what's next" when the answer is "nothing". It is shown whenever the current
  interval is the final one in the list. Knowing the last interval is the last one is the single
  most motivating fact the Watch can carry, so it gets the slot rather than a blank.
- **Rep intervals never show a time.** A rep interval has no length, so nothing may imply one —
  neither the primary (the rep target, not a clock) nor the next-up line (name only, never a
  duration). The target carries its unit as a suffix rather than on a line of its own: the row
  `reps` used to occupy was a whole line of the screen's height, and that line is worth more to the
  exercise name. The suffix is `title`-sized, not `caption` — beside a figure this size a caption
  reads as a footnote rather than as the unit. **The name is unchanged by this**: same font size,
  still capped at two rows.
- **The unit is drawn, never spoken.** The announcement says "8 reps"; "eight x" is not how anyone
  says it. This is the same asymmetry as the state word, and for the same kind of reason: the drawn
  form is compressed for a small screen, the spoken form is written to be heard.
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
| A long primary | The clock shrinks (`minimumScaleFactor 0.6`) rather than pushing the step controls inwards. The controls never move to make room for it. |
| Always-on, dimmed | The same layout. Because no essential element uses `muted`, nothing essential is lost — this is the design's whole justification for the no-dimming rule. |
| A one-line name | The name slot **always occupies two rows**, whether the name needs them or not (`lineLimit(2, reservesSpace: true)`), so the clock, context and next-up line never move between intervals. Nothing below the name is a moving target on a screen you read from a metre away. |
| No weight to show | The runner's weight line is **always present** — `weightDisplay` is nil on a rest and on an unweighted exercise, and those get an empty line rather than none, for the same reason. It is `" "`, not `""`: an empty `Text` reserves 6px less than a line of real text at `caption`, which is small but is still the clock moving. The watch has no weight line, so it has nothing to reserve. |
| Largest Dynamic Type | `label`, `title` and `caption` grow; `primary` does not. The longer text may wrap to two lines and `caption` may drop. `primary`, `title`, the state word badge where one is drawn, and **both step controls** — which are how you move at all — **must remain visible without scrolling**; that is the acceptance test. |

### Accessibility

- **VoiceOver.** The running screen is icon-and-number only, so the primary region needs a
  composed label. Announce as, in this order:
  *"Working. Barbell Bench Press. 42 seconds remaining. Set 2 of 4. Next: Lat Pulldown."* — and
  for a rep interval, *"Working. Barbell Bench Press. 8 reps. 20 kg. Set 2 of 4."* — the load is
  spoken in the position it is drawn, and **must** be, because both surfaces hide that text behind
  this label. Omitting the time when
  there isn't one is required; announcing a stale or zero time would be a lie.
  A rest reads the same way: *"Resting. Break. 30 seconds remaining. Next: Barbell Bench Press."*
  The spoken form is the screen's content in the screen's order, so the two cannot describe
  different things.
- **Controls.** The two step controls are icon-only, so each carries an `accessibilityLabel`:
  "Previous" and "Next". The pause control is the **primary itself**, so the composed announcement
  above lives on it — the thing you are looking at is the thing VoiceOver reads out and the thing
  that pauses. It gains a hint ("Double tap to pause" / "Double tap to resume") only where
  `allowsPause` is true; a rep set, where it is inert, carries the label without the hint. The
  text around the primary is `accessibilityHidden`, because the composed label already says all of
  it in order — leaving the pieces focusable would read the whole screen twice.
- **Focus order:** Previous → the primary (carrying the whole composed announcement) → Next.
  Three stops rather than six: everything the announcement covers is hidden from VoiceOver, so the
  state is heard once, in order, on the element that is also the pause control.
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
| Running, timed | Exercise name, large clock, set context, next up | `NEXT · <name>` |
| Running, rep interval | Rep target as the primary, no clock | `8x` |
| Rest | `Break`, clock, next up | `Break` · `NEXT · <name>` |
| Paused | Frozen clock, and the primary control becomes resume | *(blinking timer)* · button `Resume` |
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
| State word | never | `showsBadge` draws `DONE` alone, and a finished session **ends** the Activity, so no state word appears here at all. A paused Lock Screen is signalled by its frozen clock, which the system renders as static text — see the states below. |
| Exercise name | the current interval — the exercise, or `Break` | Same rule as the Watch: the name slot is what you are in, the next-up line is what comes after |
| Primary | the clock, driven by the **system's own timer** from the absolute end date — or `8x` for a rep interval | Not app-updated. This is what makes it live without a per-second stream. The rep unit is `8x` here too, at **one size** rather than as a smaller suffix: this view is drawn at 34pt and at 15pt, and a suffix sized as a fraction of a number that swings across that range is illegible at the bottom of it. |
| Set context | `Set 2 of 4` | |
| Next-up | `NEXT · <name>`, or `LAST` | Rep intervals show the name only, never a duration |

### States

| State | Behaviour |
|---|---|
| Running | As above. Updates only on state transitions, not per second. |
| Paused | Clock stops at the frozen remaining value, as static text — a running system timer cannot be paused. It does **not** blink here: the Lock Screen is glanced at rather than watched, and a blinking card on a locked phone is a nuisance. The frozen value is the signal. |
| Finished | The Activity is **ended** on the same three paths that send `.sessionEnded` today. |
| **Live Activities unavailable** | `ActivityAuthorizationInfo().areActivitiesEnabled` is false. **Nothing is shown and nothing is said.** The session runs normally. An unavailable enhancement is never an error state. |
| **App terminated mid-session** | The Activity outlives the app and will show a stale countdown. It must be ended on next launch — the same phantom-session class of bug the project already fixed once for the Watch. |

### Dynamic Island

Minimal by design: one string and the clock. The compact and minimal presentations have room for
exactly one, which used to be the state word — so removing `WORK`/`REST` there would have left the
leading slot empty and `minimal`, which is nothing but the word, entirely blank. They now show the
**exercise name** where there is no state word to show, and the word where there is. The full name
still does not fit in the expanded regions and is not worth the compression.

### Always-on, dimmed

The state word badge, where one is drawn, and the primary must both survive dimming — which they do,
by the no-mid-tones rule.
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

1. **One vocabulary, three surfaces.** The state words are identical everywhere, and so is the rule
   for when one is *drawn* (`StateWord.showsBadge`). A user must never have to learn two words for
   the same state.
2. **A state nothing else signals is drawn as a word** — `DONE` alone. `WORK` and `REST` are carried
   by the name slot, because a rest names itself (`Break`) rather than promoting what comes next,
   and `PAUSED` is carried by the blinking timer. The word remains **spoken** in every state
   (see §3), which is what keeps `PAUSED` off motion alone for a listener.
3. **Motion carries meaning here, which is a deliberate exception.** §8 of the original pass said
   "no animation carries meaning", and `PAUSED` now does exactly that — on the watch it is the only
   thing that does, since a frozen clock looks the same as a running one in a glance. The composed
   VoiceOver label covers a listener and the phone's control flips to *Resume* for a looker, but a
   sighted watch user who does not happen to look during the visible half of a given second sees no
   paused state, and a user with Reduce Motion set sees none at all. Recorded as a known cost of
   the direction, not as an oversight.
4. **Each slot means what it says.** The name slot is the interval you are in; the next-up line is
   the interval after it. Neither is ever suppressed, repurposed, or made to carry the other's
   content — the failure that rule exists to prevent is a line that changes meaning mid-session.
   **A slot that is always the same height is part of the same rule**: the name reserves two rows on
   both runners, and the phone's weight line is always present, so the elements below them do not
   step up and down as the session advances. The cost is an empty row on the intervals that have
   nothing to put in it, which is the cheaper of the two — a screen you read from a metre away
   cannot afford a clock that moves.
5. **Rep intervals never imply a duration**, anywhere.
6. **No surface invents a state the others lack.** If `DONE` is worth showing on the Watch, the
   Live Activity ends rather than showing a third treatment — the asymmetry is deliberate and is
   noted rather than smoothed over.

---

## 8. Copy reference

Every user-facing string this spec introduces or fixes. Existing strings marked *(kept)*.

| Context | String |
|---|---|
| Watch / runner, paused *(drawn)* | the timer blinks; no word is drawn |
| Watch, finished | `DONE` |
| Any surface, timed work *(spoken only)* | `WORK` |
| Any surface, rest *(spoken only)* | `REST` |
| Watch / Lock Screen / runner, rest interval | `Break` |
| Watch / Lock Screen, final interval | `LAST` |
| Watch / Lock Screen, next-up prefix | `NEXT · ` |
| Watch / Lock Screen / runner, target load | `20 kg`, under the primary — drawn in every running state, empty when there is none |
| Watch / Lock Screen / runner, rep unit | `x`, as a suffix on the rep count (`8x`) — `title`-sized on the two runners, where the number is 48–96pt, and one size on the Lock Screen, where it is 34pt or less |
| Watch / runner, rep unit *(spoken)* | `8 reps` — the announcement still says the word, because "eight x" is not speech |
| Watch, idle | `No workout` *(kept)* |
| Watch, idle hint | `Start a plan on your iPhone` *(kept)* |
| Watch controls, VoiceOver | `Previous` · `Next` · hint `Double tap to pause` / `Double tap to resume` on the primary |
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

1. **~~Rest promoting "what's next" into the name slot~~** — *reversed, see §3.* The rest screen
   now names the rest (`Break`) and the next-up line carries the exercise. Recorded here because
   it was the decision a reviewer was asked to judge, and it is the one that changed.
2. **The `DONE` protocol addition** — the only new behaviour in an otherwise presentation-only
   pass. It is one snapshot sent on an existing field, but it does touch the wire format, which
   `docs/integration-contracts.md` treats as the most fragile part of the system.
