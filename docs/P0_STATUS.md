# P0 implementation status — 2026-11-06

Branch: `codex/p0-network-persistence`, based on existing PR #1 head `0705b9d`.
All earlier PR changes are retained. `main` has not changed.

## Implemented locally, pending iOS build verification

- Validate HTTP status and write acknowledgements; reject HTTP 200 tunnel HTML.
- Bound transient GET retries and request/resource timeouts; preserve cancellation and clear cache on explicit endpoint reset.
- Persist the latest preferences in a durable outbox. Serialize writes and never clear a newer edit on an older acknowledgement. Retry pending preferences when active/relaunched.
- Preserve custom Home order during migration, language/timezone writes and backups of encoded local favorites/settings arrays.
- First-run club selection uses cached club identities or six verified bundled club identities when the server is unavailable. Scores and fixtures are never synthesized. Render the unchanged glass tiles only after the existing splash gate opens.
- Replace endless onboarding/search waits with bounded loading, empty/error states and native glass Retry controls. Optional competition steps remain skippable.
- Keep loaded content visible with an error/retry state when a refresh fails.
- Add read-only backend contract checker, 18 Swift unit regressions, one offline onboarding UI regression and two Node checker tests. No existing test was deleted or relaxed.

## Validation

- `node --test server/test/*.test.js`: **9 passed, 0 failed** (7 pre-existing + 2 added).
- `node --check ci/check-backend.mjs`: passed.
- `git diff --check`: passed.
- Syntax parser: no errors in changed/new Swift files. This does NOT type-check SwiftUI or replace Xcode.
- Swift unit/UI tests and a signed build: **not run here** (no Xcode/iOS SDK).
- Live backend check: **6 failed, 0 passed**, HTML instead of JSON. Details in `P0_BACKEND_HANDOFF.md`.

## Blocking access

GitHub read access works, but creating the proposed remote branch returned:
`403 Resource not accessible by integration`.
The local branch cannot yet be published and no new pull request exists. Enable GitHub integration
write access for this repository (Contents and Pull requests); do not paste a token into chat.

The original backend source and hosting access remain with the previous developer. No new server,
paid subscription, deployment, PR merge or video recording has been performed.

## Review/PR plan once access is restored

Publish this branch and open a draft PR against `cursor/complete-unfinished-flows-d997` so only P0
changes are reviewed; this is stacked on PR #1 and does not merge either PR. Retarget after the
user approves the earlier PR. Run the existing CI plus new tests; keep the draft unmerged until
build/type-check, live backend and device acceptance gates pass.

Remaining: recover and deploy the original backend with approval; verify write response schema,
API-Football entitlement/quota, data migration and server-side revision protection; complete iOS/device
validation. P1 splash performance and APNs delivery fixes are outside this P0 change.
