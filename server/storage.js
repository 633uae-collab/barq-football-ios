'use strict';
const { DatabaseSync } = require('node:sqlite');
const { mkdirSync, chmodSync } = require('node:fs');
const { dirname } = require('node:path');

function openStorage(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const connection = new DatabaseSync(path, { timeout: 5000 });
  if (path !== ':memory:') chmodSync(path, 0o600);
  connection.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
    CREATE TABLE IF NOT EXISTS prefs(device TEXT PRIMARY KEY, body TEXT NOT NULL, at INTEGER NOT NULL);`);
  return {
    q: (sql, values = []) => connection.prepare(sql).all(...values),
    db: { run: (sql, values = []) => connection.prepare(sql).run(...values) },
    save: () => {}, // SQLite commits durably before run() returns; no deferred JSON file export.
    close: () => connection.close()
  };
}
module.exports = { openStorage };
