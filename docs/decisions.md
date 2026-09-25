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

This is deliberately **not** a poll. It is one message per wrist raise, and only when the phone is
in range or the watch has nothing to lose by queueing it. The prohibition below on a per-second
message stream is untouched: the watch still renders from the absolute interval list, and the
answer is a re-anchor, not a heartbeat.

The other half of the same decision is on the phone: **only a live session may clear the watch.**
A `SessionController` advertises itself to `PhoneConnectivity` on `start` and resigns on
`teardown`, and a resignation is refused unless that controller is still the advertised one — so a
runner whose view SwiftUI re-created cannot erase a newer session's snapshot on its way out. The
reference is weak, so a controller that is deallocated without a `teardown` cannot leave the link
believing a workout is still running.

## Constraints from a free Apple personal team

These are not preferences. A paid account ($99/yr) lifts every one of them.

| Constraint | Consequence |
|---|---|
| **No HealthKit** (signing fails on a personal team) | No `HKWorkoutSession`. The Watch stays alive via `WKExtendedRuntimeSession` with `WKBackgroundModes = [physical-therapy]` — a 1-hour cap, and **workouts do not close your Activity rings**. |
| **No App Groups** | No shared container between iPhone and Watch. All data moves over WatchConnectivity. |
| **No TestFlight** | Install from Xcode only. |
| **Profiles expire every 7 days** | Re-run from Xcode weekly. See `runbook.md`. |
| Max 3 devices per platform | The Watch must be registered with Xcode, or its bundle signs unsigned and install fails with "integrity could not be verified". |

`physical-therapy` is a slightly awkward category for strength work — Apple intends it for
range-of-motion exercise. It is the longest-lived extended runtime available to us that
allows background execution, so it is what we use.

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
