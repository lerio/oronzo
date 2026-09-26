---
description: Run the full verification suite — core tests, web build and lint, and both app targets
argument-hint: [what you changed, if you want the summary tailored]
---

Run every check that proves Oronzo still works, and report the actual output rather than
asserting success. Do not skip a step because a previous run passed — the point of this command
is a single honest answer.

Run these, in this order, and stop early only if one fails:

1. **Core tests** — the fastest and most meaningful signal. Everything about the flattener, the
   session state machine and the watch projection is provable here, on macOS, in about a second.
   ```bash
   cd ios/OronzoCore && swift test
   ```
   Expect 202 tests. A failure here explains most downstream weirdness, so fix it before looking
   anywhere else.

2. **Web build** — `tsc -b` runs first and is the half that matters: it is what catches a
   reference to a field that no longer exists, which is the most common breakage in this repo
   because the model is mirrored across three languages.
   ```bash
   cd web && npm run build
   ```

3. **Web lint**
   ```bash
   cd web && npm run lint
   ```
   Four warnings are currently expected and all pre-existing (three fast-refresh advisories in
   `auth.tsx`, one `set-state-in-effect` in `ExercisePicker` that is a deliberate after-mount
   focus). Anything beyond those is new — say so.

4. **Both app targets.** Use a *generic* destination: there are two simulators named "iPhone 17
   Pro" on this machine, so a name-based destination is ambiguous, and a hardcoded UUID would not
   survive to anyone else's Mac.
   ```bash
   cd ios && xcodegen generate
   cd ios && xcodebuild build -project Oronzo.xcodeproj -scheme Oronzo \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/oronzo-check CODE_SIGNING_ALLOWED=NO
   cd ios && xcodebuild build -project Oronzo.xcodeproj -scheme OronzoWatch \
     -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/oronzo-check-watch CODE_SIGNING_ALLOWED=NO
   ```
   `CODE_SIGNING_ALLOWED=NO` keeps this off the signing path entirely, so it works without an
   Apple ID, a connected device, or a valid profile.

Then summarise in a short table: what ran, pass or fail, and the count where there is one. If
something failed, quote the real error — never paraphrase a failure into a softer claim.

If $ARGUMENTS is non-empty, close with one line on whether the named change is actually covered
by these checks, or whether it needs a device to verify.

**What this suite does not prove:** anything requiring a physical iPhone or Apple Watch. Signing,
WatchConnectivity, haptics and the extended runtime session cannot be tested here. If the change
touches `ios/Oronzo/Session/` or `ios/OronzoWatch/`, say plainly that a device run is still
needed.
