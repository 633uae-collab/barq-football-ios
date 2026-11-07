'use strict';
const { ServiceError } = require('./provider');
// A narrow deterministic guard, not a claim that free text is fully verified.
// Reject an explicitly cited event with an incorrect minute instead of serving it.
function validateEventTimes(answer, evidence) {
  const events = new Map((evidence.events || []).map(e => [e.sourceId, e]));
  const normalized = answer.replace(/[٠-٩]/g, d => String(d.charCodeAt(0)-1632)).replace(/[‐‑–—]/g, '-');
  for (const line of normalized.split('\n')) {
    const refs = [...line.matchAll(/event-(\d+)/g)].map(m => `event-${m[1]}`);
    if (refs.some(id => !events.has(id))) throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
    if (refs.length !== 1) continue;
    const times = [...line.matchAll(/(\d{1,3})(?:\s*\+\s*(\d{1,2}))?\s*[′'’]/g)];
    if (times.length !== 1) continue;
    const event = events.get(refs[0]);
    if (+times[0][1] !== event.minute || +(times[0][2] || 0) !== (event.addedTime || 0))
      throw new ServiceError('AI_FACT_CHECK_FAILED', 502);
  }
}
module.exports = { validateEventTimes };
