'use strict';
const { prepareEvidence } = require('./analyst-evidence');
// Entity aliases resolve identifiers only; every football fact comes from a fresh provider response.
const aliases = [[529, /barcelona|برشلونة|برشلونه/i], [541, /real madrid|ريال مدريد/i], [40, /liverpool|ليفربول/i], [50, /manchester city|مانشستر سيتي/i]];
const playerStats = p => ({ name: p.player?.name, statistics: (p.statistics || []).map(s => ({ team: s.team?.name, league: s.league?.name, games: s.games, goals: s.goals, shots: s.shots, passes: s.passes, tackles: s.tackles, dribbles: s.dribbles, cards: s.cards })) });
const summary = f => ({ id: f.fixture?.id, kickoffUTC: f.fixture?.date, status: f.fixture?.status,
  league: { id: f.league?.id, name: f.league?.name, season: f.league?.season, round: f.league?.round },
  teams: { home: { id: f.teams?.home?.id, name: f.teams?.home?.name }, away: { id: f.teams?.away?.id, name: f.teams?.away?.name } }, goals: f.goals });
async function collectEvidence(provider, question, context = {}) {
  const sources = [], missing = [];
  const load = async (path, params) => {
    const r = await provider.load(path + '?' + new URLSearchParams(params));
    sources.push({ path, parameters: params, fetchedAt: r.fetchedAt });
    return r.data;
  };
  const evidence = { schema: 'fotiq-chat-evidence-v1', sources, missing, events: [],
    limitations: ['Starting lineups are not current tactical shape.', 'No causal claim or probability is established by match totals.', 'Retrieval time is not the provider update time.'] };
  const teamIds = context.teamIds || aliases.filter(([, re]) => re.test(question)).map(([id]) => id);
  const playerIds = context.playerIds || [];
  const upcoming = /upcoming|next match|قادمة|القادمة|قادمه/i.test(question);
  const live = /\blive\b|مباشر/i.test(question);
  const lastFive = /last five|last 5|آخر خمس|اخر خمس|آخر 5/i.test(question);
  let fixtureId = context.fixtureId;
  if (!fixtureId && live) {
    const matches = await load('/fixtures', { live: 'all' });
    fixtureId = matches[0]?.fixture?.id;
    evidence.selection = 'First currently live fixture returned by API-Football; not a user-selected match.';
    if (!fixtureId) missing.push('No live match was returned.');
  }
  if (teamIds.length) {
    evidence.clubs = [];
    for (const team of teamIds) {
      const fixtures = await load('/fixtures', { team, [upcoming ? 'next' : 'last']: upcoming ? 1 : 5 });
      const club = { teamId: team, matches: fixtures.map(summary) };
      const league = fixtures[0]?.league;
      if (league?.id && league?.season) {
        const stats = await load('/teams/statistics', { team, league: league.id, season: league.season });
        club.season = { league: league.name, year: league.season, fixtures: stats.fixtures,
          goals: stats.goals, form: stats.form, cleanSheet: stats.clean_sheet, failedToScore: stats.failed_to_score };
      }
      evidence.clubs.push(club);
      // "Why lost last game" must use the actual last game, not search backwards for a loss.
      if (teamIds.length === 1 && !fixtureId) fixtureId = fixtures[0]?.fixture?.id;
    }
  }
  if (upcoming && evidence.clubs?.length === 1) {
    const club = evidence.clubs[0], next = club.matches[0];
    club.recentMatches = (await load('/fixtures', { team: club.teamId, last: 5 })).map(summary);
    const opponent = [next?.teams?.home?.id, next?.teams?.away?.id].find(id => Number.isInteger(id) && id !== club.teamId);
    if (opponent) {
      const recent = await load('/fixtures', { team: opponent, last: 5 });
      const other = { teamId: opponent, matches: recent.map(summary) };
      if (next.league?.id && next.league?.season) {
        const stats = await load('/teams/statistics', { team: opponent, league: next.league.id, season: next.league.season });
        other.season = { league: next.league.name, year: next.league.season, fixtures: stats.fixtures,
          goals: stats.goals, form: stats.form, cleanSheet: stats.clean_sheet, failedToScore: stats.failed_to_score };
      }
      evidence.clubs.push(other);
    } else missing.push('Upcoming opponent unavailable; no opponent statistics can be inferred.');
    missing.push('No calibrated prediction source supplied; qualitative outlook only, no numerical probabilities or guaranteed score.');
  }
  if (fixtureId) {
    const f = (await load('/fixtures', { id: fixtureId }))[0];
    if (f) {
      Object.assign(evidence, prepareEvidence(f, sources.at(-1).fetchedAt));
      evidence.players = (f.players || []).map(t => ({ team: t.team?.name,
        players: (t.players || []).slice(0, 18).map(playerStats) }));
    } else missing.push('Requested fixture was not found.');
  }
  if (/premier league|الدوري الإنجليزي|الدوري الانجليزي/i.test(question)) {
    const league = (await load('/leagues', { id: 39, current: 'true' }))[0];
    const season = league?.seasons?.find(s => s.current)?.year;
    if (season) {
      const leaders = await load('/players/topscorers', { league: 39, season });
      evidence.scoringLeaders = leaders.slice(0, 5).map(playerStats);
      evidence.leaderSeason = season;
      missing.push('Scoring leaders are not an objective ranking of the best overall player; explain selection criteria.');
    } else missing.push('Current Premier League season unavailable.');
  }
  if (playerIds.length) {
    evidence.playerProfiles = [];
    for (const player of playerIds) {
      const profile = (await load('/players/profiles', { player }))[0];
      const teams = await load('/players/teams', { player });
      const latest = teams.flatMap(t => (t.seasons || []).map(season => ({ team: t.team?.id, season }))).sort((a,b) => b.season-a.season)[0];
      if (!latest) { missing.push(`No season available for player ${player}.`); continue; }
      const stats = await load('/players', { id: player, season: latest.season });
      const item = { playerId: player, profile: profile?.player?.name, season: latest.season, statistics: stats.map(playerStats) };
      if (lastFive && latest.team) {
        const squads = await load('/players/squads', { player });
        const currentTeams = [...new Set(squads.map(t => t.team?.id).filter(Number.isInteger))].slice(0, 2);
        if (!currentTeams.length) {
          currentTeams.push(latest.team);
          missing.push('Current player team unavailable; career season team is a fallback, not verified current registration.');
        }
        const candidates = new Map();
        for (const team of currentTeams) {
          for (const f of await load('/fixtures', { team, last: 10 })) {
            if (f.fixture?.id) candidates.set(f.fixture.id, { fixture: f, team });
          }
        }
        const recent = [...candidates.values()].sort((a,b) =>
          (Date.parse(b.fixture.fixture?.date) || 0) - (Date.parse(a.fixture.fixture?.date) || 0));
        item.lastFiveTeamMatches = []; item.lastFiveAppearances = [];
        for (const { fixture: f, team } of recent.slice(0, 20)) {
          const rows = await load('/fixtures/players', { fixture: f.fixture.id, team });
          const record = rows.flatMap(t => t.players || []).find(p => p.player?.id === player);
          const entry = { match: summary(f), player: record ? playerStats(record) : null };
          if (item.lastFiveTeamMatches.length < 5) item.lastFiveTeamMatches.push({ match: { id: f.fixture.id, kickoffUTC: f.fixture.date }, player: record ? { name: record.player?.name, statistics: (record.statistics || []).map(s => ({ games: { minutes: s.games?.minutes } })) } : null });
          if (record?.statistics?.some(s => Number(s.games?.minutes) > 0)) item.lastFiveAppearances.push(entry);
          if (item.lastFiveAppearances.length === 5) break;
        }
        missing.push('Team fixtures may contain non-appearances; only lastFiveAppearances have verified positive minutes.');
        if (item.lastFiveAppearances.length < 5) missing.push(`Only ${item.lastFiveAppearances.length} appearances verified within at most 20 recent fixtures; do not invent the remaining matches.`);
        item.appearanceCoverage = { requested: 5, found: item.lastFiveAppearances.length, candidateFixtures: recent.length, maximumTeams: 2, maximumFixturesPerTeam: 10 };
      }
      evidence.playerProfiles.push(item);
    }
  } else if (/player|لاعب/i.test(question) && !evidence.scoringLeaders && !fixtureId) {
    missing.push('Ask the user to select a player identifier; do not guess which player they mean.');
  }
  if (!sources.length) missing.push('Ask the user to specify a match, supported club, or player. No facts have been retrieved for this question.');
  if (Buffer.byteLength(JSON.stringify(evidence)) > 17500 && evidence.players) {
    delete evidence.players; missing.push('Individual match-player statistics omitted to fit the evidence budget; do not infer individual ratings.');
  }
  evidence.fetchedAt = sources.length ? Math.min(...sources.map(s => s.fetchedAt)) : Date.now();
  evidence.retrievedAtUTC = new Date(evidence.fetchedAt).toISOString();
  return evidence;
}
module.exports = { collectEvidence };
