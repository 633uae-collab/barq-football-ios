// Copy of the /api/stars route added to koora-app/backend/server.js (deployed on the box backend).
// FOTIQ STARS: today's standout players backed by real fixture player stats (one batched /fixtures?ids= call, cached).
app.get('/api/stars', async (req, res) => {
  try {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(req.query.date || '') ? req.query.date : todayStr();
    const day = await fixturesFor(date);
    const started = day.data.filter(f => LEAGUE_IDS.has(f.league.id) && (LIVE.has(f.fixture.status.short) || DONE.has(f.fixture.status.short)))
      .sort((a, b) => b.fixture.timestamp - a.fixture.timestamp).slice(0, 20);
    if (!started.length) return res.json({ date, fetchedAt: day.fetchedAt, players: [] });
    const anyLive = started.some(f => LIVE.has(f.fixture.status.short));
    const ids = started.map(f => f.fixture.id).sort((a, b) => a - b).join('-');
    const r = await cached(`/fixtures?ids=${ids}&timezone=${encodeURIComponent(TZ)}`, anyLive ? 90e3 : 15 * 60e3);
    const out = [];
    for (const f of r.data) for (const t of (f.players || [])) for (const p of (t.players || [])) {
      const s = p.statistics?.[0] || {};
      const goals = s.goals?.total || 0, assists = s.goals?.assists || 0;
      const rating = s.games?.rating ? Number(s.games.rating) : null;
      if (!(goals > 0 || assists > 0 || (rating && rating >= 7.5))) continue;
      out.push({ id: p.player.id, name: p.player.name, photo: p.player.photo, team: { id: t.team.id, name: t.team.name, logo: t.team.logo },
        fixture: f.fixture.id, league: f.league.name, live: LIVE.has(f.fixture.status.short), rating, goals, assists, minutes: s.games?.minutes || 0 });
    }
    const score = x => x.goals * 3 + x.assists * 2 + (x.rating || 0) / 2;
    out.sort((a, b) => score(b) - score(a) || a.id - b.id);
    res.json({ date, fetchedAt: r.fetchedAt, stale: r.stale, players: out.slice(0, 10) });
  } catch (e) { res.status(503).json({ error: e.message }); }
});

