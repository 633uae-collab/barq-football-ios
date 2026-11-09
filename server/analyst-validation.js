'use strict';
const { ServiceError } = require('./provider');
// Narrow deterministic guards, not a claim that free text is fully verified.
// Reject an explicitly cited event with an incorrect minute or a contradictory
// substitution direction instead of serving it.
function validateAnswer(answer, evidence) {
  const events = new Map((evidence.events || []).map(e => [e.sourceId, e]));
  const normalized = answer.replace(/[٠-٩]/g, d => String(d.charCodeAt(0)-1632)).replace(/[‐‑–—]/g, '-');
  if (evidence.seasonOnlyComparison && /(?<![\d-])\d{1,2}\s*-\s*\d{1,2}(?![\d-])/.test(normalized))
    throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
  // Observed native Arabic answer inverted failedToScore=0 into "never scored".
  // A categorical no-goals claim is impossible when every compared club has goals.
  const clubs = evidence.clubs || [];
  if (evidence.seasonOnlyComparison && clubs.length > 0 && clubs.every(c => c.season?.totals?.goalsFor > 0) &&
      /لم يسجل في أي مباراة|لم يسجل أي هدف|(?:never scored|did not score in any match|failed to score in every match)/iu.test(normalized.replace(/[\u064b-\u065f]/g, '')))
    throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
  // Missing assist metadata is never evidence for a solo goal or defensive error.
  // Fail closed on the observed inference, including qualified 'may'/'speculation'.
  const missingAssist = (evidence.events || []).some(e => String(e.type).toLowerCase() === 'goal' && e.goalAssist == null);
  if (missingAssist && /(?:solo (?:goal|run|effort|attack)|individual effort|defensive (?:error|mistake)|(?:هجوم|مجهود|جهد|عمل) فردي|خطأ دفاعي|أخطاء دفاعية)/iu.test(normalized))
    throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
  for (const line of normalized.split('\n')) {
    const refs = [...line.matchAll(/event-(\d+)/g)].map(m => `event-${m[1]}`);
    if (refs.some(id => !events.has(id))) throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
    if (refs.length !== 1) continue;
    const event = events.get(refs[0]);
    const times = [...line.matchAll(/(\d{1,3})(?:\s*\+\s*(\d{1,2}))?\s*[′'’]/g)];
    if (times.length === 1 && (+times[0][1] !== event.minute || +(times[0][2] || 0) !== (event.addedTime || 0)))
      throw new ServiceError('AI_FACT_CHECK_FAILED', 502);

    if (String(event.type).toLowerCase() !== 'subst') continue;
    const lower = line.toLowerCase();
    const saysUnknown = /(?:direction|substitution)[^.!?]{0,45}(?:unknown|unverified|unclear|not (?:known|verified|specified))|(?:اتجاه|جهة)[^.!?؟]{0,45}(?:غير (?:معروف|محدد|موثق|واضح)|مجهول)/i.test(lower);
    const assertsDirection = /\breplaced\b|(?:came|comes|entered|subbed)[^.!?]{0,80}(?:for|replacing|instead of)|استبدل|(?:دخل|خرج|تم استبدال)[^.!?؟]{0,80}(?:محل|بدل|بدلا|بـ)/i.test(lower);
    const verified = !!event.playerIn && !!event.playerOut && !!event.directionBasis;
    if ((verified && saysUnknown) || (!verified && assertsDirection))
      throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
  }
}
const validateEventTimes = validateAnswer; // backwards-compatible test/export name
module.exports = { validateAnswer, validateEventTimes };
