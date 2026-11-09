'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { validateEventTimes } = require('../analyst-validation');
const evidence = { events: [
  { sourceId: 'event-6', minute: 63, addedTime: null },
  { sourceId: 'event-15', minute: 90, addedTime: 2 },
  { sourceId: 'event-1', minute: 18, addedTime: null, type: 'subst', playerIn: 'Silvan Broker', playerOut: 'Mees Laros', directionBasis: 'starting XI and substitution sequence' },
  { sourceId: 'event-2', minute: 30, addedTime: null, type: 'subst', playerIn: null, playerOut: null, participants: ['A', 'B'] }
] };
test('rejects observed zero-score-match count inversion in native Arabic and English', () => {
  const season = { seasonOnlyComparison: true, clubs: [{ season: { totals: { played: 12, goalsFor: 48, failedToScore: 0 } } }, { season: { totals: { played: 12, goalsFor: 31, failedToScore: 1 } } }] };
  for (const text of ['ريال مدريد لم يسجل في أي مباراة، بينما برشلونة لم يسجل في مباراة واحدة فقط.', 'Real Madrid never scored this season.', 'Real Madrid failed to score in every match.'])
    assert.throws(() => validateEventTimes(text, season), { code: 'AI_FACT_CHECK_FAILED' });
  for (const text of ['ريال مدريد سجل في جميع مبارياته الـ12، وبرشلونة لم يسجل في مباراة واحدة.', 'Real Madrid scored in every played match; Barcelona had one match without scoring.'])
    assert.doesNotThrow(() => validateEventTimes(text, season));
});
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
test('rejects contradictory or invented substitution direction in Arabic and English', () => {
  for (const answer of [
    '18′ دخل Silvan Broker محل Mees Laros (event-1). اتجاه الاستبدال غير محدد.',
    "18' Silvan Broker came on for Mees Laros (event-1); substitution direction is unknown.",
    '30′ دخل A محل B (event-2)',
    "30' A replaced B (event-2)"
  ]) assert.throws(() => validateEventTimes(answer, evidence), { code: 'AI_FACT_CHECK_FAILED' });
  assert.doesNotThrow(() => validateEventTimes('18′ دخل Silvan Broker محل Mees Laros (event-1)', evidence));
  assert.doesNotThrow(() => validateEventTimes("30' Substitution involving A and B; direction is unknown (event-2)", evidence));
});

test('missing assist never justifies speculative goal causation in either language', () => {
  const missing = { events: [{ type: 'Goal', sourceId: 'event-0', minute: 53, goalAssist: null }] };
  for (const text of ['Missing assist may indicate a solo effort, only speculation.', 'قد يكون هجوم فردي أو خطأ دفاعي، مجرد تخمين.'])
    assert.throws(() => validateEventTimes(text, missing), { code: 'AI_FACT_CHECK_FAILED' });
  assert.doesNotThrow(() => validateEventTimes('Assist data unavailable. No conclusion about how the goal was created.', missing));
  assert.doesNotThrow(() => validateEventTimes('بيانات صانع الهدف غير متوفرة ولا يمكن تحديد كيفية صنع الهدف.', missing));
});
