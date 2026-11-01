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
  app.locals.alertPayload = (i) => ({ aps: { alert: { title: i.title, body: i.body }, sound: 'default', 'thread-id': `fixture-${i.fixture}`, 'interruption-level': i.level === 'high' ? 'time-sensitive' : 'active' }, fixture: i.fixture, insight: i.id, type: i.type });
  // Must match Shared/MatchActivityAttributes.swift ContentState exactly (verified by BARQTests on CI).
  const contentState = (f, insight, lastEvent) => ({ homeGoals: f.goals.home ?? 0, awayGoals: f.goals.away ?? 0, minute: f.status.elapsed ?? 0,
    status: f.status.short, lastEvent: lastEvent || null, insight: insight || null });
  const short = (n) => String(n || '').replace(/ /g, '').slice(0, 3).toUpperCase();
  app.locals.contentState = contentState;
  // Live Activity update/end (apns-push-type: liveactivity, topic ae.barq.football.push-type.liveactivity).
  app.locals.livePayload = (f, insight, lastEvent) => ({ aps: { timestamp: Math.floor(Date.now() / 1000),
    event: ['FT', 'AET', 'PEN'].includes(f.status.short) ? 'end' : 'update', 'content-state': contentState(f, insight, lastEvent),
    ...(['FT', 'AET', 'PEN'].includes(f.status.short) ? { 'dismissal-date': Math.floor(Date.now() / 1000) + 900 } : {}) } });
  // Push-to-start (iOS 17.2+), sent to a pushtostart token when a favourite team kicks off.
  app.locals.startPayload = (f) => ({ aps: { timestamp: Math.floor(Date.now() / 1000), event: 'start',
    'attributes-type': 'MatchActivityAttributes',
    attributes: { fixtureId: f.id, league: f.league.name, homeName: f.home.name, awayName: f.away.name, homeShort: short(f.home.name), awayShort: short(f.away.name) },
    'content-state': contentState(f), alert: { title: `${f.home.name} - ${f.away.name}`, body: f.league.name } } });
};
