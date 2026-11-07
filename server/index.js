'use strict';
const { config } = require('./runtime');
const { Provider } = require('./provider');
const { openStorage } = require('./storage');
const { createApp } = require('./app');
const { Observations } = require('./observations');
const { port, dailyLimit, key, dbPath, storageMode } = config();
const storage = openStorage(dbPath);
const provider = new Provider({ key, dailyLimit });
const observations = new Observations(storage);
const server = createApp({ provider, storage, storageMode, observations }).listen(port, '0.0.0.0', () => console.log(`FOTIQ backend listening on ${port}; provider ${provider.key ? 'configured, not verified' : 'not configured'}`));
function stop() {
  server.close(() => { storage.close(); process.exit(0); });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.once('SIGTERM', stop); process.once('SIGINT', stop);
