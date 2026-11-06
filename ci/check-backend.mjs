// Read-only P0 smoke check. No provider key, writes, deployment or synthetic match data.
// node ci/check-backend.mjs [https://existing-backend]
export function assertJSON(status, type, body) {
  if (status < 200 || status >= 300) throw new Error(`HTTP ${status}`);
  if (/html/i.test(type) || /^\s*</.test(body)) throw new Error('HTML instead of JSON (gateway/site unavailable)');
  const json = JSON.parse(body);
  if (json.error) throw new Error(`Backend error: ${json.error}`);
  return json;
}

export async function checkBackend(base, request = fetch) {
  const url = new URL(base);
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('Use an HTTPS backend URL without credentials');
  const checks = [
    ['/api/fixtures', x => Array.isArray(x.fixtures)],
    ['/api/catalog', x => Array.isArray(x.leagues) && x.leagues.length > 0],
    ['/api/team/40', x => x.team?.id === 40 && !!x.team?.name],
    ['/api/search?q=Liverpool', x => Array.isArray(x.teams) && x.teams.some(t => t.id === 40)],
    ['/api/feed', x => Array.isArray(x.insights)],
    ['/api/stars', x => Array.isArray(x.players)],
  ];
  return Promise.all(checks.map(async ([path, valid]) => {
    const started = Date.now();
    try {
      const response = await request(base.replace(/\/$/, '') + path, {
        headers: { Accept: 'application/json', 'X-Pinggy-No-Screen': '1' }, signal: AbortSignal.timeout(20000),
      });
      const json = assertJSON(response.status, response.headers.get('content-type') || '', await response.text());
      if (!valid(json)) throw new Error('Response does not match the iOS contract');
      return { path, ok: true, elapsedMs: Date.now() - started };
    } catch (error) { return { path, ok: false, error: error.message, elapsedMs: Date.now() - started }; }
  }));
}

import { pathToFileURL } from 'node:url';
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    let base = process.argv[2];
    if (!base) {
      const response = await fetch('https://koora-ae.surge.sh/config.json', { signal: AbortSignal.timeout(20000) });
      base = assertJSON(response.status, response.headers.get('content-type') || '', await response.text()).api;
    }
    const checks = await checkBackend(base);
    console.log(JSON.stringify({ checkedAt: new Date().toISOString(), base, checks }, null, 2));
    if (checks.some(x => !x.ok)) process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
