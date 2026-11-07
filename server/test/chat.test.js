const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../app');
const { GroqAnalyst } = require('../groq');
const { collectEvidence } = require('../chat-evidence');
test('chat rejects disabled access, arbitrary context and quota bypass; each accepted send is fresh', async t => {
  let now = 1762500000000, loads = 0, generations = 0;
  const analyst = new GroqAnalyst({ key: 'private-secret', chatEnabled: false, freePlanConfirmed: true, now: () => now,
    fetchImpl: async (_url, options) => {
      generations++;
      assert.equal(JSON.parse(options.body).model, 'openai/gpt-oss-120b');
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Verified analysis' } }] }));
    } });
  const provider = { load: async () => { loads++; return { fetchedAt: now, data: [{ fixture: { id: 7, date: new Date(now).toISOString() } }] }; } };
  const server = createApp({ analyst, provider, storage: {} }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r)); t.after(() => new Promise(r => server.close(r)));
  const post = context => fetch(`http://127.0.0.1:${server.address().port}/api/analyst/chat`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ question: 'Analyze', context }) });
  assert.equal((await post({ fixtureId: 7 })).status, 503);
  analyst.chatEnabled = true;
  assert.equal((await post({ facts: 'invented', fixtureId: 7 })).status, 400);
  for (let i = 0; i < 2; i++) {
    const response = await post({ fixtureId: 7 });
    assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.json(); assert.equal(body.model, 'openai/gpt-oss-120b'); assert.ok(!JSON.stringify(body).includes('private-secret'));
    assert.equal((await post({ fixtureId: 7 })).status, 429); now += 65001;
  }
  assert.equal(loads, 2); assert.equal(generations, 2);
});
test('club comparison uses fresh season facts, last match is not silently replaced by a loss', async () => {
  const paths = [];
  const evidence = await collectEvidence({ load: async path => {
    paths.push(path);
    if (path.startsWith('/teams/statistics')) return { fetchedAt: 5, data: { fixtures: { wins: { total: 4 } } } };
    return { fetchedAt: 4, data: [{ fixture: { id: 8 }, league: { id: 140, season: 2026 }, goals: { home: 3, away: 0 } }] };
  } }, 'Compare Real Madrid and Barcelona');
  assert.equal(evidence.clubs.length, 2); assert.equal(paths.length, 4);
  assert.ok(paths.includes('/fixtures?team=529&last=5'));
  assert.equal(evidence.clubs[0].season.fixtures.wins.total, 4);
});
test('missing live fixtures and unspecified player produce explicit limitations, never invented evidence', async () => {
  const provider = { load: async () => ({ data: [], fetchedAt: 1000 }) };
  const live = await collectEvidence(provider, 'حلل مباراة مباشرة الآن');
  assert.ok(live.missing.some(s => s.includes('No live'))); assert.equal(live.fixtureId, undefined);
  const player = await collectEvidence(provider, 'Analyze a player over the last five matches');
  assert.ok(player.missing.some(s => s.includes('select a player'))); assert.equal(player.sources.length, 0);
});
test('player recent fixtures explicitly retain missing appearances', async () => {
  const evidence = await collectEvidence({ load: async path => {
    let data = [];
    if (path.startsWith('/players/teams')) data = [{ team: { id: 50 }, seasons: [2026] }];
    else if (path.startsWith('/fixtures?')) data = [{ fixture: { id: 12 }, teams: {} }];
    return { fetchedAt: 1000, data };
  } }, 'last five matches', { playerIds: [1100] });
  assert.equal(evidence.playerProfiles[0].lastFiveTeamMatches[0].player, null);
  assert.ok(evidence.missing.some(s => s.includes('non-appearances')));
});
