'use strict';
const { isAbsolute, resolve } = require('node:path');
function config(env = process.env) {
  const port = Number(env.PORT || 3000), dailyLimit = Number(env.API_DAILY_BUDGET || 1000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  if (!Number.isSafeInteger(dailyLimit) || dailyLimit < 1) throw new Error('Invalid API_DAILY_BUDGET');
  const key = env.APISPORTS_KEY?.trim();
  const storageMode = env.FOTIQ_STORAGE_MODE || 'persistent';
  if (!['persistent', 'preview'].includes(storageMode)) throw new Error('Invalid FOTIQ_STORAGE_MODE');
  if (env.NODE_ENV === 'production') {
    if (!key) throw new Error('APISPORTS_KEY is required in production');
    if (storageMode === 'persistent' && (!env.FOTIQ_DB_PATH || !isAbsolute(env.FOTIQ_DB_PATH))) throw new Error('FOTIQ_DB_PATH must be an absolute path on a persistent disk');
  }
  return { port, dailyLimit, key, storageMode, dbPath: storageMode === 'preview' ? ':memory:' : env.FOTIQ_DB_PATH || resolve(__dirname, 'data/fotiq.sqlite') };
}
module.exports = { config };
