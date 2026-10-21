const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const C=require('../src/scl297-actions-core.js'),A=require('../src/scl292-core.js');
const html=fs.readFileSync('index.html','utf8'),seed=JSON.parse(fs.readFileSync('data/library-seed.json','utf8'));
const theme=seed.themes.find(t=>t.status==='available').key,other=seed.themes.find(t=>t.status==='available'&&t.key!==theme).key;
const base=()=>({id:'base-1',type:'base',title:'Θέση 1',screenFormat:'vertical',initialPlanLocked:true,basicSchedule:Array(12).fill(theme),simpleSchedule:Array(12).fill(theme),simpleConfirmed:false,confirmedDeals:[],preagreements:[],sponsoredShelves:[]});
const tick=async()=>{for(let i=0;i<16;i++)await new Promise(r=>setImmediate(r));};
async function app(c=base(),opts={}){
 const writes=[];const x=await smoke(html,'pharmacy',{turnover:500000,cards:[c]},async(n,a)=>{
  if(n==='scl290_save_program'){writes.push(structuredClone(a));return opts.fail?{data:null,error:{message:'Offline'}}:{data:{snapshot_revision:writes.length+1},error:null};}
  if(n==='scl292_finance'&&opts.rows)return {data:{year:2026,rows:opts.rows,requests:[],history:[]},error:null};
 },{now:opts.now||'2026-09-10T12:00:00Z'});
 assert.deepEqual(x.errors,[]);
 const run=s=>vm.runInContext(s,x.ctx),click=async selector=>{const el=typeof selector==='string'?x.document.querySelector(selector):selector;assert.ok(el,String(selector));await x.click(el);await tick();};
 const field=async(key,value)=>{const el=x.document.querySelector('[data-scl297-field="'+key+'"]');assert.ok(el,key);Object.defineProperty(el,'value',{value:String(value),writable:true,configurable:true});el.dispatchEvent(new x.ctx.Event(el.tagName==='SELECT'?'change':'input',{bubbles:true}));await tick();};
 const check=async(m,value)=>{const el=x.document.querySelector('[data-scl297-month="'+m+'"]');assert.ok(el);el.checked=value;el.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));await tick();};
 const state=()=>JSON.parse(run('JSON.stringify(state.cards.find(c=>c.id==="base-1"))'));
 return {...x,run,click,field,check,state,writes,text:id=>x.document.getElementById(id)?.textContent||''};
}

test('custom multi-month draft, lost sponsorship warning, explicit confirmation and period-only return to basic',async()=>{
 const c=base();c.sponsoredShelves=[{id:'s',month:9,brand:'Shelf',price:70}];
 const x=await app(c);const before=x.state();x.run("SCL297.openCustom('base-1')");await tick();
 await x.check(10,true);const candidate=x.document.querySelector('[data-scl293="actions-select"][data-theme="'+seed.themes.find(t=>t.key===other).id+'"]');await x.click(candidate);await tick();
 assert.deepEqual(x.state(),before);assert.equal(x.writes.length,0);assert.match(x.text('customModalBody'),/θα χαθεί/);
 await x.click('[data-scl297="review-custom"]');assert.match(x.text('customModalBody'),/0€/);assert.match(x.text('customModalBody'),/1η από τις 3 δωρεάν/);assert.equal(x.writes.length,0);
 await x.click('[data-scl297="commit"]');assert.equal(x.writes.length,1);assert.equal(x.state().simpleSchedule[9],other);assert.equal(x.state().simpleSchedule[10],other);assert.equal(x.state().sponsoredShelves.length,0);assert.equal(x.run('SCL297.draft'),null);
 x.run("SCL297.openCustom('base-1')");await x.click('[data-scl297="custom-base"]');await x.click('[data-scl297="review-custom"]');await x.click('[data-scl297="commit"]');
 assert.equal(x.writes.length,2);assert.equal(x.state().simpleSchedule[9],theme);assert.equal(x.state().simpleSchedule[10],other);assert.equal(x.state().basicSchedule[9],theme);
});

test('shelf exploration is unsaved, below-reference prices and four shelves work, multi-month persistence has no video tasks',async()=>{
 const x=await app();await x.click('[data-scl295="position"][data-card="base-1"]');
 await x.click('[data-scl295="planogram"][data-month="9"]');assert.ok(x.document.querySelector('#planogramModal.open'));await x.click('[data-close="planogramModal"]');assert.equal(x.document.querySelector('#planogramModal.open'),null);
 await x.click('[data-scl295="shelf"][data-month="9"]');assert.ok(x.document.querySelector('#sponsoredModal.open'));await tick();const before=x.state();
 await x.field('brand','Shelf Brand');await x.field('products','Product');await x.field('price',35.5);await x.field('duration',2);await x.field('shelves','4 ράφια από πάνω');
 assert.deepEqual(x.state(),before);assert.equal(x.writes.length,0);assert.doesNotMatch(x.text('sponsoredModalBody'),/Σημειώσεις|Μηχανισμός προβολής/);
 await x.click('[data-scl297="review-shelf"]');assert.match(x.text('sponsoredModalBody'),/35,5€/);await x.click('[data-scl297="commit"]');assert.equal(x.writes.length,1);
 const saved=x.state();assert.equal(saved.sponsoredShelves.length,2);assert.ok(saved.sponsoredShelves.every(s=>s.price===35.5&&s.shelves==='4 ράφια από πάνω'));assert.deepEqual(saved.simpleSchedule,before.simpleSchedule);
 assert.ok(x.writes[0].p_months.filter(r=>r.position_id==='base-1').every(r=>r.final_type!=='sponsored'));assert.equal(C.blocks(saved,2026,A.active).length,0);
});

