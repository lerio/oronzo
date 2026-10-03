#!/bin/bash
#
# lib.sh — shared helpers for scripts/resign.sh and scripts/install.sh.
#
# Sourced, never run. It defines things and returns.
#
# The link check lives here rather than in either script because it is the one
# piece of this that has been wrong before: an early version reported a *locked
# phone* as a broken pairing. Two copies would drift, and the copy that drifted
# would be the one you were reading.

# This file's directory, whichever script sourced it.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$LIB_DIR/.." && pwd)"

PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

PHONE_BUNDLE="com.lerio.oronzo"
PHONE_APP_PATH_SUFFIX="Build/Products/Debug-iphoneos/Oronzo.app"

# The one copy of the Watch app that may be installed on the wrist: the app embedded
# in the newest iPhone build. A standalone Debug-watchos build puts *different bytes*
# on the Watch — a separate compile, so different UUIDs and signatures — and two
# copies that differ is exactly what the phone's periodic "Reunion" sync tries to fix
# over the air. A free-provisioning-profile app can never pass that install, and the
# failed attempt drops the companion registration with it (error 7006 on every push)
# until a direct install replaces the copy. See docs/decisions.md, "The third
# occurrence, and the cause".
EMBEDDED_WATCH_PATH_SUFFIX="Build/Products/Debug-iphoneos/Oronzo.app/Watch/OronzoWatch.app"
WATCH_EXECUTABLE_NAME="OronzoWatch"

# How long to wait for the phone to report its activation state before giving up.
#
# Polled rather than slept: activation usually lands in a second or two, but a
# cold start can take longer. The first version of this slept a flat 12 seconds
# and reported a *locked phone* as a broken pairing — a wrong answer, stated
# confidently, which is worse than no answer.
ACTIVATION_TIMEOUT=30

# What a refused launch looks like. `preflight` is the one that actually fires
# when the iPhone is locked; the rest cover an unreachable or unprepared device.
LAUNCH_FAILED_RE='failed to launch|preflight|RequestDenied|CoreDeviceError|Unable to connect|Unable to locate'

# Exit codes, so these compose with other scripts.
EXIT_PASS=0
EXIT_INCONCLUSIVE=1
EXIT_BROKEN=2
EXIT_USAGE=64

# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------

# Reads the UDID out of `devicectl list devices`. The identifier is the field
# immediately before the literal "(UDID)", which is stable regardless of what
# the device is named or how many words that name has.
devices() {
    xcrun devicectl list devices 2>/dev/null | grep physical || true
}

udid_of() {  # $1 = "watch" | "phone"
    devices | awk -v want="$1" '
        {
            udid = ""
            for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") udid = $i
            if (udid == "") next
            is_watch = ($0 ~ /Watch/) ? 1 : 0
            if (want == "watch" && is_watch) print udid
            if (want == "phone" && !is_watch) print udid
        }' | head -1
}

# Sets PHONE_UDID and WATCH_UDID, printing what it found.
# $1 = 1 if a Watch is required, 0 if not.
resolve_devices() {
    local need_watch="${1:-1}"

    PHONE_UDID="${PHONE_UDID:-$(udid_of phone)}"
    WATCH_UDID="${WATCH_UDID:-$(udid_of watch)}"

    echo "==> Devices"
    if [ -n "$PHONE_UDID" ]; then
        echo "    iPhone  $PHONE_UDID"
    else
        echo "    iPhone  (not found)"
    fi
    if [ -n "$WATCH_UDID" ]; then
        echo "    Watch   $WATCH_UDID"
    else
        echo "    Watch   (not found)"
    fi

    if [ -z "$PHONE_UDID" ] || { [ "$need_watch" -eq 1 ] && [ -z "$WATCH_UDID" ]; }; then
        echo
        echo "Could not find the devices needed. 'xcrun devicectl list devices' must"
        echo "show an iPhone — and an Apple Watch, when a Watch is needed — each with"
        echo "reality 'physical'."
        echo
        xcrun devicectl list devices || true
        return "$EXIT_INCONCLUSIVE"
    fi

    return 0
}

