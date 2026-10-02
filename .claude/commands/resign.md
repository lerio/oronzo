---
description: The weekly re-sign — reissue provisioning profiles so the iPhone and Watch apps launch again
---

The free personal team expires provisioning profiles **every 7 days**, after which the apps stop
launching. This is the ritual that fixes it. It is a weekly chore, not a bug.

## How you know you need it

The app icon is still on the home screen but tapping it does nothing, or Xcode says the
provisioning profile has expired. The apps do not warn you in advance.

## What to do

```bash
./scripts/resign.sh
```

That is the whole thing. It backs up and deletes the two Oronzo profiles, rebuilds and installs
both apps, and verifies. `--verify-only` checks the link without changing anything.

**This section used to say the steps needed a human at Xcode and that `xcodebuild` could not do
it. It was never tested, and it is false** — the CLI route is how the Watch app was repaired on
28 and 30 September 2026, and how both apps were re-signed on 2 October 2026. It is the same
mistake `AGENTS.md` records under *"HealthKit signs"*: an impossibility claim whose only evidence
was another doc. What genuinely needs a human is narrower — a device that has never been prepared
for development, no Apple ID signed in to Xcode, or the licence not accepted. The table below
covers those.

**Deleting the profiles is the point, and it is not obvious.** Xcode reuses a provisioning profile
while it is still valid, so a plain rebuild re-embeds the same one and the expiry does not move.

### By hand, in Xcode

```bash
cd ios && xcodegen generate && open Oronzo.xcodeproj
```

Then, in Xcode:

1. Run the **Oronzo** scheme to the iPhone.
2. Run the **OronzoWatch** scheme to the Apple Watch. **Do not skip this** because the phone step
   "usually" covers it — and do not skip it because the watch shows the app as installed.

**Step 1 installs the embedded Watch app only when the watch is connected at that moment.** If it
is not (`devicectl list devices` shows the watch as *available (paired)* rather than *connected*),
the phone app is re-signed and the watch app is left on the previous install — which is the state
that reads as **"No Watch app"** on the phone with a perfectly good-looking app on the wrist. It has
cost this project two afternoons, on 28 and 30 September 2026.

### Then verify, because no scheme reports whether it worked

```bash
./scripts/resign.sh --verify-only
```

Exit `0` means the pairing is registered; `1` that it could not be determined — **most often a
locked iPhone, which is not a broken pairing**, and reading it as one is a mistake this script has
already made once; `2` that it is genuinely broken. Prefer it to guessing, and run it *before*
reinstalling anything.

The raw command behind it, if you want to watch it live:

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device <iphone-udid> com.lerio.oronzo
```

`watchAppInstalled=true` and no `7006` means both halves are registered. `watchAppInstalled=false`
means the watch app must be reinstalled — see the row in `docs/runbook.md`. See `docs/decisions.md`,
*"A watch app that was installed and not installed"*.

## If it fails

| Symptom | Cause |
|---|---|
| `No Accounts: Add a new account in Accounts settings` | Xcode has no Apple ID signed in. Settings → Accounts. |
| `This app cannot be installed because its integrity could not be verified` | The Watch's UDID is not registered with the team. Window → Devices and Simulators, select the watch, let it prepare. |
| `Multiple commands produce` on the watch target | Someone set the watch target to `application.watchapp2`. It must be `application` — see `docs/decisions.md`. |
| `xcodebuild` cannot find the Apple Watch destination | The watch has never been prepared. Devices and Simulators → select it → wait for "Preparing device for development". |
| Every `xcodebuild` fails with an unrelated-looking error | Xcode needs its licence accepted. Open Xcode once. |

## The permanent fix

A paid Apple Developer account ($99/yr) removes **the weekly re-sign** — which is the whole of this
document — and unlocks TestFlight and App Groups.

**It does not buy the two things this section used to promise.** The one-hour extended runtime cap
and the missing Activity ring credit both follow from having no `HKWorkoutSession`, and that is a
**code change, not a purchase.** HealthKit itself signs fine on the free personal team, which this
project believed otherwise about for a long time — see `docs/decisions.md`.

So the upgrade is worth costing on the re-sign alone: a weekly chore removed, and a convenience
gained, with no new capability attached. The highest-value change available to this project is not
a purchase at all — it is replacing the Watch's runtime with a workout session.
