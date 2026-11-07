const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { createApp } = require('../app');
const { openStorage } = require('../storage');
const { Provider } = require('../provider');
const fixture = require('./real-fixture.json');
async function harness(t, fetchImpl, storageMode = 'persistent') {
  const folder = mkdtempSync(join(tmpdir(), 'fotiq-test-')), path = join(folder, 'prefs.sqlite');
  const storage = openStorage(path), calls = [];
  const provider = new Provider({ key: 'test-only', fetchImpl: async (url, opts) => {
    calls.push(url);
    if (fetchImpl) return fetchImpl(url, opts);
    const u = new URL(url); let response = [];
    if (u.pathname === '/fixtures' || u.pathname === '/fixtures/headtohead') response = [fixture];
    if (u.pathname === '/leagues') response = [{ league: { id: 39, name: 'Premier League', type: 'League' }, country: { name: 'England' }, seasons: [{ year: 2025, current: true }] }];
    if (u.pathname === '/teams') response = [{ team: { id: 40, name: 'Liverpool' }, venue: { name: 'Anfield' } }];
    if (u.pathname === '/standings') response = [{ league: { id: 39, name: 'Premier League', standings: [[{ rank: 1, team: { id: 40, name: 'Liverpool' }, points: 9 }]] } }];
    if (u.pathname === '/players/squads') response = [{ players: [{ id: 1, name: 'Test player', position: 'Attacker' }] }];
    if (u.pathname === '/players/seasons') response = [2024, 2025];
    if (u.pathname === '/players') response = [{ player: { id: 1, name: 'Test player' }, statistics: [] }];
    if (u.pathname === '/predictions') response = [{ predictions: { percent: { home: '50%', away: '25%', draw: '25%' } } }];
    return new Response(JSON.stringify({ errors: [], response }), { headers: { 'content-type': 'application/json' } });
  } });
  const server = createApp({ provider, storage, storageMode }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  t.after(async () => { await new Promise(r => server.close(r)); storage.close(); rmSync(folder, { recursive: true, force: true }); });
  return { storage, calls, path, request: async (url, options) => {
    const r = await fetch(`http://127.0.0.1:${server.address().port}${url}`, options);
    assert.match(r.headers.get('content-type'), /application\/json/);
    return { status: r.status, body: await r.json() };
  } };
}
test('real captured fixture is normalized for SwiftUI rather than exposing provider envelope', async t => {
  const h = await harness(t);
  const r = await h.request('/api/fixtures?date=2026-11-01');
  assert.equal(r.status, 200); assert.equal(r.body.date, '2026-11-01');
  const f = r.body.fixtures[0]; assert.equal(f.id, fixture.fixture.id);
  assert.equal(f.home.name, fixture.teams.home.name); assert.equal(f.ts, fixture.fixture.timestamp);
  assert.equal(f.status.short, 'FT'); assert.equal(f.fixture, undefined);
  const m = await h.request(`/api/match/${f.id}`); assert.equal(m.body.events.length, fixture.events.length);
});
test('catalog, current-season standings, teams and Arabic club search match client contracts', async t => {
  const h = await harness(t);
  const c = await h.request('/api/catalog'); assert.equal(c.body.leagues[0].season, 2025);
  const s = await h.request('/api/standings/39'); assert.equal(s.body.groups[0][0].team.id, 40);
  assert.ok(h.calls.some(url => url.includes('league=39&season=2025')));
  const team = await h.request('/api/team/40'); assert.equal(team.body.team.id, 40); assert.equal(team.body.squad[0].pos, 'Attacker');
  const search = await h.request('/api/search?q=' + encodeURIComponent('ليفربول'));
  assert.equal(search.body.teams[0].id, 40); assert.equal(search.body.translated, 'Liverpool');
  assert.ok(h.calls.some(url => url.includes('search=Liverpool')));
});
test('all restored read routes return JSON and explicitly missing originals return 503 JSON', async t => {
  const h = await harness(t);
  for (const path of ['/healthz', '/api/h2h/40/50', '/api/predictions/1', '/api/topscorers/39', '/api/topassists/39', '/api/league/39', '/api/player/1', '/api/stars'])
    assert.equal((await h.request(path)).status, 200, path);
  for (const path of ['/api/feed', '/api/insights/1', '/api/replay', '/api/replay/1/0']) {
    const r = await h.request(path); assert.equal(r.status, 503, path); assert.ok(r.body.error);
  }
  assert.equal((await h.request('/api/push/register', { method: 'POST' })).status, 503);
  assert.equal((await h.request('/api/push/test-device', { method: 'DELETE' })).status, 503);
});
test('favorites are durable, invalid snapshots cannot erase them, and unrelated devices remain separate', async t => {
  const h = await harness(t), device = 'test-device-1234';
  const body = { favTeams: [40], favLeagues: [39], saved: [123], muted: [], level: 1 };
  const put = value => h.request(`/api/prefs/${device}`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(value) });
  assert.deepEqual(await put(body), { status: 200, body: { ok: true } });
  assert.equal((await put({ favTeams: [] })).status, 400);
  assert.equal((await put({ ...body, favTeams: ['40'] })).status, 400);
  // Reopen the on-disk DB with a second connection, independent of app memory.
  const restored = openStorage(h.path);
  assert.deepEqual(JSON.parse(restored.q('SELECT body FROM prefs WHERE device=?', [device])[0].body), body);
  assert.equal(restored.q('SELECT body FROM prefs WHERE device=?', ['another-device']).length, 0);
  restored.close();
});
test('validation and malformed JSON return JSON errors without hitting API-Football', async t => {
  const h = await harness(t);
  for (const path of ['/api/team/no', '/api/fixtures?date=2026-02-30', '/api/standings/39?season=abc', '/api/search?q[a]=x'])
    assert.equal((await h.request(path)).status, 400, path);
  assert.equal(h.calls.length, 0);
  assert.equal((await h.request('/api/prefs/test-device', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: '{broken' })).status, 400);
  assert.equal((await h.request('/unrecognized')).status, 404);
});
test('provider outage returns 503 JSON and never fake fixtures', async t => {
  const h = await harness(t, async () => new Response('Site Unavailable', { status: 503 }));
  const r = await h.request('/api/fixtures'); assert.equal(r.status, 503);
  assert.equal(r.body.error, 'UPSTREAM_UNAVAILABLE'); assert.equal(r.body.fixtures, undefined);
});

test('free preview never acknowledges or stores preferences and still serves match data', async t => {
  const h = await harness(t, undefined, 'preview');
  const response = await h.request('/api/prefs/preview-device', { method: 'PUT', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ favTeams: [40], favLeagues: [], saved: [], muted: [], level: 1 }) });
  assert.equal(response.status, 503);
  assert.equal(response.body.error, 'PREFERENCES_SYNC_REQUIRES_PERSISTENT_STORAGE');
  assert.equal(h.storage.q('SELECT * FROM prefs').length, 0);
  assert.equal((await h.request('/healthz')).body.preferencesSync, false);
  assert.equal((await h.request('/api/fixtures')).status, 200);
});
