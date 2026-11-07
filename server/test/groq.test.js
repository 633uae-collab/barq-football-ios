const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GroqAnalyst } = require('../groq');
const { createApp } = require('../app');
const options = { key: 'test-key', token: 'evaluation-only', enabled: true, freePlanConfirmed: true };
const success = () => new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Analysis' } }] }));
test('disabled and unconfirmed billing never authorize evaluation', () => {
  for (const overrides of [{ enabled: false }, { freePlanConfirmed: false }, { key: undefined }, { token: undefined }]) {
    assert.throws(() => new GroqAnalyst({ ...options, ...overrides }).authorize('Bearer evaluation-only'), /AI_EVALUATION_DISABLED/);
  }
  assert.throws(() => new GroqAnalyst(options).authorize('Bearer wrong'), /UNAUTHORIZED/);
});
test('every identical question fetches fresh provider data and a new Groq answer', async t => {
  let upstream = 0, groq = 0;
  const analyst = new GroqAnalyst({ ...options, fetchImpl: async (_url, opts) => {
    groq++;
    const b = JSON.parse(opts.body);
    assert.equal(b.reasoning_effort, 'high');
    assert.equal(JSON.parse(b.messages[1].content).evidence.fetchedAt, upstream);
    return success();
  } });
  const provider = { load: async path => {
    assert.equal(path, '/fixtures?id=1575218'); upstream++;
    return { fetchedAt: upstream, data: [{ fixture: { id: 1575218 }, goals: { home: 1, away: 0 } }] };
  } };
  const server = createApp({ provider, storage: {}, analyst }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  t.after(() => new Promise(r => server.close(r)));
  const url = `http://127.0.0.1:${server.address().port}/api/analyst/evaluate`;
  const request = body => fetch(url, { method: 'POST', headers: { authorization: 'Bearer evaluation-only', 'content-type': 'application/json' }, body: JSON.stringify(body) });
  assert.equal((await request({ question: 'test', fixtureId: -1 })).status, 400);
  assert.equal(upstream, 0);
  for (let i = 0; i < 2; i++) {
    const r = await request({ question: 'حلل المباراة', fixtureId: 1575218 });
    assert.equal(r.status, 200); assert.equal(r.headers.get('cache-control'), 'no-store');
    assert.equal((await r.json()).fetchedAt, i + 1);
  }
  assert.equal(groq, 2); assert.equal(upstream, 2);
  provider.load = async () => { throw new Error('offline'); };
  assert.equal((await request({ question: 'test', fixtureId: 1575218 })).status, 500);
  assert.equal(groq, 2);
});
test('quota rejection blocks until retry time without retries or fallback', async () => {
  let now = 0, calls = 0;
  const a = new GroqAnalyst({ ...options, now: () => now, fetchImpl: async () => {
    calls++; return new Response('{}', { status: 429, headers: { 'retry-after': '120' } });
  } });
  await assert.rejects(a.answer('q', { fetchedAt: 1 }), /AI_FREE_QUOTA_REACHED/);
  assert.throws(() => a.authorize('Bearer evaluation-only'), e => e.retryAfter === 120);
  now = 120001; a.authorize('Bearer evaluation-only'); assert.equal(calls, 1);
});
test('incomplete output and oversize evidence are rejected, secrets not reflected', async () => {
  const a = new GroqAnalyst({ ...options, fetchImpl: async () => new Response(JSON.stringify({ choices: [{ finish_reason: 'length', message: { content: 'truncated' } }] })) });
  await assert.rejects(a.answer('q', {}), /AI_INCOMPLETE_RESPONSE/);
  await assert.rejects(a.answer('q', { data: 'x'.repeat(19000) }), /AI_EVIDENCE_TOO_LARGE/);
  assert.equal(a.active, false);
});
test('network and provider authentication failures never expose secrets or retry', async () => {
  for (const fail of [async () => { throw new Error('test-key evaluation-only'); }, async () => new Response('test-key', { status: 401 }), async () => new Response('test-key', { status: 500 })]) {
    let calls = 0;
    const a = new GroqAnalyst({ ...options, fetchImpl: async () => { calls++; return fail(); } });
    await assert.rejects(a.answer('q', {}), e => !e.message.includes('test-key') && /^AI_/.test(e.message));
    assert.equal(calls, 1); assert.equal(a.active, false);
  }
});
test('internal CLI is opt-in, expiring, claimed once, bounded and secret-redacted', async () => {
  const { run } = require('../internal-eval');
  const env = { GROQ_API_KEY: 'secret-groq', APISPORTS_KEY: 'secret-football', FOTIQ_AI_EVAL_TOKEN: 'secret-token', GROQ_FREE_PLAN_CONFIRMED: 'true', FOTIQ_INTERNAL_EVAL_UNTIL: new Date(600000).toISOString() };
  let calls = 0, claims = 0; const logs = [], waits = [];
  const opts = { env, now: () => 0, claim: () => { if (claims++) throw new Error('claimed'); }, pause: async ms => waits.push(ms), log: s => logs.push(s), provider: { load: async () => { calls++; return { fetchedAt: calls, data: [{ fixture: { id: 1575218 } }] }; } }, analyst: { answer: async () => ({ answer: 'secret-groq secret-football secret-token' }) } };
  assert.equal(await run({ ...opts, env: {} }), false);
  assert.equal(await run({ ...opts, now: () => 600001 }), false);
  assert.equal(await run(opts), true); assert.equal(calls, 2); assert.deepEqual(waits, [65000]);
  assert.equal(await run(opts), false); assert.equal(calls, 2);
  assert.ok(!logs.join('').includes('secret-')); assert.ok(logs.join('').includes('[REDACTED]'));
});
