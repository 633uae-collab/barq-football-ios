// Honour ?season= on the league routes the iOS league center already calls:
//   GET /api/standings/:id?season=YYYY
//   GET /api/topscorers/:id?season=YYYY
//   GET /api/topassists/:id?season=YYYY
//   GET /api/league/:id?season=YYYY
//
// The app sends the query. Mount this helper in koora-app/backend/server.js and pass
// `season.apiPath(kind, id, season.param(req.query))` to the existing `cached()` call
// instead of a current-season-only API-SPORTS path. Without it the picker label changes
// and the table stays on the current season (the app then shows SeasonNote.mismatch).
//
//   const season = require('./season');
//   app.get('/api/standings/:id', async (req, res) => {
//     const path = season.apiPath('standings', req.params.id, season.param(req.query));
//     const raw = await cached(path, 5 * 60e3);
//     ...
//   });

function param(query, now = new Date()) {
  const raw = query && query.season;
  if (raw == null || raw === '') return null;
  const y = Number(raw);
  const max = now.getUTCFullYear() + 1;
  if (!Number.isInteger(y) || String(raw).trim() !== String(y) || y < 2000 || y > max) return null;
  return y;
}

function apiPath(kind, leagueId, season) {
  const id = Number(leagueId);
  if (!Number.isInteger(id) || id <= 0) throw new Error('bad league');
  const s = season == null ? '' : `&season=${season}`;
  switch (kind) {
    case 'standings': return `/standings?league=${id}${s}`;
    case 'topscorers': return `/players/topscorers?league=${id}${s}`;
    case 'topassists': return `/players/topassists?league=${id}${s}`;
    case 'fixtures': return `/fixtures?league=${id}${s}`;
    default: throw new Error('bad kind');
  }
}

module.exports = { param, apiPath };
