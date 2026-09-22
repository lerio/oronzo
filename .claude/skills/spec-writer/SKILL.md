---
name: spec-writer
description: Use to turn an intake-passed ticket into a real technical spec — behavior, scope, non-goals, technical approach, risks, validation plan, and a stated confidence level. Generic across languages/frameworks; reads the repo's onboarding docs as source of truth rather than re-inferring architecture from scratch. Use before ui-design-spec (if UI-touching) and implementation-planner.
---

# Spec Writer

**Label for Valerio: Pair-with-IC.** Technical feasibility and "what does the
codebase actually look like today" both matter a lot here, and that's exactly
where current, hands-on familiarity beats general engineering judgment. You
should absolutely be in the room for the gate/approval — the drafting itself
is better done alongside someone currently in the code.

## Purpose

Convert a ready ticket into a spec detailed enough that an implementer (human
or agent) knows exactly what to build, an approver can actually evaluate the
approach without reading full code, and risk is named rather than discovered
later.

## When to use

- After `ticket-intake` (or a PRD that's already passed its own gate).
- Before `implementation-planner`. If the work is UI-touching, `ui-design-spec`
  runs alongside or immediately after this, before planning.

## Steps

1. **Read the repo's onboarding docs first** (from `repo-onboarding`) and
   treat them as source of truth. Don't let this skill re-scrape and
   re-infer the architecture from scratch — that's the exact waste
   onboarding exists to prevent.

2. **Draft the spec**, covering:
   - **Behavior:** what changes, precisely, including edge cases and error
     states — not just the happy path.
   - **Scope and non-goals:** what this explicitly does *not* cover, stated
     as clearly as what it does.
   - **Technical approach:** described at a level a human reviewer can
     actually evaluate without reading the full diff — the shape of the
     change, not a line-by-line plan.
   - **Risks:** named explicitly, with how each is mitigated or why it's
     accepted.
   - **Validation plan:** how correctness will actually be verified — tests,
     manual QA steps, metrics to watch post-release.

3. **State a confidence level and name the single biggest unknown.** Don't
   bury uncertainty in hedged language — say plainly "confidence: medium,
   because X is unverified."

4. **Treat this as a real gate.** A genuine unresolved gap (an unclarified
   dependency, an edge case with no defined behavior) should block approval,
   not get waved through because the ticket's been open a while.

5. **Human review and explicit approval required** before `implementation-planner`
   runs. Approving a spec is a commitment to build roughly this — treat it
   with the same weight as approving a PRD.

## Staying stack-agnostic

This skill should never assume a specific language, framework, or paradigm.
Wherever a stack-specific detail would help (a particular testing library, a
specific ORM pattern), that detail should already live in the repo's own
onboarding docs, which this skill reads — not hardcoded into the skill itself.

## What good looks like

A spec detailed enough that two different implementers would build
recognizably the same thing from it, and a reviewer could approve or reject
it without needing to see any code first.
