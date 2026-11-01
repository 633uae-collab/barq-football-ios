// FOTIQ server push system.
// - One central poller reuses the shared cached fixture feed (no per-user API calls).
// - Detects kickoff, goals, HT, 2nd-half start, FT, red cards + important analyst insights.
// - Dedup persisted in sqlite: notif_events(fixture,k) for detection, notif_sent(device,k) for delivery.
// - Delivers only to devices whose favourite teams / saved matches include the fixture, filtered by level.
// - APNs HTTP/2 token auth (.p8 from env). Without a key everything is queued in `outbox` with status 'no_apns_key'.
const http2 = require('http2'), crypto = require('crypto'), fs = require('fs');

const TOPIC = process.env.APNS_TOPIC || 'ae.barq.football';
const APNS_HOST = process.env.APNS_ENV === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
const POLL_MS = 30e3;
const LIVE = new Set(['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE', 'INT', 'SUSP']);
const DONE = new Set(['FT', 'AET', 'PEN']);
// level 0 = critical (kickoff, goals, red, FT), 1 = + HT/2H + high-level AI, 2 = all AI insights
const MIN_LEVEL = { kickoff: 0, goal: 0, red: 0, ft: 0, ht: 1, second: 1, ai_high: 1, ai: 2 };

/** Pure detector: given previous snapshot {status, goals} and a full API fixture (with events) returns events with stable keys. */
function detect(prev, f) {
  const out = [], id = f.fixture.id, st = f.fixture.status.short;
  const H = f.teams.home.name, A = f.teams.away.name, sc = `${f.goals.home ?? 0}-${f.goals.away ?? 0}`;
  const p = prev?.status;
  if (st === '1H' && (!p || p === 'NS' || p === 'TBD')) out.push({ type: 'kickoff', k: 'kickoff', title: `انطلقت ${H} × ${A}`, body: f.league.name });
  if (st === 'HT') out.push({ type: 'ht', k: 'ht', title: `استراحة ${H} ${sc} ${A}`, body: f.league.name });
  if (st === '2H' && p && p !== '2H') out.push({ type: 'second', k: 'second', title: `الشوط الثاني ${H} ${sc} ${A}`, body: f.league.name });
  if (DONE.has(st)) out.push({ type: 'ft', k: 'ft', title: `النهاية ${H} ${sc} ${A}`, body: f.league.name });
  for (const e of f.events || []) {
    const t = `${e.time?.elapsed ?? 0}${e.time?.extra ? '+' + e.time.extra : ''}'`;
    if (e.type === 'Goal' && e.detail !== 'Missed Penalty') {
      out.push({ type: 'goal', k: `goal:${e.team?.id}:${e.player?.id ?? e.player?.name}:${e.time?.elapsed}:${e.time?.extra ?? 0}`,
        title: `هدف ${t} · ${H} ${sc} ${A}`, body: `${e.player?.name || e.team?.name || ''}${e.detail === 'Own Goal' ? ' (عكسي)' : e.detail === 'Penalty' ? ' (جزاء)' : ''} · ${e.team?.name}` });
    }
    if (e.type === 'Card' && /Red/i.test(e.detail || '')) {
      out.push({ type: 'red', k: `red:${e.player?.id ?? e.player?.name}:${e.time?.elapsed}`, title: `طرد ${t} · ${H} ${sc} ${A}`, body: `${e.player?.name || ''} · ${e.team?.name}` });
    }
  }
  return out.map(x => ({ ...x, fixture: id }));
}

function liveState(f, lastEvent, insight) {
  return { homeGoals: f.goals.home ?? 0, awayGoals: f.goals.away ?? 0, minute: f.fixture.status.elapsed ?? 0, status: f.fixture.status.short, lastEvent: lastEvent || null, insight: insight || null };
}

function makeJwt(keyPem, keyId, teamId) {
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const data = `${b64({ alg: 'ES256', kid: keyId })}.${b64({ iss: teamId, iat: Math.floor(Date.now() / 1000) })}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: keyPem, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${data}.${sig}`;
}

