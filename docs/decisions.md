# Decisions

Why Oronzo is built the way it is. Several of these are forced by a constraint rather than
chosen, and are marked as such — those are the ones that will bite you if you change them.

## The four pieces

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase — Postgres + Auth + PostgREST + RLS | `supabase/` |
| Web app | Vite + React + TypeScript SPA, Cloudflare Workers | `web/` |
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

## Workout model: a step is an exercise, and rest is synthetic

A plan is an ordered list of **blocks**, each repeating its ordered list of **steps**
`rounds` times. A step is always an **exercise** — timed (auto-advance) or rep-based (tap to
advance). A step is never a rest.

Rest is not a kind of step. It is emitted from two places, and only ever in the *execution*
stream, as an interval:

- `step.rest_after_seconds` — after **each** set of that exercise, including the last
- `block.rest_between_rounds_seconds` — only **between** a block's rounds

**Sets and rounds are different words on purpose.** A step's `sets` is that exercise's set
count; a block's `rounds` repeats the whole group.

- *4×8 bench press with 90 s between sets* → one block, one step with `sets = 4` and
  `rest_after_seconds = 90`. No wrapper block: the set count belongs to the exercise.
- *Circuit of 4 exercises × 3 rounds, 20 s between* → one block, `rounds = 3`, four steps
  each with `rest_after_seconds = 20`.

**The asymmetry is deliberate:** `rest_after_seconds` fires even after the final set of a
step (usually what you want — it doubles as the rest before the next one), whereas
`rest_between_rounds_seconds` fires only *between* rounds. Making both fire would produce
double rests that are painful to debug in the editor.

Two things were tried and removed, rather than merely hidden:

- **Standalone rest steps** (`plan_steps.kind = 'rest'`, dropped in `0006`). Once rest lived
  on the step and the block, a rest step had nothing left to express.
- **Plan and step notes** (dropped in `0008`). Step notes were still editable in the builder
  but iOS decoded and discarded them, so guidance like "per side" never reached a workout.
  Half-supporting a field is worse than not having it.

  "Per side" is the one note that came back, as `exercises.has_two_sides` (`0012`) — because it
  is the one piece of that guidance the app can act on rather than merely display. A flagged
  exercise emits each set twice, left then right, and the pair is still one set: the rest falls
  once, after both sides, and both intervals read "set 1 of 3". See below for why the side is
  carried in the interval's name.

**Effort is structured now** (`plan_steps.intensity`, `0013`). A timed interval is prescribed as a
duration *and* an effort, and the effort had nowhere to live but the step's `label` — the seeded
plans write "Hard — 20 sec" and `PlanFlattener` prefers a label over the exercise name, so it
reached the screen as a name. A name is not a value: nothing could reason about it, and the
builder cannot set a label at all (`docs/known-issues.md` §1). The three words are policed by a
check constraint rather than by the client, the same way `mode` is, so no fourth word can exist and
every surface switches on the enum exhaustively. It is nullable, because a strength hold is just a
hold, and it sits on the *step* rather than the exercise: a HIIT block runs the same movement hard
and easy.

`session_steps.actual_reps` and `actual_weight_kg` went the same way in `0008`: the engine
could record them but nothing ever called `record(reps:weightKg:)`, so every logged session
stored nulls. `actual_duration_seconds` and `status` stay — the engine genuinely populates
both.

Not supported: EMOM/AMRAP/time-capped work, which needs a *variable* rest (whatever is left
in the minute). Adding it means a new interval concept, not a new column.

**Why two-sided lives on the exercise, and why it rides in the name.** The flag is a property of
the movement, not of a prescription, so it sits on `exercises` and is resolved while flattening —
ticking it changes every plan that uses the exercise, which is what "this movement has two sides"
means. The alternative, snapshotting it onto `plan_steps` the way `mode` is snapshotted, would
have needed a column there, a seventh redefinition of `save_plan`, and an edit to both
hand-written PostgREST select strings.

Carrying the side in `Interval.name` rather than in a field of its own costs no wire change at
all: the name is already on the wire and is what both surfaces draw. An added field would not
have *broken* decoding the way a required one would — `Interval` decodes optionals with
`decodeIfPresent`, so an optional `side` would have been readable by an older build — but it
would still be a format that two separately-installed apps have to agree on, for text that only
ever appears in one place. If the name slot ever needs the room back, an optional `side` on
`Interval` plus a `LinkTests` tolerance case is the escape hatch, and the `(left)`/`(right)`
spelling would move with it.

