'use strict';
const { config } = require('./runtime');
const { Provider } = require('./provider');
const { openStorage } = require('./storage');
const { createApp } = require('./app');
const { Observations } = require('./observations');
const { port, dailyLimit, key, dbPath, storageMode } = config();
const storage = openStorage(dbPath);
const provider = new Provider({ key, dailyLimit });
const { GroqAnalyst } = require('./groq');
const analyst = new GroqAnalyst({ key: process.env.GROQ_API_KEY, token: process.env.FOTIQ_AI_EVAL_TOKEN,
  chatEnabled: process.env.FOTIQ_AI_CHAT_ENABLED === 'true',
  enabled: process.env.FOTIQ_AI_EVAL_ENABLED === 'true',
  freePlanConfirmed: process.env.GROQ_FREE_PLAN_CONFIRMED === 'true' });
const observations = new Observations(storage);
const server = createApp({ provider, storage, storageMode, observations, analyst }).listen(port, '0.0.0.0', () => console.log(`FOTIQ backend listening on ${port}; provider ${provider.key ? 'configured, not verified' : 'not configured'}`));
function stop() {
  server.close(() => { storage.close(); process.exit(0); });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.once('SIGTERM', stop); process.once('SIGINT', stop);
