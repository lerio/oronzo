#!/usr/bin/env bash
#
# PreToolUse guard for Bash: refuses a `git commit` or `git push` that would publish one of
# this project's secrets.
#
# Oronzo's repository is public, and that was authorised on one condition — "as long as no
# sensitive data is pushed". The condition is standing rather than a one-time check, and a
# manual scan before each push is exactly the kind of habit that holds until the one time it
# doesn't. So the scan lives here instead.
#
# The values are read at run time from the gitignored files that already hold them, never
# hardcoded — a guard script that contains the secrets it guards would be its own leak.
# Nothing here ever prints a secret: findings name the file and which key matched, and mask
# the value.
#
# Contract: exit 0 allows the call; exit 2 blocks it and feeds stderr back to the model.

set -uo pipefail

payload=$(cat)
command=$(printf '%s' "$payload" | /usr/bin/python3 -c \
  'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    print("")' 2>/dev/null)

# Only git publishing verbs are interesting. Everything else passes straight through.
case "$command" in
  *"git commit"*|*"git push"*|*"git send-email"*) ;;
  *) exit 0 ;;
esac

root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
[ -n "${root:-}" ] || exit 0
cd "$root" || exit 0

# --- the author line ---------------------------------------------------------------------
# `git grep` cannot see this one. A personal address leaks just as effectively through commit
# authorship as through file content, and the project deliberately commits under a repo-local
# noreply identity for exactly that reason. If the effective identity has fallen back to the
# global personal one, every commit published from here carries it.
if [[ "$command" == *"git commit"* ]]; then
  global_email=$(git config --global user.email 2>/dev/null || true)
  effective_email=$(git config user.email 2>/dev/null || true)
  if [ -n "$global_email" ] && [ "$effective_email" = "$global_email" ] \
     && [[ "$global_email" != *noreply* ]]; then
    cat >&2 <<'EOF'
Blocked: this commit would be authored under your global personal email, and this repository
is public. The address itself is not repeated here on purpose.

Fix it for this repository (once):

    git config user.email "1845705+lerio@users.noreply.github.com"

That is the identity the project already uses. Run it, then retry the commit. Prefer this over
`git commit --author`, which would fix only the one commit and leave the next one leaking.
EOF
    exit 2
  fi
fi

# --- the secrets, from their real homes -------------------------------------------------
# Each entry is "where it lives<TAB>the value". Missing files are simply skipped: a fresh
# clone has none of them, and that is a valid state, not an error.
declare -a locations=()

add_from() { # file, key
  local file=$1 key=$2 value
  [ -f "$file" ] || return 0
  value=$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" | head -1 | tr -d '"'"'"' \r')
  [ -n "$value" ] && locations+=("${file} (${key})"$'\t'"${value}")
}

add_from "ios/Local.private.xcconfig"  "DEVELOPMENT_TEAM"
add_from "ios/Local.private.xcconfig"  "SUPABASE_PUBLISHABLE_KEY"
add_from "web/.env.local"              "VITE_SUPABASE_PUBLISHABLE_KEY"
add_from "ops/keepalive/.dev.vars"     "SUPABASE_PUBLISHABLE_KEY"

# Deliberately NOT scanned: SUPABASE_PROJECT_REF and VITE_SUPABASE_URL.
#
# Both are published on purpose. The ref appears in the JavaScript that every browser
# running the plan builder downloads, and it is committed by hand in
# ops/keepalive/wrangler.jsonc — so scanning for it would block every commit in this
# repository, which is the fastest way to get a guard switched off. The publishable key is
# public too (it ships in the same bundle), but it is kept out of the repo as policy, so it
# stays on the list above.

# The personal email is not in any file — it is the global git identity, which is precisely
# why it is easy to leak into a commit by accident.
email=$(git config --global user.email 2>/dev/null || true)
[ -n "$email" ] && locations+=("your global git identity"$'\t'"$email")

[ ${#locations[@]} -eq 0 ] && exit 0

# --- scan --------------------------------------------------------------------------------
# A commit is judged on the index (what is actually about to be recorded); a push on the
# committed tree. `git grep` only ever sees tracked content, so the gitignored files that
# hold the secrets cannot themselves trip the check.
#
# `scope` is a plain string rather than an array on purpose: an empty array expanded as
# "${a[@]}" is an unbound-variable error under `set -u` on older bash, which would have made
# the push path abort with a non-zero-but-not-2 exit — i.e. silently not a gate at all.
if [[ "$command" == *"git commit"* ]]; then
  scope="--cached"; scope_name="staged files"
else
  scope="HEAD";     scope_name="committed tree"
fi

hits=""
for entry in "${locations[@]}"; do
  where=${entry%%$'\t'*}
  value=${entry#*$'\t'}
  [ ${#value} -lt 6 ] && continue   # too short to grep for without false positives

  files=$(git grep -l -I -F -e "$value" "$scope" -- . 2>/dev/null | head -5)
  [ -n "$files" ] && hits+="  • ${where}"$'\n'"$(printf '%s\n' "$files" | sed 's/^/      /')"$'\n'
done

[ -z "$hits" ] && exit 0

cat >&2 <<EOF
Blocked: this repository is public and a secret is present in the ${scope_name} about to be
published.

${hits}
The values themselves are not shown here on purpose — check the named files or keys, and
compare against the sources in ios/Local.private.xcconfig, web/.env.local and
ops/keepalive/.dev.vars.

If the match is a false positive (a documented placeholder, or prose describing a key),
rephrase the text so it cannot be mistaken for a real value, then retry. Do not work around
this check.
EOF
exit 2
