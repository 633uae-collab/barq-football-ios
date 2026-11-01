// Writes sample APNs payloads built by push.js (from a real fixture/insight passed via stdin) into BARQTests/Payloads for CI tests.
const fs = require('fs'), path = require('path'), Module = require('module');
const orig = Module._load; Module._load = function (n, ...a) { return n === 'express' ? { json: () => 0 } : orig.call(this, n, ...a); };
const app = { post() {}, locals: {} }; require('./push.js')(app, { db: { run() {} }, q: 0, save() {} });
const { fixture, insight, lastEvent } = JSON.parse(fs.readFileSync(0, 'utf8'));
const out = path.join(__dirname, '..', 'BARQTests', 'Payloads'); fs.mkdirSync(out, { recursive: true });
const w = (n, o) => fs.writeFileSync(path.join(out, n), JSON.stringify(o, null, 1));
w('live-update.json', app.locals.livePayload({ ...fixture, status: { ...fixture.status, short: '2H' } }, insight.body, lastEvent));
w('live-end.json', app.locals.livePayload({ ...fixture, status: { ...fixture.status, short: 'FT' } }));
w('push-to-start.json', app.locals.startPayload(fixture));
const alert = app.locals.alertPayload(insight); alert['Simulator Target Bundle'] = 'ae.barq.football';
w('alert.apns', alert); w('alert.json', alert);
