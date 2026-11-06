'use strict';
const express = require('express');
const { ServiceError } = require('./provider');
const N = require('./normalize');
const TZ = 'Asia/Dubai';
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());
const pathFor = (path, query) => path + '?' + new URLSearchParams(query);
const id = value => {
  if (!/^[1-9]\d{0,9}$/.test(String(value))) throw new ServiceError('INVALID_ID', 400);
  return Number(value);
};
const date = value => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value))
    || new Date(value).toISOString().slice(0, 10) !== value) throw new ServiceError('INVALID_DATE', 400);
  return value;
};
function createApp({ provider, storage }) {
  const app = express(); app.disable('x-powered-by');
  // Random per-install device ID is the existing client's capability. Never enumerate it.
  // No proxy headers trusted here: prevents spoofed addresses bypassing the budget.
  const windows = new Map();
  app.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    res.set('X-Content-Type-Options', 'nosniff');
    const now = Date.now(), ip = req.socket.remoteAddress;
    for (const [key, w] of windows) if (now >= w.until) windows.delete(key);
    const w = windows.get(ip) || { count: 0, until: now + 60000 };
    windows.set(ip, w);
    if (++w.count > 600) { res.set('Retry-After', '60'); return res.status(429).json({ error: 'RATE_LIMITED' }); }
    next();
  });
  app.use(express.json({ limit: '32kb' }));
  const get = async (path, query, ttl = 30000) => provider.get(pathFor(path, query), ttl);
  const catalog = () => get('/leagues', { current: 'true' }, 86400000);
  const currentSeason = async (leagueId, raw) => {
    if (raw !== undefined) {
      if (!/^20\d{2}$/.test(String(raw)) || Number(raw) > new Date().getUTCFullYear() + 1)
        throw new ServiceError('INVALID_SEASON', 400);
      return Number(raw);
    }
    const c = await catalog();
    const year = c.data.find(r => r.league.id === leagueId)?.seasons?.find(s => s.current)?.year;
    if (!year) throw new ServiceError('CURRENT_SEASON_UNAVAILABLE', 404);
    return year;
  };
  app.get('/healthz', (_req, res) => {
    storage.q('SELECT 1');
    res.json({ ok: true, service: 'fotiq-backend', providerConfigured: !!provider.key,
      providerVerified: false, analyst: 'original_engine_missing', replay: 'original_recordings_missing' });
  });
  app.get('/api/catalog', async (_req, res) => {
    const r = await catalog(); const leagues = r.data.map(N.league);
    res.json({ total: leagues.length, leagues, order: leagues.map(l => l.id), fetchedAt: r.fetchedAt, stale: r.stale });
  });
  app.get('/api/fixtures', async (req, res) => {
    const day = date(req.query.date || today());
    const r = await get('/fixtures', { date: day, timezone: TZ });
    res.json({ date: day, fixtures: r.data.map(N.fixture), fetchedAt: r.fetchedAt, stale: r.stale });
  });
  app.get('/api/match/:id', async (req, res) => {
    const r = await get('/fixtures', { id: id(req.params.id), timezone: TZ });
    const f = r.data[0]; if (!f) throw new ServiceError('MATCH_NOT_FOUND', 404);
    res.json({ match: N.fixture(f), events: f.events || [], lineups: f.lineups || [],
      statistics: f.statistics || [], fetchedAt: r.fetchedAt, stale: r.stale });
  });
  app.get('/api/h2h/:home/:away', async (req, res) => {
    const r = await get('/fixtures/headtohead', { h2h: `${id(req.params.home)}-${id(req.params.away)}`, last: 10 }, 3600000);
    res.json({ fixtures: r.data.map(N.fixture), fetchedAt: r.fetchedAt, stale: r.stale });
  });
  app.get('/api/predictions/:id', async (req, res) => {
    const r = await get('/predictions', { fixture: id(req.params.id) }, 900000);
    const p = r.data[0]; if (!p) throw new ServiceError('PREDICTION_NOT_AVAILABLE', 404);
    res.json({ percent: p.predictions?.percent, advice: p.predictions?.advice,
      comparison: p.comparison, teams: p.teams, fetchedAt: r.fetchedAt, stale: r.stale });
  });
  app.get('/api/standings/:id', async (req, res) => {
    const leagueId = id(req.params.id), season = await currentSeason(leagueId, req.query.season);
    const r = await get('/standings', { league: leagueId, season }, 3600000);
    res.json({ league: r.data[0]?.league, groups: r.data[0]?.league?.standings || [], stale: r.stale });
  });
  for (const kind of ['topscorers', 'topassists']) app.get(`/api/${kind}/:id`, async (req, res) => {
    const leagueId = id(req.params.id), season = await currentSeason(leagueId, req.query.season);
    const r = await get(`/players/${kind}`, { league: leagueId, season }, 3600000);
    res.json({ players: r.data.map(N.topPlayer), stale: r.stale });
  });
  app.get('/api/league/:id', async (req, res) => {
    const leagueId = id(req.params.id), season = await currentSeason(leagueId, req.query.season);
    const results = await Promise.all(['next', 'last'].map(k => get('/fixtures', { league: leagueId, season, [k]: 20, timezone: TZ }, 300000)));
    res.json({ next: results[0].data.map(N.fixture), last: results[1].data.map(N.fixture), stale: results.some(r => r.stale) });
  });
  app.get('/api/team/:id', async (req, res) => {
    const team = id(req.params.id);
    const info = await get('/teams', { id: team }, 86400000);
    if (!info.data[0]) throw new ServiceError('TEAM_NOT_FOUND', 404);
    // No silent partial success: retry UI must know when any requested section failed.
    const [next, last, squad, transfers] = await Promise.all([
      get('/fixtures', { team, next: 10, timezone: TZ }, 300000),
      get('/fixtures', { team, last: 10, timezone: TZ }, 300000),
      get('/players/squads', { team }, 86400000), get('/transfers', { team }, 86400000)
    ]);
    res.json({ ...info.data[0], next: next.data.map(N.fixture), last: last.data.map(N.fixture),
      squad: (squad.data[0]?.players || []).map(p => ({ ...p, pos: p.position })),
      transfers: transfers.data.flatMap(p => (p.transfers || []).map(t => ({ player: p.player, date: t.date,
        type: t.type, in: t.teams?.in || {}, out: t.teams?.out || {} }))),
      stale: [info, next, last, squad, transfers].some(r => r.stale) });
  });
  app.get('/api/player/:id', async (req, res) => {
    const player = id(req.params.id);
    let season = req.query.season;
    if (season === undefined) {
      const r = await get('/players/seasons', { player }, 86400000);
      season = Math.max(...r.data.filter(Number.isInteger));
    }
    if (!Number.isInteger(Number(season)) || Number(season) < 2000 || Number(season) > new Date().getUTCFullYear() + 1)
      throw new ServiceError('PLAYER_SEASON_UNAVAILABLE', 404);
    const r = await get('/players', { id: player, season }, 3600000);
    if (!r.data[0]) throw new ServiceError('PLAYER_NOT_FOUND', 404);
    res.json({ player: r.data[0].player, stats: (r.data[0].statistics || []).map(N.playerStat), stale: r.stale });
  });
  app.get('/api/search', async (req, res) => {
    if (typeof req.query.q !== 'string' || req.query.q.trim().length > 80) throw new ServiceError('INVALID_QUERY', 400);
    const q = req.query.q.trim();
    if (q.length < 3) return res.json({ q, teams: [], leagues: [], players: [], matches: [], notes: ['Enter at least 3 characters'] });
    const aliases = { 'برشلونة': 'Barcelona', 'ريال مدريد': 'Real Madrid', 'ليفربول': 'Liverpool', 'مانشستر سيتي': 'Manchester City', 'باريس': 'Paris Saint Germain', 'الهلال': 'Al Hilal', 'النصر': 'Al Nassr', 'العين': 'Al Ain' };
    const search = aliases[q] || q;
    const [teams, leagues] = await Promise.all([get('/teams', { search }, 3600000), get('/leagues', { search }, 3600000)]);
    res.json({ q, translated: search === q ? undefined : search, teams: teams.data.map(t => t.team),
      leagues: leagues.data.map(N.league), players: [], matches: [], stale: teams.stale || leagues.stale,
      notes: ['Player and match search are not restored yet'] });
  });
  app.put('/api/prefs/:device', (req, res) => {
    if (!/^[a-z0-9-]{8,64}$/i.test(req.params.device)) throw new ServiceError('INVALID_DEVICE', 400);
    const b = req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b)) throw new ServiceError('INVALID_PREFERENCES', 400);
    // Require all fields to prevent partial/invalid requests from erasing a durable snapshot.
    for (const name of ['favTeams', 'favLeagues', 'saved', 'muted']) {
      if (!Array.isArray(b[name]) || b[name].length > 500 || b[name].some(x => !Number.isSafeInteger(x) || x <= 0))
        throw new ServiceError('INVALID_PREFERENCES', 400);
    }
    if (![0, 1, 2].includes(b.level)) throw new ServiceError('INVALID_PREFERENCES', 400);
    const body = Object.fromEntries(['favTeams', 'favLeagues', 'saved', 'muted', 'level'].map(k => [k, b[k]]));
    storage.db.run('INSERT INTO prefs(device,body,at) VALUES(?,?,?) ON CONFLICT(device) DO UPDATE SET body=excluded.body,at=excluded.at',
      [req.params.device, JSON.stringify(body), Date.now()]);
    res.json({ ok: true });
  });
  // These originals are absent. Explicit failure preserves the distinction from a working empty feed.
  for (const route of ['/api/feed', '/api/insights/:id']) app.get(route, (_req, res) => res.status(503).json({ error: 'ANALYST_ENGINE_NOT_RESTORED' }));
  for (const route of ['/api/replay', '/api/replay/:id/:step']) app.get(route, (_req, res) => res.status(503).json({ error: 'REPLAY_RECORDINGS_NOT_RESTORED' }));
  for (const method of ['post', 'delete']) app[method](method === 'post' ? '/api/push/register' : '/api/push/:device', (_req, res) =>
    res.status(503).json({ error: 'PUSH_INTEGRATION_NOT_RESTORED' }));
  app.get('/api/stars', async (req, res) => {
    const day = date(req.query.date || today());
    const daily = await get('/fixtures', { date: day, timezone: TZ });
    const started = daily.data.filter(f => ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE', 'FT', 'AET', 'PEN'].includes(f.fixture.status.short))
      .sort((a, b) => b.fixture.timestamp - a.fixture.timestamp).slice(0, 20);
    if (!started.length) return res.json({ date: day, fetchedAt: daily.fetchedAt, stale: daily.stale, players: [] });
    const r = await get('/fixtures', { ids: started.map(f => f.fixture.id).sort((a, b) => a - b).join('-'), timezone: TZ }, 90000);
    const players = [];
    for (const f of r.data) for (const team of f.players || []) for (const p of team.players || []) {
      const s = p.statistics?.[0] || {}, rating = Number(s.games?.rating) || null;
      const goals = s.goals?.total || 0, assists = s.goals?.assists || 0;
      if (goals || assists || rating >= 7.5) players.push({ ...p.player, team: team.team, fixture: f.fixture.id,
        league: f.league.name, live: !['FT', 'AET', 'PEN'].includes(f.fixture.status.short), rating, goals, assists, minutes: s.games?.minutes || 0 });
    }
    const score = p => p.goals * 3 + p.assists * 2 + (p.rating || 0) / 2;
    players.sort((a, b) => score(b) - score(a) || a.id - b.id);
    res.json({ date: day, fetchedAt: r.fetchedAt, stale: r.stale || daily.stale, players: players.slice(0, 10) });
  });
  app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));
  app.use((err, _req, res, _next) => {
    const code = err instanceof ServiceError ? err.code : err.type === 'entity.too.large' ? 'BODY_TOO_LARGE' : err.type === 'entity.parse.failed' ? 'INVALID_JSON' : 'INTERNAL_ERROR';
    const status = err instanceof ServiceError ? err.status : err.type === 'entity.too.large' ? 413 : err.type === 'entity.parse.failed' ? 400 : 500;
    if (status === 429 || status === 503) res.set('Retry-After', '30');
    res.status(status).json({ error: code });
  });
  return app;
}
module.exports = { createApp };
