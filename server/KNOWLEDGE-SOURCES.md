# Source integration status — 2026-11-09

- API-Football: existing live/fixture/season data adapter; account key stays server-side. No new subscription.
- Wikidata structured facts: CC0, https://www.wikidata.org/wiki/Wikidata:Licensing ; access policy https://www.wikidata.org/wiki/Wikidata:Data_access . Initial adapter is deliberately limited to FC Barcelona (Q7156), Gregorian day-precision foundation date. Includes entity URL, revision, modified time and retrieval time; 24-hour fact cache, six-second timeout, 429 cooldown, no stale fallback, no AI-answer cache. Other historical questions explicitly report missing mapping. Python HTTP retrieval confirmed the entity and date 1899-11-29; local Node fetch timed out, so Node/Render/native integration is not yet verified. Tests use controlled responses and are not evidence of live connectivity.
- UEFA: https://www.uefa.com/termsconditions/ explicitly prohibits systematic automated content collection. Not integrated.
- BBC syndication: official API documentation https://information-syndication.stage.api.bbc.com/ requires an existing relationship/contract and API key. No contract/key available; not integrated. RSS availability alone is not a licence for AI ingestion.
- FIFA, ESPN, continental/local associations, club announcements, injury/news feeds and advanced-statistics datasets: not connected; per-source licensing and technical suitability still unverified. No claim that websites are unavailable or that all reuse is prohibited.

Historical routing does not provide live news, confirmed transfers, injuries, complete trophy histories or a global entity search. Expand only after reviewing access/reuse terms and testing real responses. Never present this initial connector as comprehensive worldwide coverage.

Quality guard: null assist metadata cannot establish a solo goal or defensive mistake. A deterministic bilingual rejection covers the observed failure; free-form fact checking is still incomplete, not a guarantee that all numbers or causal claims are verified.
