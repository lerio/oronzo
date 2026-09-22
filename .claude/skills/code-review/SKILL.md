---
name: code-review
description: Use to validate a PR against its spec using multiple narrow, focused review passes (spec-compliance, code quality, security, observability, accessibility) rather than one do-everything reviewer that stops early. Produces a merge recommendation, never an automatic merge decision. Use after implement.
---

# Code Review

**Label for Valerio: EM-drivable.** Interpreting review findings and deciding
what's actually a merge blocker is senior-engineer/EM judgment — it doesn't
require current hands-on fluency with the specific stack, just the ability
to read a finding and weigh its real severity.

## Purpose

Review a PR thoroughly by running several narrow, single-purpose review
lenses instead of one generalist reviewer. A do-everything reviewer has an
implicit stopping point — it might report 7 issues and stop even though 20+
exist across different categories. Several focused reviewers each exhaust
their own lane instead.

## When to use

- After every `implement` run, before merge.
- Pick the lenses relevant to the specific PR — not every PR needs every
  lens (a pure backend data-migration PR doesn't need an accessibility pass).

## Steps

1. **Read the spec and the actual diff** — not just the PR description. The
   description can be incomplete or simply wrong about what the diff
   actually does.

2. **Run each relevant lens as its own separate pass:**
   - **Spec-compliance:** does the diff do exactly what the spec said —
     nothing more, nothing less? Scope creep is a finding here, not a bonus.
   - **Code quality / maintainability:** readability, consistency with the
     repo's documented patterns (from `repo-onboarding`).
   - **Security:** authorization/permission checks, injection risks, secrets
     handling, anything touching user data.
   - **Observability:** logging and metrics sufficient for on-call to
     diagnose a failure in production, error states surfaced not swallowed.
   - **Accessibility** (UI-touching PRs only): does the implementation
     actually satisfy what `ui-design-spec` required — keyboard nav,
     screen-reader labels, contrast, focus order?

3. **Draft review comments first; get human confirmation before posting
   them.** Never auto-post review comments straight to the PR.

4. **Produce a merge recommendation, not a merge decision.** The actual merge
   remains a human call, always.

5. **Track findings over time as the real trust metric.** Per this project's
   tracker: the number of real issues per PR should trend toward zero as the
   harness improves. If it isn't trending down, that's a signal to fix the
   underlying documentation/spec process (via `friction-log`), not to review
   more leniently.

## What good looks like

A set of findings, each tagged to the lens that found it and each backed by
a specific line/behavior in the diff — not a vague "looks mostly fine" or an
unfocused wall of unprioritized comments.
