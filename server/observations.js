'use strict';
const { createHash } = require('node:crypto');
const { ServiceError } = require('./provider');
const live = new Set(['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE']);

// Only actual provider observations are stored. No interpolated events or invented history.
class Observations {
  constructor(storage, { now = Date.now } = {}) {
    this.storage = storage; this.now = now;
    storage.db.run('CREATE TABLE IF NOT EXISTS observations(seq INTEGER PRIMARY KEY, fixture INTEGER NOT NULL, at INTEGER NOT NULL, body TEXT NOT NULL)');
    storage.db.run('CREATE INDEX IF NOT EXISTS observations_fixture ON observations(fixture, seq)');
  }
  prune() {
    this.storage.db.run('DELETE FROM observations WHERE at < ?', [this.now() - 86400000]);
    // <= 32 MiB of payload, including in free preview memory; bounded independently of traffic.
    this.storage.db.run('DELETE FROM observations WHERE seq NOT IN (SELECT seq FROM observations ORDER BY seq DESC LIMIT 256)');
  }
  record(detail) {
    if (detail.stale || !Number.isSafeInteger(detail.fetchedAt) || detail.fetchedAt > this.now()
      || this.now() - detail.fetchedAt > 120000) return;
    this.prune();
    const previous = this.storage.q('SELECT at FROM observations WHERE fixture=? ORDER BY seq DESC LIMIT 1', [detail.match.id])[0];
    if (previous && detail.fetchedAt - previous.at < 15000) return;
    // Record a terminal snapshot only if this server actually followed the match live.
    if (!live.has(detail.match.status.short) && !previous) return;
    const body = JSON.stringify(detail);
    if (Buffer.byteLength(body) > 128 * 1024) return;
    this.storage.db.run('INSERT INTO observations(fixture,at,body) VALUES(?,?,?)', [detail.match.id, detail.fetchedAt, body]);
    this.prune();
  }
  list() {
    this.prune();
    return this.storage.q('SELECT fixture AS id, COUNT(*) AS steps, MIN(at) AS startedAt, MAX(at) AS lastAt FROM observations GROUP BY fixture HAVING COUNT(*) >= 2 ORDER BY lastAt DESC');
  }
  replay(id, step) {
    this.prune();
    const row = this.storage.q('SELECT body FROM observations WHERE fixture=? ORDER BY seq LIMIT 1 OFFSET ?', [id, step])[0];
    if (!row) throw new ServiceError('REPLAY_STEP_NOT_RECORDED', 404);
    return { ...JSON.parse(row.body), recorded: true, source: 'API-Football observation' };
  }
  analyze(detail) {
    this.record(detail);
    const m = detail.match;
    const result = { status: detail.stale ? 'stale' : live.has(m.status.short) ? 'tracking' : 'not_tracked',
      minute: m.status.elapsed, lastAt: detail.fetchedAt, insights: [], engine: 'statistical-rules-v1' };
    if (result.status !== 'tracking' || this.now() - detail.fetchedAt > 120000) return { ...result, status: detail.stale || live.has(m.status.short) ? 'stale' : 'not_tracked' };
    const previous = this.storage.q('SELECT body FROM observations WHERE fixture=? AND at<=? AND at>=? ORDER BY at DESC LIMIT 1',
      [m.id, detail.fetchedAt - 480000, detail.fetchedAt - 720000])[0];
    if (!previous) return result;
    const old = JSON.parse(previous.body);
    // Do not compare different halves, resets, missing fields, or stale snapshots.
    if (old.match.status.short !== m.status.short || old.stale) return result;
    const stat = (d, team, type) => {
      const v = d.statistics?.find(x => x.team?.id === team)?.statistics?.find(x => x.type === type)?.value;
      return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
    };
    for (const [team, opponent] of [[m.home, m.away], [m.away, m.home]]) {
      const values = [stat(detail, team.id, 'Shots on Goal'), stat(old, team.id, 'Shots on Goal'),
        stat(detail, opponent.id, 'Shots on Goal'), stat(old, opponent.id, 'Shots on Goal')];
      if (values.some(v => v === null)) continue;
      const shots = values[0] - values[1], against = values[2] - values[3];
      if (shots < 3 || against < 0 || shots - against < 2) continue;
      const minutes = Math.round((detail.fetchedAt - old.fetchedAt) / 60000);
      const insightId = parseInt(createHash('sha256').update(`${m.id}:${team.id}:pressure:${detail.fetchedAt}`).digest('hex').slice(0, 12), 16);
      result.insights.push({ id: insightId, fixture: m.id, minute: m.status.elapsed || 0, type: 'pressure', level: 'info', team: team.name,
        title: `تفوق في التسديد على المرمى: ${team.name}`,
        body: `سجّل ${team.name} ${shots} تسديدات على المرمى مقابل ${against} خلال آخر ${minutes} دقائق مرصودة. قراءة إحصائية وليست توقعاً بتسجيل هدف.`,
        nums: { shotsOnGoal: shots, opponentShotsOnGoal: against, observedMinutes: minutes, source: 'API-Football', engine: 'statistical-rules-v1' },
        at: detail.fetchedAt, match: { home: m.home.name, away: m.away.name, homeLogo: m.home.logo, awayLogo: m.away.logo,
          league: m.league.name, score: `${m.goals.home ?? '-'} - ${m.goals.away ?? '-'}` } });
    }
    return result;
  }
}
module.exports = { Observations, live };
