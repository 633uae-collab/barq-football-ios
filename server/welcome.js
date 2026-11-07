'use strict';
const FALLBACK = { ar: 'كل سؤال في بالك عن الكورة، جوابه هني.', en: 'Every football question on your mind, answered here.' };
const IMPORTANT = new Set([1,2,3,4,9,15,17,39,78,135,140,61,307,301]);
function selectEvent(fixtures, now) {
  return fixtures.flatMap(f => {
    if (!IMPORTANT.has(f.league?.id) || !f.teams?.home?.name || !f.teams?.away?.name || !Number.isSafeInteger(f.fixture?.id)) return [];
    const kickoff = Date.parse(f.fixture.date), status = f.fixture.status?.short;
    if (!Number.isFinite(kickoff)) return [];
    let phase;
    if (['1H','HT','2H','ET','BT','P','INT'].includes(status) && now >= kickoff && now-kickoff < 4*3600000) phase='live';
    else if (status==='NS' && kickoff>now && kickoff-now<=6*3600000) phase='before';
    else if (['FT','AET','PEN'].includes(status) && now>=kickoff && now-kickoff<=6*3600000) phase='after';
    if (!phase) return [];
    return [{ id:f.fixture.id, phase, kickoff, home:f.teams.home.name, away:f.teams.away.name, league:f.league.name }];
  }).sort((a,b) => ['live','before','after'].indexOf(a.phase)-['live','before','after'].indexOf(b.phase) || Math.abs(a.kickoff-now)-Math.abs(b.kickoff-now) || a.id-b.id)[0];
}
function validInvitation(text, lang) {
  if (typeof text!=='string' || text.length>95 || text.length<8 || /[\n\r\d٠-٩<>]/.test(text)) return false;
  if (!/[?؟]$/.test(text.trim())) return false;
  if (/فاز|خسر|انتقل|صفقة|إصابة|اصابه|سجل|حسم|طرد|فوز|خسار|\b(won|lost|transfer|signed|injur|scored|winner)\b/i.test(text)) return false;
  return lang==='ar' ? /^(وش|شو|كيف|ما|هل|أي|اي)\s/.test(text) : /^(What|How|Want|Curious|Which|Would)\b/i.test(text);
}
class WelcomeService {
  constructor({ provider, analyst, now=()=>Date.now() }) {
    Object.assign(this,{provider,analyst,now}); this.checkedAt=-Infinity; this.sourceExpiresAt=0; this.event=undefined; this.texts=new Map(); this.generating=null; this.refreshing=null;
    this.day=''; this.count=0; this.nextGeneration=0;
  }
  fallback(lang) { return {text:FALLBACK[lang],dynamic:false,expiresAt:this.now()+60000}; }
  async refresh() {
    if (this.now()-this.checkedAt<60000) return;
    if (this.refreshing) return this.refreshing;
    this.refreshing=(async()=>{
      this.event=undefined;
      try {
        const now=this.now(), date=new Date(now).toISOString().slice(0,10);
        const r=await this.provider.load('/fixtures?'+new URLSearchParams({date,timezone:'UTC'}));
        const receivedAt=this.now();
        if (!r.stale && Number.isFinite(r.fetchedAt) && receivedAt-r.fetchedAt>=0 && receivedAt-r.fetchedAt<=120000) {
          this.event=selectEvent(r.data,receivedAt);
          this.sourceExpiresAt=r.fetchedAt+120000;
        }
      } catch { /* A stale or unavailable source must withdraw the event. */ }
      this.checkedAt=this.now();
    })().finally(()=>{this.refreshing=null;});
    return this.refreshing;
  }
  async get(rawLang) {
    const lang=rawLang==='en'?'en':'ar';
    await this.refresh();
    const event=this.event, now=this.now();
    if (!event || now>=this.sourceExpiresAt || now-this.checkedAt>=60000) return this.fallback(lang);
    if (event.phase==='before' && now>=event.kickoff) return this.fallback(lang);
    const key=event.id+':'+event.phase+':'+lang;
    if (!this.texts.has(key)) {
      const day=new Date(now).toISOString().slice(0,10);
      if (day!==this.day) {this.day=day;this.count=0;}
      if (this.generating || this.count>=4 || now<this.nextGeneration || this.analyst.active || now<this.analyst.blockedUntil || !this.analyst.chatEnabled || !this.analyst.freePlanConfirmed || !this.analyst.key) return this.fallback(lang);
      this.count++; this.nextGeneration=now+15*60000;
      this.generating=(async()=>{
        try {
          const text=(await this.analyst.welcome(event,lang)).trim();
          if (validInvitation(text,lang)) {
            if (this.texts.size>=64) this.texts.delete(this.texts.keys().next().value);
            this.texts.set(key,text);
          }
        } catch { /* Safe generic welcome on quota, timeout or invalid generation. */ }
      })().finally(()=>{this.generating=null;});
      await this.generating;
    }
    const invitation=this.texts.get(key), current=this.now();
    if (!invitation || current>=this.sourceExpiresAt || current-this.checkedAt>=60000 || (event.phase==='before' && current>=event.kickoff)) return this.fallback(lang);
    const phase=lang==='ar'?{before:'قريباً',live:'مباشر الآن',after:'انتهت المباراة'}:{before:'Coming up',live:'Live now',after:'Match finished'};
    // Event identity and timing are provider-owned; Groq writes only the invitation.
    return {text:`${event.home} × ${event.away} — ${phase[event.phase]}. ${invitation}`,dynamic:true,
      expiresAt:Math.min(this.sourceExpiresAt,this.checkedAt+60000,event.phase==='before'?event.kickoff:Infinity),fixtureId:event.id,phase:event.phase};
  }
}
function mountWelcome(app, dependencies) {
  const service=new WelcomeService(dependencies);
  app.get('/api/analyst/welcome',async(req,res)=>res.json(await service.get(req.query.lang)));
}
module.exports={WelcomeService,selectEvent,validInvitation,mountWelcome,FALLBACK};
