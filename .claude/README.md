# `.claude/` — project configuration for Claude Code

Scaffolded on 2026-09-15. This directory holds the things Claude Code should know about *this
repository*, as opposed to the general knowledge in `../CLAUDE.md`.

## What's here

| Path | What it does |
|---|---|
| `hooks/secret-scan.sh` | Blocks a `git commit`/`git push` that would publish a secret. **Not yet active — see below.** |
| `commands/check.md` | `/check` — the full verification suite (core tests, web build + lint, both app targets) |
| `commands/migration.md` | `/migration` — scaffold the next Supabase migration, following the append-only rules |
| `commands/deploy.md` | `/deploy` — deploy the plan builder, *after* checking it's safe against the live schema |
| `commands/resign.md` | `/resign` — the weekly re-sign recipe, for when the apps stop launching |
| `agents/contract-auditor.md` | Audits the mirrored domain model (Swift ↔ TypeScript ↔ SQL) for drift |

Each command is a prompt, not a script — they encode the ordering and the traps, because those
are what actually get forgotten. `/deploy` in particular exists to make you answer "has the
schema changed since the last deploy, and in which direction?" before shipping.

## The one thing that isn't wired up: `settings.json`

Writing `.claude/settings.json` was blocked, correctly — it would have meant Claude choosing its
own permission grants, and "scaffold a folder" doesn't authorise that. **So nothing here is
active yet:** `/check` and friends work as soon as they exist, but the hook does not run until
it's registered.

To activate the hook and the permission rules, create `.claude/settings.json` with the contents
below. Review it first — particularly the `allow` list, which is what stops Claude being
interrupted for read-only commands.

```json
{
  "permissions": {
    "allow": [
      "Bash(cd *)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(git status *)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git show *)",
      "Bash(swift build *)",
      "Bash(swift test *)",
      "Bash(npm run build *)",
      "Bash(npm run lint *)",
      "Bash(npm run dev *)",
      "Bash(xcodegen generate *)",
      "Bash(xcodebuild *)",
      "Bash(xcrun simctl launch *)",
      "Bash(xcrun simctl install *)",
      "Bash(xcrun simctl boot *)",
      "Bash(xcrun simctl io *)",
      "Bash(plutil -lint *)"
    ],
    "ask": [
      "Bash(npm run deploy *)",
      "Bash(wrangler deploy *)",
      "Bash(git commit *)",
      "Bash(git push *)"
    ],
    "deny": [
      "Bash(xcrun simctl erase *)",
      "Bash(xcrun simctl delete *)",
      "Bash(git filter-repo *)",
      "Bash(git push --force *)",
      "Bash(rm -rf *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash",
            "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/secret-scan.sh"],
            "timeout": 30,
            "statusMessage": "Checking for secrets before publishing…"
          }
        ]
      }
    ]
  }
}
```

Design notes on that block, since two choices are deliberate:

- **Deploy, commit and push are in `ask`, not `allow`**, even though the hook guards the last
  two. Publishing should always cost one visible keystroke.
- **`deny` beats `allow` and specificity never overrides it**, so the `simctl erase`/`delete`
  and `push --force` rules are a real stop, not decoration. Note the caveat: these match the
  command *text* Claude writes, so they are a guard against mistakes, not a security boundary.
- **A rule must match each part of a compound command independently.** `Bash(cd *)` is in the
  list because almost every command here starts with `cd ios/... && …`.

`settings.local.json` — for personal, uncommitted overrides — is gitignored. Claude Code only
adds it to your *global* git excludes automatically, which is not enough for a public repo, so
the rule is in the project `.gitignore` as well.

## The secret-scan hook

Oronzo's repository is **public**, authorised on one condition: *"as long as no sensitive data is
pushed."* That is a standing condition, and a manual scan before every push is precisely the kind
of habit that holds right up until the one time it doesn't.

The hook fires on every `Bash` call but only acts on `git commit`, `git push` and
`git send-email`. It checks two things:

1. **File content.** It reads the actual secret values at run time from the gitignored files that
   already hold them — `ios/Local.private.xcconfig`, `web/.env.local`, `ops/keepalive/.dev.vars`
   — and greps the staged index (for a commit) or `HEAD` (for a push). Nothing is hardcoded: a
   guard script containing the secrets it guards would be its own leak. It never prints a value,
   only the file and key that matched.
2. **The commit author.** Content greps can't see the author line, which leaks an address just as
   effectively. If the effective `user.email` has fallen back to your global personal one, the
   commit is blocked with the one-line `git config` fix.

**Deliberately not scanned:** `SUPABASE_PROJECT_REF` and the Supabase URL. Both are published on
purpose — the ref ships in the JavaScript every browser downloads and is committed by hand in
`ops/keepalive/wrangler.jsonc`. Scanning for it would block every commit in the repository, which
is the fastest possible way to get a guard switched off.

### If you change the hook, test it

A hook whose script path is wrong, or that exits non-zero-but-not-2, is a **silent
non-blocking failure** — the gate just stops existing, with no error. Exit 2 blocks; exit 1 does
not. Test changes against a scratch repo rather than trusting them:

```bash
T=/tmp/hooktest; rm -rf $T; mkdir -p $T/ios; cd $T && git init -q
printf 'DEVELOPMENT_TEAM = FAKETEAM99\n' > ios/Local.private.xcconfig
git config user.email "1845705+lerio@users.noreply.github.com"
git add -A && echo 'x' > clean.txt && git add clean.txt
printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | CLAUDE_PROJECT_DIR=$T bash /path/to/secret-scan.sh; echo "exit=$? (expect 0)"
printf 'FAKETEAM99\n' > leak.txt && git add leak.txt
printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | CLAUDE_PROJECT_DIR=$T bash /path/to/secret-scan.sh; echo "exit=$? (expect 2)"
```

Note that `bash` on this machine is macOS's **3.2.57**, so the script sticks to constructs that
work there — an empty array expanded as `"${a[@]}"` is an unbound-variable error under `set -u`
on that version, which would have disabled the push path silently.
