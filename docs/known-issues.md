# Known issues — confirm before building on these

Code that looks **unintended**, or that contradicts a comment or a stated decision elsewhere.

This file exists because the alternative is worse. Deleting an observation like this recreates the
gap: the next agent reads the same code, infers the same pattern, and re-encodes the mistake. So
each entry says what the code does, why it may be wrong, and the question that settles it.

None of these is on fire. They are recorded so that nobody *relies* on one by accident.

**Status: none of these has been confirmed as intended or as a bug by the human yet.** When one is
resolved, either fix the code or amend the entry to say explicitly why the current shape is correct
— and if it is correct, say so in the code too.

Two have been closed this way and are kept only as *how they were closed*, because the closing is
what the next agent needs to know: §4 gained the log line it was missing, and §9's refusal deadlock
was already fixed by keying the guard off a delegate-confirmed start. An entry that was closed by
**removing the code** is not recorded here at all — see `docs/decisions.md` for the Lock Screen
surface, which was deleted rather than fixed.

---

## 1. `label` is supported end-to-end but cannot be set anywhere

**What the code does.** `PlanStep.label` exists in the schema, in `Models.swift`, and in
`types.ts`. `save_plan` writes it. Both flatteners prefer it over the exercise name, and it is
covered by `testLabelOverridesTheExerciseName`. But the builder sets `label: null` and **no input
in `PlanEditor.tsx` ever updates it** — so the field is unreachable from the UI.

One thing labels used to be carrying has since found a home: an interval's *effort*, which the
seeded plans spell into the label ("Hard — 20 sec"), is `plan_steps.intensity` as of `0013`. That
leaves the label with only a rename/alias job, which is what the question below is about.

**Why it may be wrong.** This is exactly the pattern migration `0008` set out to remove: *"Half-
supporting a field is worse than not having it."* Step notes were dropped for precisely this
reason — editable in the builder, silently discarded on iOS.

**Question.** Was `label` kept deliberately as a rename/alias affordance for a future builder
feature, or is it a leftover that should go the way of `notes`?

## 2. `sessions.notes` is a dead column

**What the code does.** Nothing reads or writes it. `0008` dropped `plans.notes` and
`plan_steps.notes` but left this one, while its own header said it was removing *"capabilities the
app had stopped honouring."*

**Why it may matter.** Harmless in itself, but it is a live column that a future agent could
reasonably start populating on the assumption that it was kept on purpose.

**Question.** Drop it in a migration, or is it reserved for a post-session note that was never
built?

## 3. A failed plan fetch is indistinguishable from an empty account — closed, kept for the reasoning

**What the code does.** In `PlanListView.swift:11-32` the error banner lives in the `else` branch
of `plans.isEmpty`, so it can only render when a *cached* list exists. On a cold start with no
cache and no network, `plans.isEmpty` matches the empty-state branch first and the user is told:

> "No plans yet — Build one in the web app, then pull to refresh here."

`store.error` is set and never shown.

**Closed.** `PlanListView` now branches on `plans.isEmpty` *and* `store.error` before the empty
state, so an unreachable server shows "Can't reach your plans" with the reason and a **Try again**
button instead of telling you to go and build one. The second path below is closed with it.

Since `0012`, one more path lands here: a cache file written before that migration lacks
`twoSidedExerciseIDs`, which is required, so `PlanCache.load()` discards it — deliberately (a file
that decoded would flatten every two-sided exercise once, silently), and with no network the first
launch after updating shows a *genuinely* empty list. That is now the "No plans yet" branch, which
is correct: there really is nothing cached to show.

**Why it may be wrong.** The one case the banner was written for — offline with nothing cached —
is the one case it cannot cover. The copy actively misdirects: it sends the user to build a plan
they already have.

**Question.** Should the empty-state branch fall through to the error treatment when `store.error`
is non-nil?

## 4. `PlanCache` is unversioned — closed, kept for the reasoning

