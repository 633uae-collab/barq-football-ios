'use strict';
// Administrative CLI only: never mounted as an HTTP route.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { GroqAnalyst, MODEL } = require('./groq');
const { prepareEvidence } = require('./analyst-evidence');
const { Provider } = require('./provider');
async function run({ env = process.env, now = Date.now, provider, analyst, log = console.log,
  claim = () => fs.closeSync(fs.openSync(path.join(os.tmpdir(), 'fotiq-groq-evaluation-20261107.lock'), 'wx', 0o600)),
  pause = ms => new Promise(r => setTimeout(r, ms)) } = {}) {
  const deadline = Date.parse(env.FOTIQ_INTERNAL_EVAL_UNTIL || '');
  if (!env.GROQ_API_KEY || !env.APISPORTS_KEY || env.GROQ_FREE_PLAN_CONFIRMED !== 'true' ||
      !Number.isFinite(deadline) || deadline <= now() || deadline - now() > 15 * 60000) return false;
  try { claim(); } catch { return false; }
  // Never log raw exception messages, headers, environment, credentials or URLs with credentials.
  const secrets = [env.GROQ_API_KEY, env.APISPORTS_KEY, env.FOTIQ_AI_EVAL_TOKEN].filter(Boolean);
  const emit = value => { let s = JSON.stringify(value); for (const secret of secrets) s = s.split(secret).join('[REDACTED]'); log('FOTIQ_INTERNAL_EVAL ' + s); };
  provider ||= new Provider({ key: env.APISPORTS_KEY, dailyLimit: 3 });
  analyst ||= new GroqAnalyst({ key: env.GROQ_API_KEY });
  const questions = [
    ['ar', 'حلل هذه المباراة بالعربية. اذكر النتيجة والحالة والإحصائيات الداعمة ونقاط القوة والضعف وما تسمح التشكيلة باستنتاجه. افصل الحقائق عن الاستنتاجات، ووضح البيانات الناقصة. لا تخترع احتمالات فوز.'],
    ['en', 'Analyze this match in English. State the score, status, supporting statistics, strengths and weaknesses, and what the lineups allow you to infer. Separate facts from inferences and identify missing evidence. Do not invent win probabilities.']
  ];
  let fixtureId = 1575218;
  if (env.FOTIQ_INTERNAL_EVAL_LIVE === 'true') {
    const live = await provider.load('/fixtures?live=all');
    const candidate = live.data.find(f => ['1H', '2H', 'HT', 'ET', 'BT', 'P'].includes(f.fixture?.status?.short));
    if (!candidate) { emit({ phase: 'finished', reason: 'NO_LIVE_MATCH', httpEndpointCreated: false }); return true; }
    fixtureId = candidate.fixture.id;
  }
  emit({ phase: 'start', model: MODEL, maxRequests: 2, fixtureId });
  for (let i = 0; i < questions.length; i++) {
    if (i) await pause(65000); // Respect the verified free account's per-minute token budget.
    if (now() + 70000 >= deadline) break;
    const [language, question] = questions[i];
    try {
      const result = await provider.load(`/fixtures?id=${fixtureId}`);
      const f = result.data[0];
      if (!f || f.fixture?.id !== fixtureId) throw new Error('missing');
      const evidence = prepareEvidence(f, result.fetchedAt);
      emit({ phase: 'evidence', language, evidence });
      const answer = await analyst.answer(question, evidence);
      emit({ phase: 'answer', language, ...answer });
    } catch (e) {
      const safe = ['AI_FREE_QUOTA_REACHED','AI_AUTH_FAILED','AI_UPSTREAM_UNAVAILABLE','AI_INCOMPLETE_RESPONSE','AI_EVIDENCE_TOO_LARGE'];
      emit({ phase: 'error', language, error: safe.includes(e.code) ? e.code : 'EVALUATION_FAILED' });
      break; // No automatic retry, model fallback, or paid upgrade.
    }
  }
  emit({ phase: 'finished', httpEndpointCreated: false });
  return true;
}
if (require.main === module) run().catch(() => console.log('FOTIQ_INTERNAL_EVAL {"phase":"error","error":"EVALUATION_FAILED"}'));
module.exports = { run };
