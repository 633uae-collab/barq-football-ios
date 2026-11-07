'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { openStorage } = require('../storage');
const { Observations } = require('../observations');
const { createApp } = require('../app');
const N = require('../normalize');
const fixture = require('./real-fixture.json');
function detail(at, shots = 0) {
  const m = N.fixture(fixture); m.status = { short: '1H', elapsed: 20 };
  return { match: m, events: fixture.events, lineups: [], fetchedAt: at, stale: false,
    statistics: [m.home, m.away].map((team, i) => ({ team, statistics: [{ type: 'Shots on Goal', value: i ? 0 : shots }] })) };
}
test('analysis requires eight observed minutes, real numeric stats and fresh same-half data', t => {
  const storage = openStorage(':memory:'); t.after(() => storage.close());
  let clock = 1000000; const o = new Observations(storage, { now: () => clock });
  const first = detail(clock); assert.deepEqual(o.analyze(first).insights, []);
  clock += 480000; const last = detail(clock, 3);
  const r = o.analyze(last); assert.equal(r.insights.length, 1);
  assert.equal(r.insights[0].nums.observedMinutes, 8); assert.equal(r.insights[0].nums.shotsOnGoal, 3);
  assert.equal(r.insights[0].fixture, first.match.id);
  assert.deepEqual(o.analyze({ ...last, stale: true }).insights, []);
  assert.deepEqual(o.analyze({ ...last, statistics: [] }).insights, []);
  assert.deepEqual(o.analyze({ ...last, match: { ...last.match, status: { short: '2H', elapsed: 55 } } }).insights, []);
  clock += 180000; assert.equal(o.analyze(last).status, 'stale');
});
test('recordings survive disk reopen, deduplicate provider timestamps and never reconstruct past games', t => {
  const dir = mkdtempSync(join(tmpdir(), 'fotiq-recording-')), path = join(dir, 'db.sqlite');
  let storage = openStorage(path), clock = 1000000;
  t.after(() => { storage.close(); rmSync(dir, { recursive: true, force: true }); });
  let o = new Observations(storage, { now: () => clock });
  const first = detail(clock); o.record(first); o.record(first);
  assert.equal(o.list().length, 0);
  clock += 30000; const second = detail(clock, 2); o.record(second);
  assert.equal(o.list()[0].steps, 2);
  storage.close(); storage = openStorage(path); o = new Observations(storage, { now: () => clock });
  assert.deepEqual(o.replay(first.match.id, 0).events, first.events);
  assert.equal(o.replay(first.match.id, 1).statistics[0].statistics[0].value, 2);
  assert.throws(() => o.replay(first.match.id, 2), /REPLAY_STEP_NOT_RECORDED/);
  o.record({ ...second, match: { ...second.match, id: 987654, status: { short: 'FT' } } });
  assert.throws(() => o.replay(987654, 0), /REPLAY_STEP_NOT_RECORDED/);
  clock += 86400001; assert.deepEqual(o.list(), []);
});
test('recording memory is bounded and stale/oversized payloads are excluded', t => {
  const storage = openStorage(':memory:'); t.after(() => storage.close());
  let clock = 1000000; const o = new Observations(storage, { now: () => clock });
  for (let i = 0; i < 270; i++) { clock += 30000; o.record(detail(clock)); }
  assert.equal(o.list()[0].steps, 256);
  clock += 30000;
  o.record({ ...detail(clock), stale: true });
  o.record({ ...detail(clock), events: ['x'.repeat(140000)] });
  assert.equal(o.list()[0].lastAt, clock - 30000);
});
test('mounted analyst and replay routes use observed provider payloads and preserve upstream errors', async t => {
  const storage = openStorage(':memory:'); let clock = 1000000, fail = false;
  const o = new Observations(storage, { now: () => clock });
  const provider = { key: 'test', get: async () => {
    if (fail) throw new (require('../provider').ServiceError)('UPSTREAM_UNAVAILABLE');
    const f = structuredClone(fixture); f.fixture.status = { short: '1H', elapsed: 20 };
    return { data: [f], fetchedAt: clock, stale: false };
  } };
  const server = createApp({ provider, storage, observations: o, storageMode: 'preview' }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  t.after(async () => { await new Promise(r => server.close(r)); storage.close(); });
  const url = `http://127.0.0.1:${server.address().port}`;
  const call = async path => { const r = await fetch(url + path); return [r.status, await r.json()]; };
  assert.equal((await call('/healthz'))[1].replayPersistent, false);
  assert.equal((await call('/api/feed'))[1].tracking, 1);
  clock += 30000;
  assert.equal((await call(`/api/insights/${fixture.fixture.id}`))[0], 200);
  assert.equal((await call('/api/replay'))[1][0].steps, 2);
  assert.equal((await call(`/api/replay/${fixture.fixture.id}/0`))[1].match.id, fixture.fixture.id);
  assert.equal((await call(`/api/replay/${fixture.fixture.id}/-1`))[0], 400);
  fail = true; assert.equal((await call('/api/feed'))[0], 503);
});
