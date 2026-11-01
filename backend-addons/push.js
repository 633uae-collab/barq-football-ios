// Scaffold: mount in koora-app/backend/server.js with require('./push')(v2, { db, q, save }).
// Stores APNs device / Live Activity / push-to-start tokens. Sending needs an APNs .p8 key
// (paid Apple Developer account): set APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH, APNS_TOPIC=ae.barq.football.
module.exports = function (app, { db, q, save }) {
  db.run('CREATE TABLE IF NOT EXISTS push(token TEXT PRIMARY KEY, device TEXT, kind TEXT, fixture INTEGER, at INTEGER)');
  app.post('/api/push/register', require('express').json(), (req, res) => {
    const { device, kind, token, fixture } = req.body || {};
    if (!/^[0-9a-f]{20,200}$/i.test(token || '') || !['apns', 'liveactivity', 'pushtostart'].includes(kind)) return res.status(400).json({ error: 'bad' });
    db.run('INSERT OR REPLACE INTO push VALUES(?,?,?,?,?)', [token, String(device).slice(0, 64), kind, fixture || null, Date.now()]); save();
    res.json({ ok: true, delivery: process.env.APNS_KEY_ID ? 'enabled' : 'disabled_no_apns_key' });
  });
  // Payload builders (used once APNs key exists):
  app.locals.alertPayload = (i) => ({ aps: { alert: { title: i.title, body: i.body }, sound: 'default', 'thread-id': `fixture-${i.fixture}` }, fixture: i.fixture });
  app.locals.livePayload = (f, insight) => ({ aps: { timestamp: Math.floor(Date.now() / 1000), event: 'update',
    'content-state': { homeGoals: f.goals.home ?? 0, awayGoals: f.goals.away ?? 0, minute: f.status.elapsed ?? 0, status: f.status.short, insight: insight || null } } });
};
