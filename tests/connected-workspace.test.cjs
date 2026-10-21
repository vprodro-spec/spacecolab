const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs'),C=require('../src/scl304-workspace-core'),PP=require('../src/scl300-pharmaplus-core');
const html=fs.readFileSync('index.html','utf8'),seed=JSON.parse(fs.readFileSync('data/library-seed.json','utf8'));
const theme=seed.themes.find(t=>t.status==='available');
const position={id:'base-1',ordinal:1,type:'base',title:'Θέση 1',startsOn:'2026-10-01',screenFormat:'vertical',playerCode:'ALPHA_ADV1_P'};
const card={...position,initialPlanLocked:true,basicSchedule:Array(12).fill(theme.key),confirmedDeals:[]};
const fixture=()=>({api_version:290,registry:[{id:'ra',pharmacy_id:'a',name:'Alpha',billing_code:'001'},{id:'rb',pharmacy_id:'b',name:'Beta',billing_code:'002'}],installations:[{pharmacy_id:'a',positions:[position]}],snapshots:[{pharmacy_id:'a',year:2026,state_json:{cards:[card]}}],setup:[],months:[],deals:[],base:{pharmacies:[],pharmacy_state:[],reports:[]}});
const tick=async()=>{for(let i=0;i<6;i++)await new Promise(r=>setImmediate(r));};
test('one pharmacy/period context crosses overview, changes and charges without copying status or losing empty selection',async()=>{
 const x=await smoke(html,'hq',null,async n=>n==='scl290_hq_data'?{data:fixture(),error:null}:n==='scl304_materials'?{data:{items:[]},error:null}:undefined);assert.deepEqual(x.errors,[]);
 const u=x.ctx.SCL303;u.overview.pharmacies=['a'];u.overview.months=[10,11];u.changes.status='done';
 vm.runInContext("scl212SetTab('billing')",x.ctx);assert.deepEqual([...u.billing.months],[10,11]);assert.deepEqual([...u.billing.pharmacies],['a']);assert.equal(u.billing.status,'');
 vm.runInContext("scl212SetTab('library');scl212SetTab('changes')",x.ctx);assert.deepEqual([...u.changes.months],[10,11]);assert.equal(u.changes.status,'done');
 const names=[...x.document.querySelectorAll('#scl303Changes [data-scl303-multi="pharmacies"]')].map(n=>n.value);assert.deepEqual(names,['a','b']);
 u.billing.months=[];assert.equal(u.visibleChanges().length,0);assert.equal(u.visibleCharges().length,0);
 u.billing.months=null;assert.equal(u.changes.months,null);assert.equal(JSON.parse(x.ctx.localStorage.getItem('scl304.context')).pharmacies[0],'a');
});
test('missing theme opens its exact orientation field and save returns to the prior tab with shared filters intact',async()=>{
 let saved=null;const library=JSON.parse(JSON.stringify(seed));const x=await smoke(html,'hq',null,async(n,a)=>{
 if(n==='scl290_hq_data')return{data:fixture(),error:null};if(n==='scl304_materials')return{data:{items:[]},error:null};if(n==='scl293_library')return{data:library,error:null};
 if(n==='scl293_save'){saved=a;const i=library.themes.findIndex(t=>t.id===a.p_id);library.themes[i]=a.p_data;return{data:{},error:null};}
 });const u=x.ctx.SCL303,w=x.ctx.SCL304;
 u.openChanges({month:9,status:''});u.changes.pharmacies=['a'];const r=u.visibleChanges()[0];assert.equal(C.source(r,{},library).id,theme.id);
 await w.openFile(r);assert.equal(vm.runInContext('SCL212.tab',x.ctx),'library');assert.equal(x.ctx.SCL293.editing.data.id,theme.id);
 const f=x.document.querySelector('#scl293Editor [name="file_vertical"]');assert.ok(f.closest('label').classList.contains('scl304-target'));f.value='EXACT_PORTRAIT.mp4';
 await x.ctx.SCL293.save();assert.equal(saved.p_media_mode,'correction');assert.equal(vm.runInContext('SCL212.tab',x.ctx),'changes');assert.deepEqual([...u.changes.pharmacies],['a']);assert.deepEqual([...u.changes.months],[9]);assert.equal(u.visibleChanges()[0].file,'EXACT_PORTRAIT.mp4');
 assert.equal(w.origin,null);assert.equal(u.visibleChanges()[0].id,r.id);
});
test('source routing distinguishes local theme, PP library theme, own PP theme, campaign and agreement',()=>{
 const r={year:2026,month:10,final_type:'pharmaplus',pp_kind:'main'},data={records:[{month_on:'2026-11-01',campaign_id:'c',campaign:{title:'Campaign'},thematic:{theme_id:theme.id,title:theme.title}}]};
 assert.equal(C.source(r,data,seed).kind,'campaign');assert.equal(C.source({...r,pp_kind:'fallback'},data,seed).kind,'theme');delete data.records[0].thematic.theme_id;
 assert.equal(C.source({...r,pp_kind:'fallback'},data,seed).kind,'pp-theme');assert.equal(C.source({...r,final_type:'deal'},data,seed).kind,'agreement');
 assert.deepEqual(C.context({months:['11',11,15,-1],pharmacies:[]}),{months:[11],pharmacies:[]});
});
test('supplier confirmation gives exact filenames per changed content, destination and deadline',async()=>{
 const st={turnover:500000,cards:[{...card,confirmedDeals:[{id:'d',confirmed:true,supplier:'SUPPLIER',brand:'BRAND',startMonth:10,duration:2,monthlyContentChanges:true,schedule:{10:'First',11:'Second'},soldMonthlyPrice:100}]}]};
 const x=await smoke(html,'pharmacy',st);vm.runInContext("SCL297.document('base-1',state.cards.find(c=>c.id==='base-1').confirmedDeals[0],'confirmation')",x.ctx);
 const text=x.ctx.SCL297.documentText;assert.match(text,/ακριβώς/);assert.match(text,/2026-11_PORTRAIT\.mp4/);assert.match(text,/2026-12_PORTRAIT\.mp4/);assert.match(text,/emitropoulou@pharmaplus.gr/);assert.match(text,/18\/10\/2026/);assert.match(text,/17\/11\/2026/);
 assert.doesNotMatch(x.document.querySelector('#briefModal .modal-head').textContent,/Supplier brief|format|blocks/);
});
test('overview keeps multiple month selection open and registry exposes the shared pharmacy restriction',async()=>{
 const x=await smoke(html,'hq',null,async n=>n==='scl290_hq_data'?{data:fixture(),error:null}:n==='scl304_materials'?{data:{items:[]},error:null}:undefined);
 const u=x.ctx.SCL303;vm.runInContext("scl212SetTab('overview')",x.ctx);u.overview.months=[10];u.overview.pharmacies=['a'];x.ctx.SCL302.render();
 const cb=x.document.querySelector('#scl302Overview [data-scl303-multi="months"][value="11"]');cb.checked=true;cb.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));
 assert.deepEqual([...u.common.months],[10,11]);assert.equal(x.document.querySelector('#scl302Overview [data-key="months"]').open,true);assert.equal(x.document.querySelectorAll('#scl302Overview .scl303-pp-summary').length,2);
 vm.runInContext("scl212SetTab('pharmacies')",x.ctx);assert.equal(x.document.querySelectorAll('#scl290RegistryRows article').length,1);assert.match(x.document.getElementById('scl304RegistryFilters').textContent,/Alpha/);
 vm.runInContext("scl212SetTab('stats')",x.ctx);assert.equal(x.document.querySelectorAll('#scl212Page-stats tbody tr').length,2);assert.match(x.document.getElementById('scl212Page-stats').textContent,/Alpha/);
});