## Getting in position: the plan asks for it, and the interval has no type of its own

A timed interval starts the instant the previous one ends, so the first seconds of a hold are spent
getting into the hold. The fix is five seconds of "Get in position" in front of it — and four
things about that were decided rather than fallen into.

**It is opt-in per step, not a rule of the flattener.** The obvious rule — every timed interval
gets one — was written, planned and then dropped, because a timed step is *not always work*. The
seeded HIIT blocks prescribe their recoveries as timed steps (`Hard — 20 sec` alternating with
`Easy — 40 sec`, and the demo's `Recover`), and nothing in the model distinguishes a recovery from
a hold: `intensity` is optional and a warm-up is `.low` too, and there is no other candidate.
Under the blanket rule Monday's plan gains twelve prepares and sixty seconds, six of them in front
of a recovery. So the decision moved to where the knowledge is — `plan_steps.prepare_seconds`, and
a checkbox on the timed rows of the builder.

**A duration, not a flag.** `rest_after_seconds` is the shape being copied, and the ask was
explicit that five seconds is only today's value: with seconds in the column, a per-step value is
a builder change and not a ninth `save_plan`. The builder holds the `5`; the database does not care
what it holds, so nothing has to be migrated to widen it.

**No new `StepKind` case, and no new field on `Interval`.** This is the `0012` reasoning applied
again. `Interval` crosses to the Watch whole inside a snapshot, and `kind` is non-optional with a
synthesised decoder — so a third case is not a new possibility but a *decode failure of the entire
snapshot* for any build that predates it, which lands as "No workout" on the wrist with nothing
logged anywhere. The phone and the Watch are installed separately and a weekly re-sign can replace
one and not the other, so that pairing is not hypothetical. Naming it instead costs nothing and
degrades perfectly: an older build draws a five-second exercise interval whose name is already the
right words. The escape hatch is the one `0012` recorded — an optional field plus a `LinkTests`
tolerance case — if a surface ever needs to *reason* about the interval rather than draw it.

**It is emitted inside the side loop.** So a two-sided timed exercise gets one before the left and
one before the right — flipping over is not part of the hold — while the rest stays outside and
still falls once for the pair. And it is emitted before the interval it precedes takes its `index`,
because an index is an interval's identity in the engine: `outcomes` is keyed by it and
`SessionRecord` refuses to restore a record whose keys fall outside the array.

The costs are known and accepted. The `NEXT` line reads `NEXT · Get in position` during the
interval before a timed one, so the exercise name arrives five seconds early rather than at the
start of the rest. The Watch buzzes `start` entering the prepare and again entering the work —
"get ready", then "go" — where a boundary used to buzz once. A finished session logs it as an
`exercise` row named "Get in position" with no `exercise_id`, since `session_steps.kind` allows
only `exercise|rest`. And a pending load nudge is discarded when a prepare begins, because a
prepare carries no `stepID` and the discard rule compares steps — which is already true today
whenever `restAfter` is set, so it is existing behaviour reached by one more route.

## A session is not lost because a refresh failed

`AuthStore.restore()` decides "signed in" by whether the **keychain holds a session**, and then
renews it as a best-effort follow-up whose failure is logged and ignored. It used to call
`auth.session`, which refreshes a stale token and throws when that refresh fails — and every throw
was read as "signed out". So a dropped connection, a phone waking up, or a minute without signal
produced the sign-in screen while the credentials sat untouched in the keychain. The report was
"the session keeps getting lost"; it was never lost, it could not be renewed that second.

The consequences are the point of the design, not a side effect:

* Being signed in is a fact about stored credentials, so only an explicit Sign out — or a token
  the server actually refuses — may change it.
* A request that then fails shows its reason and offers the way out (Sign out → sign in), rather
  than the app silently logging itself out and taking the user's context with it.
* `PlanStore.refresh()` gets one retry behind a `refreshSession()` — but only when the failure
  looks like the session (a 401, or the words "jwt", "unauthorized", "refresh token"). The common
  case it fixes is a request that arrives holding a token that expired a moment ago. It is gated
  rather than unconditional because `refreshSession()` *rotates* the refresh token, and rotating
  it after an unrelated failure — a `400` from a column that does not exist, say — is exactly how
  two rotations race into "Invalid Refresh Token: Already Used".
* That same text is now the debug log's, and the banner gets a sentence a person can act on.

## The watch asks, the phone answers

For a long time the watch could only *listen*: the phone pushed when its own state changed, and
whatever the watch missed stayed missed. Every way a push can go missing is silent — a write that
lands before the phone's `WCSession` finished activating, a snapshot overwritten by a
`sessionEnded` from a runner that is no longer the live one, a resume from a wrist-drop suspension
that is never handed the context it missed. The wrist then reads **"No workout"** for the rest of
the workout, which is indistinguishable from a phone that never started one. That ambiguity is the
single most expensive bug in this project; it has been "fixed" four times, each time by narrowing
the window rather than by removing the class.

So the protocol has a second half. `WatchControl.requestState` lets the watch say *"I have nothing
— tell me the truth"*, and the phone answers from whatever is **actually running** (or with "nothing
running"), rather than from a remembered flag. The watch asks when it becomes active and when
activation completes, because those are the two moments it can be sure it is awake — a cold launch
does not necessarily produce a `scenePhase` change.

This is deliberately **not** a poll. It is a bounded retry, and the bound is the feature: cancelled
the instant anything is applied, so an hour with the phone never reachable costs a few hundred
messages at worst — against the 3,600 the four-hertz poll this project already rejected would have
spent. The watch still renders from the absolute interval list, and the answer is a re-anchor, not
a heartbeat.

### Energy pass and the fifth "No workout", 26 September 2026

An afternoon spent on the report *"I just launched one workout from the app and the watch app still
shows No workout"*, using paired simulators — which is the first time this project has been able to
watch the whole link from both ends at once. Three measurements, and the third is the one that
mattered.

* **An ask went out on two channels, not one.** *"It always queues the ask on the durable channel
  rather than only when out of range"* was wrong in practice, and expensively so: the durable copy
  does not replace the direct one — both arrive — and the phone answers *every* delivery it
  receives, on both channels as well. One wrist raise was therefore **six radio events**, against
  the single message this section said a healthy link costs. The case the duplicate was covering —
  the ask dropped while the phone *looked* reachable — is covered twice over without it: the retry
  asks again at 5, 20 and 65 seconds, and the phone's own `answer()` fires the moment its link
  finishes activating. `send` now picks exactly one channel, and `isReachable` is the only input.
* **A duplicate delivery is dropped rather than applied.** Both channels of one push land on a
  watch that is awake for the whole workout, so a single state change was decoded, applied and
  re-anchored — a fresh cue loop included — twice. `WatchLink.apply` now ignores a payload
  identical to the one it applied moments ago, and still stops the retry: the phone has spoken even
  when it said nothing new.
* **The retry was briefly cut to one attempt for a wrist showing nothing. That was wrong, and it
  was put back the same day.** The reasoning was that a wrist with nothing on it has nothing to
  *correct*. It does have something to *discover*: a workout that has just started, whose single
  push was missed. The next push is an interval away — or a tap away, on a rep set — and "No
  workout" that persists for minutes is exactly the failure this mechanism exists to remove. A
  single shot is not a recovery. The bound is four attempts for every waking, and the cost of being
  wrong in that direction is bounded, because the extra attempts are only spent when the phone does
  not answer at all.

**The bug itself was in `PhoneConnectivity.currentWatchMessage`, and it is the same mistake the
record was introduced to fix, one layer further in.** The link answered from what it had been
*told* to advertise (set when the runner's `start()` claims it) and then from the record on disk.
But between `SessionHost.begin` and that claim there is a window where the app has a session, the
engine holds the whole plan, and the link has been told nothing. An ask landing in that window —
or `activationDidCompleteWith` firing in it — was answered **"nothing running"**, and that answer
is a `.sessionEnded` written into the single-slot application context with the same authority as
everything else. The phone's own log, captured on paired simulators:

```
host: began a session for "Demo — Upper Body A"
activation: state=2 reachable=false paired=true watchAppInstalled=true
answer: nothing running                        ← mid-start, and believed
sent sessionEnded (19 bytes); reachable=false  ← written over the wrist
session: started by ObjectIdentifier(…)
sent session (7222 bytes); reachable=false
```

The fix is one line of *sourcing* and one of plumbing: `currentWatchMessage` consults the session
the app **has** (`SessionHost.controller`, handed to the link at launch) before falling back to the
record. The question is what this phone *knows* is running — which is what the record entry below
established, and the host is simply where the phone knows it.

**Two legibility fixes came out of the same afternoon, and they may matter more than the traffic
ones:**

* **The watch draws its explanation line on the idle screen now.** `link.note` and `runtime.note`
  were rendered only inside `content`, which is reached only when there *is* a session to draw —
  so the notes that explain an *empty* screen were invisible on the only screen that shows nothing.
  A stale build that cannot read the phone, a phone that never answered, and a phone that never
  started a workout were one screen: **"No workout"**. That is why this class of bug has cost hours
  five times, and it was a two-line fix that should have been made after the first.
* **An ask nobody answers now says so** — "Your iPhone didn't answer" — and it is only reachable by
  holding the wrist up for the whole retry, about a minute, because looking away cancels it. It is
  the difference between a phone that has nothing and a phone that is not listening.
* **The phone names a missing Watch app** (`No Watch app — run the Oronzo scheme to the iPhone`),
  which is the one failure a wrist cannot report about itself: with no watch app installed there is
  no process to draw the note. **It used to name the OronzoWatch scheme, and that was the wrong half
  of the pair** — see [A watch app that was installed and not installed](#a-watch-app-that-was-installed-and-not-installed).

**A clear now carries the instant it was decided, and the watch checks that against the session on
screen** (`WatchMessage.idle(at:)`, `SessionClear` in `OronzoCore`, `WireProtocol.current = 2`).
This is the half that holds even with the root cause unfixed, because the root cause was a *clear
that contradicted a live screen* and nothing in the protocol could tell.

A clear is the one message that can **erase** what the wrist is showing, and it used to carry
nothing to order it by — no session, no time — while the application context it arrives in keeps
its value across launches and installs. So a watch could be handed "nothing is running" that was
decided *before* the workout it was displaying; the daemon re-delivered exactly that during this
investigation. One comparison settles every case, with no round trip:

| The clear's instant | Against the session on screen | What the watch does |
|---|---|---|
| before it started | cannot be about this session | ignores it, and writes a line saying so |
| at or after it started | the phone's current word | believes it; the screen goes back to idle |
| absent — an older phone | unorderable | never erases a live screen; asks the phone instead |

The undated `sessionEnded` is kept so a 1 build still runs, and its behaviour is deliberately the
conservative one: it can leave a screen up for one more round trip, and it cannot erase a workout
that is running. That is why the protocol version moved for a change that breaks no session.

**What was deliberately not changed:** the watch still asks, still asks immediately, still reads
the stored context for free first, and still holds its extended runtime session for the whole of a
live workout. The recovery this section describes is worth its messages. What it was not worth was
paying for each of them twice.

The other half of the same decision is on the phone: **only a live session may clear the watch.**
A `SessionController` advertises itself to `PhoneConnectivity` on `start` and resigns on
`teardown`, and a resignation is refused unless that controller is still the advertised one — so a
runner whose view SwiftUI re-created cannot erase a newer session's snapshot on its way out. The
reference is weak, so a controller that is deallocated without a `teardown` cannot leave the link
believing a workout is still running.

## A watch app that was installed and not installed

**28 September 2026.** The sixth "No workout", and the first one that was not a bug in this codebase
at all — it was an install state, and the phone's own advice pointed away from the fix.

What the wrist and the phone said:

| Surface | What it showed |
|---|---|
| The iPhone | `No Watch app — run the OronzoWatch scheme` |
| The Watch | `No workout` · `Your iPhone didn't answer` |

`xcrun devicectl device info apps` showed `com.lerio.oronzo.watchkitapp` **installed on the watch**,
and running. So the banner was not lying about a missing app — and the phone's log said what it
actually meant:

```
activation: state=2 reachable=false paired=true watchAppInstalled=false error=none
updateApplicationContext failed: WCErrorDomain Code=7006 "Watch app is not installed."
```

`watchAppInstalled=false` with the app present means the watch app is **not registered as *this*
phone app's companion**. WatchConnectivity refuses every write with 7006, so nothing is ever sent and
the wrist can only say it was never answered. Both screens are describing the same one fact.

**The misdirection, which is the part worth keeping.** The banner named the **OronzoWatch** scheme.
That is step 2 of the weekly re-sign and, on its own, cannot fix this: the watch app is embedded in
the phone app, and it is installing *the phone app* that registers the companion relationship.
Running OronzoWatch again would have reinstalled a watch app that was already there. The banner now
names the **Oronzo** scheme to the iPhone, which covers both cases — the app cannot tell "not
installed" from "installed but not paired", and installing the phone app fixes either.

**How it was actually fixed.** Running the **Oronzo** scheme to the iPhone — the same visit that
reinstalls the embedded watch app. It has not recurred.

**What is not known.** *Why* the relationship was broken. The watch app was installed at some point
without its companion being registered, and the likeliest route is a watch-scheme install that ran
without the phone app being reinstalled alongside it — which is a hypothesis, not a finding. What is
established is the state, the refusal code, and the step that repairs it.

## The session is written down, and `advertised != nil` was never the same question

The fifth time this project chased a wrist reading **"No workout"** while a workout ran, the cause
turned out to be structural rather than another narrow window — and it was reproducible on a desk
in under a minute.

The phone's answer to *"is a workout running?"* was `advertised != nil`: a weak reference to the
one `SessionController` the link had been told about. That is not the same question. It is *"does
this process happen to be holding an object that says so"* — and a freshly launched process holds
nothing, so `PhoneConnectivity.answer()` — called from `activationDidCompleteWith` — told the watch
**"nothing is running" on every cold launch, whether or not a workout was going**. It wiped a
correct screen, and took the watch's Next / Previous / Pause controls with it, because there was no
longer a session to route them to.

Two further consequences fell out of the same root. `SessionController.start()` opened with
`guard engine.phase == .idle` *before* claiming the link or pushing, so a runner that reappeared
onto its own live session returned at that guard and never told the watch anything again — a wrist
cleared permanently, with no crash and no relaunch required. And an app that died mid-workout left
nothing on disk, so the workout was simply gone.

So the session is a value that gets **written down**. `SessionRecord` in `OronzoCore` carries the
engine's whole state — the intervals, the position, the phase, the outcomes so far, and when any
pause began — to a JSON file in Application Support, written on every state change and read on
launch. `PhoneConnectivity` answers the watch from it when there is nothing in memory, and
`SessionHost` resumes it into the runner so the watch's controls work again.

Four decisions inside that are worth keeping:

* **One rule decides both answering and resuming.** `SessionRecord.isLive` is used by the link and
  by the host, so the phone can never tell the watch "running" about a session it would refuse to
  resume. Two halves of one app disagreeing about what is happening is the failure this project has
  bought five times over.
* **The record is advanced through the engine before it is sent**, never re-derived. That reuses
  the property that a suspension across three intervals resolves in one step, and it is what
  guarantees answering from a stale file can correct the wrist but never rewind it.
* **A runner going away is not a workout ending.** `teardown()` now acts only on a session that has
  finished; a live one is left ticking and on the wrist. `onDisappear` fires for reasons that are
  not "the user left", and treating it as an ending is what let a spurious one take a session apart.
* **Ownership moved out of the view.** `SessionHost` is created once by `OronzoApp` and injected,
  like `AuthStore` and `PlanStore`; `SessionRunner` no longer builds a controller in
  `@State(initialValue:)`. The guards that contained that hazard are kept — they cost nothing and
  catch a regression — but nothing new needs them.

The same slice closed a real bug found on the way: `elapsed` excluded a pause only once `resume`
had folded it into `pausedTotal`, so a session ended *while paused* wrote the final pause into
`totalDuration`. The reading corrected itself on resume, which is why it survived — the number was
right whenever anyone looked at the end.

## Constraints from a free Apple personal team

These are not preferences. A paid account ($99/yr) lifts every one of them — **except the first,
which needed no lifting at all:** it was not true when it was written. See
[HealthKit signs on a free personal team](#healthkit-signs-on-a-free-personal-team) below.

| Constraint | Consequence |
|---|---|
| ~~**No HealthKit** (signing fails on a personal team)~~ — **never was true** | HealthKit signs; the phone records finished workouts to Apple Health. What remains is that there is **no `HKWorkoutSession`**. The Watch stays alive via `WKExtendedRuntimeSession` with `WKBackgroundModes = [physical-therapy]` — a 1-hour cap. ~~and **workouts do not close your Activity rings**~~ — **also never was true**, and measured so on 28 September 2026: a saved workout **does** move the Exercise ring. See [Twice, the same mistake](#twice-the-same-mistake). |
| **No App Groups** | No shared container between iPhone and Watch. All data moves over WatchConnectivity. |
| **No TestFlight** | Install from Xcode only. |
| **Profiles expire every 7 days** | Re-run from Xcode weekly. See `runbook.md`. |
| Max 3 devices per platform | The Watch must be registered with Xcode, or its bundle signs unsigned and install fails with "integrity could not be verified". |

`physical-therapy` is a slightly awkward category for strength work — Apple intends it for
range-of-motion exercise. It is the longest-lived extended runtime that allows background
execution, so it is what we use. That was originally framed as "available to us" — a consequence of
the HealthKit claim above. **It is a choice now, and it stands:** the Watch runtime is deliberately
unchanged, and swapping it for an `HKWorkoutSession` is a large rewrite of the most failure-prone
part of the system, for a cap that has not yet been hit in use.

## HealthKit signs on a free personal team

**The project believed the opposite for a long time, and never tested it.**

This file, `AGENTS.md`, `README.md`, `ios/OronzoWatch/Info.plist` and `WatchRuntime.swift` all
asserted that HealthKit could not be signed by a free personal team. That row is in the constraint
table above as "these are not preferences". It was written as though it had been learned the hard
way, and it was simply assumed — the repository contained no `import HealthKit` before this change,
so nothing had ever been in a position to fail.

It is false. Probing it — a throwaway target signed with the project's own team, a free Personal
Team — built cleanly, and the resulting provisioning profile carried:

```
com.apple.developer.healthkit = true
com.apple.developer.healthkit.background-delivery = true
com.apple.developer.healthkit.access = [health-records]
```

`com.lerio.oronzo` itself was then rebuilt with the entitlement and signs the same way. **A paid
account is not required to write to Apple Health.**

**What this settles, and what it does not.** It settles signing, and nothing else. The Watch's
extended runtime session, its one-hour cap, and ~~the absent Activity ring credit~~ are all still in
place — the cap follows from having no `HKWorkoutSession`, which is a separate decision, and ring
credit turned out not to follow from it at all. This entry exists so that the *next* person does not
repeat the assumption, not to reopen the Watch runtime.

### The recording that follows from it

A finished session is written to Apple Health as a single `HKWorkout`
(`.traditionalStrengthTraining`) **when it ends**, not through a live `HKWorkoutSession`.

Save-at-end keeps Oronzo the single source of truth for timing. A live session would make
HealthKit's builder a second authority on when the workout started and stopped, and would cost a
delegate, interruption handling and session recovery in `SessionController` — the file whose
guards exist because they were each bought with a real failure. Nothing here needs that: Health
writes are permitted from the background, so only the authorization sheet needs the foreground.

The rule for *whether* a session is worth recording — three minutes, judged on the pause-excluded
`totalDuration` — lives in `OronzoCore.RecordableWorkout`, where `swift test` proves it. The I/O
lives in `ios/Oronzo/Session/HealthWorkoutRecorder.swift`, and is the only file importing
HealthKit.

Two consequences worth stating plainly, because they are visible:

- **Health's duration will not always equal Oronzo's.** HealthKit derives a workout's duration from
  the dates it is given, adjusted by pause events; Oronzo's pauses are a running total rather than
  a list of intervals, so they cannot be handed over. The workout therefore spans the real
  wall-clock start and end, and a session with a long pause in it is recorded as longer than the
  work it contained.
- **No heart rate and no active energy.** Oronzo measures neither, and writing invented ones would
  be worse than writing none. It was assumed this also meant **no Exercise ring credit** — untested,
  and wrong: see [Twice, the same mistake](#twice-the-same-mistake).

### Twice, the same mistake

**Both of the constraints this file listed as consequences of having no `HKWorkoutSession` were
assumed, and neither was tested. Both were false.**

| Claim | Where it was written | What was true |
|---|---|---|
| "HealthKit will not sign on a free personal team" | This file, `AGENTS.md`, `README.md`, `ios/OronzoWatch/Info.plist`, `WatchRuntime.swift` | It signs. A throwaway target produced a profile carrying `com.apple.developer.healthkit`, and `com.lerio.oronzo` followed. |
| "Workouts do not close your Activity rings" | This file, `AGENTS.md`, `docs/prd/0001-…` | They do. A saved workout moved the Exercise ring, measured on 28 September 2026. |

The first was caught by testing it. The second survived **because** the first was fixed — the
paragraph above kept asserting it under a heading about not asserting things, and the claim was
carried forward into `AGENTS.md` and the PRD on the strength of its being written down.

That is the pattern worth naming: **a constraint that reads as a consequence of another constraint
is never re-examined when the first one falls.** The ring claim looked like it followed from "no
`HKWorkoutSession`", so nobody asked it separately. It does not follow: HealthKit derives ring
credit from the saved workout itself.

What *is* still true, and still untested, is the one-hour `WKExtendedRuntimeSession` cap — which the
Watch has not yet hit in use.

## Adjusting a load mid-workout: one row, and no way for a fixture to reach it

The runner's load arrows write `plan_steps.target_weight_kg` / `intensity` for the step being
performed. Four things about that were decided rather than fallen into.

**One row, not `save_plan`.** There are exactly two ways a step's load can change, and the other one
is the wrong tool twice over: `save_plan` replaces the whole tree, so it mints new block and step
ids — invalidating the very id the running session is holding — and it would write back a plan the
web builder may have changed since the session started. A narrow `PATCH` needs no new SQL: the
`for all` policy and the `update` grant on `plan_steps` both date from `0001`.

**An empty echo is a failure.** PostgREST answers a `PATCH` that matched no rows with `200` and `[]`,
which is what both a stale step id and an RLS-refused row look like from the client. Without checking
the response the runner would report a save that went nowhere. It is reported as *"this plan changed
elsewhere"*, and the stale id is the likelier cause by a distance — every web save mints new ones.

**The interval carries its step id, and the id is optional.** `SessionRecord` holds the interval list
and nothing else, so a map kept beside the session would be lost on relaunch — and a resumed workout
is exactly the one you are standing in a gym wanting to adjust. Optional because `Interval` is
`Codable`, rides to the Watch whole, and is cached to disk, so a snapshot written by an older build
has to decode: the rule `docs/integration-contracts.md` states and `Interval.intensity` set.

**A fixture cannot reach the write, for the third time.** `savesPlan` joins `persistsRecord` and
`recordsHealth` — one flag each, because the three answer different questions and one of them differs
again for exactly one case. `docs/known-issues.md` §13 records that the *history* write is kept out
of production only incidentally, by the app happening to be signed out; this write does not repeat
that. For a fixture the commit folds into the session and reports success without sending anything,
which is also what makes the arrows exercisable by `-demoSession -demoAdjust` with no account.

## The plan list's order is content, and it belongs to the user

The list of plans was ordered by `updated_at desc` — not by a decision, but by what a timestamp
will do if you let it. It meant the order could not be chosen at all (the only way to move a plan
up was to edit it), and that editing a plan *did* move it, which is a different thing wearing the
same clothes. The list is the picker you scroll on your way into a workout, so its order is
content, and content the user cannot arrange is content that is wrong.

`plans.position` (`0015`) stores that order, and both clients read it. Three choices inside it are
worth the ink, because each looks like an accident and is not:

**The first is that it is in the database at all.** `localStorage` would have been less work and
correct on a desktop — and would have been wrong the moment the order had to mean anything on the
phone, which is the whole point. The iPhone fetches the plans and has no way to ask the browser
what it thinks.

**The second is the deferrable constraint.** `unique (user_id, position)` is the only deferrable
constraint in the schema, because it is the only one whose rows are renumbered **in place**:
`plan_blocks` and `plan_steps` get a fresh tree on every save, so their constraints never see a
transient collision. PostgreSQL checks a non-deferrable unique constraint per row, so renumbering
0,1,2 to 1,2,0 fails on a state that is never committed. Deferring moves the check to COMMIT,
which PostgREST makes the end of the request — with the honest consequence that a violation
arrives as a `500` from the commit rather than from the function that caused it. That is why
`reorder_plans` refuses a partial list rather than trusting one: a list it cannot complete is a
failure it cannot report.

**The third is that the backfill runs with `plans_set_updated_at` disabled.** The trigger is
`new.updated_at = now()` with no condition, so a plain `update … set position` would have stamped
every plan with the migration's own timestamp — destroying the ordering the backfill exists to
preserve, and doing it most invisibly on a phone that has not been rebuilt yet, which still orders
by that column. It is the only place in the schema where a trigger is switched off, and the reason
is that this migration must not have a side effect.

**What is accepted.** Reordering, and creating a plan at the top, both bump `updated_at` on every
plan the user owns — the same trigger fires, and there is no way to write a position without it.
The backfill is the one write that does not, because it runs with the trigger disabled, and the
worth of that is bounded and worth stating exactly: it keeps the *pre-migration* order readable by
a phone that has not been rebuilt yet, and it stops being true the first time anything writes a
position. Nothing reads `updated_at` for ordering afterwards, and nothing renders it, so the cost
is a column whose meaning is now "last time the list was touched" rather than "last edited". If
something ever needs to know when a plan was last *edited*, that will have to be a `WHEN` clause on
the trigger or a second column — and this paragraph is here so that the difference is found before
it is relied on.

**What it forecloses.** A new plan goes to the top, which means `save_plan` shifts the whole list
down on the insert path. That is O(n) writes for a rare event on a personal account, and it buys
two things the sibling tables also keep: positions are **non-negative**, and inserting never
requires a negative one. The alternative — giving a new plan `min(position) - 1` and dropping the
check — is cheaper and would have made `plans` the one table whose positions can go below zero.

Contiguity is *not* on that list, and the difference is worth stating because it is the sort of
claim that gets built on: **deleting a plan leaves a gap.** `deletePlan` is a bare delete and
nothing renumbers, so removing the middle of three plans leaves `{0, 2}`. That is harmless — the
order is still a total order, uniqueness is about equality rather than adjacency, and the shift
and the seed scripts' append are both gap-safe — and the next drag heals it, because a reorder
renumbers `0..n-1`. But it is why nothing should ever "tidy up" gaps with a
`set position = position - 1`: that collides on the way, and being deferred it would surface as a
failure at COMMIT, after the function had returned.

## The Lock Screen surface: built, and removed

A Live Activity showing the current interval on the iPhone's Lock Screen was specified (PRD 0001's
first amendment), built as slice S7, used, and then **deleted**. The reasoning is worth keeping
because the removal was the correct outcome of a real design flaw rather than a failed
implementation.

**It worked.** Feasibility question 10 came back positive — a Live Activity provisions on a free
personal team with no App Groups and no entitlement beyond `NSSupportsLiveActivities`, which was the
one genuinely uncertain thing in the whole plan. The countdown was right: an absolute end date handed
to the system, which renders the timer itself, so the clock stayed correct with no per-second traffic.
That is the same principle the Watch is built on, and it held.

**It could not do the job it was specified for.** The card changes only when the app posts a content
update. The system's timer is display-only and clamps at `0:00`; the handover to the next interval is
the app's. And while the phone is locked, iOS does not take a content update from an app whose only
background justification is audio playback — which is the only kind this app has, and the same
mechanism that makes the pocketed-phone cues work. So for the half of a workout when the phone was in
a pocket, the card held whichever interval it had last been handed.

**The stated use case and the mechanism were in conflict from the start.** The amendment's reasoning
was "the phone sits on a surface with its screen on, so the Lock Screen is what is visible for most of
a workout" — but a phone left on a surface *locks*, and a locked phone is exactly where the surface
stopped working. Question 10 asked whether the surface was achievable, and nothing asked what it added
that the Watch screen did not.

**What it cost, and what that decided.** A widget extension is a third target: its own bundle
identifier, its own provisioning profile, and therefore a third thing in the seven-day re-sign ritual
for a free personal team. Push-to-update — the supported path for keeping an Activity current while
locked — needs a server and a paid account, both of which are non-goals. So the price was real and the
benefit was a surface that was right only while the phone was in your hand.

The Watch carries the whole no-look burden, as it always did.

**The generalisable rule.** For a surface whose value is not obvious from the design, ask *what does
this get you that the surface you already have does not* **before** the feasibility work. Feasibility
is the easier question, and it is the one that feels like progress — it produces a crisp yes or no and
a working prototype, while the value question produces an argument. Two surfaces were added by
amendment in one sitting and both were essentially additive; the one that was asked "can we" rather
than "should we" is the one that is gone.

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
committed. On iOS they live in `ios/Local.private.xcconfig` (gitignored, and included
*optionally* by the committed `ios/Local.xcconfig` so a fresh clone still builds). The
signing team ID sits in the same file, for the same reason — this repository is public.
