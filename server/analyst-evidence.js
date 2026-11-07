'use strict';
// Deterministic source preparation. Never ask a language model to decode overloaded
// provider fields or convert timestamps. Unknown/contradictory facts remain unknown.
function prepareEvidence(f, fetchedAt) {
  const iso = value => { const d = new Date(value); return value != null && Number.isFinite(d.valueOf()) ? d.toISOString() : null; };
  const warnings = [];
  const state = f.fixture?.status?.short;
  const halfComplete = ['HT', '2H', 'ET', 'BT', 'P', 'FT', 'AET', 'PEN'].includes(state);
  const matchComplete = ['FT', 'AET', 'PEN'].includes(state);
  const completedPeriodScores = { halftime: halfComplete ? (f.score?.halftime ?? null) : null,
    fulltime: matchComplete ? (f.score?.fulltime ?? null) : null };
  if (!halfComplete) warnings.push('First-half score is not final yet. Never call a provisional halftime field the current score.');
  const rosters = new Map();
  const lineups = (f.lineups || []).map(l => {
    const starters = l.startXI || [], bench = l.substitutes || [];
    rosters.set(l.team?.id, { on: new Set(starters.map(x => x.player?.id).filter(Number.isInteger)),
      bench: new Set(bench.map(x => x.player?.id).filter(Number.isInteger)) });
    return { team: l.team?.name, startingFormation: l.formation ?? null, coach: l.coach?.name ?? null,
      startingXI: starters.map(x => ({ name: x.player?.name, position: x.player?.pos, number: x.player?.number })) };
  });
  const events = [...(f.events || [])].sort((a,b) => (a.time?.elapsed ?? 0)-(b.time?.elapsed ?? 0) || (a.time?.extra ?? 0)-(b.time?.extra ?? 0)).map((e, index) => {
    const event = { sourceId: `event-${index}`, minute: e.time?.elapsed ?? null, addedTime: e.time?.extra ?? null,
      team: e.team?.name, type: e.type, detail: e.detail };
    if (String(e.type).toLowerCase() === 'subst') {
      const roster = rosters.get(e.team?.id), p = e.player?.id, a = e.assist?.id;
      let incoming = null, outgoing = null;
      // Infer only when the supplied starting XI + bench establish both roles.
      if (roster?.on.has(p) && roster.bench.has(a)) { outgoing = e.player; incoming = e.assist; }
      else if (roster?.on.has(a) && roster.bench.has(p)) { outgoing = e.assist; incoming = e.player; }
      if (incoming && outgoing) {
        roster.on.delete(outgoing.id); roster.bench.delete(incoming.id); roster.on.add(incoming.id);
        return { ...event, playerIn: incoming.name, playerOut: outgoing.name, directionBasis: 'starting XI and substitution sequence' };
      }
      warnings.push(`${event.sourceId}: substitution direction cannot be verified from supplied lineups`);
      return { ...event, playerIn: null, playerOut: null, participants: [e.player?.name, e.assist?.name].filter(Boolean) };
    }
    if (String(e.type).toLowerCase() === 'card' && /red/i.test(e.detail || '')) rosters.get(e.team?.id)?.on.delete(e.player?.id);
    return { ...event, player: e.player?.name ?? null,
      ...(String(e.type).toLowerCase() === 'goal' ? { goalAssist: e.assist?.name ?? null } : {}) };
  });
  const statistics = (f.statistics || []).map(s => {
    const values = s.statistics || [];
    const yellow = values.find(x => x.type === 'Yellow Cards')?.value;
    const eventYellows = (f.events || []).filter(e => e.team?.id === s.team?.id && e.type === 'Card' && /yellow/i.test(e.detail || '')).length;
    if (typeof yellow === 'number' && yellow !== eventYellows) warnings.push(`${s.team?.name}: yellow-card aggregate (${yellow}) differs from supplied event count (${eventYellows}); do not resolve silently`);
    return { team: s.team?.name, values };
  });
  return { schema: 'fotiq-match-evidence-v2', fetchedAt, retrievedAtUTC: iso(fetchedAt), providerUpdatedAt: null,
    kickoffUTC: iso(f.fixture?.date), fixtureId: f.fixture?.id, status: f.fixture?.status ?? null,
    league: { name: f.league?.name, season: f.league?.season, round: f.league?.round },
    teams: { home: f.teams?.home?.name, away: f.teams?.away?.name }, goals: f.goals, currentScore: f.goals ?? null, completedPeriodScores,
    events, lineups, statistics, warnings,
    limitations: ['Lineups and formations describe kickoff, not confirmed current tactical shape.',
      'Whole-match statistics do not establish before/after red-card or substitution effects.',
      'Null goalAssist means unreported; never borrow a participant from a substitution.',
      'Retrieval time is not kickoff time or the provider last-update time.'] };
}
module.exports = { prepareEvidence };
