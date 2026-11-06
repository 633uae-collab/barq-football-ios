const test = require('node:test');
const assert = require('node:assert');
const { param, apiPath } = require('../../backend-addons/season');

const now = new Date('2026-11-06T00:00:00Z');

test('season param accepts a real year and rejects junk', () => {
  assert.strictEqual(param({ season: '2024' }, now), 2024);
  assert.strictEqual(param({ season: '2027' }, now), 2027);
  assert.strictEqual(param({}, now), null);
  assert.strictEqual(param({ season: '' }, now), null);
  assert.strictEqual(param({ season: '1999' }, now), null);
  assert.strictEqual(param({ season: '2028' }, now), null);
  assert.strictEqual(param({ season: '20a4' }, now), null);
  assert.strictEqual(param({ season: '2024.5' }, now), null);
});

test('api paths include season only when the picker chose one', () => {
  assert.strictEqual(apiPath('standings', 39, 2024), '/standings?league=39&season=2024');
  assert.strictEqual(apiPath('topscorers', 39, null), '/players/topscorers?league=39');
  assert.strictEqual(apiPath('topassists', 2, 2023), '/players/topassists?league=2&season=2023');
  assert.strictEqual(apiPath('fixtures', 307, 2025), '/fixtures?league=307&season=2025');
  assert.throws(() => apiPath('standings', 0, null));
  assert.throws(() => apiPath('news', 39, null));
});
