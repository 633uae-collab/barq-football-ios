'use strict';
const { resolve } = require('node:path');
const { Provider } = require('./provider');
const { openStorage } = require('./storage');
const { createApp } = require('./app');
const port = Number(process.env.PORT || 3000);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
if (process.env.NODE_ENV === 'production' && !process.env.FOTIQ_DB_PATH) throw new Error('FOTIQ_DB_PATH must point to a persistent disk');
const dailyLimit = Number(process.env.API_DAILY_BUDGET || 1000);
if (!Number.isSafeInteger(dailyLimit) || dailyLimit < 1) throw new Error('Invalid API_DAILY_BUDGET');
const storage = openStorage(process.env.FOTIQ_DB_PATH || resolve(__dirname, 'data/fotiq.sqlite'));
const provider = new Provider({ key: process.env.APISPORTS_KEY, dailyLimit });
const server = createApp({ provider, storage }).listen(port, '0.0.0.0', () => console.log(`FOTIQ backend listening on ${port}; provider ${provider.key ? 'configured, not verified' : 'not configured'}`));
function stop() {
  server.close(() => { storage.close(); process.exit(0); });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.once('SIGTERM', stop); process.once('SIGINT', stop);
