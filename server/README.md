# FOTIQ server

This directory retains the original `notify.js` module and its tests, and now contains a draft reconstruction of the missing API backend. Node 24 is required.

```
npm ci --prefix server
npm test --prefix server
npm start --prefix server
```

Configuration names are in `.env.example`; Node reads environment variables from the host, not automatically from this file. Never commit real secrets. See [backend reconstruction status and Render setup](../docs/BACKEND_REBUILD.md) for exact route coverage, missing features, persistence requirements and deployment gates.

The service has not been deployed or verified against the owner's live API-Football subscription. `notify.js` is preserved but not yet mounted in the new entrypoint.
