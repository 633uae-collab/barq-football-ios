'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { HistoricalKnowledge } = require('../knowledge');
const entity = { id: 'Q7156', labels: { en: { value: 'FC Barcelona' } }, lastrevid: 42, modified: '2026-01-01T00:00:00Z', claims: { P571: [{ rank: 'normal', mainsnak: { snaktype: 'value', datavalue: { value: { time: '+1899-11-29T00:00:00Z', precision: 11, calendarmodel: 'http://www.wikidata.org/entity/Q1985727' } } } }] } };
const response = e => new Response(JSON.stringify({ entities: { Q7156: e } }));
test('history routes selectively, caches facts not answers, preserves source and revision', async () => {
  let calls = 0, now = 100000;
  const k = new HistoricalKnowledge({ now: () => now, fetchImpl: async (url, options) => { calls++; assert.equal(new URL(url).hostname, 'www.wikidata.org'); assert.match(options.headers['User-Agent'], /FOTIQ/); return response(entity); } });
  assert.equal(await k.collect('Barcelona live score'), null); assert.equal(calls, 0);
  const a = await k.collect('تاريخ تأسيس برشلونة');
  assert.equal(a.facts[0].value, '1899-11-29'); assert.equal(a.sources[0].license, 'CC0'); assert.equal(a.sources[0].revision, 42);
  a.facts[0].value = 'tampered';
  assert.equal((await k.collect('When was Barcelona founded?')).facts[0].value, '1899-11-29'); assert.equal(calls, 1);
  now += 86400001; await k.collect('Barcelona history'); assert.equal(calls, 2);
});
test('conflicting dates, identity mismatch, outages and unknown clubs fail closed', async () => {
  const conflict = structuredClone(entity); const other = structuredClone(conflict.claims.P571[0]); other.mainsnak.datavalue.value.time = '+1900-01-01T00:00:00Z'; conflict.claims.P571.push(other);
  for (const value of [conflict, { ...entity, id: 'Q1' }]) {
    const k = new HistoricalKnowledge({ fetchImpl: async () => response(value) });
    assert.deepEqual((await k.collect('Barcelona history')).facts, []);
  }
  let calls = 0; const k = new HistoricalKnowledge({ fetchImpl: async () => { calls++; return new Response('', {status:429}); } });
  await k.collect('Barcelona history'); await k.collect('Barcelona history'); assert.equal(calls, 1);
  assert.deepEqual((await k.collect('Unknown club history')).facts, []);
});
