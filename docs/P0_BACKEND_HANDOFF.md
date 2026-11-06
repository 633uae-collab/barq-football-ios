# FOTIQ P0: backend recovery handoff

Audit date: 2026-11-06. Base: `0705b9d621955805b50e42fe51393ac0b0bcbb83`
(the existing, unmerged PR #1). No server has been created or deployed and no paid service has been purchased.

## What is actually in this repository

| File | Role | Standalone server? |
| --- | --- | --- |
| `server/notify.js` | APNs sender, event detection and polling; exports `start`, `detect`, `liveState`, `makeJwt`, `MIN_LEVEL` | No: requires an existing Express app and injected provider/database helpers |
| `backend-addons/push.js` | Older registration/payload scaffold | No: requires an existing app and database |
| `backend-addons/stars-endpoint.js` | Extracted `/api/stars` route | No: assumes `app`, `todayStr`, `fixturesFor`, `LEAGUE_IDS`, `LIVE`, `DONE`, `cached`, `TZ` already exist |
| `backend-addons/season.js` | Season parameter/path helper from PR #1 | No: requires mounting into the missing host routes |
| `backend-addons/dump-payloads.js` | Generates test payloads from supplied data | No: test utility, not application startup |
| `server/test/*` | Event/payload/season and smoke-check tests | Tests do not supply the production server |

There is no Node dependency manifest/lockfile, HTTP entry point, database bootstrap,
complete provider client, analyst engine, deployment definition or production database in this repository.
The Swift app expects normalized FOTIQ responses, not raw API-Football responses; pointing it directly
at API-Football would break the contract and expose the provider credential.

## Precisely what to recover from the previous developer

Names are only called exact where the checked-in sources identify them. Do not invent missing filenames.

| Missing artifact | Evidence / required contents |
| --- | --- |
| `koora-app/backend/server.js` | Explicitly referenced by the stars, season and push additions; must contain startup, route mounting and dependency wiring |
| `catalog.js` in the original backend | Named by `PrefsPayload` documentation; recover catalog/prefs routes and their schema, including `/api/prefs/:device` acknowledgement contract |
| Original `package.json` and corresponding lockfile | Required Node version, exact dependencies and startup command. `express` is directly required; the SQLite library cannot be determined from the injected `db` interface |
| Provider/cache implementation (filename unknown) | Definitions of `cached`, `fixturesFor`, provider authentication, request budgets, cache expiry, stale-data handling and normalization into Swift's response models |
| Database bootstrap/migrations and persistence implementation (filenames unknown) | Definitions of `db`, `q`, `save`; schema for at least `prefs` and `insights`, which the notification module queries without creating |
| Analyst implementation and scheduling (filenames unknown) | Generates/stores insights; serves `/api/feed` and `/api/insights/:fixture` |
| Search and catalog data/importers (filenames unknown) | Arabic/English search, team/league metadata, supported league IDs and ordering |
| Replay handler and recordings (location unknown) | `/api/replay` and `/api/replay/:fixture/:step` required by the existing integration tests |
| Deployment/startup configuration | Current runtime version, start command, data directory, process manager/container configuration if used, bind host/port and shutdown behavior |
| Environment variable template WITHOUT values | Provider variable name and all required names. Confirmed APNs names: `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_ENV` |
| Database backup + restore instructions through a secure transfer | Preserve preferences, insight history, push tokens and delivery state when moving hosts. Do not commit device tokens or database contents publicly |
| Access to config publication | Owner/control of `https://koora-ae.surge.sh/config.json` so the old app can discover the approved stable endpoint |

Request the full original backend directory with its referenced modules and startup instructions,
excluding `.env`, private keys and `node_modules`. Secrets must be entered in the approved hosting
dashboard, never pasted into chat or committed to GitHub.

## Routes the recovered backend must support

- `/api/fixtures`, `/api/match/:id`, `/api/h2h/:home/:away`, `/api/predictions/:id`
- `/api/catalog`, `/api/standings/:id`, `/api/topscorers/:id`, `/api/topassists/:id`, `/api/league/:id`
- `/api/team/:id`, `/api/player/:id`, `/api/search`, `/api/stars`
- `/api/feed`, `/api/insights/:id`, `/api/prefs/:device`
- `/api/push/register`, `/api/push/:device`
- `/api/replay`, `/api/replay/:id/:step` for existing test coverage

Verify write acknowledgements against the recovered source. The P0 client rejects HTML, non-2xx,
JSON errors and `ok:false`; it requires JSON `ok:true` or HTTP 204 before clearing a pending preference.
Server-side revision/idempotency handling is still needed to guarantee ordering across ambiguous
network timeouts or multiple clients; client serialization alone is not that guarantee.

## Hosting proposal (not executed)

For an initial private TestFlight trial, provision the recovered Node application as one always-on
Render paid web service with a persistent disk if its current SQLite architecture is retained.
The smallest paid compute option listed on 2026-11-06 is 0.5 CPU / 512 MB at $7/month;
disk storage is $0.25/GB/month. A 1 GB disk gives a base estimate of $7.25/month,
before tax, traffic/build overages, provider subscription or a separately required worker.
This is provisional: measure the recovered process's memory and database size first.

Paid compute does not sleep on inactivity. The free service does and is unsuitable for the existing
continuous polling design. A disk is needed because the default filesystem is ephemeral.
One disk-backed instance can pause during deployment/restart; this is not a high-availability guarantee.
The poller must run in only one process unless its locking/dedup logic is upgraded.

Alternative: Railway Hobby starts at a $5/month minimum with included resource credit,
but RAM/CPU/storage/egress can increase the bill. Disable serverless sleeping for this continuous worker.
No account or service should be created until the user approves the recovered architecture and cost.

Sources checked:
- https://render.com/pricing
- https://render.com/docs/faq
- https://render.com/docs/disks
- https://docs.railway.com/pricing

## Current live status and acceptance gates

Read-only check at **2026-11-06 18:32 UTC (22:32 UAE)**:
the published config points to a `pinggy-free` hostname. All six checks in
`node ci/check-backend.mjs` failed because the response was HTML instead of JSON:
fixtures, catalog, Liverpool club details, Liverpool search, feed and stars.
Therefore live API-Football connectivity, app data display and 24-hour operation are NOT verified.

Before declaring recovery complete:
1. Restore the original server and data on the user-approved host; no rewrite or feature replacement.
2. Verify provider credentials/plan inside the host; pass the six read-only contract checks.
3. Confirm real fixture results against the provider, including empty days, null data and quota errors.
4. Test preferences across write failures/restart, and validate acknowledgement/revision behavior.
5. Verify persistent data across host restart/deploy and observe uninterrupted polling over a full day.
6. Publish the stable URL through config and the Release build setting; keep a rollback target.
7. Run existing iOS tests and new P0 regressions, then test on an actual iPhone.
