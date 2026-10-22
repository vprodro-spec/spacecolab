const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');
const tick=async()=>{for(let i=0;i<16;i++)await new Promise(r=>setImmediate(r));};
function context(y){return {pharmacy_id:'fixture-pharmacy',pharmacy_name:'Fixture',registry:{legacy:false},installation:{version:1,service_from:'2026-10-01',positions:[{id:'hq',ordinal:0,type:'hq',screenFormat:'vertical',startsOn:'2026-10-01'},{id:'base-1',ordinal:1,type:'base',title:'Θέση 1',screenFormat:'vertical',startsOn:'2026-10-01'}]},state_json:{turnover:500000,cards:[{id:'base-1',type:'base',initialPlanLocked:true,basicSchedule:Array(12).fill('Έτος '+y),simpleSchedule:Array(12).fill('Έτος '+y),confirmedDeals:[],preagreements:[],sponsoredShelves:[]}]},snapshot_revision:1,available_years:[2026,2027,2028]};}
async function app(handler=()=>{}){const calls=[];const x=await smoke(html,'pharmacy',null,async(n,a)=>{calls.push({name:n,args:a});const res=await handler(n,a);if(res!==undefined)return res;if(n==='scl290_get_pharmacy')return {data:context(a.p_year),error:null};});assert.deepEqual(x.errors,[]);return {...x,requests:calls,run:s=>vm.runInContext(s,x.ctx)};}

test('latest year selection wins during a slow read, with no programme write or stale year commit',async()=>{
 let slow=false,release;const x=await app((n,a)=>slow&&n==='scl290_get_pharmacy'&&a.p_year===2027?new Promise(r=>release=()=>r({data:context(2027),error:null})):undefined);
 slow=true;const p=x.run('loadYear(2027)');await tick();
 assert.equal(x.ctx.SCL290.loading,true);assert.equal(x.document.getElementById('plannerPage').inert,true);
 const latest=x.run('loadYear(2028)');await tick();release();await Promise.all([p,latest]);await tick();
 assert.equal(x.run('state.programYear'),2028);assert.equal(x.run('state.cards.find(c=>c.id==="base-1").basicSchedule[0]'),'Έτος 2028');
 assert.equal(x.ctx.SCL290.loading,false);assert.equal(x.document.getElementById('plannerPage').inert,false);
 assert.match(x.document.getElementById('timelineGrid').textContent,/2028/);
 assert.equal(x.requests.filter(r=>/save_program|upsert_pharmacy/.test(r.name)).length,0);
});

test('failed year read preserves the prior year and retry opens the intended year',async()=>{
 let fail=false;const x=await app(n=>fail&&n==='scl290_get_pharmacy'?{data:null,error:{message:'TypeError: Failed to fetch'}}:undefined);
 const prior=x.run('JSON.stringify(state.cards)');fail=true;await assert.rejects(x.run('loadYear(2027)'));
 assert.equal(x.run('state.programYear'),2026);assert.equal(x.run('JSON.stringify(state.cards)'),prior);assert.equal(x.run('SCL_ROUTING.ready'),true);
 assert.equal(x.ctx.SCL290.failedYear,2027);assert.equal(x.ctx.SCL290.loading,false);
 assert.match(x.document.getElementById('scl290Notice').textContent,/2027.*2026/);
 fail=false;await x.click(x.document.querySelector('[data-scl295="reload"]'));await tick();
 assert.equal(x.run('state.programYear'),2027);assert.equal(x.ctx.SCL290.failedYear,null);
 assert.equal(x.document.getElementById('scl290Notice').hidden,true);
});

test('interrupted next-year preparation cannot save its template into another year',async()=>{
 let slow=false,release;const x=await app((n,a)=>{
  if(slow&&n==='scl290_get_pharmacy'&&a.p_year===2027)return new Promise(r=>release=()=>r({data:{...context(2027),state_json:null,snapshot_revision:0},error:null}));
  if(n==='scl290_get_pharmacy'&&a.p_year===2028)return {data:{...context(2028),state_json:null,snapshot_revision:0},error:null};
 });
 slow=true;const pending=x.run('createNextProgramYear()');await tick();const latest=x.run('loadYear(2028)');release();await Promise.all([pending,latest]);await tick();
 assert.equal(x.run('state.programYear'),2028);
 assert.equal(x.requests.filter(r=>r.name==='scl290_save_program').length,0);
});

test('a stalled read times out, unlocks navigation and cannot later overwrite a recovered year',async()=>{
 let slow=false,release;const x=await app((n,a)=>slow&&n==='scl290_get_pharmacy'?new Promise(r=>release=()=>r({data:context(a.p_year),error:null})):undefined);
 let timeout;const nativeTimer=x.ctx.setTimeout;x.ctx.setTimeout=(fn,ms,...args)=>{if(ms===20000){timeout=fn;return 10000;}return nativeTimer(fn,ms,...args);};
 slow=true;const pending=x.run('loadYear(2027)');const rejected=assert.rejects(pending);await tick();assert.equal(typeof timeout,'function');timeout();await rejected;
 assert.equal(x.ctx.SCL290.loading,false);assert.equal(x.run('state.programYear'),2026);
 slow=false;await x.run('loadYear(2028)');release();await tick();
 assert.equal(x.run('state.programYear'),2028);assert.equal(x.run('state.cards.find(c=>c.id==="base-1").basicSchedule[0]'),'Έτος 2028');
});

test('startup failure can recover through a server-backed year load',async()=>{
 let fail=true;const x=await app(n=>fail&&n==='scl290_get_pharmacy'?{data:null,error:{message:'TypeError: Failed to fetch'}}:undefined);
 assert.equal(x.ctx.SCL290.context,null);fail=false;await x.run('loadYear(2027)');await tick();
 assert.equal(x.run('state.programYear'),2027);assert.equal(x.run('SCL_ROUTING.ready'),true);assert.equal(x.ctx.SCL290.context.snapshot_revision,1);
});

test('finance failure does not trigger render-driven retries; a successful explicit retry clears the error',async()=>{
 let fail=false;const x=await app(n=>fail&&n==='scl292_finance'?{data:null,error:{message:'TypeError: Failed to fetch'}}:undefined);
 fail=true;await assert.rejects(x.ctx.SCL292.loadFinance(true));const count=x.requests.filter(r=>r.name==='scl292_finance').length;
 for(let i=0;i<5;i++)x.ctx.SCL292.renderEconomics();await tick();
 assert.equal(x.requests.filter(r=>r.name==='scl292_finance').length,count);assert.match(x.document.getElementById('economicsGrid').textContent,/Δεν φορτώθηκαν/);
 fail=false;await x.ctx.SCL292.loadFinance(true);
 assert.equal(x.document.getElementById('scl292Status').hidden,true);assert.equal(x.ctx.SCL292.errorKey,'');assert.match(x.document.getElementById('economicsGrid').textContent,/Συμφωνημένα έσοδα/);
});

test('concurrent forced finance refreshes share one follow-up request',async()=>{
 let slow=false,release;const x=await app((n,a)=>{if(slow&&n==='scl292_finance'){slow=false;return new Promise(r=>release=()=>r({data:{year:a.p_year,rows:[],requests:[],history:[]},error:null}));}});
 const count=x.requests.filter(r=>r.name==='scl292_finance').length;slow=true;
 const a=x.ctx.SCL292.loadFinance(true),b=x.ctx.SCL292.loadFinance(true),c=x.ctx.SCL292.loadFinance(true);await tick();release();await Promise.all([a,b,c]);
 assert.equal(x.requests.filter(r=>r.name==='scl292_finance').length-count,2);
});
