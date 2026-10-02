#!/bin/bash
#
# install.sh — the day-to-day loop: build and install the side(s) you changed.
#
# This is deliberately NOT resign.sh. It never touches provisioning profiles,
# because a normal code change does not need the 7-day clock resetting — Xcode
# reuses the valid profile and that is the correct behaviour. Profiles only need
# resetting when the apps stop launching, which is resign.sh's job.
#
# Which side to install:
#
#   Not always "both", but it IS both whenever you touch ios/OronzoCore/ —
#   both targets link that package (ios/project.yml), so installing one side
#   leaves the other running different code. The wire check will flag that as
#   "Your Watch app is out of date", but by then you have lost the time.
#
#     ios/Oronzo/       ->  phone
#     ios/OronzoWatch/  ->  watch
#     ios/OronzoCore/   ->  both
#     web/              ->  neither (deployed separately)
#
# Usage:
#   scripts/install.sh phone            build + install the iPhone app
#   scripts/install.sh watch            build + install the Watch app
#   scripts/install.sh both             both, phone first
#   scripts/install.sh phone --no-verify
#
# Options:
#   --no-verify   skip the link check, which relaunches the phone app
#   -h, --help    this text

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
    cat <<'EOF'
Usage: scripts/install.sh <phone|watch|both> [--no-verify]

  phone          build + install the iPhone app
  watch          build + install the Watch app
  both           both, phone first (needed after ios/OronzoCore/ changes)

Options:
  --no-verify    skip the link check, which relaunches the phone app
  -h, --help     this text

Unlike scripts/resign.sh, this never deletes provisioning profiles — a normal
code change does not need the 7-day clock resetting.

Exit codes: 0 PASS · 1 INCONCLUSIVE · 2 BROKEN · 64 usage error
EOF
}

TARGET=""
DO_VERIFY=1

for arg in "$@"; do
    case "$arg" in
        phone|watch|both) TARGET="$arg" ;;
        --no-verify)      DO_VERIFY=0 ;;
        -h|--help)        usage; exit "$EXIT_PASS" ;;
        *)                echo "Unknown argument: $arg" >&2; echo >&2; usage >&2; exit "$EXIT_USAGE" ;;
    esac
done

if [ -z "$TARGET" ]; then
    usage >&2
    exit "$EXIT_USAGE"
fi

# A Watch is needed to build for one, and to verify the link either way —
# the check reads the phone's own WCSession, which reports on the Watch.
NEED_WATCH=1
if [ "$TARGET" = "phone" ] && [ "$DO_VERIFY" -eq 0 ]; then
    NEED_WATCH=0
fi

if ! resolve_devices "$NEED_WATCH"; then
    exit "$EXIT_INCONCLUSIVE"
fi

warn_if_not_connected

case "$TARGET" in
    phone) build_install_phone ;;
    watch) build_install_watch ;;
    both)  build_install_phone; build_install_watch ;;
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
