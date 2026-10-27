# Oronzo — web app

The workout builder. A Vite + React + TypeScript SPA that talks to Supabase directly with the
publishable key, and deploys to Cloudflare Workers as static assets.

```bash
cp .env.example .env.local     # Supabase URL + publishable key
npm install
npm run dev                    # http://localhost:5173
```

| Command | Does |
|---|---|
| `npm run dev` | Vite dev server with HMR |
| `npm run build` | `tsc -b` then `vite build` — the type-check is the useful half |
| `npm run lint` | oxlint |
| `npm run deploy` | build, then `wrangler deploy` |

**Workouts and weekly plans are authored only here.** The iPhone selects a plan and executes one
workout; the Watch displays it — building a structured workout on a phone is miserable, and on a
watch worse.

`src/lib/types.ts` holds the domain model *and* `flattenWorkout`, the contract it shares with
`ios/OronzoCore/` and the `save_workout` SQL function. If you change the flattening rule, change
it in all three. It also holds `sideSuffixes` — the twin of `WorkoutFlattener.sideSuffixes` in the
Swift package — which is what makes an exercise flagged *2 sides* emit left, then right. An
exercise flagged *Alternate* is deliberately **not** two-sided and so is not a case of that
function: it emits one interval per set, marked `(alt)` on the name.

See the [root README](../README.md) for the whole system, `docs/decisions.md` for why it is
shaped this way, and `docs/runbook.md` for deployment.
