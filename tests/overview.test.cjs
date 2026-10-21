const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const C=require('../src/scl302-overview-core'),A=require('../src/scl292-core'),D=require('../src/scl297-actions-core');
const {smoke}=require('./fixtures/full-app.cjs');
const pos=(id,n)=>({id,ordinal:n,type:n?'base':'hq',startsOn:'2026-10-01',screenFormat:'vertical',playerCode:'TEST_ADV'+n+'_P',contentCode:'TEST_ADV'+n+'_P'});
function fixture(){
 const deal={id:'deal',confirmed:true,supplier:'Supplier',brand:'Brand',startMonth:9,duration:2,monthlyContentChanges:false,schedule:Array(12).fill('Material'),materialRequests:[{month:9,end:10,status:'awaiting',deadline:'2026-09-17'}]};
 return {api_version:290,registry:[{id:'r',pharmacy_id:'p',name:'Test pharmacy',billing_code:'A'},{id:'uninstalled',pharmacy_id:'u',name:'Uninstalled'},{id:'inactive',pharmacy_id:null,name:'Inactive'}],installations:[{pharmacy_id:'p',positions:[pos('hq',0),pos('base-1',1),pos('base-2',2)]}],snapshots:[{pharmacy_id:'p',year:2026,state_json:{cards:[{id:'base-1',type:'base',screenFormat:'vertical',initialPlanLocked:true,basicSchedule:Array(12).fill('Base'),confirmedDeals:[deal]},{id:'base-2',type:'base',initialPlanLocked:false}]}}],setup:[],months:[],deals:[],base:{pharmacy_state:[],pharmacies:[],reports:[]}};
}
const meta=()=>({today:'2026-10-21',deadlines:[{pharmacy_id:'p',year:2026,position_id:'base-2',due_on:'2026-10-19',revision:1}],requests:[{id:'q',pharmacy_id:'p',year:2026,position_id:'base-1',from_month:10,status:'pending',reason:'Reset'}]});
test('overview counts one task while waiting for material, ignores inactive pharmacy and PP initial setup, keeps overdue across years',()=>{
 const hq=fixture(),row={pharmacy_id:'p',year:2026,month:9,position_id:'base-1',final_type:'deal',final_title:'Brand',content_change_required:true};
 const build=(year,done={})=>C.build({hq,meta:meta(),year,month:0,today:'2026-10-21',rows:[row,row,{...row,pharmacy_id:'removed'}],done,taskKey:A.taskKey,active:A.active,dealAt:D.at,dealFiles:D.files,positionTitle:x=>'Θέση '+x});
 const m=build(2026);assert.equal(m.pharmacies.length,2);assert.equal(m.installation,1);assert.equal(m.pending,1);assert.equal(m.open.length,3);assert.equal(m.all.filter(t=>t.material).length,1);assert.equal(m.overdue.length,2);assert.equal(m.all.some(t=>t.position_id==='hq'),false);
 assert.equal(C.filter(m,'material').length,1);const next=build(2027);assert.equal(next.overdue.length,2);assert.ok(next.overdue.some(t=>t.year===2026&&t.kind==='local'));
 const completed=build(2026,{[A.taskKey(row)]:true});assert.equal(completed.open.length,2);assert.equal(completed.all.filter(t=>t.material).length,0);
 hq.snapshots[0].state_json.cards[1].initialPlanLocked=true;assert.equal(build(2026).pending,0);assert.equal(build(2026).all.some(t=>t.kind==='initial'),false);
});
test('overview links filters to exact rows, shares completion with Changes and rolls back failed saves',async()=>{
 const data=fixture(),metadata=meta(),calls=[],done=[];let fail=false;
 const x=await smoke(fs.readFileSync('index.html','utf8'),'hq',null,async(n,a)=>{
  calls.push(n);if(n==='scl290_hq_data')return{data,error:null};if(n==='scl302_overview')return{data:metadata,error:null};
  if(n==='scl292_get_done')return{data:done,error:null};
  if(n==='scl292_set_done'){if(fail)return{error:{message:'Save failed'}};done.push({change_key:a.p_change_key,done:a.p_done});return{data:true,error:null};}
  if(n==='scl300_pp_hq')return{data:{year:a.p_year,revision:1,today:'2026-10-21',records:[{month_on:'2026-10-01',thematic:{title:'Thematic'},campaign:{}}],pharmacies:[{id:'p',registry_id:'r',name:'Test pharmacy',active:true,positions:data.installations[0].positions}],history:[]},error:null};
 });assert.deepEqual(x.errors,[]);
 const run=s=>vm.runInContext(s,x.ctx),host=()=>x.document.getElementById('scl302Overview');
 assert.doesNotMatch(host().textContent,/Reports|setup|Open to-dos|Fallback|Supplier|gaps/);
 assert.match(host().textContent,/Θεματική Pharmaplus/);assert.doesNotMatch(host().textContent,/χωρίς εφαρμόσιμο περιεχόμενο/);
 await x.click(host().querySelector('[data-filter="local"]'));assert.equal(run('SCL302.filter'),'local');
 const row=run("SCL302.model.changes.find(t=>t.kind==='local')");assert.ok(row);assert.equal(row.material,true);
 await x.click(host().querySelector('[data-id="'+row.id+'"]'));assert.match(x.document.getElementById('scl302Dialog').textContent,/TEST_ADV1_P/);
 const cb=x.document.getElementById('scl302Done');cb.checked=true;cb.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));
 assert.equal(run('SCL302.model.changes.find(t=>t.kind===\'local\').complete'),true);assert.ok(calls.includes('scl292_set_done'));assert.equal(calls.includes('scl302_set_initial_deadline'),false);
 assert.equal(run('SCL212.done['+JSON.stringify(row.id)+']'),true);
 fail=true;x.ctx.confirm=()=>true;const uncheck=x.document.getElementById('scl302Done');uncheck.checked=false;uncheck.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));
 assert.equal(run('SCL212.done['+JSON.stringify(row.id)+']'),true);assert.match(x.document.getElementById('scl302Error').textContent,/Δεν αποθηκεύτηκε/);
 await x.click(x.document.querySelector('#scl302Dialog [data-scl302="close"]'));
 run("document.getElementById('scl212Year').value='2027';SCL302.render()");assert.ok(run('SCL302.model.overdue.some(t=>t.year===2026)'));
});
test('next month rolls December into January and persists both year and month',async()=>{
 const x=await smoke(fs.readFileSync('index.html','utf8'),'hq',null,null,{now:'2026-12-20T12:00:00Z'});assert.deepEqual(x.errors,[]);
 Object.defineProperty(x.document.getElementById('scl212Year'),'value',{value:'2026',writable:true});
 await x.click(x.document.querySelector('[data-scl302="next"]'));
 assert.equal(vm.runInContext('scl212Year()',x.ctx),2027);assert.equal(x.ctx.SCL302.month,0);assert.deepEqual(JSON.parse(x.ctx.localStorage.getItem('scl302.period')),{year:2027,month:0});
});
