# Runbook

Operational chores. Most of these exist because of the free Apple personal team.

## The weekly re-sign (every 7 days)

Free-team provisioning profiles expire after 7 days, at which point the apps stop launching
on your devices. Fix:

```bash
cd ios && xcodegen generate && open Oronzo.xcodeproj
```

Then run the **Oronzo** scheme to your iPhone (this also installs the embedded Watch app),
and the **OronzoWatch** scheme to your Apple Watch if it doesn't follow automatically.

Symptoms that you've hit this: the app icon is still there but tapping it does nothing, or
Xcode says the provisioning profile has expired.

## Regenerating the Xcode project

After editing `ios/project.yml` — or after adding/removing Swift files if you also updated
`sources` — run:

```bash
cd ios && xcodegen generate
```

Never edit `Oronzo.xcodeproj` directly: it is gitignored and regenerated, so those changes
are lost. Add files under `ios/Oronzo/`, `ios/OronzoWatch/` or `ios/Shared/` and they are
picked up by folder, no project edit needed.

## First-time setup after cloning

```bash
cd ios
cp Local.private.xcconfig.example Local.private.xcconfig   # then fill in your values
xcodegen generate

cd ../web
cp .env.example .env.local                    # then fill in URL + publishable key
npm install
```

Both files are gitignored and optional: without the iOS one the project still builds and
the app reports that it is unconfigured.

## Running the web app

```bash
cd web && npm run dev
```

## Deploying the web app (Cloudflare Pages)

Build command `npm run build`, output directory `web/dist`, root directory `web`. Set
`VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` as build environment variables in
the Pages project — they are compiled into the bundle, so they must be present at build
time, not runtime.

## Supabase

**Applying migrations.** Paste the files in `supabase/migrations/` into the Supabase SQL
Editor, in filename order. They are idempotent — `0002` upserts on `slug`, so re-running it
corrects the seed rather than duplicating it.

**The free project pauses after 7 days of low inactivity.** A paused project is entirely
unavailable until restored from the dashboard, and the first request afterwards takes
10–30 s. Normal app usage keeps it awake; if you're away, open the dashboard or hit the API
occasionally.

**Auth emails are capped at 2/hour** on the free tier, which is why email confirmation is
disabled and the single user account is created by hand in the dashboard rather than
through a sign-up flow.

## Seeing the session runner without a backend

Debug builds accept two launch arguments that skip sign-in entirely:

```bash
xcrun simctl launch booted com.lerio.oronzo -demoSession   # a realistic plan
xcrun simctl launch booted com.lerio.oronzo -demoFinish    # 6 seconds, reaches the summary
```

Useful for working on the runner UI without an account or a network. Release builds have
no such entry point — see `ios/Oronzo/Session/DemoPlan.swift`, which is wrapped in
`#if DEBUG`.

The watch app has the same escape hatch, seeding a session already in progress so its
screen can be looked at without a paired phone:

```bash
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -demoSession
```

Note that the demo cannot save: with no signed-in session, finishing reports "Auth session
missing" and offers a retry. That is the failure path working, not a bug.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `No Accounts: Add a new account in Accounts settings` | Xcode has no Apple ID signed in. Re-add it under Settings → Accounts. |
| `This app cannot be installed because its integrity could not be verified` | The Watch's UDID isn't registered with your team. Open Window → Devices and Simulators, select the watch, and let it prepare. |
| `Multiple commands produce` on the watch target | Someone set the watch target to `application.watchapp2`. It must be `application`. |
| `xcodebuild` can't find the Apple Watch destination | The watch has never been prepared. Devices and Simulators → select it → wait for "Preparing device for development" to finish. |
