---
name: ticket-intake
description: Use as a readiness pass on an existing ticket or PRD before any spec work starts — surfaces missing context and decides whether the ticket is actually ready to move forward, without guessing at the gaps. Use before spec-writer.
---

# Ticket Intake

**Label for Valerio: EM-drivable** — also a good one to hand to whoever owns
the ticket day-to-day. The judgment required is scoping clarity, not
technical depth, so it doesn't demand current hands-on stack fluency.

## Purpose

A readiness gate, not a design session. Its only job is to answer: **is this
ticket actually ready for a spec to be written against it, or is something
missing?** Equivalent to the "grill-with-docs" step referenced elsewhere in
this project's tracker.

## When to use

- Before `spec-writer`, on any ticket that didn't just come out of
  `prd-writer` (a PRD that's already been through that discipline may not
  need a second full pass, but a quick check is still cheap insurance).
- Any time a ticket has sat around long enough that its original context may
  have gone stale.

## Steps

1. **Read the ticket and everything it links to** — don't work from the
   title alone.

2. **Name concrete gaps, not vague ones.** "Needs more detail" is not a
   useful output. "Doesn't say what happens if the user has zero existing
   records" is.

3. **Ask the missing questions to a human directly.** Never fabricate a
   plausible-sounding answer to fill a gap just to keep moving — an invented
   assumption here compounds into real rework at implementation time.

4. **Update the ticket** with whatever gets clarified, so the next reader
   (human or agent) doesn't have to re-ask the same question.

5. **Output an explicit verdict:** either "ready for spec" or "not yet ready,
   blocked on X" — don't leave it ambiguous.

## What good looks like

A ticket that a `spec-writer` run could pick up cold and make real technical
progress on, without immediately bouncing back with "wait, what did you mean
by...?" If intake keeps surfacing the same category of gap across many
tickets, that's a signal for a process fix (a ticket template change), not
just a one-off fix per ticket.
