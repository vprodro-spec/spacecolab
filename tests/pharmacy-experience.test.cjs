const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8'),seed=JSON.parse(fs.readFileSync('data/library-seed.json','utf8'));
const theme=seed.themes.find(t=>t.status==='available').key;
const card=(id='base-1')=>({id,type:'base',title:'Θέση 1',initialPlanLocked:true,basicSchedule:Array(12).fill(theme),simpleSchedule:Array(12).fill(theme),simpleConfirmed:false,confirmedDeals:[],preagreements:[],sponsoredShelves:[]});
const tick=async()=>{for(let i=0;i<16;i++)await new Promise(r=>setImmediate(r));};
function controls(x){return {run:s=>vm.runInContext(s,x.ctx),click:async sel=>{const e=x.document.querySelector(sel);assert.ok(e,sel);await x.click(e);await tick();},text:id=>x.document.getElementById(id)?.textContent||''};}

test('local HTML onboarding requires a selected turnover; selection is unsaved and saved amounts survive later edits',async()=>{
 const writes=[];let saved=null;
 const x=await smoke(html,'pharmacy',{turnover:0,cards:[]},async(n,a)=>{if(n==='scl290_save_program'){writes.push(structuredClone(a));saved=a.p_state;return {data:{snapshot_revision:writes.length},error:null};}}, {baseUrl:'file:///C:/Users/Test/Downloads/SpaceCoLab_v295.html'});
 const {click,run,text}=controls(x);assert.deepEqual(x.errors,[]);assert.equal(run('state.turnover'),0);assert.equal(run('SCL295.page'),'overview');assert.match(text('scl295Profile'),/υποχρεωτική/);
 assert.equal(x.document.querySelector('[data-scl295="save-turnover"]').disabled,true);
 await click('[data-scl295="turnover"][data-value="1000000"]');assert.equal(writes.length,0);assert.equal(run('state.turnover'),0);assert.match(text('scl295Profile'),/Συμφωνία προμηθευτή/);
 await click('[data-scl295="save-turnover"]');assert.equal(saved.turnover,1000000);assert.equal(run('SCL295.page'),'planner');assert.equal(run('SCL290.dirty'),false);
 const reentry=await smoke(html,'pharmacy',saved);assert.equal(reentry.ctx.SCL295.page,'planner');
 const storedDeal={id:'deal',confirmed:true,startMonth:11,duration:1,brand:'Brand',supplier:'Supplier',soldMonthlyPrice:175};
 run(`state.cards.find(c=>c.id==='base-1').confirmedDeals=[${JSON.stringify(storedDeal)}];state.cards.find(c=>c.id==='base-1').sponsoredShelves=[{id:'s',month:9,brand:'Shelf',price:67}];refresh(false)`);
 await click('[data-scl295="page"][data-page-value="overview"]');await click('[data-scl295="edit-turnover"]');await click('[data-scl295="turnover"][data-value="2000000"]');await click('[data-scl295="save-turnover"]');
 assert.equal(run("state.cards.find(c=>c.id==='base-1').confirmedDeals[0].soldMonthlyPrice"),175);assert.equal(run("state.cards.find(c=>c.id==='base-1').sponsoredShelves[0].price"),67);
 assert.equal(x.document.querySelector('[data-toggle-setup]'),null);assert.equal(x.document.querySelector('[data-counters]'),null);
});

