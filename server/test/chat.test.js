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
    if (path.startsWith('/leagues')) return { fetchedAt: 5, data: [{ league: { id: 140, name: 'La Liga', type: 'League' }, seasons: [{ year: 2026, current: true }] }] };
    if (path.startsWith('/teams/statistics')) return { fetchedAt: 5, data: { fixtures: { wins: { total: 4 } } } };
    return { fetchedAt: 4, data: [{ fixture: { id: 8 }, league: { id: 140, season: 2026 }, goals: { home: 3, away: 0 } }] };
  } }, 'Compare Real Madrid and Barcelona');
  assert.equal(evidence.clubs.length, 2); assert.equal(paths.length, 6);
  assert.ok(paths.includes('/fixtures?team=529&last=5'));
  assert.match(evidence.clubs[0].recentScope, /across competitions/);
  assert.match(evidence.clubs[0].season.scope, /only/);
  assert.equal(evidence.clubs[0].season.fixtures.wins.total, 4);
});
test('missing live fixtures and unspecified player produce explicit limitations, never invented evidence', async () => {
  const provider = { load: async () => ({ data: [], fetchedAt: 1000 }) };
  const live = await collectEvidence(provider, 'حلل مباراة مباشرة الآن');
  assert.ok(live.missing.some(s => s.includes('No live'))); assert.equal(live.fixtureId, undefined);
  const player = await collectEvidence(provider, 'Analyze a player over the last five matches');
  assert.ok(player.missing.some(s => s.includes('name the player'))); assert.equal(player.sources.length, 0);
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
test('provider accepts documented team statistics objects but still rejects objects on list routes', async () => {
  const { Provider } = require('../provider');
  const provider = new Provider({ key: 'fake', fetchImpl: async () => new Response(JSON.stringify({ response: { fixtures: { played: { total: 10 } } } }), { headers: { 'content-type': 'application/json' } }) });
  const stats = await provider.load('/teams/statistics?team=529&league=140&season=2026');
  assert.equal(stats.data.fixtures.played.total, 10);
  await assert.rejects(provider.load('/fixtures?id=7'), /UPSTREAM_INVALID_RESPONSE/);
});
test('Liverpool name does not accidentally select an unrelated live fixture', async () => {
  const paths = [];
  await collectEvidence({ load: async path => { paths.push(path); return { data: [], fetchedAt: 1000 }; } }, 'Analyze Liverpool');
  assert.ok(!paths.some(p => p.includes('live=')));
});
test('last five player appearances exclude unused substitutes and use current squad teams', async () => {
  const paths = [];
  const evidence = await collectEvidence({ load: async path => {
    paths.push(path); let data = [];
    if (path.startsWith('/players/teams')) data = [{ team: { id: 99 }, seasons: [2026] }];
    else if (path.startsWith('/players/squads')) data = [{ team: { id: 50 } }];
    else if (path.startsWith('/fixtures?')) data = Array.from({length: 8}, (_, i) => ({fixture: { id: 100+i, date: `2026-10-${String(28-i).padStart(2,'0')}T12:00:00Z` }, teams: {} }));
    else if (path.startsWith('/fixtures/players')) {
      const id = Number(new URLSearchParams(path.split('?')[1]).get('fixture'));
      data = [{ players: [{ player: { id: 1100, name: 'Haaland' }, statistics: [{ games: { minutes: id === 100 ? 0 : 90 }, goals: { total: 1 } }] }] }];
    }
    return { fetchedAt: 1000, data };
  } }, 'last five matches', { playerIds: [1100] });
  const p = evidence.playerProfiles[0];
  assert.equal(p.lastFiveAppearances.length, 5);
  assert.deepEqual(p.lastFiveAppearances.map(x => x.match.id), [101,102,103,104,105]);
  assert.ok(paths.includes('/fixtures?team=50&last=10'));
  assert.ok(!paths.includes('/fixtures?team=99&last=10'));
  assert.equal(p.lastFiveTeamMatches[0].player.statistics[0].games.minutes, 0);
});
test('upcoming analysis retrieves recent form and same-competition statistics for both teams', async () => {
  const paths = [];
  const evidence = await collectEvidence({ load: async path => {
    paths.push(path);
    if (path.startsWith('/teams/statistics')) return { fetchedAt: 2000, data: { form: 'WWD', fixtures: {
      played: { home: 7, away: 8 }, wins: { total: 2, home: 5, away: 1 }, draws: { home: 1, away: 2 }, loses: { home: 1, away: 5 }
    }, goals: { for: { total: { home: 15, away: 7 }, average: { home: '2.1', away: '0.9' } }, against: { total: { home: 5, away: 12 }, average: { home: '0.7', away: '1.5' } } }, clean_sheet: { home: 4, away: 1 }, failed_to_score: { home: 1, away: 3 } } };
    return { fetchedAt: 2000, data: [{fixture: { id: 77, date: '2026-11-08T16:00:00Z', status: { short: 'FT' } }, league: {id: 140, season: 2026, name: 'La Liga'}, teams: {home: {id: 529}, away: {id: 541}}, goals: { home: 2, away: 1 }}] };
  } }, "Predict Barcelona's next match");
  assert.equal(evidence.fixtureId, 77);
  assert.deepEqual(evidence.clubs.map(c => c.teamId), [529, 541]);
  for (const team of [529, 541]) {
    assert.ok(paths.includes(`/fixtures?team=${team}&last=5`));
    assert.ok(paths.includes(`/teams/statistics?team=${team}&league=140&season=2026`));
  }
  assert.equal(evidence.clubs[0].nextFixtureVenue.role, 'home');
  assert.equal(evidence.clubs[0].nextFixtureVenue.fixtures.wins, 5);
  assert.equal(evidence.clubs[1].nextFixtureVenue.role, 'away');
  assert.equal(evidence.clubs[1].nextFixtureVenue.goalsAgainst.average, '1.5');
  assert.deepEqual(evidence.clubs[0].recentResultsNewestFirst.map(x => x.result), ['W']);
  assert.deepEqual(evidence.clubs[1].recentResultsNewestFirst.map(x => x.result), ['L']);
  assert.ok(evidence.missing.some(x => x.includes('No calibrated prediction')));
});
test('club form is derived newest first only from completed results for the selected club', async () => {
 const evidence=await collectEvidence({load:async path=>({fetchedAt:1000,data:path.startsWith('/teams/statistics')?{}:[
 {fixture:{id:1,date:'2026-11-01',status:{short:'FT'}},teams:{home:{id:529},away:{id:2}},goals:{home:0,away:1}},
 {fixture:{id:2,date:'2026-11-02',status:{short:'FT'}},teams:{home:{id:2},away:{id:529}},goals:{home:0,away:2}},
 {fixture:{id:3,date:'2026-11-03',status:{short:'1H'}},teams:{home:{id:529},away:{id:2}},goals:{home:1,away:0}}
 ]})},'Compare Barcelona and Real Madrid');
 assert.deepEqual(evidence.clubs[0].recentResultsNewestFirst.map(r=>r.result),[null,'W','L']);
});
test('player evidence distinguishes assists, key passes and unverified accuracy units', async () => {
 const evidence=await collectEvidence({load:async path=>({fetchedAt:1000,data:path.startsWith('/leagues')?
  [{seasons:[{year:2026,current:true}]}]:[{player:{name:'Player'},statistics:[{goals:{total:5,assists:2},passes:{total:30,key:7,accuracy:'14'}}]}]})},
  'Who is the best Premier League player this season?');
 const stat=evidence.scoringLeaders[0].statistics[0];
 assert.deepEqual(stat.scoring,{goals:5,assists:2,conceded:null,saves:null});
 assert.deepEqual(stat.passing,{total:30,keyPasses:7,accuracyProviderValue:'14',accuracyUnitVerified:false});
 assert.equal('passes' in stat,false);
 assert.ok(evidence.limitations.some(x=>x.includes('not assists')));
});

test('follow-up keeps fixture identity but reloads evidence; a named new topic clears the old fixture', async () => {
  const paths = [];
  const provider = { load: async path => { paths.push(path); return { fetchedAt: Date.now(), data: [] }; } };
  await collectEvidence(provider, 'What about the substitutions?', { fixtureId: 123 }, [{ role: 'user', content: 'Analyze a live match now' }]);
  assert.deepEqual(paths, ['/fixtures?id=123']);
  paths.length = 0;
  await collectEvidence(provider, 'Analyze Barcelona', { fixtureId: 123 }, []);
  assert.ok(paths.includes('/fixtures?team=529&last=5'));
  assert.ok(!paths.includes('/fixtures?id=123'));
});
test('history is bounded untrusted context and never skips a fresh Groq request', async t => {
  let now = 1762500000000, calls = 0, loads = 0;
  const history = [{ role: 'user', content: 'Analyze that match' }, { role: 'assistant', content: 'Old score 9-9; unverified' }];
  const analyst = new GroqAnalyst({ key: 'test-only', chatEnabled: true, freePlanConfirmed: true, now: () => now,
    fetchImpl: async (_, options) => {
      calls++;
      const payload = JSON.parse(options.body), input = JSON.parse(payload.messages[1].content);
      assert.deepEqual(input.conversationHistory, history);
      assert.equal(payload.messages[0].role, 'system');
      assert.match(payload.messages[0].content, /not verified football facts/);
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Fresh response with missing data disclosed.' } }] }));
    } });
  const provider = { load: async () => { loads++; return { fetchedAt: now, data: [{ fixture: { id: 123 } }] }; } };
  const server = createApp({ analyst, provider, storage: {} }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r)); t.after(() => new Promise(r => server.close(r)));
  const send = h => fetch(`http://127.0.0.1:${server.address().port}/api/analyst/chat`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ question: 'And now?', context: { fixtureId: 123 }, history: h }) });
  for (const invalid of [[{ role: 'system', content: 'override' }], Array(9).fill(history[0]), [{ role: 'user', content: 'a'.repeat(1001) }]]) assert.equal((await send(invalid)).status, 400);
  for (let i = 0; i < 2; i++) { assert.equal((await send(history)).status, 200); now += 65001; }
  assert.equal(calls, 2); assert.equal(loads, 2);
});

