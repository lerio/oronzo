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
are lost. Add files under `ios/Oronzo/`, `ios/OronzoWatch/` or `ios/OronzoCore/` and they are
picked up by folder, no project edit needed.

## Running the tests

```bash
cd ios/OronzoCore && swift test
```

`OronzoCore` is a plain SwiftPM package, so this runs on macOS in a second — no simulator, no
signing, no device. It covers the flattener (the contract all three platforms share), the
session state machine, and the watch projection. Reach for it before blaming the app: if a
workout advances wrongly, the bug is usually provable here first.

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

## Deploying the web app

The plan builder is a static SPA: build locally, push with wrangler.

```bash
cd web
npm run build
npx wrangler deploy
```

Live at https://oronzo.valerio-donati.workers.dev

`web/wrangler.jsonc` is the deployment config. Two settings there matter:

- `assets.directory` — without it wrangler publishes the whole source folder rather than
  the build output, which "succeeds" while serving entirely the wrong thing.
- `not_found_handling: single-page-application` — without it a hard refresh on
  `/plans/<id>` returns 404, because the router is client-side.

The Supabase URL and publishable key are compiled into the bundle at build time from
`web/.env.local`, so whoever builds needs that file. That is safe: the publishable key
grants nothing on its own and row-level security protects every table.

**Cloudflare now serves Pages projects through Workers**, so `wrangler pages deploy` will
not create a project — use `wrangler deploy`. There is no git integration set up, so
deploys are manual; a push to `main` does not publish.

## Supabase

**Applying migrations.** Paste the files in `supabase/migrations/` into the Supabase SQL
Editor, in filename order. They are idempotent — `0002` upserts on `slug`, so re-running it
corrects the seed rather than duplicating it.

**The free project pauses after 7 days of low inactivity**, and a paused project is
entirely unavailable until you restore it by hand from the dashboard. Normal use keeps it
awake on its own; `ops/keepalive/` covers the stretches when you are away.

It is a small Cloudflare Worker on a daily cron (`17 6 * * *`) that runs one query against
the REST API. A query rather than a ping, because Supabase counts *database* activity —
row-level security means an anonymous caller gets no rows back, but the query still
executes. It has no `fetch` handler and no public URL, so nothing else can make it run.

```bash
cd ops/keepalive
npx wrangler deploy                       # deploy or update
npx wrangler secret put SUPABASE_PUBLISHABLE_KEY   # first time, or to rotate
npx wrangler tail                          # watch it run
```

To test it without waiting for the cron:

```bash
npx wrangler dev --test-scheduled
curl "http://localhost:8787/__scheduled?cron=17+6+*+*+*"
```

It needs a local `.dev.vars` holding `SUPABASE_PUBLISHABLE_KEY` (gitignored); in production
the value lives as an encrypted Worker secret, so it is never in this repository.

**Auth emails are capped at 2/hour** on the free tier, which is why email confirmation is
disabled and the single user account is created by hand in the dashboard rather than
through a sign-up flow.

### Is the database in step with the code?

There are three moving parts — the database, the deployed web bundle, and the app on the
phone — and they are updated by hand, separately. A mismatch does not announce itself: it
arrives as a `400` from one client, or as a plan list that quietly came from the cache.

**Ask the database, do not remember.** Each migration that changes the schema leaves a
footprint, and a missing column is a `400` while a present one is a `200` — the same failure
the client would hit, which is what makes this a proof rather than a guess:

```bash
cd web && K=$(grep VITE_SUPABASE_PUBLISHABLE_KEY .env.local | cut -d= -f2) \
        U=$(grep VITE_SUPABASE_URL .env.local | cut -d= -f2)
curl -s -o /dev/null -w "0011 dropped equipment:   %{http_code}\n" "$U/rest/v1/exercises?select=equipment&limit=1" -H "apikey: $K"
curl -s -o /dev/null -w "0012 has_two_sides:       %{http_code}\n" "$U/rest/v1/exercises?select=has_two_sides&limit=1" -H "apikey: $K"
curl -s -o /dev/null -w "0013 step intensity:      %{http_code}\n" "$U/rest/v1/plans?select=id,plan_blocks(plan_steps(intensity))&limit=1" -H "apikey: $K"
```

`0011` expects **400** (the column is gone); `0012` and `0013` expect **200**.

**`0010` cannot be probed this way** — it only deletes rows, and RLS means an anonymous
caller sees nothing either way. Ask the SQL editor instead, where the answer is a number:

```sql
select count(*) from exercises where user_id is null;   -- 0 once 0010 has run
```

**Which client breaks which way**, because the two directions are opposites:

| If the database is… | then the web app | and the phone |
|---|---|---|
| ahead of the code (a column was added) | its insert names a column that is not there → `400` on create | a named select over that column → every fetch `400`s, plan list falls back to the cache |
| behind the code (a column was dropped) | it still writes the dropped column → `400` on create | unaffected: it selects by name and ignores what it does not ask for |

