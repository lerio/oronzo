# Friction log

Gaps and ambiguities hit while running the skills in `.claude/skills/`, recorded at the moment
they were hit. Each entry says **what the gap was**, **what was chosen**, **why**, and **what
would resolve it for next time**.

This is not a session summary. An entry only exists where there was genuine uncertainty — a
missing input, two sources of guidance in conflict, or an edge case the instructions never
addressed. Confident, undisputed reasoning does not belong here.

**Reviewing it:** read for *repeats*. The same category of gap twice means the harness has a real
hole, not that one agent made one odd call. Fix the source — an onboarding doc, a spec template, a
rule — and note the resolution in the entry so it is not re-litigated blind.

---

## 2026-09-16 — `repo-onboarding` assumes a repo with no existing harness docs

**Run against:** `oronzo-app`, first onboarding pass.

**The gap.** The skill prescribes creating `AGENTS.md` as the index plus topic docs including
`architecture-decisions.md`, and says to point `CLAUDE.md` at `AGENTS.md` — but it is written as
though the repository starts empty. Oronzo already had:

- a curated, hand-written `CLAUDE.md` (114 lines: layout, commands, the flatten contract, the
  traps that had cost real time, and the public-repo secrets rules);
- `docs/decisions.md`, which **is** the architecture-decisions doc — ADRs, with the forced
  constraints marked as such;
- `docs/runbook.md`, which **is** the ops doc.

Followed literally, the skill produces two failure modes it elsewhere names as the thing to
avoid: an `architecture-decisions.md` duplicating `docs/decisions.md`, and `CLAUDE.md` drifting
from `AGENTS.md` once both hold the same facts.

**What was chosen.** Treated the existing docs as the skeleton. `AGENTS.md` became the owner of
the index content; `CLAUDE.md` shrank to a pointer plus only what is Claude-Code-specific (the
slash commands, the agent, the hook, the skill pack). No `architecture-decisions.md` was created —
`docs/decisions.md` already was it, and is now linked from the reading list instead. Only the
genuinely absent docs were written: `patterns.md`, `integration-contracts.md`,
`testing-strategy.md`, `known-issues.md`.

The structural choice was put to the human rather than assumed, because it rewrites a file they
had hand-crafted. They chose "AGENTS.md owns it; CLAUDE.md slims".

**Why.** Duplication is the failure the skill itself warns about, and a second ADR file would
split the "why" across two homes that then drift. Preserving the *substance* of the existing
traps mattered more than preserving their file.

**What would resolve it.** The skill should open with: *check for an existing harness
(`AGENTS.md`, `CLAUDE.md`, `docs/`) and treat it as the skeleton — reuse an existing ADR or
runbook doc rather than creating a parallel one, and never restate a fact in two entry points.*
A one-line inventory step before the scrape would do it.

---

## 2026-09-16 — "Needs human confirmation" has no durable home

**The gap.** The skill says to flag inferred intent in a *"Needs human confirmation" section in
the PR description*. A PR description is ephemeral: it is not read by the next agent, and it
scrolls away once merged. But the material it carries — code that looks unintended, comments that
contradict the code — is exactly what the skill's own review checklist says must not be silently
dropped, because *"the next agent will scrape the same mistaken code and infer the same wrong
pattern again."*

So the instruction is in tension with itself: flag it somewhere durable, but the named place is
not durable.

**What was chosen.** Both. The PR description carries the confirmation list as instructed, *and*
`docs/known-issues.md` holds each item permanently with the question that settles it — referenced
from `AGENTS.md`, and explicitly marked as unconfirmed.

**Why.** The review checklist is the more important instruction; the PR description alone would
have recreated the gap it warns about. Writing them down also made it easy to separate what was
*verified* (the probe of the `anon` role, the unreachable error branch, the dead watch control)
from what was *inferred* (whether each was intended).

**What would resolve it.** The skill should say the confirmation list lives in a repo doc
(`known-issues.md` or similar) and that the PR description summarises it — not that the PR
description *is* the record.

---

## 2026-09-16 — neither skill says where the friction log itself is written

**The gap.** `friction-log` is defined as a cross-cutting practice that "every other skill in this
pack should log to", and `repo-onboarding` closes by saying to revisit onboarding "whenever
`friction-log` entries repeatedly point at the same undocumented gap". Neither file says **where
those entries go**, and no log existed in the repository.

**What was chosen.** Created this file at `docs/friction-log.md`, alongside the other durable
repo docs, and linked it from the onboarding reading list so an agent can find reviewed decisions
rather than re-litigating them.