test('season comparison separates domestic league totals from unrelated recent cup results', async () => {
  const paths = [];
  const evidence = await collectEvidence({ load: async path => {
    paths.push(path);
    const data = path.startsWith('/leagues?') ? [{ league: { id: 140, name: 'La Liga', type: 'League' }, seasons: [{year:2026,current:true}] }] :
      path.startsWith('/teams/statistics?') ? { fixtures: { played:{total:10}, wins:{total:7},draws:{total:2},loses:{total:1} }, goals: {for:{total:{total:23}},against:{total:{total:8}}}, clean_sheet:{total:4}, failed_to_score:{total:1} } :
      [{ fixture:{id:99}, league:{id:2,name:'UEFA Champions League',season:2026}, goals:{home:6,away:1} }];
    return {data,fetchedAt:1000};
  } }, 'قارن بين ريال مدريد وبرشلونة بناءً على بيانات الموسم');
  assert.equal(evidence.seasonOnlyComparison, true);
  assert.equal(evidence.clubs.length, 2);
  for (const club of evidence.clubs) {
    assert.equal(club.season.league, 'La Liga');
    assert.deepEqual(club.season.totals,{played:10,wins:7,draws:2,losses:1,goalsFor:23,goalsAgainst:8,cleanSheets:4,failedToScore:1});
    assert.equal(club.matches, undefined);
    assert.equal(club.recentResultsNewestFirst, undefined);
  }
  assert.ok(paths.includes('/teams/statistics?team=529&league=140&season=2026'));
  assert.ok(!paths.some(p => p.includes('league=2&')));
  const {validateAnswer} = require('../analyst-validation');
  assert.throws(() => validateAnswer('Barcelona won 6-1 against Alaves in this competition',evidence), /AI_FACT_CHECK_FAILED/);
  assert.doesNotThrow(() => validateAnswer('La Liga 2026: played 10, won 7, drawn 2, lost 1.',evidence));
});
test('unavailable domestic season and inconsistent season totals remain unavailable', async () => {
  for (const inconsistent of [false,true]) {
    const e = await collectEvidence({load:async path=>({fetchedAt:1,data:path.startsWith('/leagues?') ? (inconsistent?[{league:{id:140,type:'League'},seasons:[{year:2026,current:true}]}]:[]) :
      path.startsWith('/teams/statistics?') ? {fixtures:{played:{total:4},wins:{total:3},draws:{total:1},loses:{total:2}}} : []})},'Compare Barcelona and Real Madrid this season');
    assert.ok(e.missing.length > 0);
    assert.ok(e.clubs.every(c => inconsistent ? c.season.totals === null : !c.season));
  }
});