test('preagreement save stays preagreement; final confirmation replaces customization/shelves, creates supplier document',async()=>{
 const c=base();c.simpleConfirmed=true;c.simpleSchedule[9]=other;c.sponsoredShelves=[{id:'s',month:9,brand:'Shelf',price:70}];
 const x=await app(c);x.run("SCL297.openDeal('base-1')");await x.field('supplier','Supplier');await x.field('brand','Brand');await x.field('duration',2);await x.field('soldMonthlyPrice',175);
 assert.equal(x.writes.length,0);await x.click('[data-scl297="save-pre"]');assert.equal(x.writes.length,1);assert.equal(x.state().preagreements.length,1);assert.equal(x.state().confirmedDeals.length,0);assert.equal(x.state().sponsoredShelves.length,1);assert.equal(x.state().simpleSchedule[9],other);
 x.run("SCL297.openDeal('base-1','preagreement',0)");await x.field('products','Product');await x.click('[data-scl297="save-pre"]');assert.equal(x.state().preagreements.length,1);assert.equal(x.state().confirmedDeals.length,0);
 x.run("SCL297.openDeal('base-1','preagreement',0)");await x.click('[data-scl297="review-deal"]');assert.match(x.text('negotiationModalBody'),/Χορηγίες ραφιών/);assert.match(x.text('negotiationModalBody'),/30€/);assert.equal(x.writes.length,2);
 await x.click('[data-scl297="commit"]');const s=x.state();assert.equal(x.writes.length,3);assert.equal(s.preagreements.length,0);assert.equal(s.confirmedDeals.length,1);assert.equal(s.sponsoredShelves.length,0);assert.equal(s.simpleSchedule[9],theme);assert.equal(s.confirmedDeals[0].soldMonthlyPrice,175);
 assert.equal(x.document.querySelector('.modal.open'),null);assert.match(x.text('scl295Notice'),/Η οριστική συμφωνία καταχωρίστηκε/);
 await x.click('[data-scl297="document"][data-pre="false"]');
 assert.match(x.text('briefModalBody'),/emitropoulou@pharmaplus.gr/);assert.match(x.text('briefModalBody'),/17\/09\/2026/);assert.doesNotMatch(x.text('briefModalBody'),/Αναφορά Αποτελεσμάτων|5 εργάσιμες/);
 assert.equal(s.confirmedDeals[0].materialRequests[0].status,'awaiting');
});

test('mandatory supplier and brand, agreement overlap and deadline errors never save',async()=>{
 const c=base();c.confirmedDeals=[{id:'d',confirmed:true,supplier:'S',brand:'B',startMonth:10,duration:1,soldMonthlyPrice:100,monthlyContentChanges:false}];
 const x=await app(c);x.run("SCL297.openDeal('base-1')");await x.field('brand','Brand');await x.click('[data-scl297="review-deal"]');assert.match(x.text('scl297Error'),/και Προμηθευτή και Μάρκα/);
 await x.field('supplier','Supplier');await x.field('duration',2);await x.click('[data-scl297="review-deal"]');assert.match(x.text('scl297Error'),/υπάρχει Συμφωνία/);assert.equal(x.writes.length,0);
 x.run('window.confirm=()=>true');x.run("closeModal('negotiationModal')");x.run("SCL297.openShelf('base-1',10)");assert.match(x.text('scl295Notice'),/Συμφωνία/);assert.equal(x.run('SCL297.draft'),null);
 const late=await app(base(),{now:'2026-10-20T12:00:00Z'});late.run("SCL297.openDeal('base-1')");await late.field('startMonth',10);await late.field('supplier','Supplier');await late.field('brand','Brand');await late.click('[data-scl297="review-deal"]');assert.match(late.text('scl297Error'),/15\/10\/2026/);assert.equal(late.writes.length,0);
});