**Why.** `docs/` is where this repository keeps durable documents; the alternative (`.claude/`)
holds harness *configuration*, and that directory was mid-restructure, so adding to it risked
colliding with work in flight.

**What would resolve it.** `friction-log/SKILL.md` should name the path explicitly, the way the
other skills name their outputs.

---

## 2026-09-16 — `prd-writer`'s "withhold codebase access" is unenforceable in this harness

**Run against:** `oronzo-app`, PRD 0001 (UI/UX polish, iPhone + Watch).

**The gap.** `prd-writer` makes a structural argument: don't give the PRD step codebase access,
because an agent that has read the code will judge it inadequate and quietly shrink the product
ask — and the fix is *structural, not a reminder to "be careful"*.

That works when the PRD step is a separate agent run over a clean context. It does not work here.
The skill is invoked as a slash command inside a general-purpose coding agent that already has the
repository loaded, and in this instance the same session had just read most of the codebase to
write the onboarding docs. There is no mechanism that removes that context, and "explicitly
withhold" is addressed to *the agent doing the reading* — which is the party that already read it.

So the skill's central safeguard degraded into exactly the thing it warns against: a reminder to
be careful.

**What was chosen.** Honoured the *intent* by separating the outputs rather than the context. The
PRD was written as pure product framing — no file names, no technical tradeoffs, no mention of
what the current code does or does not make easy — and every technical observation was pushed into
the "for `spec-writer` to assess" section as an open question instead of being used to bound the
design. Specifically, things noticed during onboarding that would have quietly capped the ask
(no accent-colour asset on the Watch, the free-tier background-mode ceiling) were *not* allowed to
shape the proposed directions; they appear only as feasibility questions.

Confidence that this worked: **moderate, not high.** Nothing verified it. A reader cannot tell
from the PRD whether the ask would have been larger had the context been clean — which is the
whole point of the original safeguard.

**What would resolve it.** The skill needs a mechanism, not an instruction, for a harness where
the agent has repo access. Realistic options: run `prd-writer` as a *subagent with no repository
context* (a fork with a scrubbed prompt would not do it — the context travels), or have it emit
the PRD to a file and require a separate, fresh session to review it against the code. The skill
should also say plainly that in a coding-agent harness the safeguard is best-effort, so the
reviewer knows to check for shrinkage rather than assuming the discipline held.


---

## 2026-09-16 — `implement` has no path for a slice whose verification is not automatable

**Run against:** `oronzo-app`, slice S1 (Live Activity feasibility spike).

**The gap.** `implement` says "test-first by default" and treats tests-passing as the signal that a
slice is complete. It has no guidance for a slice whose entire purpose is an *answer that only a
physical device can give*.

S1 is exactly that. Its artifact is a widget extension target and some throwaway view code, but its
**done-condition is "does a Live Activity provision on a free personal team?"** — and that cannot be
answered in a simulator, because provisioning is the thing under test. So the honest end state is:
the code is complete, the build is green, `swift test` passes, and **the slice is not done**.

The skill's step 6 covers "never silently guess on ambiguity" and step 7 covers logging, but there is
no stated expectation for *how far an agent should go* when verification is out of its reach — and no
warning that "tests pass" can be a misleading completion signal in that situation.

**What was chosen.** Implemented the slice fully, verified everything reachable (both schemes build;
the built bundle inspected rather than the YAML trusted — the extension at `PlugIns/…appex` with the
right extension point and `NSSupportsLiveActivities` in both plists), and then **stated plainly in
the commit message and the PR title-adjacent body that S1 is not done**, with the exact device steps
handed over. Deliberately did not shade "it builds" into "it works".

**Why it matters beyond this slice.** Four of the seven slices in this plan have device-only
verification (S3, S4, S6, S7 — S6 literally cannot be checked anywhere but a wrist). If the pattern
is "agent reports success when the build is green", this plan produces four false completions in a
row, and the failures would surface as *silent* — a Live Activity that never appears looks exactly
like one that was never started, which is the same failure shape
`docs/integration-contracts.md` already warns about for WatchConnectivity.

**What would resolve it.** `implement` should distinguish *implemented* from *verified*, and say that
when verification needs a device it must (a) never be implied as done, (b) hand over exact
reproduction steps, and (c) name what the *negative* answer would mean for the plan — so a "no" is
recognised as a result rather than reported as a failure. The plan already writes done-conditions
this way ("either (a) … or (b) it is not, and the failing step is named"); `implement` should match it.