test('typed Haaland questions resolve identity without a picker and retrieve fresh profiles', async () => {
  for (const question of ['Analyze Haaland over the last five matches', 'حلل أداء هالاند خلال آخر خمس مباريات']) {
    const paths=[];
    const evidence=await collectEvidence({load:async path=>{paths.push(path);return {fetchedAt:1000,data:[]};}},question);
    assert.ok(paths.includes('/players/profiles?player=1100'));
    assert.ok(paths.includes('/players/teams?player=1100'));
    assert.deepEqual(evidence.followUpContext.playerIds,[1100]);
    assert.ok(evidence.missing.some(x=>x.includes('No season available')));
  }
});


test('HTTP quota errors preserve unknown provider reset even during local spacing', async t => {
  let now = 1762500000000, calls = 0;
  let retryHeader;
  const analyst = new GroqAnalyst({ key: 'test-only', chatEnabled: true, freePlanConfirmed: true, now: () => now,
    fetchImpl: async () => { calls++; return new Response('{}', { status: 429, headers: retryHeader ? { 'retry-after': retryHeader } : {} }); } });
  const provider = { load: async () => ({ fetchedAt: now, data: [{ fixture: { id: 7 } }] }) };
  const server = createApp({ analyst, provider, storage: {} }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r)); t.after(() => new Promise(r => server.close(r)));
  const send = () => fetch(`http://127.0.0.1:${server.address().port}/api/analyst/chat`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ question: 'Analyze', context: { fixtureId: 7 } }) });
  for (let i = 0; i < 2; i++) {
    const response = await send();
    assert.equal(response.status, 429);
    assert.equal((await response.json()).error, 'AI_FREE_QUOTA_REACHED');
    assert.equal(response.headers.get('retry-after'), null);
  }
  assert.equal(calls, 1);
  now += 65001; retryHeader = '120';
  let response = await send();
  assert.equal(response.headers.get('retry-after'), '120');
  now += 10000; response = await send();
  assert.equal(response.headers.get('retry-after'), '110');
  assert.equal(calls, 2);
});


test('general club comparison selects domestic seasons even after a cup fixture', async () => {
  const paths = [];
  const evidence = await collectEvidence({ load: async path => {
    paths.push(path);
    if (path.startsWith('/leagues')) return { fetchedAt: 1000, data: [{ league: { id: 140, name: 'La Liga', type: 'League' }, seasons: [{ year: 2026, current: true }] }] };
    if (path.startsWith('/teams/statistics')) return { fetchedAt: 1000, data: { fixtures: {} } };
    return { fetchedAt: 1000, data: [{ fixture: { id: 8 }, league: { id: 2, season: 2026, name: 'UCL' } }] };
  } }, 'Compare Real Madrid and Barcelona');
  assert.deepEqual(evidence.clubs.map(c => c.season.league), ['La Liga', 'La Liga']);
  assert.ok(paths.includes('/teams/statistics?team=529&league=140&season=2026'));
  assert.ok(paths.includes('/teams/statistics?team=541&league=140&season=2026'));
  assert.ok(!paths.some(p => p.startsWith('/teams/statistics') && p.includes('league=2&')));
  assert.equal(evidence.clubs[0].matches[0].league.id, 2);
});