test('discard, server error and double confirmation preserve saved state and prevent duplicate writes',async()=>{
 const x=await app(base(),{fail:true});const before=x.state();x.run("SCL297.openShelf('base-1',9)");await x.field('brand','Draft');
 x.run("closeModal('sponsoredModal')");assert.ok(x.run('SCL297.draft'));x.run('window.confirm=()=>true');x.run("closeModal('sponsoredModal')");assert.equal(x.run('SCL297.draft'),null);assert.deepEqual(x.state(),before);
 x.run("SCL297.openShelf('base-1',9)");await x.field('brand','Draft');await x.click('[data-scl297="review-shelf"]');const b=x.document.querySelector('[data-scl297="commit"]');await Promise.all([x.click(b),x.click(b)]);await tick();
 assert.equal(x.writes.length,1);assert.deepEqual(x.state(),before);assert.match(x.text('scl297Error'),/Δεν αποθηκεύτηκε: Offline/);assert.equal(x.run('SCL290.dirty'),false);assert.ok(x.run('SCL297.draft'));assert.equal(x.run('SCL297.busy'),false);assert.equal(x.document.querySelector('[data-scl297="commit"]').disabled,false);
});

test('a post-save rendering failure cannot undo the saved action or leave its modal open',async()=>{
 const x=await app();x.run("SCL297.openShelf('base-1',9)");await x.field('brand','Saved Brand');await x.click('[data-scl297="review-shelf"]');
 x.run("refresh=()=>{throw Error('Render failure')}");await x.click('[data-scl297="commit"]');
 assert.equal(x.writes.length,1);assert.equal(x.state().sponsoredShelves[0].brand,'Saved Brand');assert.equal(x.run('SCL297.draft'),null);assert.equal(x.document.querySelector('.modal.open'),null);assert.match(x.text('scl295Notice'),/αποθηκεύτηκε/);
});

test('confirmation while another save is pending is visibly busy and cannot submit twice',async()=>{
 const x=await app();x.run("SCL297.openShelf('base-1',9)");await x.field('brand','Saved once');await x.click('[data-scl297="review-shelf"]');
 x.run('SCL290.saving=new Promise(resolve=>window.releasePendingSave=()=>{SCL290.saving=null;resolve()})');
 const b=x.document.querySelector('[data-scl297="commit"]'),pending=x.click(b);await tick();
 assert.equal(x.run('SCL297.busy'),true);assert.match(x.text('scl297Status'),/Αποθήκευση/);assert.equal(b.disabled,true);
 await x.click(b);assert.equal(x.writes.length,0);x.run('releasePendingSave()');await pending;
 assert.equal(x.writes.length,1);assert.equal(x.document.querySelector('.modal.open'),null);
});

test('monthly supplier content, file dates and planned custom quota agree with continuous-block rules',async()=>{
 const c=base();c.confirmedDeals=[{id:'d',confirmed:true,supplier:'S',brand:'B',subline:'',products:'',startMonth:9,duration:3,monthlyContentChanges:true,schedule:Array(12).fill(''),monthlySublines:Array(12).fill('Same'),monthlyProducts:Array(12).fill('P')}];
 assert.equal(C.blocks(c,2026,A.active).filter(b=>b.category==='deal').length,1);c.confirmedDeals[0].monthlyProducts[11]='Different';assert.equal(C.blocks(c,2026,A.active).filter(b=>b.category==='deal').length,2);
 const files=C.files(c,c.confirmedDeals[0],2026);assert.equal(files.length,2);assert.equal(files[0].end,10);assert.match(files[1].file,/_2026-12_ΚΑΘΕΤΟ.mp4$/);assert.equal(files[1].deadline,'2026-11-17');
 c.confirmedDeals=[];c.simpleConfirmed=true;c.simpleSchedule[9]=other;c.simpleSchedule[10]=other;
 const rows=[1,2,3].map((q,i)=>({position_id:c.id,year:2026,category:'custom',month:i,quota_index:q,status:'finalized',amount:0}));
 const predicted=C.forecast(c,2026,rows,A.active);assert.equal(predicted.length,1);assert.equal(predicted[0].quota,4);assert.equal(predicted[0].amount,15);
 const x=await app(base());x.run("SCL297.openDeal('base-1')");await x.field('monthlyContentChanges','monthly');await x.field('duration',2);await x.field('monthlySublines.9','Line A');await x.field('monthlySublines.10','Line B');assert.equal(x.writes.length,0);
 assert.doesNotMatch(x.text('negotiationModalBody'),/Θέμα \/ μήνυμα|Μηχανισμός προβολής|Αναφορά Αποτελεσμάτων|Σημειώσεις/);
});


test('removing one future month from a group preserves its historical months',async()=>{
 const c=base();c.sponsoredShelves=[9,10,11].map(m=>({id:'g-'+m,groupId:'g',brand:'Shelf',products:'P',price:55,month:m,shelves:'2 πρώτα ράφια',status:'confirmed'}));
 const x=await app(c,{now:'2026-10-20T12:00:00Z'});x.run("SCL297.openShelf('base-1',11)");await x.click('[data-scl297="review-shelf-remove"]');await x.click('[data-scl297="commit"]');
 assert.equal(x.writes.length,1);assert.deepEqual(x.state().sponsoredShelves.map(s=>s.month),[9,10]);
});
