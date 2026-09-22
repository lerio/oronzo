---
name: friction-log
description: A cross-cutting practice, not a standalone task — every other skill in this pack should log to this whenever it hits genuine ambiguity or a gap in its instructions, recording what it chose and why. This is the actual diagnostic tool for improving the harness over time, distinct from a normal session summary that only narrates confident reasoning. Review the accumulated log periodically to find recurring gaps.
---

# Friction Log

**Label for Valerio: Cross-cutting practice.** This isn't a skill you "run" —
it's a discipline every other skill in this pack should follow. Your role is
periodic review of the accumulated log to spot patterns, which is exactly the
kind of pattern-recognition/root-cause work senior engineering experience is
good for, regardless of current stack fluency.

## Purpose

Make the invisible visible. When an agent hits a genuine ambiguity mid-task —
missing information, conflicting instructions, an edge case the spec never
addressed — and has to make a judgment call, that call is normally invisible
to whoever reviews the output later. You only see the (possibly wrong)
result, never that it was a coin-flip. The friction log fixes that by making
every such moment a written, reviewable entry.

This is explicitly **different from a session summary**, which just narrates
confident, undisputed reasoning ("I did X because the spec said so"). A
friction log entry only exists for genuine uncertainty.

## When an entry gets written

Any of the other skills in this pack — `spec-writer`, `implement`,
`code-review`, etc. — should write an entry whenever it:

- Finds information missing that it needs to proceed
- Finds two sources of guidance (e.g. a spec and a repo pattern) that
  conflict
- Faces an edge case the spec/plan didn't address
- Has to choose between two reasonable approaches with no clear tie-breaker

## What an entry contains

- **What the gap was** — stated precisely, not "something was unclear"
- **What was chosen** — the actual decision made
- **Why** — the reasoning behind that specific choice
- **What would resolve it for next time** — a specific doc to update, a
  specific rule to add, a specific question to ask a human

## Steps for reviewing the log (Valerio's part)

1. **Periodically** (aligned with a cycle or sprint boundary is reasonable to
   start), read through accumulated entries across recent PRs.

2. **Look for repeats.** The same category of gap showing up more than once
   is the actual signal — it means the harness (onboarding docs, spec
   template, a rule file) has a real hole, not that one agent made one odd
   call.

3. **Fix the root cause, not the symptom.** When a repeated gap is found,
   update the relevant `repo-onboarding` doc, spec template, or rule —
   whatever will keep the same ambiguity from recurring — rather than just
   noting "watch out for this" informally.

4. **Close the loop in the log itself.** Once a gap has been fixed at the
   source, note the resolution in the log so the same question doesn't get
   re-litigated blind the next time someone reads old entries.

## Why this matters (per the tracker's trust-building framework)

The actual metric for whether the AI-native process is working is a
declining number of real issues per PR over time. A friction log is the only
way to know *why* an issue happened in the first place — without it, fixing
one bad PR teaches the system nothing, and the same mistake resurfaces next
time under a different name.
