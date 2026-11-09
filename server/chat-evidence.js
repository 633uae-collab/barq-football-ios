'use strict';
const { historicalKnowledge } = require('./knowledge');
const { prepareEvidence } = require('./analyst-evidence');
// Entity aliases resolve identifiers only; every football fact comes from a fresh provider response.
const aliases = [[529, /barcelona|برشلونة|برشلونه/i], [541, /real madrid|ريال مدريد/i], [40, /liverpool|ليفربول/i], [50, /manchester city|مانشستر سيتي/i]];
// Provider player fields are overloaded. Give the model semantic names and keep
// assists separate from key passes. API-Football's per-fixture `passes.accuracy`
// values are retained as provider values but are not labelled as percentages.
const playerStats = p => ({ name: p.player?.name, statistics: (p.statistics || []).map(s => ({
  team: s.team?.name,
  league: s.league?.name,
  games: s.games,
  scoring: { goals: s.goals?.total ?? null, assists: s.goals?.assists ?? null, conceded: s.goals?.conceded ?? null, saves: s.goals?.saves ?? null },
  shooting: { total: s.shots?.total ?? null, onTarget: s.shots?.on ?? null },
  passing: { total: s.passes?.total ?? null, keyPasses: s.passes?.key ?? null,
    accuracyProviderValue: s.passes?.accuracy ?? null, accuracyUnitVerified: false },
  defending: { tackles: s.tackles?.total ?? null, blocks: s.tackles?.blocks ?? null, interceptions: s.tackles?.interceptions ?? null },
  dribbling: s.dribbles,
  discipline: s.cards
})) });
const summary = f => ({ id: f.fixture?.id, kickoffUTC: f.fixture?.date, status: f.fixture?.status,
  league: { id: f.league?.id, name: f.league?.name, season: f.league?.season, round: f.league?.round },
  teams: { home: { id: f.teams?.home?.id, name: f.teams?.home?.name }, away: { id: f.teams?.away?.id, name: f.teams?.away?.name } }, goals: f.goals });
