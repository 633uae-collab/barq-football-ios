'use strict';
const { ServiceError } = require('./provider');
function fixture(f) {
  if (!f?.fixture?.id || !f.teams?.home?.id || !f.teams?.away?.id || !f.league?.id
    || !f.fixture.date || !Number.isInteger(f.fixture.timestamp) || !f.fixture.status?.short)
    throw new ServiceError('UPSTREAM_INVALID_FIXTURE');
  return { id: f.fixture.id, date: f.fixture.date, ts: f.fixture.timestamp,
    status: f.fixture.status, venue: f.fixture.venue?.name ?? null, referee: f.fixture.referee,
    league: f.league, home: f.teams.home, away: f.teams.away, goals: f.goals || { home: null, away: null } };
}
function league(row) {
  const current = row.seasons?.find(s => s.current);
  return { id: row.league.id, name: row.league.name, logo: row.league.logo,
    type: row.league.type, country: row.country?.name, season: current?.year, active: !!current };
}
function topPlayer(row) {
  const s = row.statistics?.[0] || {};
  return { ...row.player, team: s.team, goals: s.goals?.total, assists: s.goals?.assists, apps: s.games?.appearences };
}
function playerStat(s) {
  return { team: s.team, league: s.league, apps: s.games?.appearences, minutes: s.games?.minutes,
    rating: s.games?.rating == null ? null : String(s.games.rating), pos: s.games?.position,
    goals: s.goals?.total ?? 0, assists: s.goals?.assists ?? 0, shots: s.shots?.total ?? 0,
    sot: s.shots?.on ?? 0, passes: s.passes?.total ?? 0, keyPasses: s.passes?.key ?? 0,
    dribbles: s.dribbles?.success ?? 0, tackles: s.tackles?.total ?? 0,
    yellow: s.cards?.yellow ?? 0, red: s.cards?.red ?? 0 };
}
module.exports = { fixture, league, topPlayer, playerStat };
