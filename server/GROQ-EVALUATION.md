# Groq evaluation — not approved for public rollout

Private, disabled-by-default POST `/api/analyst/evaluate` accepts `{question, fixtureId}` and an evaluator Bearer token. No iOS UI/design changes. Existing statistical analyst remains unchanged.

Initial candidate: `openai/gpt-oss-120b`, high reasoning. This is a candidate, NOT a measured quality winner. Official docs reviewed 2026-11-07: https://console.groq.com/docs/model/openai/gpt-oss-120b and https://console.groq.com/docs/rate-limits . Published free limits: 30 RPM, 1000 RPD, 8000 TPM, 200000 TPD. Actual account limits take precedence. Shared organization quotas make unlimited free public usage impossible.

## Render-only setup
Verify the Groq organization is actually on Free before setting `GROQ_FREE_PLAN_CONFIRMED=true`. This flag is an operator assertion, NOT a billing API check or spending cap. Never enable it on an unverified/paid organization. No payment settings are changed by this code.
Set `GROQ_API_KEY` and a separately generated `FOTIQ_AI_EVAL_TOKEN` in Render Environment, never GitHub, iOS or chat. Enable private evaluation with `FOTIQ_AI_EVAL_ENABLED=true` only after that verification. Leave disabled until credentials are configured. No automatic paid model fallback, retries or paid subscription creation.

Every accepted question loads API-Football via uncached provider.load first; upstream failure blocks analysis. Each answer uses a separate Groq call. No answer cache or history persistence. Response includes retrieval timestamp, generation timestamp and quota headers; retrieval time is not the upstream measurement time. 429 returns AI_FREE_QUOTA_REACHED and Retry-After; if Groq omits its reset, 60 seconds is a retry interval, not a promised quota reset. No automatic request is scheduled. Existing API budget also applies.

## Coverage and limits
Current private prototype is match-scoped: fixture, teams, score, events, lineups and aggregate stats. Club season statistics, individual player statistics, comparisons across fixtures and prediction sources are NOT integrated yet. Missing facts and numerical odds must be declined. Instructions discourage hallucination but do not guarantee factual accuracy. No claim that real Groq answers have been tested yet.

Before public adoption: evaluate Arabic/English groundedness on a live match, a finished match and absent-data fixture; compare candidates blindly for factual support, tactical usefulness and uncertainty; reject unsupported claims and prompt injection; measure latency/token usage on Render Free. Inspect current provider lineups/stats against every numerical assertion. Implement public abuse controls and durable shared quota accounting before removing evaluator authentication. Process-local cooldown is not a durable global quota tracker. Test the iOS quota/error presentation before enabling UI. Obtain user approval after sharing actual results.