test('initial programme discards drafts, names missing months, previews HQ format, then saves one completed position',async()=>{
 const writes=[];const x=await smoke(html,'pharmacy',{turnover:500000,cards:[]},async(n,a)=>{if(n==='scl290_save_program'){writes.push(structuredClone(a));return {data:{snapshot_revision:1},error:null};}});
 const {click,run,text}=controls(x);assert.deepEqual(x.errors,[]);
 run("renderInitialPlanModal('base-1')");await tick();
 assert.equal(run('SCL293.initial.refs.filter(Boolean).length'),0);assert.match(text('programModalBody'),/Ιαν–Σεπ/);
 await click('[data-scl293="initial-lock"]');assert.match(text('scl295InitialError'),/Οκτ, Νοε, Δεκ/);assert.equal(writes.length,0);
 await click('[data-scl293="initial-select"]');const draft=run('SCL293.initial.refs[9].theme');assert.ok(draft);assert.equal(writes.length,0);
 await click('[data-scl293="preview"]');assert.match(text('planogramModalBody'),/Κάθετη οθόνη/);assert.equal(x.document.querySelectorAll('[data-scl293="preview-setup"]').length,3);
 run("closeModal('planogramModal')");run('window.confirm=()=>false');run("closeModal('programModal')");assert.ok(run('SCL293.initial'));
 run('window.confirm=()=>true');run("closeModal('programModal')");assert.equal(run('SCL293.initial'),null);assert.equal(writes.length,0);
 run("renderInitialPlanModal('base-1')");await tick();assert.equal(run('SCL293.initial.refs.filter(Boolean).length'),0);
 const select=x.document.getElementById('scl293InitialProgram');Object.defineProperty(select,'value',{value:seed.programs[0].id,writable:true,configurable:true});select.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));await tick();
 await click('[data-scl293="initial-lock"]');assert.equal(writes.length,1);assert.equal(run("state.cards.find(c=>c.id==='base-1').initialPlanLocked"),true);assert.equal(run('SCL293.initial'),null);
 assert.ok(writes[0].p_months.filter(r=>r.position_id==='base-1').every(r=>r.month>=9));
 run("renderInitialPlanModal('base-1')");assert.match(text('scl295Notice'),/έγκριση/);
});

test('failed initial submission stays unlocked and keeps choices available for retry',async()=>{
 const x=await smoke(html,'pharmacy',{turnover:500000,cards:[]},async(n)=>n==='scl290_save_program'?{data:null,error:{message:'Connection unavailable'}}:undefined);
 const {click,run,text}=controls(x);run("renderInitialPlanModal('base-1')");await tick();run('SCL293.initial.refs=JSON.parse(JSON.stringify(SCL293.data.programs[0].months));SCL293.initialPicker()');
 await click('[data-scl293="initial-lock"]');assert.equal(run("state.cards.find(c=>c.id==='base-1').initialPlanLocked"),false);assert.ok(run('SCL293.initial'));assert.match(text('scl295InitialError'),/Δεν οριστικοποιήθηκε/);
});

test('cards use real current and next year; annual view distinguishes agreements and shelf sponsorship without changing finance',async()=>{
 const c=card();c.preagreements=[{id:'pre',brand:'Pre Brand',startMonth:11,duration:1}];c.sponsoredShelves=[{id:'shelf',brand:'Shelf Brand',month:11,price:75}];
 let writes=0;const x=await smoke(html,'pharmacy',{turnover:500000,cards:[c]},async(n,a)=>{
  if(n==='scl290_save_program')writes++;
  if(n==='scl290_get_pharmacy'&&a.p_year===2027)return{data:{state_json:{cards:[{...c,initialPlanLocked:false}]}},error:null};
  if(n==='pharmacy_get_pharmaplus_campaigns')return {data:[{month:a.p_year===2027?0:11,display_kind:'fallback',display_title:'PP '+a.p_year}],error:null};
 },{now:'2026-12-20T12:00:00Z'});
 const {click,run,text}=controls(x);await tick();assert.deepEqual(x.errors,[]);assert.match(text('cards'),/Δεκ 2026/);assert.match(text('cards'),/Ιαν 2027/);assert.match(text('cards'),/PP 2027/);assert.match(text('cards'),/Εκκρεμεί αρχικό πρόγραμμα/);
 assert.match(text('timelineGrid'),/Προσυμφωνία · Pre Brand/);assert.match(text('timelineGrid'),/Χορηγία ραφιών · Shelf Brand/);assert.doesNotMatch(text('cards'),/Fixed|Pending|Ζωντανή|Συμφων\./);
 await click('[data-scl295="position"][data-card="base-1"]');assert.match(text('plannerRoot'),/Ιαν–Σεπ/);assert.equal(x.document.querySelector('[data-scl295="custom"]').disabled,true);
 await click('[data-scl295="shelf-view"]');assert.match(text('scl295Dialog'),/75/);assert.equal(x.document.querySelector('#scl295Dialog [data-save-sponsored]'),null);assert.equal(writes,0);
});
