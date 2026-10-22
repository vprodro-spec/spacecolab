const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');
const records=['2026-11-01','2026-12-01','2027-01-01','2027-02-01'].map(month_on=>({month_on,campaign_id:'winter',campaign:{title:'Winter campaign',supplier:'Supplier',scope:{mode:'all',ids:[]},files:{vertical:'WINTER_P.mp4'}},thematic:{theme_id:'theme',title:'Underlying theme'},starts_on:'2026-11-01',ends_on:'2027-02-01'}));
const data=y=>({year:y,revision:1,today:'2026-10-21',records,pharmacies:[{id:'fixture-pharmacy',registry_id:'registry',name:'Fixture',billing_code:'001',active:true,positions:[{id:'hq',type:'hq',screenFormat:'vertical',startsOn:'2026-10-01',playerCode:'FIXTURE_ADV0_P'}]}],history:[]});
const field=(x,name,value)=>{const el=x.document.querySelector('#scl300Form [name="'+name+'"]');assert.ok(el,name);Object.defineProperty(el,'value',{value,writable:true,configurable:true});};
test('HQ thematic picker preserves search and selection through preview without saving',async()=>{
 let request,saves=0;
 const x=await smoke(html,'hq',null,async(n,a)=>{
  if(n==='scl300_pp_hq')return{data:data(a.p_year),error:null};
  if(n==='scl300_pp_preview'){request=a.p_request;return{data:{fingerprint:'preview',conflicts:[],affected_pharmacies:0,content_changes:0,months:[]},error:null};}
  if(n==='scl300_pp_save'){saves++;return{data:{},error:null};}
 });
 const run=s=>vm.runInContext(s,x.ctx);await run("SCL300.start('theme','2026-11-01')");
 const choice=x.document.querySelector('[data-scl293="pp-select"]');assert.ok(choice);
 const id=choice.dataset.theme;await x.click(choice);
 assert.equal(x.document.querySelector('[name="theme_id"]').value,id);
 const search=x.document.querySelector('[data-scl293-search="pp"]');search.value='δενυπαρχειθεματικη';search.dispatchEvent(new x.ctx.Event('input',{bubbles:true}));
 assert.match(x.document.getElementById('scl300Form').textContent,/Δεν βρέθηκε/);
 assert.equal(x.document.querySelector('[name="theme_id"]').value,id);
 await x.click(x.document.querySelector('[data-scl306="clear-search"]'));
 await x.click(x.document.querySelector('[data-scl293="preview"][data-theme="'+id+'"]'));
 assert.equal(run('SCL300.draft.data.theme_id'),id);assert.ok(x.document.querySelector('#planogramModal.open'));
 await x.click(x.document.querySelector('[data-close="planogramModal"]'));
 await x.click(x.document.querySelector('[data-scl300="preview"]'));
 assert.equal(request.data.theme_id,id);assert.equal(saves,0);assert.deepEqual(x.errors,[]);
});
test('annual cards keep campaign and theme separate; preview never writes, failed save preserves choices and successful save closes',async()=>{
 let saves=0,fail=true,request;
 const x=await smoke(html,'hq',null,async(n,a)=>{
  if(n==='scl300_pp_hq')return{data:data(a.p_year),error:null};
  if(n==='scl300_pp_preview'){request=a.p_request;return{data:{fingerprint:'review',conflicts:[],affected_pharmacies:1,content_changes:4,missing_content:0,months:records.map(r=>({month_on:r.month_on,campaign_before:r.campaign.title,campaign_after:'New campaign',thematic:r.thematic.title,affected:1,pharmacies:[{name:'Fixture',player_code:'FIXTURE_ADV0_P',before:'Winter campaign',after:'New campaign'}]}))},error:null};}
  if(n==='scl300_pp_save'){saves++;assert.equal(a.p_fingerprint,'review');return fail?{error:{message:'Retry safely'}}:{data:{revision:2},error:null};}
 });assert.deepEqual(x.errors,[]);
 const run=s=>vm.runInContext(s,x.ctx),page=x.document.getElementById('scl212Page-pharmaplus');
 assert.equal(page.querySelectorAll('.scl300-month').length,12);assert.equal(page.querySelectorAll('.scl300-campaign').length,12);assert.match(page.textContent,/Winter campaign/);assert.match(page.textContent,/Underlying theme/);assert.equal(x.document.getElementById('scl231EditorPanel'),null);
 await run("SCL300.start('create','2026-11-01')");field(x,'title','New campaign');field(x,'supplier','Supplier');field(x,'duration','4');
 await x.click(x.document.querySelector('[data-scl300="preview"]'));
 assert.equal(request.duration,4);assert.equal(saves,0);assert.match(x.document.getElementById('scl300Dialog').textContent,/Φεβ 2027/);
 await x.click(x.document.querySelector('[data-scl300="save"]'));assert.equal(saves,1);assert.match(x.document.getElementById('scl300Error').textContent,/Retry safely/);
 await x.click(x.document.querySelector('[data-scl300="back"]'));assert.equal(x.document.querySelector('[name="title"]').value,'New campaign');
 await x.click(x.document.querySelector('[data-scl300="preview"]'));fail=false;await x.click(x.document.querySelector('[data-scl300="save"]'));assert.equal(saves,2);assert.equal(x.document.getElementById('scl300Dialog'),null);
 run("SCL300.showMonth('2026-09-01')");assert.equal(x.document.querySelector('[data-scl300="edit"]'),null);assert.match(x.document.getElementById('scl300Dialog').textContent,/Μόνο προβολή/);
});
test('pharmacy joins continuous Pharmaplus months across the displayed year and remains view only',async()=>{
 const pp=Array.from({length:12},(_,month)=>({month,year:2026,display_kind:month<10?'empty':'main',display_title:month<10?'Προσεχώς':'Winter campaign',content_key:month<10?'empty':'winter',starts_on:'2026-11-01',ends_on:'2027-02-01',supplier:'Supplier'}));
 const x=await smoke(html,'pharmacy',{turnover:500000,cards:[]},async n=>n==='scl300_pp_pharmacy'?{data:pp,error:null}:undefined);assert.deepEqual(x.errors,[]);
 const cells=[...x.document.querySelectorAll('.scl296-timeline-cell')].filter(c=>c.textContent.includes('Winter campaign'));assert.equal(cells.length,1);assert.equal(cells[0].getAttribute('aria-colspan'),'2');
 await x.click(cells[0].querySelector('button'));
 assert.match(x.document.getElementById('scl295Dialog').textContent,/Φεβ 2027/);
 assert.equal(x.document.querySelector('[data-scl295="initial"]'),null);
});
