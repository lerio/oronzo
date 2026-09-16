# Oronzo — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first.** It is the single source of truth for how this codebase
works: the stack, the flattening contract, the core patterns, the traps that have cost real time,
and the secrets rules for this public repository.

This file covers only the Claude Code harness in `.claude/`. Nothing about the codebase is
repeated here — if you find yourself wanting to add some, it belongs in `AGENTS.md` or one of the
`docs/` topic files it points to.

## What's in `.claude/`

| Path | What it does |
|---|---|
| `commands/check.md` | `/check` — the full verification suite: core tests, web build + lint, both app targets |
| `commands/migration.md` | `/migration` — scaffold the next Supabase migration, following the append-only rules |
| `commands/deploy.md` | `/deploy` — deploy the plan builder, *after* checking it is safe against the live schema |
| `commands/resign.md` | `/resign` — the weekly re-sign, for when the apps stop launching |
| `agents/contract-auditor.md` | Audits the mirrored domain model (Swift ↔ TypeScript ↔ SQL) for drift |
| `hooks/secret-scan.sh` | Blocks a `git commit`/`git push` that would publish a secret — **not active, see below** |
| `skills/` | The process skill pack (spec, plan, implement, review, friction log) |

Each command is a prompt, not a script — they encode ordering and traps, because those are what
actually get forgotten. `/deploy` in particular exists to make you answer *"has the schema changed
since the last deploy, and in which direction?"* before shipping.

## The things that are not wired up

**There is no `.claude/settings.json`**, so none of the permission rules are in force and the
secret-scan hook never runs. Writing it was blocked the first time — correctly, since it would
have meant Claude choosing its own permission grants. The block that activates it is written out
in full in `.claude/README.md`. See `docs/known-issues.md` §5.

Until it is registered, **the pre-push secret scan is manual**: scan the working tree for the four
known values listed in `AGENTS.md` and confirm none appear.

If you do change the hook, test it. A hook whose script path is wrong, or that exits non-zero-but-
not-2, is a **silent non-blocking failure** — the gate just stops existing. Exit 2 blocks; exit 1
does not. Note that `bash` on this machine is macOS's 3.2.57, so the script sticks to constructs
that work there.

## Working with the user

The user is experienced and reviews work line by line. Prefer showing the real output over
asserting success, and say plainly when something was not verified — especially anything requiring
a physical iPhone or Watch. `/check` ends with a note on exactly that limit; keep it honest.
