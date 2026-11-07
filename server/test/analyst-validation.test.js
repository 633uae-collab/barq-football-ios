'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { validateEventTimes } = require('../analyst-validation');
const evidence = { events: [{ sourceId: 'event-6', minute: 63, addedTime: null }, { sourceId: 'event-15', minute: 90, addedTime: 2 }] };
test('rejects observed hallucinated substitution minute in Arabic and English', () => {
  for (const answer of ['59′ – دخل البديل (event‑6)', "59' – substitution [event-6]", '٥٩′ – تبديل [event-6]'])
    assert.throws(() => validateEventTimes(answer, evidence), { code: 'AI_FACT_CHECK_FAILED' });
  assert.doesNotThrow(() => validateEventTimes('63′ – تبديل (event-6)', evidence));
});
test('preserves stoppage time and rejects nonexistent citations', () => {
  assert.doesNotThrow(() => validateEventTimes('90+2′ – card [event-15]', evidence));
  assert.throws(() => validateEventTimes('90′ – card [event-15]', evidence), { code: 'AI_FACT_CHECK_FAILED' });
  assert.throws(() => validateEventTimes('90′ – goal [event-99]', evidence), { code: 'AI_FACT_CHECK_FAILED' });
});
