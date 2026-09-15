---
description: The weekly re-sign — rebuild from Xcode so the iPhone and Watch apps launch again
---

The free personal team expires provisioning profiles **every 7 days**, after which the apps stop
launching. This is the ritual that fixes it. It is a monthly-or-so chore, not a bug.

## How you know you need it

The app icon is still on the home screen but tapping it does nothing, or Xcode says the
provisioning profile has expired. The apps do not warn you in advance.

## What to do

**These steps need a human at Xcode.** You cannot do this by running `xcodebuild` in the
background — the point is a fresh signed install onto physical devices. So surface the
instructions and let the user run them, rather than attempting them.

```bash
cd ios && xcodegen generate && open Oronzo.xcodeproj
```

Then, in Xcode:

1. Run the **Oronzo** scheme to the iPhone. This also installs the embedded Watch app.
2. Run the **OronzoWatch** scheme to the Apple Watch, if it did not follow automatically.

The Watch is the one that usually needs the second step.

## If it fails

| Symptom | Cause |
|---|---|
| `No Accounts: Add a new account in Accounts settings` | Xcode has no Apple ID signed in. Settings → Accounts. |
| `This app cannot be installed because its integrity could not be verified` | The Watch's UDID is not registered with the team. Window → Devices and Simulators, select the watch, let it prepare. |
| `Multiple commands produce` on the watch target | Someone set the watch target to `application.watchapp2`. It must be `application` — see `docs/decisions.md`. |
| `xcodebuild` cannot find the Apple Watch destination | The watch has never been prepared. Devices and Simulators → select it → wait for "Preparing device for development". |
| Every `xcodebuild` fails with an unrelated-looking error | Xcode needs its licence accepted. Open Xcode once. |

## The permanent fix

A paid Apple Developer account ($99/yr) removes this entirely, along with the one-hour extended
runtime cap and the missing Activity ring credit. `docs/decisions.md` records what else it
unlocks — it is the single highest-value upgrade available to this project.
