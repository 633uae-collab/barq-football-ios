const { test } = require('node:test');
const assert = require('node:assert/strict');
const { prepareEvidence } = require('../analyst-evidence');
const named = (id,name) => ({id,name});
const t = named(1,'Team');
const a = named(10,'Starter'), b = named(20,'Substitute'), c = named(30,'Later substitute');
const fixture = () => ({ fixture: {id:1,date:'2026-11-06T19:30:00Z',status:{short:'2H',elapsed:80}}, lineups:[{team:t,formation:'3-5-2',startXI:[{player:a}],substitutes:[{player:b},{player:c}]}],events:[] });
test('goal assists stay null and substitutions use verified roster direction in either provider ordering', () => {
 const f=fixture(); f.events=[
 {type:'Goal',team:t,time:{elapsed:70},player:a,assist:{id:null,name:null}},
 {type:'subst',team:t,time:{elapsed:80},player:a,assist:b},
 {type:'subst',team:t,time:{elapsed:90,extra:2},player:c,assist:b}];
 const e=prepareEvidence(f,1794035241032);
 assert.equal(e.events[0].goalAssist,null);
 assert.equal(e.events[1].playerIn,'Substitute'); assert.equal(e.events[1].playerOut,'Starter');
 assert.equal(e.events[2].playerIn,'Later substitute'); assert.equal(e.events[2].playerOut,'Substitute');
 assert.equal('goalAssist' in e.events[1],false); assert.equal('assist' in e.events[1],false);
 assert.equal(e.events[2].minute,90); assert.equal(e.events[2].addedTime,2);
 assert.equal(e.kickoffUTC,'2026-11-06T19:30:00.000Z'); assert.equal(e.retrievedAtUTC,'2026-11-07T07:07:21.032Z');
 assert.equal(e.providerUpdatedAt,null); assert.equal(e.lineups[0].startingFormation,'3-5-2');
});
test('unknown or contradictory substitutions remain unknown rather than guessing field direction', () => {
 const f=fixture(); f.events=[{type:'subst',team:t,time:{elapsed:60},player:b,assist:c}];
 const e=prepareEvidence(f,1); assert.equal(e.events[0].playerIn,null);assert.equal(e.events[0].playerOut,null); assert.equal(e.warnings.length,1);
 delete f.lineups; assert.equal(prepareEvidence(f,1).events[0].playerIn,null);
});
test('aggregate contradictions are surfaced and red-carded players cannot be substituted', () => {
 const f=fixture(); f.events=[{type:'Card',detail:'Yellow Card',team:t,player:a,time:{elapsed:30}}, {type:'Card',detail:'Red Card',team:t,player:a,time:{elapsed:49}}, {type:'subst',team:t,player:a,assist:b,time:{elapsed:50}}];
 f.statistics=[{team:t,statistics:[{type:'Yellow Cards',value:0}]}];
 const e=prepareEvidence(f,1); assert.equal(e.events[2].playerOut,null); assert.ok(e.warnings.some(s=>s.includes('differs')));
 assert.equal(e.statistics[0].values[0].value,0);
});
test('live first-half goals never become a completed halftime result', () => {
 const f=fixture(); f.fixture.status={short:'1H',elapsed:17}; f.goals={home:1,away:0}; f.score={halftime:{home:0,away:0},fulltime:{home:null,away:null}};
 const e=prepareEvidence(f,1000);
 assert.deepEqual(e.currentScore,{home:1,away:0}); assert.equal(e.completedPeriodScores.halftime,null);
 assert.equal(e.completedPeriodScores.fulltime,null); assert.equal('score' in e,false);
 f.fixture.status.short='HT'; f.score.halftime={home:1,away:0};
 assert.deepEqual(prepareEvidence(f,1000).completedPeriodScores.halftime,{home:1,away:0});
});
