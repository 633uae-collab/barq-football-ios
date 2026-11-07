'use strict';
// Administrative CLI only: never mounted as an HTTP route.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { GroqAnalyst, MODEL } = require('./groq');
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
  provider ||= new Provider({ key: env.APISPORTS_KEY, dailyLimit: 2 });
  analyst ||= new GroqAnalyst({ key: env.GROQ_API_KEY });
  const questions = [
    ['ar', 'حلل هذه المباراة بالعربية. اذكر النتيجة والحالة والإحصائيات الداعمة ونقاط القوة والضعف وما تسمح التشكيلة باستنتاجه. افصل الحقائق عن الاستنتاجات، ووضح البيانات الناقصة. لا تخترع احتمالات فوز.'],
    ['en', 'Analyze this match in English. State the score, status, supporting statistics, strengths and weaknesses, and what the lineups allow you to infer. Separate facts from inferences and identify missing evidence. Do not invent win probabilities.']
  ];
  emit({ phase: 'start', model: MODEL, maxRequests: 2, fixtureId: 1575218 });
  for (let i = 0; i < questions.length; i++) {
    if (i) await pause(65000); // Respect the verified free account's per-minute token budget.
    if (now() + 70000 >= deadline) break;
    const [language, question] = questions[i];
    try {
      const result = await provider.load('/fixtures?id=1575218');
      const f = result.data[0];
      if (!f || f.fixture?.id !== 1575218) throw new Error('missing');
      // Keep source facts, remove repeated URLs/IDs and unused substitutes to fit free TPM.
      const evidence = { fetchedAt: result.fetchedAt, fixture: { id: f.fixture.id, date: f.fixture.date, status: f.fixture.status },
        league: { name: f.league?.name, season: f.league?.season },
        teams: { home: f.teams?.home?.name, away: f.teams?.away?.name }, goals: f.goals, score: f.score,
        events: (f.events || []).map(e => ({ minute: e.time, team: e.team?.name, player: e.player?.name, assist: e.assist?.name, type: e.type, detail: e.detail })),
        lineups: (f.lineups || []).map(l => ({ team: l.team?.name, formation: l.formation, coach: l.coach?.name,
          startXI: (l.startXI || []).map(x => ({ name: x.player?.name, position: x.player?.pos })) })),
        statistics: (f.statistics || []).map(s => ({ team: s.team?.name, statistics: s.statistics })) };
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
