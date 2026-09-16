# PRD 0001 — UI/UX polish, iPhone and Apple Watch

**Status:** **approved** — 16 September 2026. The direction question is settled; see [Decision](#decision).
**Date:** 16 September 2026
**Scope:** iPhone app and Apple Watch app. The web plan builder is explicitly deferred.

---

## Problem statement

Oronzo's MVP is functionally complete. Every feature in the original scope works end to end: plans are authored, a session runs, the Watch mirrors it, the result is saved. What does not yet exist is a designed interface — the screens accumulated one milestone at a time, each added to serve the function that milestone needed. The result is *correct* but not *shaped*.

That would be a cosmetic complaint in most software. Here it is not, because of when this app is used. Oronzo is read in exactly the conditions where interface design matters most and is hardest to get right:

- **Mid-set, out of breath, one hand free.** The user is not reading the screen; they are glancing at it while recovering. Comprehension has a budget of roughly two to three seconds.
- **A wrist, not a hand.** The Watch is seen at an angle, at arm's length, often while moving.
- **A gym.** Variable and frequently poor lighting; the phone is often face-down on a bench or in a pocket.
- **Physically distracted.** Attention is on the lift, not the layout.

An interface that has to be *studied* fails in all four conditions. Today, the state that matters most — *am I working or resting, and how long is left* — is not guaranteed to be the most prominent thing on screen, because prominence was never decided, only inherited.

**The cost is felt as:** reaching for the phone to check something the watch should have said; misreading whether a rest is over; and a nagging sense that the app is a prototype you happen to rely on.

## Target users

**Primary and, for v1, only: the single owner-user.** One person, training regularly, running Oronzo for the full length of their own sessions. There is no onboarding, no second user, and no support burden to design around.

This matters for scoping: the success condition is not "a new user can figure it out" — it is "an expert user, mid-session, never has to think about the interface at all." Familiarity can be assumed; discoverability cannot be leaned on as an excuse for a weak hierarchy.

**Not a target for v1:** anyone being shown the app. Should Oronzo later become something to demonstrate or share, that is a second, different audience — and it would argue for a different direction (more self-explanatory, more conventionally handsome). It is noted here only so the choice is visible, not because it is in scope.

## Success metrics

Design work resists numbers, so the numbers below are deliberately behavioural tests that can be run by the user on himself, and measured before and after. The "before" measurement is the baseline and has not been taken yet — taking it is the first task.

| # | Metric | How it is measured | Target |
|---|---|---|---|
| 1 | **The 3-second glance** | Standing, phone face-down, watch on wrist, mid-session. On raising the wrist, correctly state: (a) the current exercise, (b) *working or resting*, (c) time remaining. 10 timed trials, no instructions, no practice run. | 10/10 on (b) — working vs resting is never ambiguous. 9/10 on (a) and (c). |
| 2 | **No-look transitions** | Run one complete session. Count how many times the phone is picked up specifically to check session state. | 0. |
| 3 | **One design, not seven screens** | Count the distinct text sizes, spacing steps, and colour roles visible across the two apps. | Each reduced to a single small defined set, every value traceable to a named role. No one-off values. |
| 4 | **Hierarchy is instant** | On each of the two mid-workout screens, a single element is unmistakably the most prominent. Judged by squinting at a screenshot from arm's length. | One clear primary element per screen; no two elements competing. |

**Guardrail, not a metric:** zero functional regression. The whole session flow — start, advance, pause, finish, save — behaves identically, and every existing test still passes. Polish must not be a rewrite.

**Explicitly not a metric:** subjective "does it look nice". If it cannot be judged by one of the four tests above, it is a design decision to be argued on its merits, not a success criterion.

## Scope

**In scope for v1 — the two surfaces where the product is actually used:**

1. **The session runner (iPhone)** — the screen(s) visible for the entire duration of a workout.
   The highest-value surface by a wide margin: it is on screen for 45 minutes, where every other screen is on screen for seconds.
2. **The Watch session screen** — the glance surface. The hardest constraint and the one where the 3-second test is won or lost.
3. **The visual language those two force** — type scale, spacing, colour roles, and how state (working / resting / paused / finished) is expressed. Defined once, applied consistently.

**In scope if cheap once the above is settled** — these are seconds-long exposures, so they follow the system rather than driving it: sign-in, plan list, plan detail, session summary.

## Non-goals

Stated plainly, because several of these are tempting:

- **The web plan builder.** Deferred by decision, not oversight. It is a desk-bound authoring surface with entirely different constraints, and designing it in the same pass would produce a compromise. It gets its own PRD, and should inherit the visual language rather than co-author it.
- **Any new functionality.** No new workout types (EMOM/AMRAP), no per-step logging of reps or load, no charts, no calendar. This is a design pass over what exists.
- **Changing the product's core premise.** The Watch stays a renderer and remote; the phone stays the source of truth. No watch-standalone execution.
- **Anything gated behind a paid Apple account** — HealthKit, Activity ring credit, and the constraints that come with the free tier are accepted as given.
- **A brand identity.** No logo, no marketing surface, no name change. (App icon: see open questions — currently leaning out of scope.)
- **Accessibility beyond the basics** is not deferred entirely, but see open questions: Dynamic Type and colour-independence for work/rest are treated as *requirements*, not nice-to-haves, because the 3-second test is unwinnable without them.

## Decision

**Settled 16 September 2026.** The direction is a deliberate *per-surface* combination, because the two surfaces have genuinely different jobs.

| Surface | Direction | Why |
|---|---|---|
| **Apple Watch** | **A — Instrument panel** | It is a two-second readout, held at an angle, in a gym. This is where the 3-second glance test is won or lost, and A is the direction least likely to fail it. Density is a feature here: every fact present, nothing hidden. |
| **iPhone** | **B — Quiet coach** | It is on screen for the whole session — 45 minutes, not 2 seconds — and it is the surface you have to *want* to open on a bad day. Calm and generous beats a readout at that exposure. |

**The two share one vocabulary** — type scale, spacing steps, and colour roles — which is what makes success metric 3 achievable at all. This is a mix of two directions, *not* two designs: the shared vocabulary is the part that must not fork.

**Watch information depth: current interval plus what's next.** The next exercise is shown subordinate to the current one. This answers *"am I nearly done with this?"* without a tap. It costs vertical space on a small screen and competes with the primary element, so the primary must win decisively — if the next-up line starts competing, it is the thing that gets cut, not the clock.

### What was considered and not chosen

- **A on both** — maximum glance performance, safest against the test, but reads utilitarian for a full session on the phone.
- **B on both** — the most liveable, but calm applied to the Watch is the easiest way to miss the 3-second budget.
- **C — One thing at a time** on both — the strongest opinion and the most contemporary result, but it deliberately withholds "what's next", which the chosen Watch depth explicitly wants. C remains the most interesting direction to revisit for the web builder.

The three directions as originally proposed are kept below as the record of what was weighed.

## Aesthetic direction — the three options as proposed

Each is a coherent position with a real cost.

### A. Instrument panel
High-contrast and information-dense: the screen reads like a piece of gym equipment. Large numerals, state carried by colour and weight, near-zero decoration. Dark-first, which suits most gyms and every wrist. The interface looks *engineered*.
**Strongest at:** the glance. This is the direction least likely to fail the 3-second test.
**Cost:** can read as cold or utilitarian on the phone, where the user spends much longer and may
want more than a readout.

### B. Quiet coach
Calm and low-arousal. Fewer elements, larger and softer; what has been completed is surfaced as much as what remains. Rest is visually quiet, work is warm. Restrained, generous spacing. The interface looks *designed to be lived with*.
**Strongest at:** the phone, and at being an app you don't resent opening on a bad day.
**Cost:** the watch may lose immediacy if calm is applied there without discipline — this direction is the easiest to over-apply and the hardest to hold to a 3-second budget.

### C. One thing at a time
Ruthless singular focus. Each surface shows exactly one primary element at maximum size; anything else is either subordinate at a much smaller size or revealed on demand. The watch shows the current interval and nothing else; the phone shows it plus a minimal progress indicator. The interface looks *confident and contemporary*.
**Strongest at:** a distinct, modern feel with no loss of glance performance. Strongest opinion, strongest result if it lands.
**Cost:** deliberately withholds information some sessions want (what's coming next, how much of the block remains). Needs a clear, discoverable reveal — which is a design risk.

**Combining them is allowed and may be correct.** The two surfaces have genuinely different jobs:
the Watch is a readout used for two seconds, the phone is a companion used for the whole session.
A defensible answer is one direction on the Watch and another on the phone, sharing a common type scale and colour roles. Whichever is chosen, the *shared* vocabulary is what makes metric 3 pass.

## Open questions

These are not resolved here. Each names who should answer it.

**Resolved at sign-off (16 September 2026):**

1. ~~Which direction?~~ **Decided** — A on the Watch, B on the phone, sharing one vocabulary. See [Decision](#decision).
2. ~~How much should the Watch show about upcoming intervals?~~ **Decided** — the current interval plus what's next, shown subordinate.

**Still open — product questions, needed before `ui-design-spec`:**

3. Is the phone screen-on during a session, or pocketed? It changes whether the phone's mid-session screen is primarily *read* or primarily *glanced at between sets*.
4. Does haptic language (how transitions and the final countdown are announced by feel) fall inside this pass, or is it considered settled? **Metric 2 depends on it** — the "no-look transitions" target of zero phone pickups is unreachable if transitions are announced only visually. This one gates a success criterion, so it needs an answer rather than a default.

**For `spec-writer` to assess (feasibility — deliberately not guessed at here):**
5. Whether the accessibility requirements above (Dynamic Type, colour-independence) can be met on both platforms without compromising the chosen direction — and if they conflict, which wins.
6. Whether a distinctive accent colour is achievable on the Watch, and what that constrains.
7. Whether the bright-sunlight and dim-gym contrast targets can both be satisfied by one visual system, or need a mode.
8. App icon: in or out of scope for v1.
9. Anything the current design of the two apps makes structurally difficult to change — surfaced as a finding, not used to shrink the ask.

## Rough sizing

**Medium.** Larger than a bug-fix sweep, smaller than a feature build. Directionally comparable to the session runner itself (M5) — a focused pass over two surfaces plus a small shared vocabulary.

Sequenced as thin slices so each is independently verifiable:

1. Baseline measurement (metrics 1–3) and the direction decision.
2. The shared vocabulary — type scale, spacing, colour roles. Verified by metric 3 alone.
3. The Watch session screen. Verified by metrics 1, 2 and 4 — the hardest slice, done early.
4. The iPhone session runner. Verified by metrics 2 and 4.
5. The seconds-long screens, following the settled system.

Slices 3 and 4 are where the work either succeeds or does not; 1, 2 and 5 are cheap by comparison.

---

## Gate — passed

**Approved 16 September 2026.** The direction is settled and recorded above, so the gate is satisfied. This PRD is now a commitment to build roughly this: a design pass over the two mid-workout surfaces, with the web builder and all new functionality explicitly excluded.

Next in the pipeline: `spec-writer` assesses the feasibility questions (5–8) and produces the technical spec; `ui-design-spec` then defines every screen state, accessibility behaviour and the actual copy before any implementation. Questions 3 and 4 above are still open and should arrive at that step answered rather than assumed.
