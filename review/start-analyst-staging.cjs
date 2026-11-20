'use strict';

// This entry point is used only by the PR #7 staging service.
if (process.env.FOTIQ_AI_CHAT_ENABLED === 'true') {
  if (process.env.GROQ_FREE_PLAN_CONFIRMED !== 'true' ||
      !process.env.GROQ_API_KEY?.trim() || !process.env.APISPORTS_KEY?.trim()) {
    throw new Error('Staging chat requires both provider credentials and a confirmed free Groq plan.');
  }
  require('../server/index.js');
} else {
  const http = require('node:http');
  const readiness = JSON.stringify({
    mode: 'staging-preflight',
    groqConfigured: Boolean(process.env.GROQ_API_KEY?.trim()),
    footballConfigured: Boolean(process.env.APISPORTS_KEY?.trim()),
    groqFreePlanFlag: process.env.GROQ_FREE_PLAN_CONFIRMED === 'true'
  });
  http.createServer((req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET' && req.url === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(readiness);
      return;
    }
    res.writeHead(503);
    res.end();
  }).listen(Number(process.env.PORT || 10000), '0.0.0.0');
}
