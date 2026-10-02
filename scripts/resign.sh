#!/bin/bash
#
# resign.sh — force fresh 7-day provisioning profiles onto both devices.
#
# For the day-to-day loop (changed some code, want it on the devices) use
# scripts/install.sh instead. This one is for when the 7-day clock runs out.
#
# Why "force" is a separate thing from "rebuild":
#
#   On a free personal team every app stops launching 7 days after it was signed.
#   Rebuilding does NOT reset that clock, because Xcode reuses a provisioning
#   profile while it is still valid — so the build re-embeds the same profile and
#   the expiry does not move. Measured on 2 Oct 2026: a rebuild at 08:49 embedded
#   the profile from 25 Sep, which still expired that same evening.
#
#   So this deletes the Oronzo profiles first. With nothing valid to reuse, the
#   build has to mint new ones and the seven days start again.
#
# Why it installs BOTH apps, phone first:
#
#   The iPhone app embeds the Watch app, but only replaces the one already on
#   the wrist when the Watch is connected at that moment. When it is not, you
#   get a freshly signed phone app beside an old Watch app — which is what the
#   phone reports as "No Watch app". Reinstalling the Watch app is what repairs
#   it, so the Watch step is not optional even when the phone step looks fine.
#
# Usage:
#   scripts/resign.sh                 full resign, then verify
#   scripts/resign.sh --verify-only   check the link without touching anything
#
# The device UDIDs are discovered at runtime, never hardcoded — this repo is
# public. Override with PHONE_UDID=... / WATCH_UDID=... if discovery picks wrong.

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
    cat <<'EOF'
Usage: scripts/resign.sh [--verify-only]

  (no arguments)   Back up and delete the Oronzo profiles, rebuild and reinstall
                   both apps so they carry fresh 7-day profiles, then verify.
  --verify-only    Touch nothing. Only check whether the phone can see the
                   Watch app. ~5 seconds; use this before assuming it is broken.

Exit codes:
  0   PASS          watchAppInstalled=true — the pairing is registered
  1   INCONCLUSIVE  could not determine — the app would not launch, or said nothing
  2   BROKEN        the Watch app is not registered to this phone app
  64  usage error
EOF
}

VERIFY_ONLY=0

case "${1:-}" in
    --verify-only) VERIFY_ONLY=1 ;;
    -h|--help)     usage; exit "$EXIT_PASS" ;;
    "")            ;;
    *)             echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit "$EXIT_USAGE" ;;
esac

if ! resolve_devices 1; then
    exit "$EXIT_INCONCLUSIVE"
fi

# Scoped to the resign path: a `connected` device is only needed to *install*,
# and --verify-only reads the activation line quite happily without one.
if [ "$VERIFY_ONLY" -eq 0 ]; then
    warn_if_not_connected
fi

# ---------------------------------------------------------------------------
# Resign — the half install.sh deliberately does not do
# ---------------------------------------------------------------------------

profile_field() {  # $1 = file, $2 = plist key
    security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw - 2>/dev/null || true
}

resign() {
    echo
    echo "==> Backing up all provisioning profiles"
    BACKUP="$PROFILE_DIR.backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp "$PROFILE_DIR"/*.mobileprovision "$BACKUP"/ 2>/dev/null || true
    echo "    $BACKUP"
    echo "    (restore with: cp \"$BACKUP\"/*.mobileprovision \"$PROFILE_DIR\"/)"

    echo
    echo "==> Removing the Oronzo profiles, so the build must mint new ones"
    local removed=0 f name expiry
    for f in "$PROFILE_DIR"/*.mobileprovision; do
        [ -e "$f" ] || continue
        name="$(profile_field "$f" Name)"
        case "$name" in
            *com.lerio.oronzo*)
                expiry="$(profile_field "$f" ExpirationDate)"
                echo "    $name"
                echo "        was expiring $expiry"
                rm -f "$f"
                removed=$((removed + 1))
                ;;
        esac
    done

    if [ "$removed" -eq 0 ]; then
        echo "    (none found — they may already have been reclaimed by Xcode)"
    fi

    build_install_phone
    build_install_watch

    echo
    echo "==> New profiles"
    local f2
    for f2 in "$PROFILE_DIR"/*.mobileprovision; do
        [ -e "$f2" ] || continue
        name="$(profile_field "$f2" Name)"
        case "$name" in
            *com.lerio.oronzo*) echo "    $name  expires $(profile_field "$f2" ExpirationDate)" ;;
        esac
    done
}

if [ "$VERIFY_ONLY" -eq 0 ]; then
    resign
fi

set +e
verify
STATUS=$?
set -e
exit "$STATUS"
