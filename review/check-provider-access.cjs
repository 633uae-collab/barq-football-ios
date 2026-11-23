'use strict';

// A single read-only check per staging preflight process. Never log vendor bodies or headers.
async function checkProviderAccess() {
  const groq = async () => {
    const response = await fetch('https://api.groq.com/openai/v1/models', {
      headers: { Authorization: 'Bearer ' + process.env.GROQ_API_KEY },
      signal: AbortSignal.timeout(12000), redirect: 'error'
    });
    if (!response.ok) { await response.body?.cancel(); return { status: response.status }; }
    const body = await response.json();
    return {
      status: response.status,
      modelAvailable: Array.isArray(body.data) && body.data.some(model => model.id === 'openai/gpt-oss-120b')
    };
  };
  const football = async () => {
    const response = await fetch('https://v3.football.api-sports.io/status', {
      headers: { 'x-apisports-key': process.env.APISPORTS_KEY },
      signal: AbortSignal.timeout(12000), redirect: 'error'
    });
    if (!response.ok) { await response.body?.cancel(); return { status: response.status }; }
    const body = await response.json();
    const { subscription, requests } = body.response || {};
    const tiers = ['free', 'pro', 'ultra', 'mega', 'custom'];
    const plan = String(subscription?.plan || '').toLowerCase();
    const used = requests?.current, limit = requests?.limit_day;
    const knownQuota = Number.isSafeInteger(used) && Number.isSafeInteger(limit) &&
      used >= 0 && limit >= used;
    return {
      status: response.status,
      active: subscription?.active === true,
      plan: tiers.includes(plan) ? plan : 'unknown',
      remaining: knownQuota ? limit - used : null
    };
  };
  const [model, data] = await Promise.all([
    groq().catch(() => ({ status: 'unavailable' })),
    football().catch(() => ({ status: 'unavailable' }))
  ]);
  console.info('FOTIQ_STAGE_ACCESS ' + JSON.stringify({ groq: model, football: data }));
}

module.exports = { checkProviderAccess };