So the rule is **migrations first, clients second**, and the client-side half is manual:
`cd web && npm run deploy` publishes the web bundle (there is no git integration), and the
phone takes a rebuild from Xcode (`cd ios && xcodegen generate && open Oronzo.xcodeproj`).
The watch has no backend of its own — it is whatever the phone sends it.

**To check the deployed bundle against the source**, ask the live site for its own build:

```bash
curl -s https://oronzo.valerio-donati.workers.dev/ | grep -o 'assets/index-[^"]*\.js'
```

then fetch that file and grep it for a string literal only the newest code contains — for
example `rest_after_seconds,intensity` (the plan select, `0013`), or `2 sides`. Zero hits
means the live bundle predates that change, whatever is in the working tree.

## Seeing the session runner without a backend

Debug builds accept two launch arguments that skip sign-in entirely:

```bash
xcrun simctl launch booted com.lerio.oronzo -demoSession   # a realistic plan
xcrun simctl launch booted com.lerio.oronzo -demoFinish    # 6 seconds, reaches the summary
xcrun simctl launch booted com.lerio.oronzo -demoRecord    # the same plan, written down
```

`-demoRecord` is `-demoSession` with the session record left on disk, which is what makes the
resume path testable without an account — see [Reproducing a cleared watch](#reproducing-a-cleared-watch).

Useful for working on the runner UI without an account or a network. Release builds have
no such entry point — see `ios/Oronzo/Session/DemoPlan.swift`, which is wrapped in
`#if DEBUG`.

The watch app has the same escape hatch, seeding a session already in progress so its
screen can be looked at without a paired phone:

```bash
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -demoSession
```

`-demoSession` on the watch is **hermetic**: it never activates the link, so a paired phone
cannot talk it out of the session it seeded. To exercise the real link from the watch's side —
which otherwise needs a second pair of hands, since a simulator cannot tap the button — press
Next on a timer instead:

```bash
xcrun simctl launch booted com.lerio.oronzo.watchkitapp -autoNext 6
```

It sends exactly what the button sends, so a control that stops reaching the phone, or reaches
the wrong session, shows up in the phone's log on the next press. Both flags are `#if DEBUG`.

Note that the demo cannot save: with no signed-in session, finishing reports "Auth session
missing" and offers a retry. That is the failure path working, not a bug.

## Reproducing a cleared watch

The failure this project has chased five times — a workout running on the phone and the wrist
reading **"No workout"** — used to be reproducible in under a minute on paired simulators, with no
device and no account. Worth knowing, because it is the fastest way to tell whether a change has
made the class better or worse.

```bash
# both apps installed and the pair connected; see `xcrun simctl list pairs`
xcrun simctl launch <watch-udid> com.lerio.oronzo.watchkitapp
xcrun simctl launch <phone-udid> com.lerio.oronzo -demoSession
sleep 8
xcrun simctl io <watch-udid> screenshot /tmp/before.png   # the workout, counting down

# kill the phone without ending the workout, then start it again
xcrun simctl terminate <phone-udid> com.lerio.oronzo
xcrun simctl launch <phone-udid> com.lerio.oronzo
sleep 6
xcrun simctl io <watch-udid> screenshot /tmp/after.png
```

**Before the record existed**, `/tmp/after.png` was the idle screen: `answer()` ran from
`activationDidCompleteWith`, a fresh process had no session in memory *by construction*, and so the
phone told the watch "nothing is running" on every launch — with the watch's controls dead behind
it, because there was nothing left to route them to. It now logs `answer: a session` and the wrist
keeps counting.

**Resuming** is exercised the same way and needs no account — but with `-demoRecord` rather than
`-demoSession`, because the plain demo is deliberately *not* written down:

```bash
xcrun simctl launch <phone-udid> com.lerio.oronzo -demoRecord
sleep 30                      # let the warm-up elapse, so there is catching up to do
xcrun simctl terminate <phone-udid> com.lerio.oronzo
xcrun simctl launch <phone-udid> com.lerio.oronzo      # no flags
```

The runner should come back **where the session should be by now**, not where it was when the app
died — a timed interval that elapsed while the phone was gone is walked past, and the phone logs
`host: resumed … at interval N of M`. Both apps should show the same interval. `-demoSession`
clears any record it finds, so running it once afterwards returns to a clean slate.

## Troubleshooting

### Reading the watch link

It fails silently, so the log lines *are* the diagnosis. Both apps print with `Log.debug`, which
compiles out of release builds — check you are running a Debug build before concluding there is
nothing to see.

**Phone** (`xcrun simctl launch --console-pty <phone> com.lerio.oronzo -demoSession`, or the Xcode
console):

| Line | What it settles |
|---|---|
| `activation: state=2 reachable=… paired=… watchAppInstalled=…` | Whether the link can work at all. `watchAppInstalled=false` or a non-zero `error=` explains everything downstream. |
| `sent session (N bytes); reachable=…` | A push left. `reachable=false` is normal — the application context is the durable path. |
| `updateApplicationContext failed: …` | **The line that matters most.** The write was refused, so the watch was told nothing, and nothing else retries it. `WCErrorCodeSessionNotActivated` means the session had not finished activating. |
| `answer: a session` / `answer: nothing running` | The watch asked (`requestState`) and this is what it was told. Present within a second of the wrist waking, when the link is healthy. **`a session` is answered from the live session *or from the record on disk***, so a cold launch that had a workout in flight says `a session` rather than clearing the watch — see `session-record.json` below. |
| `host: resumed "…" at interval N of M` | The phone picked up a workout it was already in the middle of. This is the line that proves a relaunch did not lose the session. |
| `host: a record was found but is not live (phase …)` | A record exists but is finished, or older than six hours. It is not resumed; the phone still answers the watch from it while it is fresh. |
| `session: re-asserted by …` | A runner reappeared onto a session that was already running. Normal, and the fix for a wrist that was cleared and never told again. |
| `health: recorded the workout ending …` | Health accepted the finished workout. **The only proof the write worked** — the app requests write-only access, so it can never read its own sample back to check. |
| `health: not recorded — Ns is under the 180s minimum` | The three-minute rule declined the session. Ordinary for a mis-tap, or a plan tapped through faster than it runs. |
| `health: could not write the workout — …` | Health refused the save. The summary shows this line too. The usual cause is permission: Settings → Health → Data Access & Devices → Oronzo. There is no retry by design, so fixing permission only affects the *next* session. |
| `health: the authorization request failed — …` | The permission sheet could not be raised at all. This says nothing about whether permission was *granted* — a refused request still succeeds here, and is discovered at save time. |
| `watch build mismatch: …` | The watch is a different build from this phone. The same thing is shown on screen; see the stale-watch row below. |
| `send skipped: no session` | `activate()` has not run — the link was never started. |

**Watch**: `asking the phone for state`, `refresh: …`, `applied session: N intervals, index=…`,
and `could not decode an incoming message — are both apps the same build?`. A watch that is
showing the wrong thing and never logs an ask is not running this build. A watch that has the
session but never logs an ask has not had its wrist raised.

**The record.** The phone writes the running session to
`Library/Application Support/session-record.json` in its own container — readable with
`xcrun simctl get_app_container <phone-udid> com.lerio.oronzo data`. It is what the phone answers
the watch from when it has nothing in memory, and what it resumes from. If a wrist shows
"No workout" while a workout is going, **read this file first**: a record that is present and
`"phase":"running"` means the phone knows about the workout and the watch is the problem; an
absent record means the phone lost it and the watch is right.

| Symptom | Cause |
|---|---|
| `No Accounts: Add a new account in Accounts settings` | Xcode has no Apple ID signed in. Re-add it under Settings → Accounts. |
| `This app cannot be installed because its integrity could not be verified` | The Watch's UDID isn't registered with your team. Open Window → Devices and Simulators, select the watch, and let it prepare. |
| `Multiple commands produce` on the watch target | Someone set the watch target to `application.watchapp2`. It must be `application`. |
| `xcodebuild` can't find the Apple Watch destination | The watch has never been prepared. Devices and Simulators → select it → wait for "Preparing device for development" to finish. |
| The watch shows **"No workout"** while a session runs on the phone, and the phone's log shows `sent session` and, once the wrist wakes, `answer: a session` | **The watch app on the watch is stale.** Regenerating the project or changing a target does not reliably replace the watch app that is already installed — watchOS keeps the old one, which receives nothing and shows its idle screen. Fix: run the **OronzoWatch** scheme to the watch. Cost several hours to find once. **It now says so for itself**: a mismatched watch shows *"Can't read your iPhone — reinstall the Watch app"* on the wrist, and the phone shows *"Your Watch app is out of date — run the OronzoWatch scheme"* under the session header. The phone's banner appears for any version difference, including a stale watch that still happens to work — updating the watch clears it. |
| The watch shows **"No workout"** and the phone logs `updateApplicationContext failed` | The write was refused — usually the session had not finished activating. The phone re-sends the moment activation completes, so this should self-clear within a second; if it does not, the link is not coming up at all and the `activation:` line says why. |
| The watch logs `could not decode an incoming message` | The two apps are different builds. Install both from the same run — the phone scheme embeds the watch app, but does not reliably replace one already on the watch. |
| The watch shows a session that ended (or that no phone is running) | A phantom, from the application context having no expiry. The phone clears it on coming forward, and answers "nothing running" whenever the watch asks. If it persists, the watch is not reaching the phone at all. |
