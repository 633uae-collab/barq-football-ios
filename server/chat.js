'use strict';
const { ServiceError } = require('./provider');
const { collectEvidence } = require('./chat-evidence');
function mountChat(app, { analyst, provider }) {
  // Global conservative budget: not bypassable with spoofed device/IP headers.
  // No shared administrator capability is shipped to the iOS client.
  let active = false, nextAt = 0, day = '', count = 0;
  app.post('/api/analyst/chat', async (req, res) => {
    if (!analyst.chatEnabled || !analyst.freePlanConfirmed || !analyst.key) throw new ServiceError('AI_CHAT_DISABLED');
    const { question, context = {} } = req.body || {};
    if (typeof question !== 'string' || !question.trim() || question.length > 1000 || !context || typeof context !== 'object') throw new ServiceError('INVALID_ANALYSIS_REQUEST', 400);
    for (const key of Object.keys(context)) if (!['fixtureId', 'teamIds', 'playerIds'].includes(key)) throw new ServiceError('INVALID_ANALYSIS_CONTEXT', 400);
    const validID = n => Number.isSafeInteger(n) && n > 0 && n < 1000000000;
    if (context.fixtureId !== undefined && !validID(context.fixtureId)) throw new ServiceError('INVALID_ANALYSIS_CONTEXT', 400);
    for (const key of ['teamIds', 'playerIds']) if (context[key] !== undefined && (!Array.isArray(context[key]) || context[key].length > 2 || !context[key].every(validID))) throw new ServiceError('INVALID_ANALYSIS_CONTEXT', 400);
    const now = analyst.now(), today = new Date(now).toISOString().slice(0,10);
    if (day !== today) { day = today; count = 0; }
    if (active) throw new ServiceError('AI_BUSY', 429);
    if (count >= 20 || now < nextAt || now < analyst.blockedUntil) {
      const e = new ServiceError('AI_FREE_QUOTA_REACHED', 429);
      e.retryAfter = count >= 20 ? Math.ceil((Date.parse(today) + 86400000-now)/1000) : Math.max(1, Math.ceil((Math.max(nextAt, analyst.blockedUntil)-now)/1000));
      throw e;
    }
    active = true; count++; nextAt = now + 65000;
    try {
      const evidence = await collectEvidence(provider, question.trim(), context);
      const result = await analyst.answer(question.trim(), evidence);
      // Do not expose account quota, usage, prompts, or internal capabilities to clients.
      res.json({ answer: result.answer, model: result.model, fetchedAt: evidence.fetchedAt,
        generatedAt: result.generatedAt, sources: evidence.sources, missing: evidence.missing });
    } finally { active = false; }
  });
}
module.exports = { mountChat };