**What the code does.** `PlanStore.swift:64-83` encodes `Plan`/`Interval` straight to JSON with a
bare `JSONEncoder()` — no version key, no timestamp, no user keying. `load()` returns `nil` on any
failure via `try?` with **no `Log.debug` call**.

**Why it may be wrong.** Renaming or retyping any `Codable` property in `Models.swift` silently
invalidates every existing cache file, and nothing anywhere reported it — the user just saw a
slower first paint. `PhoneConnectivity` logs *every* skip it makes, so the silence here read as an
oversight rather than a decision.

**Closed — the log half, and deliberately not the version half.** `PlanCache.load()` now logs the
decode failure, which was the actual defect: an unreadable cache and no cache yet were
indistinguishable in the log, and offline that is the difference between a workout and none. A
version key was **not** added. It would buy nothing on its own — the decode either succeeds or it
does not — and it would be a field to keep in step across two apps for no behaviour. Silent
invalidation is fine for a single-user app; silent *failure* was not.

## 5. The secret-scan guard is written but not active

**What the code does.** `.claude/hooks/secret-scan.sh` is complete and careful: it reads the real
secrets from the gitignored files at run time, scans the staged index for a commit and `HEAD` for a
push, and separately blocks a commit that would be authored under the global personal email.
**It is not registered.** There is no `.claude/settings.json`, so it never runs, and the only
remaining protection is a manual scan before each push.

**Why it matters.** This repository is public, and that was authorised on the standing condition
*"as long as no sensitive data is pushed."* The hook is the thing that makes the condition hold
without discipline.

**Where the fix lives.** The `settings.json` that activates it — including the permission
allow/ask/deny lists — is written out in full inside **`.claude/README.md`**, which is committed
and now restored. Nothing is at risk of being lost; the block simply has not been applied.

**Question.** Wire it up, and restore or relocate that `settings.json` block? Note that creating
permission grants is the user's call, not an agent's — which is why `.claude/README.md` records
that writing it was blocked the first time.

## 6. Web error handling has three different treatments

**What the code does.** `Plans.tsx` and `History.tsx` replace the whole screen with the error, so a
failed *delete* blanks the *list*. `Exercises.tsx` renders it inline above a still-visible list.
`PlanEditor.tsx` routes load failures through a `!plan` branch rendered in muted, non-error style,
sharing one `error` string with save failures.

**Why it may be wrong.** There is no stated convention, and the treatments have different
consequences for the user. Bare `err.message` is also used in three routes while `PlanEditor` uses
`err instanceof Error ? … : …`.

**Question.** Which is the intended pattern? `Exercises.tsx` (keep content, show error inline)
looks like the one worth standardising on.

## 7. The web app is not type-strict

**What the code does.** `web/tsconfig.app.json` enables `noUnusedLocals`, `noUnusedParameters`,
`verbatimModuleSyntax` and `erasableSyntaxOnly` — but **not `strict`**. So `strictNullChecks` and
`noImplicitAny` are off. No tsconfig in `web/` sets `strict`.

**Why it may be wrong.** It is the gap between the repo's discipline and its checks: the model is
mirrored across three languages and `tsc -b` is described as the thing that catches stale field
references, yet nullable domain fields (`reps: number | null`) get no enforcement at call sites,
and the bare `err.message` catches compile only because of it.

**Question.** Deliberate, or inherited from the Vite template and never revisited? Turning it on is
a real piece of work, not a config flip.

## 8. A session cannot be ended from the wrist

**What the code does.** `WatchControl.finish` exists, and the phone handles it
(`SessionController.swift:183` → `finishEarly()`). The watch UI sends only `.previous`,
`.togglePause` and `.next`.

**Why it may be wrong.** Ending a workout means reaching for the phone — the opposite of the
"phone in a locker" case the whole design is built around. The handler exists, so the intent
clearly was there.

**Question.** Add the control, or is ending a session deliberately phone-only?

