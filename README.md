# Oronzo

A personal fitness system: author workout plans in the browser, run them on iPhone, follow them on
Apple Watch.

| Piece | Stack | Lives in |
|---|---|---|
| Backend | Supabase (Postgres + Auth + PostgREST + RLS) | `supabase/` |
| Web app | Vite + React + TypeScript → Cloudflare (static assets) | `web/` |
| iOS app | SwiftUI (iOS 26) | `ios/Oronzo/` |
| Watch app | SwiftUI (watchOS 26) | `ios/OronzoWatch/` |
| Shared Swift | Interval model + flattening engine | `ios/Shared/` |

## How it fits together

The **iPhone owns session state** — it is the single source of truth for what you actually did. It
loads plans from Supabase (cached for offline use), runs the session engine, and writes the finished
session back.

The **Watch is a companion**, not an independent app. At session start the iPhone sends it the *full
flattened interval list with absolute end dates*, so the Watch renders an always-accurate countdown
and fires its own haptics without needing a per-second message stream — it keeps working even if the
phone is briefly unreachable. Controls travel back to the phone over WatchConnectivity.

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

The `.xcodeproj` is **generated and gitignored** — edit `ios/project.yml` instead. Likewise
`.env.local` and `Local.private.xcconfig` are gitignored: this repo is public, so the
Supabase project and the signing team ID stay local. See `docs/decisions.md` for the
architecture and `docs/runbook.md` for the weekly re-signing ritual.

## Constraints we build around

This project targets a **free Apple personal team**, which rules out HealthKit, App Groups, and
TestFlight, and expires provisioning profiles every 7 days. See `docs/decisions.md` for the full
reasoning and `docs/runbook.md` for the weekly re-sign ritual.
