# Oronzo

A personal fitness system: author workout plans in the browser, run them on iPhone, follow them on
Apple Watch.

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase (Postgres + Auth + PostgREST + RLS) | `supabase/` |
| Web app | Vite + React + TypeScript → Cloudflare Workers | `web/` |
| iOS app | SwiftUI (iOS 26) | `ios/Oronzo/` |
| Watch app | SwiftUI (watchOS 26) | `ios/OronzoWatch/` |
| Shared Swift | Interval model, flattening engine, session state machine | `ios/OronzoCore/` |
| Ops | Cloudflare Worker that keeps the free Supabase project awake | `ops/keepalive/` |

## How it fits together

The **iPhone owns session state** — it is the single source of truth for what you actually did. It
loads plans from Supabase (cached for offline use), runs the session engine, and writes the finished
session back.

The **Watch is a companion**, not an independent app. It is sent the *full flattened interval list
with absolute end dates*, so it renders an always-accurate countdown and fires its own haptics
without needing a per-second message stream — it keeps working even if the phone is briefly
unreachable. Controls travel back to the phone over WatchConnectivity.

Plans are authored **only** in the web app; the iPhone executes them.

## Getting started

```bash
# Web app
cd web
cp .env.example .env.local                    # fill in your Supabase URL + publishable key
npm install && npm run dev

# iOS / watchOS
cd ios
cp Local.private.xcconfig.example Local.private.xcconfig   # team ID + Supabase values
xcodegen generate && open Oronzo.xcodeproj                 # requires: brew install xcodegen
```

The iOS project builds with or without that last file — the committed `Local.xcconfig`
includes it optionally, so a fresh clone compiles and simply tells you at runtime that it
is unconfigured.

## Tests and checks

```bash
cd ios/OronzoCore && swift test     # the engine, flattener and watch projection — no device needed
cd web && npm run lint              # oxlint
cd web && npm run build             # tsc -b + vite build
```

`OronzoCore` is a plain SwiftPM package, so the trickiest logic in the project is testable on
macOS in a second, with no simulator and no signing.

## Deploying

```bash
cd web && npm run deploy            # build + wrangler deploy
```

Live at **https://oronzo.valerio-donati.workers.dev**. There is no git integration, so a push
to `main` does not publish — deploys are manual. See `docs/runbook.md`.

The `.xcodeproj` is **generated and gitignored** — edit `ios/project.yml` instead. Likewise
`.env.local` and `Local.private.xcconfig` are gitignored: this repo is public, so the
Supabase project and the signing team ID stay local.

See `docs/decisions.md` for the architecture and why it is shaped this way, and
`docs/runbook.md` for the operational chores — the weekly re-sign above all.

## Constraints we build around

This project targets a **free Apple personal team**, which rules out HealthKit, App Groups, and
TestFlight, and expires provisioning profiles every 7 days. See `docs/decisions.md` for the full
reasoning and `docs/runbook.md` for the weekly re-sign ritual.
