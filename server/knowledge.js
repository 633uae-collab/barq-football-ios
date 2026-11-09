'use strict';
// Structured Wikidata facts are CC0. No articles, logos, news or arbitrary URLs.
// https://www.wikidata.org/wiki/Wikidata:Licensing
// https://www.wikidata.org/wiki/Wikidata:Data_access
const CLUBS = [[/barcelona|برشلونة|برشلونه/i, 'Q7156', 'FC Barcelona', 529]];
class HistoricalKnowledge {
  constructor({ fetchImpl = fetch, now = Date.now } = {}) {
    this.fetch = fetchImpl; this.now = now; this.cache = new Map(); this.blockedUntil = 0;
  }
  async collect(question) {
    if (!/history|historical|founded|foundation|تاريخ|تأسيس|تاسيس|تأسس|تاسس/i.test(question)) return null;
    const club = CLUBS.find(([pattern]) => pattern.test(question));
    const empty = { schema: 'fotiq-licensed-history-v1', events: [], sources: [], missing: [], facts: [] };
    if (!club) return { ...empty, missing: ['No verified historical entity mapping is available for this club.'] };
    const [, id, name, teamId] = club, url = `https://www.wikidata.org/wiki/Special:EntityData/${id}.json`;
    const cached = this.cache.get(id);
    if (cached && this.now() - cached.fetchedAt < 86400000) return structuredClone(cached);
    if (this.now() < this.blockedUntil) return { ...empty, missing: ['Historical source temporarily rate limited; no stale facts supplied.'] };
    try {
      const response = await this.fetch(url, { redirect: 'error', signal: AbortSignal.timeout(6000), headers: {
        'User-Agent': 'FOTIQ/1.0 (https://github.com/633uae-collab/barq-football-ios)', 'Accept': 'application/json'
      }});
      if (response.status === 429) {
        const seconds = Number(response.headers.get('retry-after'));
        this.blockedUntil = this.now() + (Number.isFinite(seconds) && seconds > 0 ? Math.max(60, Math.min(seconds, 86400)) : 300) * 1000;
      }
      if (!response.ok) throw new Error('source unavailable');
      const text = await response.text();
      if (Buffer.byteLength(text) > 2000000) throw new Error('source too large');
      const entity = JSON.parse(text).entities?.[id];
      if (entity?.id !== id || entity.labels?.en?.value !== name) throw new Error('entity mismatch');
      const statements = (entity.claims?.P571 || []).filter(s => s.rank !== 'deprecated' && s.mainsnak?.snaktype === 'value');
      const preferred = statements.filter(s => s.rank === 'preferred');
      const dates = [...new Set((preferred.length ? preferred : statements).map(s => s.mainsnak.datavalue?.value)
        .filter(v => v?.precision === 11 && v.calendarmodel === 'http://www.wikidata.org/entity/Q1985727' && /^\+\d{4}-\d{2}-\d{2}T/.test(v.time)).map(v => v.time.slice(1,11)))];
      const fetchedAt = this.now();
      const result = { ...empty, fetchedAt, retrievedAtUTC: new Date(fetchedAt).toISOString(), followUpContext: { teamIds: [teamId] },
        sources: [{ name: 'Wikidata', url: `https://www.wikidata.org/wiki/${id}`, license: 'CC0', revision: entity.lastrevid, publishedAt: null, modifiedAt: entity.modified, fetchedAt }],
        facts: dates.length === 1 ? [{ subject: name, property: 'foundationDate', value: dates[0] }] : [],
        missing: dates.length === 1 ? ['Only foundation date verified. No wider club history, trophies or current news retrieved.'] : ['Foundation dates conflict or lack day precision; do not choose or invent a date.'] };
      this.cache.set(id, result); return structuredClone(result);
    } catch { return { ...empty, missing: ['Historical source unavailable; no verified historical facts retrieved.'] }; }
  }
}
const historicalKnowledge = new HistoricalKnowledge();
module.exports = { HistoricalKnowledge, historicalKnowledge };
