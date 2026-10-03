#!/bin/bash
#
# install.sh — the day-to-day loop: build the phone app, put it on the device, and
# put the Watch app it embeds onto the wrist.
#
# There is ONE source of Watch app installs: the copy embedded in the phone app
# (Oronzo.app/Watch/OronzoWatch.app). A standalone OronzoWatch build is never sent
# to a device — it is different bytes, and two copies that differ is what the
# phone's periodic "Reunion" sync trips over; the failed over-the-air update it
# then attempts drops the Watch companion registration (see docs/decisions.md,
# "The third occurrence, and the cause").
#
# This is deliberately NOT resign.sh. It never touches provisioning profiles,
# because a normal code change does not need the 7-day clock resetting — Xcode
# reuses the valid profile and that is the correct behaviour. Profiles only need
# resetting when the apps stop launching, which is resign.sh's job.
#
# Which side to install — note the Watch app rides inside the phone app, so
# editing it rebuilds the phone:
#
#     ios/Oronzo/       ->  phone
#     ios/OronzoWatch/  ->  phone (the Watch app is built inside it)
#     ios/OronzoCore/   ->  phone (both targets link that package)
#     web/              ->  neither (deployed separately)
#
# Usage:
#   scripts/install.sh phone            build + install the iPhone app, then push its
#                                       embedded Watch app to the wrist
#   scripts/install.sh watch            push the embedded Watch app — the REPAIR for a
#                                       dropped registration; builds nothing
#   scripts/install.sh both             phone, but a failed Watch push is an error
#   scripts/install.sh hash             print the embedded Watch app's executable sha256
#   scripts/install.sh phone --no-verify
#
# Options:
#   --no-verify   skip the link check, which relaunches the phone app
#   -h, --help    this text

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
    cat <<'EOF'
Usage: scripts/install.sh <phone|watch|both|hash> [--no-verify]

  phone          build + install the iPhone app, then push the Watch app embedded in it
  watch          push the Watch app embedded in the newest iPhone build (the repair;
                 builds nothing — run `phone` after changing ios/OronzoWatch/)
  both           phone, but a Watch push that fails is an error
  hash           print the embedded Watch app's executable sha256 and exit

Options:
  --no-verify    skip the link check, which relaunches the phone app
  -h, --help     this text

There is one source of Watch app installs: the copy embedded in the phone app.
A standalone OronzoWatch build is never sent to a device — different bytes, and
the phone's sync trips over exactly that difference.

Unlike scripts/resign.sh, this never deletes provisioning profiles — a normal
code change does not need the 7-day clock resetting.

Exit codes: 0 PASS · 1 INCONCLUSIVE · 2 BROKEN · 64 usage error
EOF
}

TARGET=""
DO_VERIFY=1

for arg in "$@"; do
    case "$arg" in
        phone|watch|both|hash) TARGET="$arg" ;;
        --no-verify)           DO_VERIFY=0 ;;
        -h|--help)             usage; exit "$EXIT_PASS" ;;
        *)                     echo "Unknown argument: $arg" >&2; echo >&2; usage >&2; exit "$EXIT_USAGE" ;;
    esac
done

if [ -z "$TARGET" ]; then
    usage >&2
    exit "$EXIT_USAGE"
fi

# `hash` travels no further: it needs no devices and no build.
if [ "$TARGET" = "hash" ]; then
    app="$(embedded_watch_app)"
    if [ -z "$app" ]; then
        echo "No embedded Watch app found in ~/Library/Developer/Xcode/DerivedData."
        echo "Run scripts/install.sh phone first — the Watch app is built inside the iPhone app."
        exit "$EXIT_INCONCLUSIVE"
    fi
    echo "$(embedded_watch_hash)  $app/$WATCH_EXECUTABLE_NAME"
    exit "$EXIT_PASS"
fi

# A Watch is needed to push to one, and to verify the link — the check reads the
# phone's own WCSession, which reports on the Watch. `phone` proceeds without
# either: the install must not be blocked by a Watch that is out of reach; the
# push warns instead.
NEED_WATCH=1
if [ "$TARGET" = "phone" ]; then
    NEED_WATCH=0
fi

if ! resolve_devices "$NEED_WATCH"; then
    exit "$EXIT_INCONCLUSIVE"
fi

warn_if_not_connected

case "$TARGET" in
    phone)
        build_install_phone
        if ! install_embedded_watch; then
            echo
            echo "    WARNING: THE IPHONE IS INSTALLED, BUT ITS WATCH APP DID NOT"
            echo "    REACH THE WRIST. The two copies now differ — the state the"
            echo "    phone's periodic sync tries to fix over the air, which a"
            echo "    free-profile app cannot pass; the failed attempt drops the"
            echo "    Watch registration (error 7006) until the Watch app is"
            echo "    replaced. With the Watch reachable, run:"
            echo
            echo "        scripts/install.sh watch"
        fi
        ;;
    watch) install_embedded_watch ;;
    both)
        build_install_phone
        install_embedded_watch
        ;;
esac

if [ "$DO_VERIFY" -eq 0 ]; then
    echo
    echo "==> Skipped the link check (--no-verify)."
    echo "    Check any time with:  scripts/resign.sh --verify-only"
    exit "$EXIT_PASS"
fi

set +e
verify
STATUS=$?
set -e
exit "$STATUS"
