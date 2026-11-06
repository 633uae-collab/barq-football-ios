# FOTIQ backend reconstruction — draft, not a live deployment

The original server entrypoint, catalog implementation, analyst engine and production database are absent from the inspected iOS repository. This branch adds a replacement service **inside the same repository**, stacked on PR #3 and therefore preserving PR #1/#2. It does not recover the former developer's private host or database.

## Implemented and locally exercised

Node 24 + Express 5; API-Football requests are made only on the server. Responses normalize to `BARQ/Core/Models.swift`. Timeouts, HTTP-200 HTML rejection, provider error-envelope handling, bounded caching, coalescing and concurrency limits are included. Stale results are limited and flagged. Credentials and raw upstream errors are never returned to the app. A defensive request budget defaults to 1,000 provider requests per process per UTC day; this is not the account's actual quota and resets on process restart.

Preferences PUT commits to SQLite before acknowledging success. WAL and FULL synchronous mode are enabled. Existing iOS local persistence and durable retry outbox are unchanged. The client's revision is local-only and is not sent to this server; server-side ordering beyond the client's existing serial writer is not claimed. Invalid/incomplete snapshots cannot clear saved preferences.

| Route | State |
| --- | --- |
| `/healthz` | Process/database liveness; explicitly does **not** certify provider availability |
| `/api/fixtures`, `/api/match/:id`, `/api/h2h/:home/:away` | Implemented; normalized fixtures, events, lineups, statistics |
| `/api/catalog`, `/api/standings/:id` | Implemented; current season comes from provider metadata |
| `/api/topscorers/:id`, `/api/topassists/:id`, `/api/league/:id` | Implemented |
| `/api/team/:id` | Team, venue, next/last fixtures, squad, transfers |
| `/api/player/:id` | Profile and season stats; latest provider season if unspecified |
| `/api/search` | Club and league search; limited explicit Arabic club aliases. Player/match search not restored, reported in notes |
| `/api/stars` | Real fixture player stats, up to 20 most recent started fixtures per date |
| `PUT /api/prefs/:device` | Durable validated snapshot; compatible with current iOS sender |
| `/api/feed`, `/api/insights/:id` | HTTP 503 `ANALYST_ENGINE_NOT_RESTORED` |
| `/api/replay`, `/api/replay/:id/:step` | HTTP 503 `REPLAY_RECORDINGS_NOT_RESTORED` |
| `POST /api/push/register`, `DELETE /api/push/:device` | HTTP 503 `PUSH_INTEGRATION_NOT_RESTORED` |

Existing `server/notify.js`, backend add-ons, APNs tests and all iOS functionality remain intact. The notifier is not mounted: it needs the analyst persistence/schema, APNs configuration and delivery lifecycle review. No generated analysis, fabricated matches or fake replay recordings substitute for these missing parts. The full pre-existing `ci/check-backend.mjs` intentionally still fails the feed check until the engine is restored.

## Run locally

Use Node 24.14 or later in the 24.x line:

```
npm ci --prefix server
npm test --prefix server
npm start --prefix server
```

Without `APISPORTS_KEY`, liveness works, but provider routes correctly fail with JSON `API_KEY_NOT_CONFIGURED`. Local tests use mocked provider responses and the existing real captured fixture; they do not verify the user's subscription, live data or production performance. No SwiftUI design, native Liquid Glass, bottom tabs, or launch behavior was modified.

## Render — manual setup only after owner authorizes hosting charges

No service has been created and no purchase made. The user's screenshots show an empty workspace, Hobby plan and no payment card. Their confirmed subscription is API-Football, not Render. A Safari login on the owner's iPhone does not authenticate the automation browser.

1. Review the draft PR and finish required production gaps before exposing this service to users.
2. In the intended Render workspace, prepare a **Web Service** linked to this existing repository, branch `codex/backend-rebuild`. Do not deploy `main` and do not merge any PR.
3. Root directory: leave blank. Build command: `npm ci --prefix server`. Start command: `npm start --prefix server`. Health check: `/healthz`.
4. Configure `NODE_VERSION=24.22.1`, `NODE_ENV=production`, and `FOTIQ_DB_PATH=/var/data/fotiq/fotiq.sqlite`. The database path must be on an actual persistent disk mounted at `/var/data`. Setting the variable alone does not provision or verify persistence. Use one service instance; SQLite is not a multi-instance shared database.
5. Set `APISPORTS_KEY` directly in Render's secret Environment field. Never paste it into chat, GitHub, the app, or screenshots. Adjust `API_DAILY_BUDGET` below the provider account's remaining allowance, considering other consumers.
6. Review the displayed compute, disk and other charges with the owner before selecting any paid resources or confirming deployment. A paid workspace alone is not proof of always-on compute. No Blueprint is included that could provision billable resources automatically.
7. Once deployed, verify the public HTTPS URL and inspect logs without showing secrets. Run `node ci/check-backend.mjs https://ACTUAL-SERVICE.onrender.com` and exercise every route in the table. Expected missing-feature errors are blockers, not passes.
8. Save preferences, restart/redeploy the service, and verify the durable snapshot survived using a controlled test device. Verify backups/restore and load/performance before wider release.
9. Only after live checks, set GitHub Actions secret `FOTIQ_API_BASE` to that exact HTTPS base URL. The existing workflow passes it to the app's `FOTIQAPIBase` build setting. Do not embed the API-Football key. Do not replace the old public config with an untested URL.
10. Run the complete iOS workflow on the chosen branch with that base URL; offline launch tests alone are insufficient. The existing live-timeline and screenshot steps still resolve the old remote config and must be aligned to the validated base before claiming full integration.

## Production blockers / limitations

- Render access, approved compute/disk cost, a deployed URL and secret provider configuration are not available in the automation session.
- Live provider coverage, API plan permissions, real-world latency and 24-hour operation remain unverified.
- Missing analyst engine, original replay recordings, push integration, player/match search and original user database backup.
- The existing client uses a random installation ID as a preferences-write capability. It is not account authentication. Do not expose broad account data or preferences enumeration; add an authenticated registration/migration strategy before public release. Current server has no preferences GET endpoint.
- The IP limiter intentionally does not trust forwarded headers. Behind a proxy it may apply to shared proxy IPs. Configure verified proxy handling plus edge abuse controls before public traffic; the process-local request budget is not global rate accounting.
- Cache memory is bounded by serialized bytes and entries, not a hard V8 heap limit. Benchmark under the selected host's memory and CPU limits.
- App endpoint wiring, APNs, TestFlight signing and full online iOS validation are not complete.

Validation at preparation: 22 Node tests pass (all 9 existing plus 13 added). No tests were removed or weakened. This is a draft reconstruction checkpoint, **not a claim that FOTIQ is ready for production or TestFlight**.
