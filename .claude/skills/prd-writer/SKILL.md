---
name: prd-writer
description: Use to turn a raw idea into a Product Requirements Document — deliberately without any codebase or technical context, so the product shape isn't silently constrained by an agent's read of current code quality. Use before spec-writer, whenever the starting point is an idea rather than an already-scoped ticket.
---

# PRD Writer

**Label for Valerio: EM-drivable.** This is product and strategy framing —
exactly where senior engineering judgment matters more than current
hands-on coding fluency. This is the skill in this pack you should feel most
comfortable driving yourself, end to end.

## Purpose

Turn an idea into a real PRD through the same discipline a good PM would
apply, kept **deliberately separate from any technical/codebase context**.

Per Brian Tobler's cautionary example: giving an agent both product and code
context at the same time led it to quietly shrink a product proposal, because
it had scraped the codebase, judged it "not good enough" to support the full
idea, and adjusted the ask downward — without ever saying so out loud. The
fix is structural, not a reminder to "be careful": don't give this skill
codebase access at all.

## When to use

- The starting point is a raw idea, a customer ask, or a leadership directive
  — not yet an actual scoped ticket.
- Before `spec-writer`. Technical feasibility gets assessed there, on
  purpose, not here.

## Steps

1. **Gather only product-relevant material**: the original ask, target
   customer/segment, relevant prior discussion (Slack, Notion, Linear),
   related past PRDs, any known constraints that are genuinely business
   constraints (compliance, contractual commitments) — not technical ones.

2. **Explicitly withhold codebase access.** If the process tries to explore
   the target repo at this stage, stop it. Feasibility is a later gate.

3. **Interrogate the idea like a good PM would**, out loud, in the PRD:
   - Who is this actually for?
   - What does success look like, concretely — a number, not a feeling?
   - How will that be measured?
   - What's explicitly **out of scope** for a first version?
   - What's the smallest version that still delivers real value?

4. **Produce the PRD**, covering: problem statement, target users/segment,
   success metrics, scope and explicit non-goals, open questions, rough
   sizing (directional, not an estimate in hours).

5. **Flag feasibility questions rather than guessing at them.** Anything that
   sounds like "this might be hard to build" gets named as an open question
   for `spec-writer` to actually assess — never quietly resolved here by
   assumption.

6. **Gate: get explicit human (EM/PM) sign-off on the PRD** before anything
   moves to `spec-writer`. This is a real decision point — approving a PRD is
   committing to build roughly this, not a formality to clear before the
   "real" work starts.

## What good looks like

A PRD specific enough that a spec-writer could start immediately without
having to go back and re-ask "wait, who is this actually for?" — but with
zero mention of implementation approach, file names, or technical tradeoffs.
If technical language is creeping into the PRD, that's a sign context split
is leaking — pull it back out into an open question instead.
