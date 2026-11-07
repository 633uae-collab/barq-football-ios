const {test}=require('node:test');
const assert=require('node:assert/strict');
const {WelcomeService,selectEvent,validInvitation,FALLBACK}=require('../welcome');
const {GroqAnalyst}=require('../groq');
const epoch=1794078000000;
const fixture=(status='1H',time=epoch-600000)=>({fixture:{id:7,date:new Date(time).toISOString(),status:{short:status}},league:{id:39,name:'Premier League'},teams:{home:{name:'Home'},away:{name:'Away'}}});
test('welcome selects only recent supported factual phases; not postponed or unverified news',()=>{
 assert.equal(selectEvent([fixture()],epoch).phase,'live');
 assert.equal(selectEvent([fixture('NS',epoch+60000)],epoch).phase,'before');
 assert.equal(selectEvent([fixture('FT')],epoch).phase,'after');
 for(const status of ['PST','CANC','TBD']) assert.equal(selectEvent([fixture(status)],epoch),undefined);
 assert.equal(selectEvent([fixture('FT',epoch-7*3600000)],epoch),undefined);
 assert.equal(validInvitation('وش تبا تعرف عن مجريات المباراة؟','ar'),true);
 assert.equal(validInvitation('وش رأيك فاز الفريق بهدفين؟','ar'),false);
 assert.equal(validInvitation('What about the 2 goals?','en'),false);
});
test('welcome caches per event and phase, refreshes facts and withdraws stale data without generating answers',async()=>{
 let now=epoch,loads=0,calls=0,status='1H',stale=false;
 const service=new WelcomeService({now:()=>now,provider:{load:async()=>{loads++;return{data:[fixture(status)],fetchedAt:now,stale};}},analyst:{chatEnabled:true,freePlanConfirmed:true,key:'test',blockedUntil:0,welcome:async()=>{calls++;return 'وش تبا تعرف عن مجريات المباراة؟';}}});
 assert.equal((await service.get('ar')).dynamic,true);
 assert.equal((await service.get('ar')).dynamic,true);assert.equal(calls,1);assert.equal(loads,1);
 now+=61000;assert.equal((await service.get('ar')).dynamic,true);assert.equal(loads,2);assert.equal(calls,1);
 status='FT';now+=61000;assert.equal((await service.get('ar')).text,FALLBACK.ar); // generation cooldown
 now+=16*60000;assert.equal((await service.get('ar')).phase,'after');assert.equal(calls,2);
 stale=true;now+=61000;assert.equal((await service.get('ar')).dynamic,false);assert.equal(calls,2);
});
test('missing source, invalid output, network failures and quota all fall back without retries',async()=>{
 for(const mode of ['missing','invalid','network','quota']) {
 let calls=0;
 const service=new WelcomeService({now:()=>epoch,provider:{load:async()=>({data:mode==='missing'?[]:[fixture()],fetchedAt:epoch})},analyst:{chatEnabled:true,freePlanConfirmed:true,key:'test',blockedUntil:mode==='quota'?epoch+60000:0,welcome:async()=>{calls++;if(mode==='network')throw Error('offline');return 'Home won 3-0';}}});
 assert.equal((await service.get('ar')).text,FALLBACK.ar);
 await service.get('ar');assert.equal(calls,mode==='missing'||mode==='quota'?0:1);
 }
});
test('welcome uses GPT OSS 120B, sends phase only and honours upstream quota',async()=>{
 let count=0;
 const analyst=new GroqAnalyst({key:'test',freePlanConfirmed:true,chatEnabled:true,now:()=>epoch,fetchImpl:async(url,options)=>{
 count++;const body=JSON.parse(options.body);assert.equal(body.model,'openai/gpt-oss-120b');assert.deepEqual(JSON.parse(body.messages[1].content),{language:'en',phase:'live'});
 return new Response('{}',{status:429,headers:{'retry-after':'30'}});
 }});
 await assert.rejects(()=>analyst.welcome({phase:'live'},'en'));
 await assert.rejects(()=>analyst.welcome({phase:'live'},'en'));
 assert.equal(count,1);assert.equal(analyst.blockedUntil,epoch+30000);
});
