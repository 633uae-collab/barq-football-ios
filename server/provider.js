'use strict';

class ServiceError extends Error {
  constructor(code, status = 503) { super(code); this.code = code; this.status = status; }
}

// Only server-owned paths reach the provider; the key never enters client JSON or logs.
class Provider {
  constructor({ key, fetchImpl = fetch, timeout = 8000, now = Date.now,
    maxEntries = 256, maxCacheBytes = 16 * 1024 * 1024, maxConcurrent = 4, dailyLimit = 1000 } = {}) {
    this.key = key; this.fetch = fetchImpl; this.timeout = timeout; this.now = now;
    this.maxEntries = maxEntries; this.maxConcurrent = maxConcurrent; this.dailyLimit = dailyLimit;
    this.cache = new Map(); this.pending = new Map(); this.active = 0;
    this.day = ''; this.used = 0;
    this.maxCacheBytes = maxCacheBytes; this.cacheBytes = 0; this.sizes = new Map(); this.waiting = [];
  }
  async get(path, ttl = 30000) {
    if (!path.startsWith('/') || path.startsWith('//')) throw new ServiceError('INVALID_PROVIDER_PATH', 500);
    const old = this.cache.get(path);
    if (old && this.now() - old.fetchedAt < ttl) return { ...old, stale: false };
    if (this.pending.has(path)) return this.pending.get(path);
    const task = this.load(path).then(result => {
      const bytes = Buffer.byteLength(JSON.stringify(result));
      this.evict(path);
      if (bytes <= this.maxCacheBytes) {
        this.cache.set(path, result); this.sizes.set(path, bytes); this.cacheBytes += bytes;
        while (this.cache.size > this.maxEntries || this.cacheBytes > this.maxCacheBytes)
          this.evict(this.cache.keys().next().value);
      }
      return { ...result, stale: false };
    }).catch(error => {
      // Never hide missing/invalid credentials or quota exhaustion with old data.
      if (old && ['UPSTREAM_UNAVAILABLE', 'UPSTREAM_TIMEOUT'].includes(error.code)
        && this.now() - old.fetchedAt < ttl + Math.min(ttl, 300000)) return { ...old, stale: true };
      throw error;
    }).finally(() => this.pending.delete(path));
    this.pending.set(path, task);
    return task;
  }
  evict(path) {
    this.cacheBytes -= this.sizes.get(path) || 0;
    this.sizes.delete(path); this.cache.delete(path);
  }
  release() {
    // Reserve this slot until the queued request resumes.
    if (this.waiting.length) { this.waiting.shift()(); } else this.active--;
  }
  async load(path) {
    if (!this.key) throw new ServiceError('API_KEY_NOT_CONFIGURED');
    if (this.active >= this.maxConcurrent) {
      if (this.waiting.length >= 32) throw new ServiceError('UPSTREAM_BUSY');
      await new Promise(resolve => this.waiting.push(resolve));
    } else this.active++;
    const day = new Date(this.now()).toISOString().slice(0, 10);
    if (this.day !== day) { this.day = day; this.used = 0; }
    if (this.used >= this.dailyLimit) { this.release(); throw new ServiceError('LOCAL_REQUEST_BUDGET', 429); }
    this.used++;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeout);
    try {
      const r = await this.fetch(`https://v3.football.api-sports.io${path}`, {
        headers: { 'x-apisports-key': this.key, accept: 'application/json' },
        signal: controller.signal, redirect: 'error'
      });
      if (r.status === 429) throw new ServiceError('PLAN_LIMIT', 429);
      if (r.status === 401 || r.status === 403) throw new ServiceError('API_AUTH_FAILED');
      if (!r.ok) throw new ServiceError('UPSTREAM_UNAVAILABLE');
      if (r.status === 204) return { data: [], fetchedAt: this.now() };
      if (!(r.headers.get('content-type') || '').includes('application/json')) throw new ServiceError('UPSTREAM_INVALID_JSON');
      const reader = r.body.getReader(); const chunks = []; let size = 0;
      try {
        for (;;) {
          const { done, value } = await reader.read(); if (done) break;
          size += value.length;
          if (size > 16 * 1024 * 1024) { await reader.cancel(); throw new ServiceError('UPSTREAM_RESPONSE_TOO_LARGE'); }
          chunks.push(Buffer.from(value));
        }
      } finally { reader.releaseLock(); }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { throw new ServiceError('UPSTREAM_INVALID_JSON'); }
      if (body.errors && Object.keys(body.errors).length) {
        const keys = Object.keys(body.errors).join(' ');
        if (/rateLimit|requests|quota/i.test(keys)) throw new ServiceError('PLAN_LIMIT', 429);
        if (/token|key|access/i.test(keys)) throw new ServiceError('API_AUTH_FAILED');
        throw new ServiceError('UPSTREAM_REJECTED_REQUEST', 502);
      }
      const objectResponse = path.split('?')[0] === '/teams/statistics' && body.response && typeof body.response === 'object' && !Array.isArray(body.response);
      if (!Array.isArray(body.response) && !objectResponse) throw new ServiceError('UPSTREAM_INVALID_RESPONSE');
      return { data: body.response, fetchedAt: this.now() };
    } catch (e) {
      if (controller.signal.aborted) throw new ServiceError('UPSTREAM_TIMEOUT', 504);
      if (e instanceof ServiceError) throw e;
      throw new ServiceError('UPSTREAM_UNAVAILABLE');
    } finally { clearTimeout(timer); this.release(); }
  }
}
module.exports = { Provider, ServiceError };
