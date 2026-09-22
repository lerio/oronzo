---
name: ui-design-spec
description: Use whenever a spec includes user-facing UI, before implementation starts, to define every screen state, accessibility requirements, responsive behavior, and actual copy — generic across web, mobile, and native frameworks. Defines behavior and requirements, not final pixel-level visuals. Use after spec-writer and before implementation-planner.
---

# UI Design Spec

**Label for Valerio: EM-drivable at the direction/requirements level,
pair-with-designer-or-IC for concrete visual execution.** Defining what states
and requirements a UI must satisfy is product/quality judgment a Senior EM
can drive directly. Producing the actual pixel-level visuals is a design
skill this document deliberately doesn't try to replace.

## Purpose

Make UI/UX requirements an explicit, reviewable gate — not a subsection
buried inside a technical spec, and not something silently improvised during
implementation. This exists because visual/UX requirements (empty states,
accessibility, responsive behavior, real copy) are routinely the first thing
skipped under time pressure; naming it as its own step is the fix.

## When to use

- Any time `spec-writer`'s output includes a user-facing surface — web,
  mobile, native, or otherwise.
- Skip entirely for backend-only, API-only, or infra-only work.

## Steps

1. **Enumerate every state the feature can be in**, not just the primary
   happy path:
   - Empty state (no data yet)
   - Loading state
   - Success state
   - Error state(s) — and which errors are user-actionable vs. not
   - Permission-denied / not-entitled state, if relevant
   - Edge-case content: unusually long text, zero items, the maximum
     realistic number of items

2. **Check the existing design system / component library first.** Default
   to reusing existing patterns. If something genuinely new is required,
   name it explicitly as new — don't quietly invent a one-off component when
   an existing one would do, and don't force-fit an existing one where it
   genuinely doesn't apply either.

3. **Accessibility is a non-negotiable minimum, not a nice-to-have:**
   - Full keyboard navigability
   - Screen-reader labels for interactive elements and meaningful images
   - Color contrast meeting at least the team's baseline standard
   - Sensible, logical focus order

4. **Responsive/adaptive behavior**, described for more than just the
   primary breakpoint — what happens at narrow widths or small screens,
   not just "it should be responsive."

5. **Write the actual user-facing copy as part of this spec** — every
   button label, error message, and empty-state message. Don't leave
   copy as a `TODO` for implementation time; that's exactly when it gets
   skipped or improvised badly.

6. **Produce a lightweight artifact**: an annotated description of each
   state (even plain text/markdown is fine), or a reference link if an
   actual design tool (e.g. Figma) is already in use. This skill does not
   require a dedicated design tool to be useful.

7. **Explicitly out of scope for this skill:** pixel-perfect visual design,
   final spacing/typography polish, brand-level visual decisions — those
   belong to a human designer where one is available. This skill defines
   *behavior and requirements*, not final visuals.

8. **Gate:** sign-off from whoever owns visual design for the team (a
   designer if one is resourced, otherwise the EM/PM) before
   `implementation-planner` runs.

## Staying framework-agnostic

Nothing here should assume React, a specific mobile framework, or any
particular component library by name — the states, accessibility minimums,
and responsive requirements apply identically whether the surface is a web
app, a native mobile screen, or something else entirely. Framework-specific
implementation detail belongs in the repo's own onboarding docs, consumed
later by `implementation-planner` and `implement`.

## What good looks like

An implementer could build every state listed here without needing to invent
a single piece of missing UX behavior or copy on the spot.