## 9. `WatchRuntime.start()` can be refused and never retried — closed, was stale

**What the code does.** `WatchRuntime.swift:27-37` assigns `self.session` **before** calling
`session.start()`, and guards with `guard session == nil else { return }`. Its own comment says
*"Must be called while the app is active, or it is refused."* `start()` is only ever called from
the `intervals.isEmpty` onChange in `WatchSessionView`.

**Why it may be wrong.** If watchOS refuses the session without firing `didInvalidateWith` (which
is what nils `self.session`), the property stays non-nil and the guard blocks every future retry
for the life of that object — the workout would freeze with no explanation.

**Closed — already fixed, and this entry was stale.** The guard does key off a delegate-confirmed
start: `WatchRuntime` carries a separate `didStart` that only the delegate sets, and
`setRunning` discards a session that was created but never confirmed before starting another. Re-read
at the time of writing — the lines this entry cites (`:27-37`) are the constructor, and the relevant
code is `:46-54`. The entry was written before that fix landed and never revisited.

**Closes the question it asked**, and the reason it mattered has not gone away: a refused session
that is never retried still freezes the workout with no explanation, which is why the recovery path
is also re-asserted on every wrist raise.

## 10. Stale comments that contradict the code

Comments that assert behaviour which is no longer true. None changes behaviour, but each has
already misled an agent once. The third was fixed while adding the fourth, which is why this is
now two:

- **Fixed.** `web/src/styles.css` explained a rule by referring to *"the exercise-name select"*,
  which no longer exists — it was replaced by `ExercisePicker` in `2965c33`. The sentence now names
  `ExercisePicker`. The dead rule beside it, `.step-row > input`, has been deleted: every numeric
  input is wrapped in a `label.inline-field` and `ExercisePicker` renders its own input inside a
  `div`, so the selector could never match anything.
- **Fixed.** `WatchLink.startHaptics` explained its positive delay by saying *"`nextEvent` and
  `nextSecond` are both strictly after the moment they were asked about"* — but the watch has never
  called `nextSecond`, and it no longer exists at all: the phone's clock moved to a `TimelineView`,
  so nothing schedules a per-second wake any more. The comment was doubly wrong by the time anyone
  read it, which is the cost this entry is about.

Still open:

- `ios/OronzoWatch/Info.plist` says *"Single-target watchOS app (watchapp2)"* — the target is
  correctly `type: application`, and the traps section insists it must **not** be `watchapp2`.
  Trusting this comment would re-break the build with `Multiple commands produce`.
- `ios/project.yml:16` says `cp ios/Local.xcconfig.example ios/Local.xcconfig`. That file does not
  exist; the real one is `Local.private.xcconfig.example`, which is what `README.md` and
  `runbook.md` correctly say.

## 11. A security comment describes the wrong mechanism

