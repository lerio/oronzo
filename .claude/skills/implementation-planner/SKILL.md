---
name: implementation-planner
description: Use to turn an approved spec (and UI design spec, if applicable) into small, independently-verifiable, sequenced sub-tickets ("thin tracer bullets") with explicit dependencies. Generic across tech stacks. The whole plan must be approved by a human before any sub-ticket implementation starts. Use before implement.
---

# Implementation Planner

**Label for Valerio: Pair-with-IC.** Slicing work correctly requires real
fluency with the current codebase's actual dependency structure — where
things genuinely can be split versus where they can't. You can absolutely
review the resulting plan for sequencing logic and scope discipline without
having drafted it yourself.

## Purpose

Break an approved spec into the smallest slices that can each be
independently implemented, tested, and reviewed — the concrete mechanism
behind "shrink agent scope from epic to ticket," made structural rather than
a discipline someone has to remember to apply.

## When to use

- After `spec-writer` (and `ui-design-spec`, if the work is UI-touching) has
  been approved.
- Before any `implement` run. Never let implementation start against an
  unapproved plan.

## Steps

1. **Read the approved spec and the repo's onboarding docs.** The plan's
   slicing should respect the codebase's actual architecture, not an
   idealized one.

2. **Break the work into the smallest independently-shippable slices.**
   Resist bundling "while I'm in there" cleanup or adjacent improvements into
   the same slice — that's exactly the kind of scope creep that turns one
   review into an unreviewable one.

3. **Make dependencies explicit and sequential.** If slice 2 genuinely
   depends on slice 1 landing first, say so directly — don't leave it
   implicit and hope the sequencing is obvious.

4. **For each slice, name:**
   - The exact behavior it delivers
   - How it will be tested
   - What "done" looks like, concretely enough that a reviewer can check it

5. **Get the whole plan approved by a human, in conversation, before writing
   anything to a ticket system.** This is a real gate — the value here is
   catching a bad sequencing decision before code exists, not after.

6. **Never start slice 2's implementation while slice 1 is still
   unreviewed.** Errors compound across sequential specs — a small mistake
   in slice 1, undetected, gets expensive fast once slices 2 through N are
   built on top of it.

## Staying stack-agnostic

The slicing logic here (smallest independently-verifiable unit, explicit
dependencies, one slice per review cycle) applies regardless of language or
framework. Anything stack-specific (how a particular repo's build/test
pipeline actually works) belongs in that repo's onboarding docs, not in this
skill.

## What good looks like

A plan where slice 1 could be implemented, reviewed, and merged completely
independently of whether slices 2 through N ever happen — each slice stands
on its own as real, shippable progress.
