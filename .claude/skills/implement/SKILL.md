---
name: implement
description: Use to execute exactly one sub-ticket from an approved implementation plan, in one PR, in one fresh session — never advancing to a second slice in the same session. Test-first by default. Deliberately language- and framework-agnostic; re-discovers current code paths rather than trusting plan-time assumptions about where things live. Use after implementation-planner, before code-review.
---

# Implement

**Label for Valerio: Pair-with-IC, strongly recommended.** This is the most
hands-on-coding-dependent skill in the pack. A background in engineering
means you can meaningfully review direction, catch an obviously wrong
approach, and ask sharp questions — but you shouldn't expect to solo-drive
production implementation without a currently-active IC alongside, given how
fast stack-specific detail moves.

## Purpose

The mechanical, structural version of "shrink scope from epic to ticket" —
removing the judgment call about scope entirely by making the boundary a hard
rule: one sub-ticket, one PR, one session.

## When to use

- After `implementation-planner` has produced an approved plan.
- Once per sub-ticket. Run again, fresh, for the next one.

## Steps

1. **Start a genuinely fresh session, scoped to exactly one sub-ticket.**
   Never carry context over from a previous slice's implementation session —
   mixed context from multiple slices is exactly how rules and assumptions
   from one slice bleed incorrectly into another.

2. **Re-discover the current, actual code paths relevant to this slice.**
   Don't trust a plan-time assumption about where a piece of logic lives —
   the codebase may have moved since the plan was written, even hours ago.

3. **Test-first by default.** Write the failing test(s) that define this
   slice's expected behavior before writing the implementation that satisfies
   them. This applies regardless of language or test framework — the
   discipline is stack-agnostic even though the syntax isn't.

4. **Implement the smallest change that makes the tests pass and matches the
   spec.** If something else clearly needs fixing along the way, don't fix it
   inline — log it via `friction-log` or raise a new ticket. Scope discipline
   here is the entire point of this skill.

5. **Stop once tests pass and the diff matches the spec's stated scope.**
   Do not continue on to a second slice in the same session, even if it
   feels efficient to keep going — that's precisely the pattern this skill
   exists to prevent.

6. **Never silently guess on ambiguity.** If something in the spec is
   genuinely unclear mid-implementation, either ask a human, or make an
   explicit, logged call via `friction-log` — an unlogged guess is invisible
   to whoever reviews the PR later.

7. **Output:** the PR itself, a short human-readable summary of what was done
   and why, and any `friction-log` entries generated along the way.

## Staying stack-agnostic

Nothing in this skill should reference a specific language, test framework,
or build tool by name. All of that detail should live in the target repo's
own onboarding documentation (from `repo-onboarding`), which this skill reads
before acting — that's what lets the same `implement` skill work whether the
repo is Kotlin, TypeScript, Swift, Go, or anything else.

## What good looks like

A PR small enough to review in one sitting, whose diff maps cleanly onto
exactly one sub-ticket from the plan — nothing more, nothing less.
