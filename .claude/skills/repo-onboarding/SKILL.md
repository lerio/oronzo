---
name: repo-onboarding
description: Use once per repository (and re-run after major architectural change) to scrape the existing codebase and produce the harness documentation — architecture decisions, patterns, integration contracts, testing strategy — that every future agent run in this repo will read before doing any work. This is the single highest-leverage step in the whole AI-native process: skip it and every agent re-infers your architecture from scratch every single run, burning tokens and producing inconsistent results.
---

# Repo Onboarding

**Label for Valerio: EM-drivable (review/approval).** You don't need to write
this documentation by hand, but you should personally review the resulting PR
line by line before it merges — it will shape how every future agent behaves
in this repo, for better or worse. This is architecture-review work, which
transfers directly from IC experience even if it isn't recent.

## Purpose

Generate a durable, external memory of "how this codebase actually works" so
agents stop scraping and re-inferring it on every single run. Per Brian
Tobler's framing: the code itself is not a reliable source of truth for an
agent to read cold — it may encode mistakes, dead patterns, or undocumented
tribal knowledge. This skill turns tribal knowledge into reviewable, durable
documentation.

## When to use

- The first time any of the other skills in this pack are used against a
  repository.
- After a significant architectural shift (a new service split off, a major
  framework upgrade, a new cross-cutting pattern like an auth model change).
- Never as a "set once, forget forever" step — treat staleness here the same
  way you'd treat a stale runbook.

## Steps

1. **Scope it.** For a normal-sized repo, onboard the whole thing. For a very
   large monorepo, scope to the module/service actually being worked on and
   note explicitly what was excluded.

2. **Scrape for existing conventions**, generic across any language/framework:
   - Language, framework, and major dependencies
   - Folder/module structure and what lives where
   - Naming conventions (files, functions, types)
   - Error-handling pattern (how failures propagate and get surfaced)
   - Data-access pattern (how the codebase talks to its datastore(s))
   - Auth/permission pattern (how access checks are structured)
   - Integration pattern (how this service talks to others — sync calls,
     events, shared contracts)
   - Testing pattern (unit vs. integration split, what's mocked vs. real,
     naming/location conventions for tests)

3. **Produce the artifacts**, not as one giant file:
   - A lean **index file** (`AGENTS.md`, with `CLAUDE.md` pointing to it if
     your tooling needs both — never duplicate content across the two, one
     drifting out of sync with the other is a real, hard-to-detect failure
     mode) stating, **in this order**: language/stack, then core patterns,
     then narrower rules. Order matters — agents weight earlier information
     more heavily.
   - Topic docs it points to: `architecture-decisions.md` (ADRs), `patterns.md`,
     `integration-contracts.md`, `testing-strategy.md`. Split further only if
     a single doc is getting unwieldy.

4. **Flag uncertainty explicitly.** Where the agent had to infer intent rather
   than found it stated outright, say so in a "Needs human confirmation"
   section in the PR description — never assert an inference as settled fact.

5. **Open a single PR** titled `AI harness onboarding: <repo>`, small enough
   to actually review, not a drive-by mega-commit.

## Review checklist (the part that actually needs a human)

For every generated ADR or pattern in the PR, ask: **"Is this our actual
intended pattern, or just what happens to be in the code right now —
possibly by mistake?"**

- If it's a real, intended pattern → approve it as documented.
- If it's actually a mistake in the current code → don't just delete the
  generated doc. Either (a) fix the underlying code, or (b) explicitly
  document a "don't do this, do X instead" rule. **Silent deletion recreates
  the gap** — the next agent will scrape the same mistaken code and infer the
  same wrong pattern again.

## What good looks like

A small, lean index plus a handful of focused topic docs — not a 5,000-word
`AGENTS.md`. If you find yourself writing an exhaustive ADR for something that
hasn't caused a real problem yet, stop — add documentation reactively, when a
gap actually bites, not speculatively (YAGNI applies here as much as anywhere
else).

## Common failure mode

Treating onboarding as done forever after the first PR. Revisit whenever the
architecture moves meaningfully, and whenever `friction-log` entries
repeatedly point at the same undocumented gap.
