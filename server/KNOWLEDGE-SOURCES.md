# Source integration status — 2026-11-09

- API-Football: existing live/fixture/season data adapter; account key stays server-side. No new subscription.
- Wikidata structured facts: CC0, https://www.wikidata.org/wiki/Wikidata:Licensing ; access policy https://www.wikidata.org/wiki/Wikidata:Data_access . Initial adapter is deliberately limited to FC Barcelona (Q7156), Gregorian day-precision foundation date. Includes entity URL, revision, modified time and retrieval time; 24-hour fact cache, six-second timeout, 429 cooldown, no stale fallback, no AI-answer cache. Other historical questions explicitly report missing mapping. Python HTTP retrieval confirmed the entity and date 1899-11-29. Real Node-adapter retrieval passed in GitHub run 42611291680: revision 2562671913, retrieved 2026-11-09T11:43:44.702Z (artifact 13670836305 inspected). Local Node hit its six-second deadline; Render/native integration is not yet verified. Separate unit tests use controlled responses.
- UEFA: https://www.uefa.com/termsconditions/ explicitly prohibits systematic automated content collection. Not integrated.
- BBC syndication: official API documentation https://information-syndication.stage.api.bbc.com/ requires an existing relationship/contract and API key. No contract/key available; not integrated. RSS availability alone is not a licence for AI ingestion.
- FIFA: https://inside.fifa.com/terms-of-service sections 5.3 and 6 restrict content reuse; no specific permitted API/ingestion agreement has been established for FOTIQ, so not integrated.
- ESPN, continental/local associations, club announcements, injury/news feeds and advanced-statistics datasets: not connected; per-source licensing and technical suitability still unverified. No claim that websites are unavailable or that all reuse is prohibited.

Historical routing does not provide live news, confirmed transfers, injuries, complete trophy histories or a global entity search. Expand only after reviewing access/reuse terms and testing real responses. Never present this initial connector as comprehensive worldwide coverage.

Quality guard: null assist metadata cannot establish a solo goal or defensive mistake. A deterministic bilingual rejection covers the observed failure; free-form fact checking is still incomplete, not a guarantee that all numbers or causal claims are verified.

Current transfer/injury/news/trend questions explicitly receive missing-announcement evidence until an appropriately licensed source is connected. Unrelated fixtures are not used to imply an official announcement.
