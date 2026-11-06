const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Provider } = require('../provider');
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
test('provider coalesces concurrent requests, caches success and keeps key server-side', async () => {
  let calls = 0;
  const p = new Provider({ key: 'test-only-secret', fetchImpl: async (url, options) => {
    calls++; assert.equal(options.headers['x-apisports-key'], 'test-only-secret');
    assert.equal(url, 'https://v3.football.api-sports.io/teams?id=40');
    return json({ errors: [], response: [{ team: { id: 40 } }] });
  } });
  const results = await Promise.all(Array.from({ length: 20 }, () => p.get('/teams?id=40')));
  await p.get('/teams?id=40'); assert.equal(calls, 1);
  assert.equal(results[0].data[0].team.id, 40);
  assert.ok(!JSON.stringify(results).includes('test-only-secret'));
});
test('HTTP 200 HTML and API error envelopes never become successful empty results', async () => {
  for (const [response, code] of [
    [new Response('<html>unavailable</html>', { headers: { 'content-type': 'text/html' } }), 'UPSTREAM_INVALID_JSON'],
    [json({ errors: { requests: 'limit' }, response: [] }), 'PLAN_LIMIT'],
    [json({ errors: { token: 'secret internal text' }, response: [] }), 'API_AUTH_FAILED'],
    [json({ response: {} }), 'UPSTREAM_INVALID_RESPONSE'],
    [json({ errors: { season: 'invalid' }, response: [] }), 'UPSTREAM_REJECTED_REQUEST']
  ]) {
    const p = new Provider({ key: 'test', fetchImpl: async () => response });
    await assert.rejects(p.get('/fixtures'), e => e.code === code && !e.message.includes('secret'));
    assert.equal(p.cache.size, 0); assert.equal(p.pending.size, 0);
  }
});
test('temporary outage may return bounded stale data but auth and quota failures never do', async () => {
  let now = 0, mode = 'ok';
  const p = new Provider({ key: 'test', now: () => now, fetchImpl: async () => mode === 'ok'
    ? json({ response: [1] }) : json({}, mode === 'outage' ? 500 : 429) });
  await p.get('/fixtures', 100); now = 110; mode = 'outage';
  assert.equal((await p.get('/fixtures', 100)).stale, true);
  now = 201; await assert.rejects(p.get('/fixtures', 100), { code: 'UPSTREAM_UNAVAILABLE' });
  now = 150; mode = 'quota'; await assert.rejects(p.get('/fixtures', 100), { code: 'PLAN_LIMIT' });
});
test('missing credentials, request budget and timeout produce explicit failures', async () => {
  await assert.rejects(new Provider().get('/fixtures'), { code: 'API_KEY_NOT_CONFIGURED' });
  const p = new Provider({ key: 'test', dailyLimit: 1, fetchImpl: async () => json({ response: [] }) });
  await p.get('/teams'); await assert.rejects(p.get('/fixtures'), { code: 'LOCAL_REQUEST_BUDGET' });
  const slow = new Provider({ key: 'test', timeout: 10, fetchImpl: (_url, { signal }) => new Promise((_resolve, reject) => {
    signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }) });
  await assert.rejects(slow.get('/fixtures'), { code: 'UPSTREAM_TIMEOUT' });
  assert.equal(slow.active, 0);
});
test('cache size remains bounded', async () => {
  const p = new Provider({ key: 'test', maxEntries: 2, fetchImpl: async () => json({ response: [] }) });
  for (let i = 0; i < 5; i++) await p.get(`/teams?id=${i}`);
  assert.equal(p.cache.size, 2);
});
test('seven onboarding leagues queue without rejection and never exceed the concurrency cap', async () => {
  let active = 0, peak = 0;
  const p = new Provider({ key: 'test', maxConcurrent: 2, fetchImpl: async () => {
    active++; peak = Math.max(peak, active);
    await new Promise(r => setTimeout(r, 5)); active--;
    return json({ response: [] });
  } });
  await Promise.all(Array.from({ length: 7 }, (_, i) => p.get(`/standings?league=${i}`)));
  assert.equal(peak, 2); assert.equal(p.active, 0); assert.equal(p.waiting.length, 0);
});
test('cache is bounded by bytes as well as count and oversized successful results are not retained', async () => {
  const p = new Provider({ key: 'test', maxCacheBytes: 150, fetchImpl: async () => json({ response: ['x'.repeat(60)] }) });
  for (let i = 0; i < 4; i++) await p.get(`/teams?id=${i}`);
  assert.ok(p.cacheBytes <= 150); assert.equal(p.cache.size, 1);
  const small = new Provider({ key: 'test', maxCacheBytes: 10, fetchImpl: async () => json({ response: ['test'] }) });
  assert.deepEqual((await small.get('/teams')).data, ['test']); assert.equal(small.cache.size, 0);
});
