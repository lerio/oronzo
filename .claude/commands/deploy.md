---
description: Deploy the plan builder to Cloudflare, after checking it is safe to
argument-hint: [optional note about what is being shipped]
---

Deploy the web app to Cloudflare Workers. This is outward-facing and goes live immediately, so
run the checks before the deploy, not after.

## 1. Check it actually builds

```bash
cd web && npm run build && npm run lint
```

Do not deploy on a failing build, and do not deploy with new lint warnings without saying so.

## 2. Check the deploy is safe against the *current* database

This is the step that is easy to skip and expensive to skip.

The bundle selects explicit columns from Postgres. If a migration has been applied that dropped
or renamed a column the **currently-deployed** bundle still selects, the live site starts
returning 400s the moment the migration lands — the deployed code is what breaks, not the new
build.

So, before deploying, ask: has the schema changed since the last deploy, and in which direction?

- **Dropped a column the old bundle still selects?** Deploy **first**, migrate second. The new
  bundle is written against the new schema, and it also works against the old one if the column
  still exists — so deploying first is strictly the safe order.
- **Added a column the new bundle needs?** Migrate first, or the new bundle 400s on arrival.

State which case this is before running the deploy. If it is neither, say so.

## 3. Deploy

```bash
cd web && npm run deploy
```

`npm run deploy` is `npm run build && wrangler deploy`. `web/wrangler.jsonc` holds the target:
`assets.directory: ./dist` (without it wrangler publishes the whole source folder — which
"succeeds" while serving entirely the wrong thing) and
`not_found_handling: single-page-application` (without it a hard refresh on `/plans/<id>` 404s,
because the router is client-side).

There is **no git integration** — a push to `main` does not publish. This command is the only
way the site changes.

## 4. Confirm

Live at https://oronzo.valerio-donati.workers.dev.

Verify rather than assume: load the URL and check the plan list renders, and that signing in
works. A deploy that reports success but serves a stale bundle is the exact failure
`assets.directory` guards against, and it looks identical to a successful one from the terminal.

Report the deployed URL and what you saw when you loaded it. If you only ran the command and did
not load the page, say that plainly rather than implying it was verified.

$ARGUMENTS
