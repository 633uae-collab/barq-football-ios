// Run: node --test test/   (uses a real finished fixture captured from API-SPORTS via the server cache)
const test = require('node:test'), assert = require('node:assert');
const { detect, liveState } = require('../notify');
const real = require('./real-fixture.json');

const at = (f, status, elapsed, upto) => ({ ...f, fixture: { ...f.fixture, status: { ...f.fixture.status, short: status, elapsed } },
  events: (f.events || []).filter(e => (e.time.elapsed ?? 0) <= upto) });

test('kickoff/HT/2H/FT transitions detected once per phase', () => {
  const ko = detect({ status: 'NS' }, at(real, '1H', 1, 1)).map(e => e.type);
  assert.ok(ko.includes('kickoff'));
  assert.ok(detect({ status: '1H' }, at(real, 'HT', 45, 45)).some(e => e.type === 'ht'));
  assert.ok(detect({ status: 'HT' }, at(real, '2H', 46, 46)).some(e => e.type === 'second'));
  assert.ok(!detect({ status: '2H' }, at(real, '2H', 60, 60)).some(e => e.type === 'second'));
  assert.ok(detect({ status: '2H' }, at(real, 'FT', 90, 200)).some(e => e.type === 'ft'));
});

test('every real goal and red card yields exactly one stable key', () => {
  const goals = real.events.filter(e => e.type === 'Goal' && e.detail !== 'Missed Penalty').length;
  const reds = real.events.filter(e => e.type === 'Card' && /Red/.test(e.detail)).length;
  const ev = detect({ status: '2H' }, at(real, 'FT', 90, 200));
  assert.strictEqual(ev.filter(e => e.type === 'goal').length, goals);
  assert.strictEqual(ev.filter(e => e.type === 'red').length, reds);
  assert.strictEqual(new Set(ev.map(e => e.k)).size, ev.length, 'keys unique');
});

test('dedup: replaying successive polls never re-emits a key', () => {
  const seen = new Set(); let prev = { status: 'NS' }, emitted = [];
  const timeline = [['1H', 1], ['1H', 20], ['1H', 20], ['HT', 45], ['HT', 45], ['2H', 46], ['2H', 70], ['2H', 90], ['FT', 90], ['FT', 90]];
  for (const [st, m] of timeline) {
    for (const e of detect(prev, at(real, st, m, st === 'FT' ? 200 : m))) if (!seen.has(e.k)) { seen.add(e.k); emitted.push(e.k); }
    prev = { status: st };
  }
  assert.strictEqual(emitted.length, new Set(emitted).size);
  assert.strictEqual(emitted.filter(k => k === 'kickoff').length, 1);
  assert.strictEqual(emitted.filter(k => k === 'ft').length, 1);
});

test('Live Activity content-state matches iOS ContentState keys', () => {
  assert.deepStrictEqual(Object.keys(liveState(real)).sort(), ['awayGoals', 'homeGoals', 'insight', 'lastEvent', 'minute', 'status']);
});

test('push titles are concise: goal/red titles carry minute + score, no em dash', () => {
  const { detect } = require('../notify.js');
  const f = require('./real-fixture.json');
  const evs = detect({ status: '2H' }, f);
  for (const e of evs) {
    assert.ok(!/—/.test(e.title + e.body), e.title);
    if (e.type === 'goal' || e.type === 'red') {
      assert.match(e.title, /\d+(\+\d+)?'/);
      assert.match(e.title, /\d+-\d+/);
    }
  }
});
