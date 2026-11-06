const test = require('node:test');
const assert = require('node:assert/strict');

test('backend smoke check rejects 200 HTML, JSON errors, and non-success HTTP', async () => {
  const { assertJSON } = await import('../../ci/check-backend.mjs');
  assert.throws(() => assertJSON(200, 'text/html', '<html>Site Unavailable</html>'));
  assert.throws(() => assertJSON(200, 'application/json', '<html>Site Unavailable</html>'));
  assert.throws(() => assertJSON(200, 'application/json', '{"error":"PLAN_LIMIT"}'));
  assert.throws(() => assertJSON(503, 'application/json', '{}'));
  assert.deepEqual(assertJSON(200, 'application/json', '{"fixtures":[]}'), { fixtures: [] });
});

test('backend smoke check detects missing club/search data, not just HTTP success', async () => {
  const { checkBackend } = await import('../../ci/check-backend.mjs');
  const request = async () => new Response(JSON.stringify({ fixtures: [], leagues: [], teams: [], insights: [], players: [] }),
    { headers: { 'content-type': 'application/json' } });
  const checks = await checkBackend('https://stub.local', request);
  assert.equal(checks.find(x => x.path === '/api/team/40').ok, false);
  assert.equal(checks.find(x => x.path.startsWith('/api/search')).ok, false);
  assert.equal(checks.find(x => x.path === '/api/fixtures').ok, true);
});
