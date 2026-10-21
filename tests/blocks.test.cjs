const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const C=require('../src/scl297-actions-core.js'),A=require('../src/scl292-core.js');
const html=fs.readFileSync('index.html','utf8');
const card=()=>({id:'base-1',type:'base',title:'Θέση 1',initialPlanLocked:true,screenFormat:'vertical',basicSchedule:Array(12).fill('Base'),simpleSchedule:Array(12).fill('Base'),simpleConfirmed:true,confirmedDeals:[],preagreements:[],sponsoredShelves:[]});
const deal=()=>({id:'D',confirmed:true,supplier:'Supplier',brand:'Brand',soldMonthlyPrice:175,subline:'',products:'',startMonth:0,duration:3,monthlyContentChanges:true,schedule:Array(12).fill(''),monthlySublines:Array(12).fill('Same'),monthlyProducts:Array(12).fill('Product')});
const values=x=>JSON.parse(JSON.stringify(x));
test('same monthly content joins; A B A stays three blocks in timeline, operations, fees and material requests',()=>{
 const c=card();c.confirmedDeals=[deal()];
 for(const pattern of [['Same','Same','Same'],['A','B','A'],['A','A','B']]){
  c.confirmedDeals[0].monthlySublines.splice(0,3,...pattern);
  const n=pattern.reduce((n,s,i)=>n+(!i||s!==pattern[i-1]?1:0),0);
  assert.equal(C.segments(c,2027,A.active).filter(b=>b.kind==='deal').length,n);
  assert.equal(C.operationalRows(c,2027,[],A.active).filter(r=>r.final_type==='deal'&&r.content_change_required).length,n);
  assert.equal(C.blocks(c,2027,A.active).filter(b=>b.category==='deal').length,n);
  assert.equal(C.files(c,c.confirmedDeals[0],2027).length,n);
 }
 c.confirmedDeals=[];c.simpleSchedule.splice(0,5,'X','X','Y','X','X');
 assert.deepEqual(C.blocks(c,2027,A.active).map(b=>[b.start,b.end]),[[0,1],[2,2],[3,4]]);
 c.preagreements=[{...deal(),confirmed:false}];c.sponsoredShelves=[{month:0,brand:'Shelf'}];
 assert.equal(C.operationalRows(c,2027,[],A.active).some(r=>r.final_type==='deal'),false);
 assert.equal(C.blocks(c,2027,A.active).filter(b=>b.category==='custom').length,3);
});
test('HQ repairs stale monthly flags from saved state; merged rows survive async legacy loads',async()=>{
 const c=card();c.confirmedDeals=[deal()];
 const pid='fixture-pharmacy',source=Array.from({length:12},(_,m)=>({pharmacy_id:pid,position_id:c.id,year:2027,month:m,final_type:m<3?'deal':'basic',final_title:m<3?'Brand':'Base',content_change_required:m<4,content_change_reason:m<3?'deal_monthly_change':'deal_end_return_to_basic'}));
 const hq={api_version:290,setup:[],months:source,deals:[],registry:[{pharmacy_id:pid,name:'Fixture',legacy:true}],installations:[],base:{pharmacies:[],pharmacy_state:[{pharmacy_id:pid,year:2027,state_json:{cards:[c]}}],hq_programs:[],hq_changes_done:[],reports:[]}};
 const x=await smoke(html,'hq',null,async(n)=>n==='scl290_hq_data'?{data:hq,error:null}:undefined);
 assert.deepEqual(x.errors,[]);const run=s=>vm.runInContext(s,x.ctx);
 const select=x.document.getElementById('scl212Year');Object.defineProperty(select,'value',{value:'2027',configurable:true});
 await run('scl212Load()');
 for(let i=0;i<2;i++){
  const rows=values(run('scl212VisibleChanges()')).filter(r=>r.position_id===c.id);
  assert.deepEqual(rows.map(r=>r.month),[0,3]);assert.equal(rows[0].block_end,2);assert.match(rows[0].month_label,/Ιαν–Μαρ 2027/);
  await run('scl212Load()');
 }
});
test('pharmacy timeline renders one spanning cell and explicit preagreement conversion states',async()=>{
 const c=card(),d=deal();d.startMonth=9;c.confirmedDeals=[d];
 const x=await smoke(html,'pharmacy',{turnover:500000,cards:[c]},null,{now:'2026-09-10T12:00:00Z'});
 assert.deepEqual(x.errors,[]);const run=s=>vm.runInContext(s,x.ctx);
 const cells=x.document.querySelectorAll('.scl296-timeline-cell.deal');assert.equal(cells.length,1);assert.equal(cells[0].getAttribute('aria-colspan'),'3');assert.match(cells[0].textContent,/Οριστική συμφωνία/);
 run("SCL297.openDeal('base-1','confirmed',0)");assert.match(x.document.getElementById('negotiationModalBody').textContent,/Οριστική συμφωνία · έχει ήδη/);assert.equal(x.document.querySelector('[data-scl297="save-pre"]'),null);
 run("closeModal('negotiationModal');state.cards.find(c=>c.id==='base-1').confirmedDeals=[];state.cards.find(c=>c.id==='base-1').preagreements=[{...SCL297Core.clone("+JSON.stringify(d)+"),confirmed:false,pending:true}];SCL297.openDeal('base-1','preagreement',0)");
 assert.match(x.document.getElementById('negotiationModalBody').textContent,/Προσυμφωνία · δεν έχει κλείσει/);
 assert.match(x.document.querySelector('[data-scl297="review-deal"]').textContent,/Μετατροπή σε οριστική συμφωνία/);
 await x.click(x.document.querySelector('[data-scl297="review-deal"]'));
 assert.match(x.document.getElementById('negotiationModalBody').textContent,/Προσυμφωνία → Οριστική συμφωνία/);
 assert.equal(x.document.querySelector('[data-scl297="commit"]').textContent,'Οριστικοποίηση συμφωνίας');
});
test('billing shows one amount for a full continuous period and filters by charge month',async()=>{
 const row={pharmacy_id:'fixture-pharmacy',pharmacy_name:'Fixture',billing_code:'F1',position_id:'base-1',position_name:'Θέση 1',year:2026,month:9,end_month:11,category:'deal',description:'Same content',status:'planned',amount:30};
 const x=await smoke(html,'hq',null,async(n)=>n==='scl292_finance'?{data:{year:2026,rows:[row],history:[],requests:[]},error:null}:undefined);
 assert.deepEqual(x.errors,[]);const run=s=>vm.runInContext(s,x.ctx);run('SCL292.renderBilling()');
 const page=x.document.getElementById('scl212Page-billing');assert.match(page.textContent,/Προβολή: Οκτ–Δεκ 2026/);assert.equal(page.querySelectorAll('tbody tr').length,1);
 assert.match(page.textContent,/Μήνας χρέωσης/);run("SCL292.filters.month='10';SCL292.renderBilling()");assert.equal(page.querySelectorAll('tbody tr').length,0);
});
