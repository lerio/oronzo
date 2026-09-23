# Known issues — confirm before building on these

Code that looks **unintended**, or that contradicts a comment or a stated decision elsewhere.

This file exists because the alternative is worse. Deleting an observation like this recreates the
gap: the next agent reads the same code, infers the same pattern, and re-encodes the mistake. So
each entry says what the code does, why it may be wrong, and the question that settles it.

None of these is on fire. They are recorded so that nobody *relies* on one by accident.

**Status: none of these has been confirmed as intended or as a bug by the human yet**, except §12 —
confirmed, accepted as a platform limitation, and closed by correcting the documents it contradicted.
When one is resolved, either fix the code or amend the entry to say explicitly why the current shape
is correct — and if it is correct, say so in the code too.

---

## 1. `label` is supported end-to-end but cannot be set anywhere

**What the code does.** `PlanStep.label` exists in the schema, in `Models.swift`, and in
`types.ts`. `save_plan` writes it. Both flatteners prefer it over the exercise name, and it is
covered by `testLabelOverridesTheExerciseName`. But the builder sets `label: null` and **no input
in `PlanEditor.tsx` ever updates it** — so the field is unreachable from the UI.

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

## 3. A failed plan fetch is indistinguishable from an empty account

**What the code does.** In `PlanListView.swift:11-32` the error banner lives in the `else` branch
of `plans.isEmpty`, so it can only render when a *cached* list exists. On a cold start with no
cache and no network, `plans.isEmpty` matches the empty-state branch first and the user is told:

> "No plans yet — Build one in the web app, then pull to refresh here."

`store.error` is set and never shown.

**Why it may be wrong.** The one case the banner was written for — offline with nothing cached —
is the one case it cannot cover. The copy actively misdirects: it sends the user to build a plan
they already have.

**Question.** Should the empty-state branch fall through to the error treatment when `store.error`
is non-nil?

## 4. `PlanCache` is unversioned, and its failures are silent

**What the code does.** `PlanStore.swift:64-83` encodes `Plan`/`Interval` straight to JSON with a
bare `JSONEncoder()` — no version key, no timestamp, no user keying. `load()` returns `nil` on any
failure via `try?` with **no `Log.debug` call**.

**Why it may be wrong.** Renaming or retyping any `Codable` property in `Models.swift` silently
invalidates every existing cache file, and nothing anywhere reports it — the user just sees a
slower first paint. `PhoneConnectivity` logs *every* skip it makes, so the silence here reads as an
oversight rather than a decision.

**Question.** Add a version field plus a debug log, or accept silent invalidation as fine for a
single-user app?

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

## 9. `WatchRuntime.start()` can be refused and never retried

**What the code does.** `WatchRuntime.swift:27-37` assigns `self.session` **before** calling
`session.start()`, and guards with `guard session == nil else { return }`. Its own comment says
*"Must be called while the app is active, or it is refused."* `start()` is only ever called from
the `intervals.isEmpty` onChange in `WatchSessionView`.

**Why it may be wrong.** If watchOS refuses the session without firing `didInvalidateWith` (which
is what nils `self.session`), the property stays non-nil and the guard blocks every future retry
for the life of that object — the workout would freeze with no explanation.

**Confidence: unverified.** The refusal path was read from the code, not reproduced on a device.
This one needs a watch to settle.

**Question.** Should the guard key off a delegate-confirmed start rather than assignment?

## 10. Stale comments that contradict the code

Three comments assert behaviour that is no longer true. None changes behaviour, but each has
already misled an agent once:

- `ios/OronzoWatch/Info.plist` says *"Single-target watchOS app (watchapp2)"* — the target is
  correctly `type: application`, and the traps section insists it must **not** be `watchapp2`.
  Trusting this comment would re-break the build with `Multiple commands produce`.
- `ios/project.yml:16` says `cp ios/Local.xcconfig.example ios/Local.xcconfig`. That file does not
  exist; the real one is `Local.private.xcconfig.example`, which is what `README.md` and
  `runbook.md` correctly say.
- `web/src/styles.css:329` explains a rule by referring to *"the exercise-name select"*, which no
  longer exists — it was replaced by `ExercisePicker` in `2965c33`. The rule and the stale
  selectors around it (`.step-row > input`) are documented in `patterns.md`.

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

## 12. The Lock Screen Activity cannot advance while the phone is locked

**What the code does.** S7's Live Activity carries the current interval plus an absolute end date,
and posts a content update only on state transitions (`SessionController.pushState` →
`LiveSessionActivity.update`). `Text(timerInterval:)` renders the countdown from that date, which is
what makes the clock live with no per-second traffic — and it clamps at `0:00` once the date passes,
changing nothing by itself.

**What was measured.** On the device, with the phone locked: the countdown reaches zero and the card
keeps that interval, on that exercise, indefinitely — while the watch and the phone (once unlocked)
both move on correctly. **The wiring is not at fault.** Verified in the Simulator: a write from a
backgrounded app is applied, and the daemon's own permission line names its criterion —
`Process is doing more than playing background media so is permitted to update activity`. Holding a
`beginBackgroundTask` assertion across the write (added for exactly that reason, then measured on the
device) **changed nothing**, so that criterion is either not about assertions or not the whole story.

**Why it matters.** Two claims elsewhere are false as stated. `docs/spec/0001-ui-polish.md` says the
countdown "stays correct with **no ongoing updates from the app at all**", and
`docs/ui-design/0001-ui-polish.md` §5 says "Updates only on state transitions, not per second". Both
are true of the countdown and false of the **transition**: the card can only change when the app
posts a content update, and this app's only justification for running with the phone locked is
background audio — the category the daemon's criterion names. The same mechanism that makes the
pocketed-phone cues work is the one that appears to disqualify the card. Apple documents no local way
around it; push-to-update is the supported path, and `docs/spec` chose local updates deliberately
because this project has no server.

**Mitigation in place, and it is not a fix.** The content carries `staleDate = intervalEnd`, so the
system marks the card out of date at the moment the interval ends rather than leaving it asserting an
interval that is over. That is the honest signal available locally.

**Confidence.** The device behaviour is measured by the human; the mechanism is inferred from the
daemon's log plus public reports. The one reading that would settle which mechanism it is — whether
the app is running-and-refused, or suspended outright — is the phone's own ActivityKit log across a
boundary, which needs `sudo log collect` or Console.app on the device. It would not change the card
either way, and it matters only as a symptom of something else: a suspended app fires no cues while
pocketed, which the `UIBackgroundModes` design depends on.

**Resolved — accepted, not fixed.** Both documents named above have been corrected to say what the
surface actually does, and the payload now carries `staleDate = intervalEnd`, so the card goes out of
date at the moment it stops being true instead of asserting an interval that is over. Push-to-update
is the only mechanism that would advance it while locked; it needs a paid account and a server, and
belongs in a PRD rather than in this entry.
