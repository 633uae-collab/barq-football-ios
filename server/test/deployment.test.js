const { test } = require('node:test');
const assert = require('node:assert/strict');
const { config } = require('../runtime');
test('production startup fails clearly without secrets or an absolute database path', () => {
  assert.throws(() => config({ NODE_ENV: 'production' }), /APISPORTS_KEY/);
  assert.throws(() => config({ NODE_ENV: 'production', APISPORTS_KEY: 'test' }), /FOTIQ_DB_PATH/);
  for (const db of [':memory:', 'data/test.sqlite']) assert.throws(() => config({ NODE_ENV: 'production', APISPORTS_KEY: 'test', FOTIQ_DB_PATH: db }), /absolute/);
  const c = config({ NODE_ENV: 'production', APISPORTS_KEY: ' test ', FOTIQ_DB_PATH: '/var/data/fotiq.sqlite', PORT: '10000' });
  assert.equal(c.port, 10000); assert.equal(c.key, 'test'); assert.equal(c.dbPath, '/var/data/fotiq.sqlite');
  for (const port of ['0', 'abc', '65536']) assert.throws(() => config({ PORT: port }), /PORT/);
});
test('explicit backend override wins without fetching old config and invalid overrides never fall back', async () => {
  const { resolveBase } = await import('../../ci/resolve-api-base.mjs');
  let calls = 0; const request = async () => { calls++; throw new Error('must not fetch'); };
  assert.equal(await resolveBase('https://fotiq-test.onrender.com/', request), 'https://fotiq-test.onrender.com');
  for (const url of ['http://example.com', 'https://user:secret@example.com', 'https://example.com?key=secret', 'https://example.com#x']) await assert.rejects(resolveBase(url, request));
  assert.equal(calls, 0);
});
test('remote backend config must have valid JSON status, type and HTTPS API URL', async () => {
  const { resolveBase } = await import('../../ci/resolve-api-base.mjs');
  const good = () => Promise.resolve(new Response(JSON.stringify({ api: 'https://example.com' }), { headers: { 'content-type': 'application/json' } }));
  assert.equal(await resolveBase('', good), 'https://example.com');
  for (const r of [new Response('<html>unavailable</html>'), new Response('{}', { status: 503 }), new Response('{"api":"http://bad"}', { headers: { 'content-type': 'application/json' } })])
    await assert.rejects(resolveBase('', async () => r));
});
test('real server process accepts durable preferences, restarts on the same database and shuts down cleanly', async t => {
  const { spawn } = require('node:child_process');
  const { mkdtempSync, rmSync } = require('node:fs');
  const { tmpdir } = require('node:os');
  const { join } = require('node:path');
  const net = require('node:net');
  const { openStorage } = require('../storage');
  const dir = mkdtempSync(join(tmpdir(), 'fotiq-runtime-')), dbPath = join(dir, 'prefs.sqlite');
  const listener = net.createServer(); listener.listen(0, '127.0.0.1');
  await new Promise(r => listener.once('listening', r));
  const port = listener.address().port; await new Promise(r => listener.close(r));
  let child;
  t.after(() => { child?.kill('SIGKILL'); rmSync(dir, { recursive: true, force: true }); });
  async function start() {
    child = spawn(process.execPath, [join(__dirname, '../index.js')], {
      env: { ...process.env, NODE_ENV: 'production', PORT: String(port), APISPORTS_KEY: 'test-key-not-live', FOTIQ_DB_PATH: dbPath }, stdio: ['ignore', 'pipe', 'pipe']
    });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Server startup timed out')), 5000);
      child.once('exit', code => { clearTimeout(timer); reject(new Error(`Premature exit ${code}`)); });
      child.stdout.on('data', d => { if (d.toString().includes('listening')) { clearTimeout(timer); resolve(); } });
    });
  }
  async function stop() {
    const p = child;
    const exited = new Promise(r => p.once('exit', (code, signal) => r({ code, signal })));
    p.kill('SIGTERM');
    assert.deepEqual(await exited, { code: 0, signal: null }); child = undefined;
  }
  await start();
  const base = `http://127.0.0.1:${port}`;
  const health = await (await fetch(base + '/healthz')).json();
  assert.equal(health.ok, true); assert.equal(health.providerVerified, false);
  const payload = { favTeams: [40], favLeagues: [39], saved: [], muted: [], level: 1 };
  const r = await fetch(base + '/api/prefs/runtime-test-device', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) });
  assert.equal(r.status, 200); assert.deepEqual(await r.json(), { ok: true });
  await stop(); await start();
  assert.equal((await fetch(base + '/healthz')).status, 200);
  await stop();
  const db = openStorage(dbPath);
  assert.deepEqual(JSON.parse(db.q('SELECT body FROM prefs WHERE device=?', ['runtime-test-device'])[0].body), payload);
  db.close();
});

test('preview needs no disk but still requires provider credentials and never uses a supplied disk', () => {
  const c = config({ NODE_ENV: 'production', FOTIQ_STORAGE_MODE: 'preview', APISPORTS_KEY: 'test', FOTIQ_DB_PATH: '/unused/db' });
  assert.equal(c.storageMode, 'preview'); assert.equal(c.dbPath, ':memory:');
  assert.throws(() => config({ NODE_ENV: 'production', FOTIQ_STORAGE_MODE: 'preview' }), /APISPORTS_KEY/);
  assert.throws(() => config({ FOTIQ_STORAGE_MODE: 'typo' }), /FOTIQ_STORAGE_MODE/);
});