function start(app, { cached, q, db, save, todayStr, TZ, health }) {
  db.run('CREATE TABLE IF NOT EXISTS notif_events(fixture INTEGER, k TEXT, at INTEGER, PRIMARY KEY(fixture,k))');
  db.run('CREATE TABLE IF NOT EXISTS notif_sent(device TEXT, k TEXT, at INTEGER, PRIMARY KEY(device,k))');
  db.run('CREATE TABLE IF NOT EXISTS fx_state(fixture INTEGER PRIMARY KEY, status TEXT, goals TEXT, at INTEGER)');
  db.run('CREATE TABLE IF NOT EXISTS outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT, token TEXT, kind TEXT, payload TEXT, status TEXT, at INTEGER)');
  db.run("CREATE TABLE IF NOT EXISTS push(token TEXT PRIMARY KEY, device TEXT, kind TEXT, fixture INTEGER, at INTEGER)");
  const S = { lastTick: null, lastError: null, ticks: 0, watched: 0, detected: 0, queued: 0, sent: 0, failed: 0, apns: 'unknown' };

  // --- APNs sender
  let key = null, jwt = null, jwtAt = 0, client = null;
  try { if (process.env.APNS_KEY_PATH && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID) key = fs.readFileSync(process.env.APNS_KEY_PATH, 'utf8'); } catch (e) { S.lastError = 'APNs key read: ' + e.message; }
  S.apns = key ? 'configured' : 'APNs key missing';
  if (!key) console.log('[notify] APNs key missing: pushes are queued in outbox, not delivered');
  function send(token, kind, payload, device) {
    const push = kind === 'liveactivity' || kind === 'pushtostart';
    if (!key) { db.run('INSERT INTO outbox(device,token,kind,payload,status,at) VALUES(?,?,?,?,?,?)', [device, token, kind, JSON.stringify(payload), 'no_apns_key', Date.now()]); S.queued++; return Promise.resolve(false); }
    if (!jwt || Date.now() - jwtAt > 40 * 60e3) { jwt = makeJwt(key, process.env.APNS_KEY_ID, process.env.APNS_TEAM_ID); jwtAt = Date.now(); }
    if (!client || client.closed || client.destroyed) { client = http2.connect(APNS_HOST); client.on('error', e => { S.lastError = 'apns: ' + e.message; client = null; }); }
    return new Promise(res => {
      const r = client.request({ ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${jwt}`,
        'apns-topic': push ? `${TOPIC}.push-type.liveactivity` : TOPIC, 'apns-push-type': push ? 'liveactivity' : 'alert', 'apns-priority': '10' });
      let status = 0, body = '';
      r.on('response', h => { status = h[':status']; }); r.on('data', d => body += d);
      r.on('end', () => {
        const ok = status === 200; ok ? S.sent++ : S.failed++;
        if (!ok) { S.lastError = `apns ${status} ${body}`; if (status === 410 || /BadDeviceToken|Unregistered/.test(body)) db.run('DELETE FROM push WHERE token=?', [token]); }
        db.run('INSERT INTO outbox(device,token,kind,payload,status,at) VALUES(?,?,?,?,?,?)', [device, token, kind, JSON.stringify(payload), ok ? 'sent' : 'failed:' + status, Date.now()]);
        res(ok);
      });
      r.on('error', e => { S.failed++; S.lastError = 'apns req: ' + e.message; res(false); });
      r.end(JSON.stringify(payload));
    });
  }

  // --- subscribers
  function subscribers() {
    const prefs = new Map(q('SELECT device,body FROM prefs').map(r => [r.device, JSON.parse(r.body)]));
    const toks = q('SELECT token,device,kind,fixture FROM push');
    return { prefs, toks };
  }
  function interested(p, f) {
    if (!p) return false;
    const teams = new Set([...(p.favTeams || []), ...(p.teams || []).map(t => t.id)]);
    const muted = new Set(p.muted || []);
    const t = [f.teams.home.id, f.teams.away.id].filter(x => !muted.has(x));
    return (p.saved || []).includes(f.fixture.id) || t.some(x => teams.has(x));
  }
  function fanout(ev, f, subs) {
    for (const t of subs.toks) {
      if (t.kind !== 'apns') continue;
      const p = subs.prefs.get(t.device);
      if (!interested(p, f) || (p.level ?? 1) < MIN_LEVEL[ev.type]) continue;
      const k = `${ev.fixture}:${ev.k}`;
      if (q('SELECT 1 FROM notif_sent WHERE device=? AND k=?', [t.device, k]).length) continue;
      db.run('INSERT INTO notif_sent(device,k,at) VALUES(?,?,?)', [t.device, k, Date.now()]);
      send(t.token, 'apns', { aps: { alert: { title: ev.title, body: ev.body }, sound: 'default', 'thread-id': `fixture-${ev.fixture}`,
        'interruption-level': ['goal', 'red', 'kickoff'].includes(ev.type) ? 'time-sensitive' : 'active' }, fixture: ev.fixture, type: ev.type }, t.device);
    }
  }

  let lastInsight = q('SELECT MAX(id) m FROM insights')[0]?.m || 0;
  let running = false;
  async function tick() {
    if (running) return; running = true;
    try {
      const subs = subscribers();
      const r = await cached(`/fixtures?date=${todayStr()}&timezone=${encodeURIComponent(TZ)}`, 20e3); // shared with app + analyst
      const watch = r.data.filter(f => [...subs.prefs.values()].some(p => interested(p, f)) || subs.toks.some(t => t.fixture === f.fixture.id));
      const active = watch.filter(f => LIVE.has(f.fixture.status.short) || DONE.has(f.fixture.status.short));
      S.watched = watch.length;
      for (let i = 0; i < active.length; i += 20) {
        const ids = active.slice(i, i + 20).map(f => f.fixture.id);
        const br = await cached(`/fixtures?ids=${ids.join('-')}&timezone=${encodeURIComponent(TZ)}`, 15e3);
        for (const f of br.data) {
          const id = f.fixture.id, prevRow = q('SELECT status,goals FROM fx_state WHERE fixture=?', [id])[0];
          const prev = prevRow ? { status: prevRow.status, goals: prevRow.goals } : null;
          const goalsNow = `${f.goals.home ?? 0}-${f.goals.away ?? 0}`;
          for (const ev of detect(prev, f)) {
            if (q('SELECT 1 FROM notif_events WHERE fixture=? AND k=?', [id, ev.k]).length) continue;
            db.run('INSERT INTO notif_events(fixture,k,at) VALUES(?,?,?)', [id, ev.k, Date.now()]); S.detected++;
            // first sighting of a fixture (e.g. server restart / new favourite): seed history silently, only a fresh kickoff is sent
            if (!prev && !(ev.type === 'kickoff' && (f.fixture.status.elapsed ?? 0) <= 10)) continue;
            fanout(ev, f, subs);
          }
          // Live Activity update/end on change only
          if (!prev || prev.status !== f.fixture.status.short || prev.goals !== goalsNow || LIVE.has(f.fixture.status.short)) {
            const lastEv = [...(f.events || [])].reverse().find(e => e.type === 'Goal' || e.type === 'Card');
            const le = lastEv ? `${lastEv.type === 'Goal' ? 'هدف' : (lastEv.detail || 'بطاقة')} - ${lastEv.player?.name || lastEv.team?.name} ${lastEv.time?.elapsed}'` : null;
            const done = DONE.has(f.fixture.status.short);
            for (const t of subs.toks.filter(t => t.kind === 'liveactivity' && t.fixture === id)) {
              const k = `${id}:la:${f.fixture.status.short}:${goalsNow}:${f.fixture.status.elapsed}`;
              if (q('SELECT 1 FROM notif_sent WHERE device=? AND k=?', [t.token, k]).length) continue;
              db.run('INSERT INTO notif_sent(device,k,at) VALUES(?,?,?)', [t.token, k, Date.now()]);
              send(t.token, 'liveactivity', { aps: { timestamp: Math.floor(Date.now() / 1000), event: done ? 'end' : 'update', 'content-state': liveState(f, le),
                ...(done ? { 'dismissal-date': Math.floor(Date.now() / 1000) + 900 } : {}) } }, t.device);
            }
            // push-to-start at kickoff for devices that follow a team in this match
            if ((!prev || prev.status === 'NS') && f.fixture.status.short === '1H') {
              const short = n => String(n || '').replace(/ /g, '').slice(0, 3).toUpperCase();
              for (const t of subs.toks.filter(t => t.kind === 'pushtostart' && interested(subs.prefs.get(t.device), f))) {
                const k = `${id}:pts`; if (q('SELECT 1 FROM notif_sent WHERE device=? AND k=?', [t.device, k]).length) continue;
                db.run('INSERT INTO notif_sent(device,k,at) VALUES(?,?,?)', [t.device, k, Date.now()]);
                send(t.token, 'pushtostart', { aps: { timestamp: Math.floor(Date.now() / 1000), event: 'start', 'attributes-type': 'MatchActivityAttributes',
                  attributes: { fixtureId: id, league: f.league.name, homeName: f.teams.home.name, awayName: f.teams.away.name, homeShort: short(f.teams.home.name), awayShort: short(f.teams.away.name) },
                  'content-state': liveState(f), alert: { title: `${f.teams.home.name} × ${f.teams.away.name}`, body: f.league.name } } }, t.device);
              }
            }
          }
          db.run('INSERT OR REPLACE INTO fx_state(fixture,status,goals,at) VALUES(?,?,?,?)', [id, f.fixture.status.short, goalsNow, Date.now()]);
        }
      }
      // important analyst insights -> fans of that match
      const fresh = q('SELECT * FROM insights WHERE id>? ORDER BY id', [lastInsight]);
      for (const i of fresh) {
        lastInsight = i.id;
        if (['red', 'ht', 'ft'].includes(i.type)) continue; // already covered by event notifications
        const f = r.data.find(x => x.fixture.id === i.fixture); if (!f) continue;
        fanout({ type: i.level === 'high' ? 'ai_high' : 'ai', k: `ai:${i.id}`, fixture: i.fixture, title: String(i.title).replace(/\s*—\s*/g, ' · '), body: String(i.body).replace(/\s*—\s*/g, ' · ') }, f, subs);
      }
      db.run('DELETE FROM notif_sent WHERE at<?', [Date.now() - 4 * 86400e3]);
      db.run('DELETE FROM outbox WHERE at<?', [Date.now() - 2 * 86400e3]);
      save(); S.ticks++; S.lastTick = Date.now();
    } catch (e) { S.lastError = e.message; health?.error('notify', e.message); }
    finally { running = false; }
  }
  setInterval(tick, POLL_MS); setTimeout(tick, 8000);

  app.post('/api/push/register', require('express').json({ limit: '4kb' }), (req, res) => {
    const { device, kind, token, fixture } = req.body || {};
    if (!/^[0-9a-f]{20,400}$/i.test(token || '') || !['apns', 'liveactivity', 'pushtostart'].includes(kind) || !/^[a-z0-9-]{8,64}$/i.test(String(device || ''))) return res.status(400).json({ error: 'bad' });
    db.run('INSERT OR REPLACE INTO push VALUES(?,?,?,?,?)', [token, String(device), kind, Number.isInteger(fixture) ? fixture : null, Date.now()]); save();
    res.json({ ok: true, delivery: key ? 'enabled' : 'queued_no_apns_key' });
  });
  // opt-out: remove all tokens + sent history for a device (also used to clean QA registrations)
  app.delete('/api/push/:device', (req, res) => {
    const d = String(req.params.device); if (!/^[a-z0-9-]{8,64}$/i.test(d)) return res.status(400).json({ error: 'bad' });
    db.run('DELETE FROM push WHERE device=?', [d]); db.run('DELETE FROM notif_sent WHERE device=?', [d]); db.run('DELETE FROM outbox WHERE device=?', [d]); save(); res.json({ ok: true });
  });
  return { state: () => ({ recentOutbox: q('SELECT kind,status,at,payload FROM outbox ORDER BY id DESC LIMIT 5').map(r => { const p = JSON.parse(r.payload); return { kind: r.kind, status: r.status, at: r.at, title: p.aps?.alert?.title || p.aps?.event, type: p.type || null }; }), ...S, devices: q('SELECT COUNT(DISTINCT device) n FROM push')[0].n, tokens: q('SELECT kind, COUNT(*) n FROM push GROUP BY kind'),
    outbox: q('SELECT status, COUNT(*) n FROM outbox GROUP BY status') }), tick };
}
module.exports = { start, detect, liveState, makeJwt, MIN_LEVEL };