function clubResults(fixtures, team) {
  return [...fixtures].sort((a, b) => (Date.parse(b.fixture?.date) || 0) - (Date.parse(a.fixture?.date) || 0)).map(f => {
    const home = f.teams?.home?.id === team, away = f.teams?.away?.id === team;
    const own = home ? f.goals?.home : f.goals?.away, opponent = home ? f.goals?.away : f.goals?.home;
    const known = (home || away) && ['FT','AET','PEN'].includes(f.fixture?.status?.short) && Number.isInteger(own) && Number.isInteger(opponent);
    return { fixtureId: f.fixture?.id, kickoffUTC: f.fixture?.date, result: known ? (own > opponent ? 'W' : own < opponent ? 'L' : 'D') : null,
      basis: f.fixture?.status?.short === 'PEN' ? 'goals before penalty shootout; shootout outcome not inferred' : 'completed match goals' };
  });
}
function relevantVenueSeason(stats, role) {
  if (!['home', 'away'].includes(role)) return null;
  return {
    role,
    fixtures: {
      played: stats.fixtures?.played?.[role] ?? null,
      wins: stats.fixtures?.wins?.[role] ?? null,
      draws: stats.fixtures?.draws?.[role] ?? null,
      losses: stats.fixtures?.loses?.[role] ?? stats.fixtures?.losses?.[role] ?? null
    },
    goalsFor: {
      total: stats.goals?.for?.total?.[role] ?? null,
      average: stats.goals?.for?.average?.[role] ?? null
    },
    goalsAgainst: {
      total: stats.goals?.against?.total?.[role] ?? null,
      average: stats.goals?.against?.average?.[role] ?? null
    },
    cleanSheets: stats.clean_sheet?.[role] ?? null,
    failedToScore: stats.failed_to_score?.[role] ?? null
  };
}
async function collectEvidence(provider, question, context = {}, history = []) {
  // Current announcements require an announcement source, not unrelated fixtures.
  if (/\b(?:transfer|transfers|injury|injuries|injured|news|trend|trending)\b|انتقال|صفقة|اصابة|إصابة|إصابات|اصابات|أخبار|اخبار|ترند/i.test(question)) {
    const fetchedAt = Date.now();
    return { schema: 'fotiq-unavailable-announcement-v1', fetchedAt, retrievedAtUTC: new Date(fetchedAt).toISOString(),
      events: [], sources: [], facts: [], missing: ['No licensed and verified current announcement source is connected for transfers, injuries, news or trends. State this limitation. Do not use model memory, past chat claims, or fixture data as confirmation.'] };
  }
  const historical = await historicalKnowledge.collect(question);
  if (historical) {
    historical.fetchedAt ??= Date.now();
    historical.retrievedAtUTC ??= new Date(historical.fetchedAt).toISOString();
    return historical;
  }
  const sources = [], missing = [];
  const load = async (path, params) => {
    const r = await provider.load(path + '?' + new URLSearchParams(params));
    sources.push({ path, parameters: params, fetchedAt: r.fetchedAt });
    return r.data;
  };
  const evidence = { schema: 'fotiq-chat-evidence-v1', sources, missing, events: [],
    limitations: ['Starting lineups are not current tactical shape.', 'No causal claim or probability is established by match totals.', 'Retrieval time is not the provider update time.',
      'Player passing.keyPasses are chances created, not assists. passing.accuracyProviderValue has no verified unit and must not be printed as a percentage.'] };
  const namedTeams = aliases.filter(([, re]) => re.test(question)).map(([id]) => id);
  const namesPlayer = /\bhaaland\b|هالاند/i.test(question);
  const changesTopic = namesPlayer || namedTeams.length > 0 || /\blive\b|مباشر|premier league|الدوري الإنجليزي|الدوري الانجليزي/i.test(question);
  const previousQuestion = [...history].reverse().find(m => m.role === 'user')?.content || '';
  const routingQuestion = changesTopic ? question : question + ' ' + previousQuestion;
  const teamIds = namesPlayer ? [] : namedTeams.length ? namedTeams : context.teamIds || [];

  // Identity alias only; profile and every statistic are still retrieved fresh.
  const namedPlayerIds = namesPlayer ? [1100] : [];
  const playerIds = namedPlayerIds.length ? namedPlayerIds : context.playerIds || [];
  const seasonComparison = teamIds.length === 2 && /season|الموسم/i.test(question);
  if (seasonComparison) {
    evidence.seasonOnlyComparison = true;
    evidence.limitations.push('Season-only comparison: no individual match results supplied. Do not invent scorelines or reconstruct season totals from recent fixtures.');
  }
  const upcoming = /upcoming|next match|قادمة|القادمة|قادمه/i.test(routingQuestion);
  const live = /\blive\b|مباشر/i.test(routingQuestion);
  const lastFive = /last five|last 5|آخر خمس|اخر خمس|آخر 5/i.test(routingQuestion);
  let fixtureId = changesTopic ? undefined : context.fixtureId;
  if (!fixtureId && live) {
    const matches = await load('/fixtures', { live: 'all' });
    fixtureId = matches[0]?.fixture?.id;
    evidence.selection = 'First currently live fixture returned by API-Football; not a user-selected match.';
    if (!fixtureId) missing.push('No live match was returned.');
  }
  if (teamIds.length) {
    evidence.clubs = [];
    for (const team of teamIds) {
      const fixtures = seasonComparison ? [] : await load('/fixtures', { team, [upcoming ? 'next' : 'last']: upcoming ? 1 : 5 });
      const club = { teamId: team,
        recentScope: 'Latest fixtures across competitions as returned by API-Football; inspect each match league before making competition-specific claims.',
        matches: fixtures.map(summary), recentResultsNewestFirst: upcoming ? [] : clubResults(fixtures, team) };
      let league = fixtures[0]?.league;
      if (teamIds.length === 2) {
        const leagues = await load('/leagues', { team, current: 'true', type: 'league' });
        const domestic = leagues.find(l => l.league?.type === 'League' && l.seasons?.some(s => s.current));
        league = domestic ? { ...domestic.league, season: domestic.seasons.find(s => s.current).year } : undefined;
        if (seasonComparison) { delete club.matches; delete club.recentResultsNewestFirst; delete club.recentScope; }
        if (!league) missing.push(`Current domestic league season unavailable for club ${team}; no alternative competition inferred.`);
      }
      if (league?.id && league?.season) {
        const stats = await load('/teams/statistics', { team, league: league.id, season: league.season });
        club.season = { scope: `Season aggregate for ${league.name} only`, league: league.name, year: league.season, fixtures: stats.fixtures,
          goals: stats.goals, form: stats.form, cleanSheet: stats.clean_sheet, failedToScore: stats.failed_to_score };
        if (seasonComparison) {
          const value = n => typeof n === 'number' && Number.isFinite(n) ? n : null;
          club.season = { league: league.name, year: league.season, scope: 'Current domestic league only; season totals, not recent match results',
            totals: { played: value(stats.fixtures?.played?.total), wins: value(stats.fixtures?.wins?.total), draws: value(stats.fixtures?.draws?.total), losses: value(stats.fixtures?.loses?.total ?? stats.fixtures?.losses?.total),
              goalsFor: value(stats.goals?.for?.total?.total), goalsAgainst: value(stats.goals?.against?.total?.total), cleanSheets: value(stats.clean_sheet?.total), failedToScore: value(stats.failed_to_score?.total) } };
          const t = club.season.totals;
          if ([t.played,t.wins,t.draws,t.losses].every(n => n !== null) && t.played !== t.wins+t.draws+t.losses) {
            club.season.totals = null; missing.push(`Conflicting season totals for club ${team}; do not use them.`);
          }
        }
        if (upcoming) {
          const role = fixtures[0]?.teams?.home?.id === team ? 'home' : fixtures[0]?.teams?.away?.id === team ? 'away' : null;
          club.nextFixtureVenue = relevantVenueSeason(stats, role);
        }
      }
      evidence.clubs.push(club);
      // "Why lost last game" must use the actual last game, not search backwards for a loss.
      if (teamIds.length === 1 && !fixtureId) fixtureId = fixtures[0]?.fixture?.id;
    }
  }
  if (upcoming && evidence.clubs?.length === 1) {
    const club = evidence.clubs[0], next = club.matches[0];
    const clubRecent = await load('/fixtures', { team: club.teamId, last: 5 });
    club.recentMatches = clubRecent.map(summary);
    club.recentResultsNewestFirst = clubResults(clubRecent, club.teamId);
    const opponent = [next?.teams?.home?.id, next?.teams?.away?.id].find(id => Number.isInteger(id) && id !== club.teamId);
    if (opponent) {
      const recent = await load('/fixtures', { team: opponent, last: 5 });
      const other = { teamId: opponent,
        recentScope: 'Latest fixtures across competitions as returned by API-Football; inspect each match league before making competition-specific claims.',
        matches: recent.map(summary), recentResultsNewestFirst: clubResults(recent, opponent) };
      if (next.league?.id && next.league?.season) {
        const stats = await load('/teams/statistics', { team: opponent, league: next.league.id, season: next.league.season });
        other.season = { scope: `Season aggregate for ${next.league.name} only`, league: next.league.name, year: next.league.season, fixtures: stats.fixtures,
          goals: stats.goals, form: stats.form, cleanSheet: stats.clean_sheet, failedToScore: stats.failed_to_score };
        const role = next.teams?.home?.id === opponent ? 'home' : next.teams?.away?.id === opponent ? 'away' : null;
        other.nextFixtureVenue = relevantVenueSeason(stats, role);
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
    missing.push('Ask the user to name the player in the conversation; do not guess which player they mean.');
  }
  if (!sources.length) missing.push('Ask the user to specify a match, supported club, or player. No facts have been retrieved for this question.');
  if (Buffer.byteLength(JSON.stringify(evidence)) > 17500 && evidence.players) {
    delete evidence.players; missing.push('Individual match-player statistics omitted to fit the evidence budget; do not infer individual ratings.');
  }
  evidence.followUpContext = {
    ...(fixtureId ? { fixtureId } : {}),
    ...(teamIds.length ? { teamIds } : {}),
    ...(playerIds.length ? { playerIds } : {})
  };
  evidence.fetchedAt = sources.length ? Math.min(...sources.map(s => s.fetchedAt)) : Date.now();
  evidence.retrievedAtUTC = new Date(evidence.fetchedAt).toISOString();
  return evidence;
}
module.exports = { collectEvidence };