**What the code does.** `0001_init.sql` grants table privileges only to `authenticated` and states:
*"`anon` deliberately gets NOTHING — combined with RLS being enabled and every policy being `to
authenticated`, an unauthenticated request can read and write nothing at all."*

**What was measured.** Probing the live REST endpoint with the publishable key (the `anon` role)
returns **HTTP 200 with `[]`** — not a `401 permission denied`. An `anon` caller therefore *does*
hold `SELECT` on `exercises`; it is **row-level security alone** that returns no rows, because
every policy is scoped `to authenticated`. Supabase's default privileges grant to `anon` and
`authenticated` alike, so the explicit grants in `0001` do not remove what the defaults added.

**Why it matters.** The security posture is fine — RLS is doing the work and the outcome is
correct. But the comment names the wrong mechanism, and someone reasoning from it could conclude
that a future table needs no policy as long as it carries no grant. It does. This also confirms
`ops/keepalive/` works as its own comment claims: the query succeeds and returns nothing, which is
exactly the database activity that keeps the free project from pausing.

**Question.** Correct the comment to say RLS is the control, and keep the grants as belt-and-braces?

---

## 12. The HealthKit write is proven to build, and not proven to work

**What the code does.** `ios/Oronzo/Session/HealthWorkoutRecorder.swift` writes one
`HKWorkout` (`.traditionalStrengthTraining`) for any session that ends after three minutes,
via `HKWorkoutBuilder`. `OronzoCore.RecordableWorkout` decides *whether*, and is covered by
`RecordableWorkoutTests` in `swift test`.

**What has actually been measured — and what has not.** This is the entry to read before trusting
the feature, because the gap is wider than usual here:

- **Verified.** HealthKit signs on this free personal team, and `com.lerio.oronzo` itself signs with
  `com.apple.developer.healthkit` in both its entitlements and its embedded profile — inspected on
  the built device artifact with `codesign -d --entitlements` and `security cms -D`, not inferred
  from a green build. Both targets compile with no warnings. The three-minute rule is unit-tested.
- **Verified, and a trap worth knowing.** HealthKit *validates* `NSHealthUpdateUsageDescription`
  and crashes with `NSInvalidArgumentException` if the string is not a real sentence. A probe app
  using `"Probe"` as a placeholder died at the authorization call; the same shape with a proper
  sentence raised the sheet normally. The string in `ios/Oronzo/Info.plist` is a real sentence.
- **Not verified.** The save itself. The authorization sheet was reached on an iOS Simulator, but
  this machine has no `Simulator.app` — only the headless CoreSimulator runtime — so the sheet could
  not be tapped and the write could not complete. **No workout has been observed in Apple Health.**

**Why it matters.** Two things follow from the unverified part, and neither can be settled by
reading the code. First, whether a workout that is saved *without* a live `HKWorkoutSession`, and
with no heart-rate or energy samples, earns **Exercise ring credit** — `docs/decisions.md` claims
workouts do not close the rings, and that claim rests on the same untested part. Second, whether a
workout written from a phone that is locked and in a pocket is delivered at all; HealthKit permits
background writes, but that has not been seen here.

A failure is **not silent**: the summary reports the outcome beside the history line
(`Added to Apple Health` / `Not added to Apple Health — …`), so a denied permission is visible
rather than showing up as a workout that never appears. That is also why there is no "Try again" on
that line, unlike the history one — a retry after a write that failed is the one path that could
double-post if the failure landed after the store had already committed.

**Question.** Do a real workout of more than three minutes on the phone, then check the Fitness app
for the entry and the Activity rings for credit? If the summary says `Added to Apple Health` but the
ring does not move, the escalation is a live `HKWorkoutSession` — a scoped follow-up, not a fix to
this code.

---

## 13. The history write has no demo guard, and a fixture can reach production

**What the code does.** `SessionRunner.persist` (`ios/Oronzo/Views/SessionRunner.swift:482`) calls
`SessionLogger().log(...)`, which inserts into Supabase `sessions` + `session_steps`. It consults
nothing about whether this launch is a fixture. `SessionController.persistsRecord` — the flag that
does distinguish them — is `private`, so the view cannot read it.

**Why it matters.** `-demoSession` runs `DemoPlan.make()`, a realistic full-length plan, and it
reaches the summary screen like any other. Today a demo run is kept out of history only
*incidentally*: either the app is signed out, so `auth.session.user.id` throws, or `plan_id` is a
fresh random UUID that violates the foreign key to `public.plans`. Neither is a guard. A demo run
with a live keychain session inserts a row named `"Demo — Upper Body A"` into real history, where
it is indistinguishable from a workout that was done.

This is pre-existing, and was found while adding the HealthKit write next to it — **which does have
a guard**, via `recordsHealth`, precisely because the same reasoning was applied there. The two
paths should not differ in whether they can be reached by a fixture.

**Question.** Guard `persist` the way `writeToHealth` is guarded — expose the flag the controller
already holds and skip the write for a fixture — rather than leaving the FK to catch it by luck?
