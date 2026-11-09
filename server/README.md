# FOTIQ server

This directory retains the original `notify.js` module and its tests, and now contains a draft reconstruction of the missing API backend. Node 24 is required.

```
npm ci --prefix server
npm test --prefix server
npm start --prefix server
```

Configuration names are in `.env.example`; Node reads environment variables from the host, not automatically from this file. Never commit real secrets. See [backend reconstruction status and Render setup](../docs/BACKEND_REBUILD.md) for exact route coverage, missing features, persistence requirements and deployment gates.

The core service is deployed at https://barq-football-ios.onrender.com and core provider routes have been verified with live responses. `notify.js` is preserved but not yet mounted in the new entrypoint.

The entrypoint mounts `Observations`: a bounded recorder of actual match responses and an evidence-based statistical pressure rule. It is not the recovered original AI engine or a trained prediction model. Analysis requires fresh, same-half observations at least eight minutes apart and numeric shots-on-goal data. Missing or stale inputs produce no invented insight. Feed sampling covers at most five live matches per request; the analyst screen refreshes while active.

Replay returns only captured snapshots, never a reconstructed video or invented earlier match events. Only matches observed live are recorded. Up to 256 snapshots (128 KiB each) are retained for at most 24 hours. In Render Free preview these are temporary and disappear on restart. Disk-mode restart durability is tested locally; permanent cloud preferences/recordings still require provisioned persistent storage. No paid resource is provisioned by this change.

Validation of this addition: 33 local Node tests passed, including all 29 prior tests unchanged. New tests cover observation time windows, stale/missing data suppression, actual snapshot round trips across SQLite reopen, bounds, API routes and upstream failures. Live deployment and iOS validation of this addition must be checked separately; local tests do not establish production readiness.
