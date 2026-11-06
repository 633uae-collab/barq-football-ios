import { pathToFileURL } from 'node:url';
export function validateBase(value) {
  if (typeof value !== 'string' || !value.trim()) throw new Error('Backend base URL is missing');
  const url = new URL(value.trim());
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash)
    throw new Error('Backend base must be HTTPS without credentials, query or fragment');
  return url.href.replace(/\/+$/, '');
}
export async function resolveBase(override, request = fetch) {
  // An explicit deployment URL must never silently fall back to the former tunnel.
  if (override?.trim()) return validateBase(override);
  const r = await request('https://koora-ae.surge.sh/config.json', { signal: AbortSignal.timeout(10000) });
  if (!r.ok || !(r.headers.get('content-type') || '').includes('application/json')) throw new Error('Remote backend config is unavailable or not JSON');
  return validateBase((await r.json()).api);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { console.log(await resolveBase(process.env.FOTIQ_API_BASE)); }
  catch { console.error('Unable to resolve a valid HTTPS FOTIQ backend. Set FOTIQ_API_BASE.'); process.exitCode = 1; }
}