# `connected` is the state an *install* wants: an `available (paired)` device is
# reachable over the network, and that is not always enough for `device install
# app`. It is, however, enough to launch the app and read its activation line —
# so this must not be called from a verify-only path, where it would be a false
# alarm, and a warning that fires when nothing is wrong is one you stop reading.
warn_if_not_connected() {
    if ! devices | grep -q "connected"; then
        echo
        echo "    WARNING: neither device reports 'connected'. Wake and unlock both,"
        echo "    keep them near this Mac, then re-run. Continuing anyway."
    fi
}

# Newest Oronzo DerivedData, in case more than one exists.
derived_data() {
    ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Oronzo-* 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Build + install
# ---------------------------------------------------------------------------
#
# The build needs an absolute -project path rather than a `cd`, so that a caller
# can run these from anywhere.

build_install_phone() {
    local dd
    echo
    echo "==> Building Oronzo for the iPhone"
    echo "    (this takes a few minutes; -quiet hides the xcodebuild log)"
    xcodebuild build -project "$REPO/ios/Oronzo.xcodeproj" -scheme Oronzo \
        -destination "id=$PHONE_UDID" -configuration Debug \
        -allowProvisioningUpdates -quiet

    dd="$(derived_data)"
    echo
    echo "==> Installing onto the iPhone"
    xcrun devicectl device install app --device "$PHONE_UDID" "$dd/$PHONE_APP_PATH_SUFFIX"
}

# The embedded Watch app, if a phone build exists. Echoes its path.
embedded_watch_app() {
    local dd
    dd="$(derived_data)"
    [ -n "$dd" ] && [ -d "$dd/$EMBEDDED_WATCH_PATH_SUFFIX" ] \
        && echo "$dd/$EMBEDDED_WATCH_PATH_SUFFIX"
}

# The executable hash the wrist must report after a push — the shasum of the file,
# which is what `appconduitd`'s `watchKitAppExecutableHash=` echoes back.
embedded_watch_hash() {
    local app
    app="$(embedded_watch_app)"
    [ -n "$app" ] || return 1
    shasum -a 256 "$app/$WATCH_EXECUTABLE_NAME" | awk '{print $1}'
}

# Push the embedded Watch app to the wrist — the repair for a dropped companion
# registration, and the only install path that keeps the two copies identical.
#
# Callers decide whether a failure is fatal; this explains and returns non-zero.
install_embedded_watch() {
    local app staging
    if [ -z "$WATCH_UDID" ]; then
        echo "ERROR: no Watch found — cannot install the Watch app."
        return 1
    fi

    app="$(embedded_watch_app)"
    if [ -z "$app" ]; then
        echo "ERROR: no Watch app is embedded in a phone build yet."
        echo "       Run scripts/install.sh phone first — the Watch app is built"
        echo "       inside the iPhone app."
        return 1
    fi

    # Stale bytes are worth interrupting for: the Watch app is compiled from these
    # sources, so if any file is newer than the bundle, the bundle is behind them.
    # Not fatal — this push still repairs a dropped registration.
    if [ -n "$(find "$REPO/ios/OronzoWatch" "$REPO/ios/Shared" "$REPO/ios/OronzoCore/Sources" \
               -name '*.swift' -newer "$app" -print -quit 2>/dev/null)" ]; then
        echo "    WARNING: the embedded Watch app is older than the Watch sources."
        echo "    Pushing it installs stale code — scripts/install.sh both rebuilds."
        echo
    fi

    echo
    echo "==> Installing the Watch app embedded in the newest iPhone build"
    echo "    executable sha256: $(embedded_watch_hash)"
    echo "    (the wrist reports it back as appconduitd's watchKitAppExecutableHash)"

    if xcrun devicectl device install app --device "$WATCH_UDID" "$app"; then
        return 0
    fi

    # devicectl can refuse a bundle nested inside another app. The staged copy is
    # the same bytes — ditto preserves the signature — so the hash, which is the
    # thing the sync compares, does not move.
    echo
    echo "    devicectl refused the bundle in place; staging a copy and retrying."
    staging="$(mktemp -d -t oronzo-watch)"
    ditto "$app" "$staging/OronzoWatch.app"
    if xcrun devicectl device install app --device "$WATCH_UDID" "$staging/OronzoWatch.app"; then
        rm -rf "$staging"
        return 0
    fi
    rm -rf "$staging"
    echo
    echo "ERROR: the Watch app did not reach the wrist. Wake the Watch, keep it"
    echo "       near this Mac and on Wi-Fi, then re-run."
    return 1
}

# ---------------------------------------------------------------------------
# Verify — the only part that answers the actual question
# ---------------------------------------------------------------------------
#
# Neither scheme reports whether the install registered, so this asks the one
# thing that knows: the phone's own WCSession. The three outcomes are kept
# apart on purpose, because they have different fixes and only one of them
# means anything about the watch link.
#
# Returns EXIT_PASS / EXIT_INCONCLUSIVE / EXIT_BROKEN.

verify() {
    echo
    echo "==> Verifying the link (relaunching the phone app)"
    echo "    NOTE: this terminates a running workout on the phone."

    local log pid waited
    log="$(mktemp -t oronzo-verify)"

    xcrun devicectl device process launch --console --terminate-existing \
        --device "$PHONE_UDID" "$PHONE_BUNDLE" >"$log" 2>&1 &
    pid=$!

    waited=0
    while [ "$waited" -lt "$ACTIVATION_TIMEOUT" ]; do
        if grep -q "activation:" "$log" 2>/dev/null; then break; fi
        if grep -qE "$LAUNCH_FAILED_RE" "$log" 2>/dev/null; then break; fi
        # The launch process itself died — no point waiting out the clock.
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 1
        waited=$((waited + 1))
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    if grep -q "activation:" "$log"; then
        grep "activation:" "$log"
        echo
    fi

    # A refused launch says nothing about the watch link. Reporting it as a
    # broken pairing is what this check exists to stop doing.
    if grep -qE "$LAUNCH_FAILED_RE" "$log" 2>/dev/null; then
        echo "INCONCLUSIVE — the app could not be launched, so the phone was never"
        echo "               asked. This says nothing about the watch link."
        echo
        grep -E "NSLocalizedFailureReason|BSErrorCodeDescription|error [0-9]+" "$log" \
            | head -3 | sed 's/^/    /'
        echo
        echo "               Most often the iPhone is locked. Unlock it, keep it"
        echo "               awake, and re-run:  scripts/resign.sh --verify-only"
        return "$EXIT_INCONCLUSIVE"
    fi

    if ! grep -q "activation:" "$log" 2>/dev/null; then
        echo "INCONCLUSIVE — the app launched but reported no activation state"
        echo "               within ${ACTIVATION_TIMEOUT}s. Full output:"
        echo
        sed 's/^/    /' "$log"
        return "$EXIT_INCONCLUSIVE"
    fi

    if grep -q "watchAppInstalled=true" "$log"; then
        echo "PASS — the Watch app is registered as this phone app's companion."
        if grep -q "reachable=false" "$log"; then
            echo
            echo "       reachable=false: the Watch is not on the wrist this second."
            echo "       That is fine and not a problem — it turns true when it wakes."
        fi
        return "$EXIT_PASS"
    fi

    # Activation completed, so the phone answered for real. This one is genuine.
    echo "BROKEN — activation succeeded, and the phone reports the Watch app is not"
    echo "         registered to it. This is the 'No Watch app' state."
    echo
    echo "         This state can clear by itself within minutes (measured, twice on"
    echo "         2 Oct 2026) — if you are in no hurry, re-run this check once before"
    echo "         rebuilding anything."
    echo
    if grep -q "paired=false" "$log"; then
        echo "         paired=false, so no Watch is paired to this iPhone at all —"
        echo "         a different problem. Check pairing in the Watch app."
    else
        echo "         Fix — push the Watch app embedded in the newest iPhone build,"
        echo "         which repairs the registration and keeps the two copies identical"
        echo "         (the difference between them is what the phone's sync trips over):"
        echo "           $REPO/scripts/install.sh watch"
    fi
    return "$EXIT_BROKEN"
}
