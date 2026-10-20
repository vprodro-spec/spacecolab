const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {parseHTML}=require('linkedom');
const Core=require('../src/scl292-core.js');
const html=fs.readFileSync('index.html','utf8');
function fixture(mode='pharmacy',response={rows:[],requests:[],history:[]}){
 const {document}=parseHTML(html),calls=[],alerts=[],prompts=[];
 const selected=document.getElementById('scl212Year');selected.querySelector('option').setAttribute('selected','');
 const card={id:'base-1',title:'Θέση 1',type:'base',installationStart:'2026-10-01',pendingScreenFormat:'vertical',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),simpleSchedule:Array(12).fill('A'),confirmedDeals:[]};
 const env={document,Intl,Date,URL,URLSearchParams,Blob,console,SCL292Core:Core,MONTHS:['Ιαν','Φεβ','Μαρ','Απρ','Μάι','Ιουν','Ιουλ','Αυγ','Σεπ','Οκτ','Νοε','Δεκ'],
  state:{programYear:2026,cards:[card],selectedCardId:'base-1'},SCL_ROUTING:{ready:true,pharmacy:{id:'ph'},pharmacyToken:'fixture-token',hqKey:'fixture-key'},SCL290:{context:{installation:{service_from:'2026-10-01',positions:[{type:'base'}]}}},SCL212:{done:{}},
  esc:s=>String(s??'').replace(/[&<>"']/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x])),
  sb:{rpc:async(name,args)=>{calls.push({name,args});return {data:name==='scl292_finance'?response:[],error:null};}},
  sclMode:()=>mode,dealRevenue:()=>200,sponsoredRevenue:()=>55,suggestedPrice:()=>150,customCost:()=>0,dealCost:()=>0,
  refresh:()=>{},scl212Render:()=>{},scl212RenderChanges:()=>{},scl212Load:async()=>{},sclSaveNow:async()=>{calls.push({name:'save'});},
  clone:x=>JSON.parse(JSON.stringify(x)),mechanisms:()=>Array(12).fill(''),defaultNegotiation:()=>({}),
  setTimeout:()=>0,alert:m=>alerts.push(m),confirm:()=>true,prompt:()=>prompts.shift()??null,sclResetCurrentPharmacyYearV190:()=>{},
  loadYear:async()=>{},renderInitialPlanModal:()=>{}
 };env.window=env;const ctx=vm.createContext(env);
 const originalLock=html.match(/function lockInitialPlan\(card,type,program,sched\)\{[\s\S]*?\n\}\nfunction renderInitialPlanModal/)[0].replace(/\nfunction renderInitialPlanModal$/,'');
 vm.runInContext(originalLock,ctx);vm.runInContext(fs.readFileSync('src/scl292-ui.js','utf8'),ctx);
 return {ctx,document,calls,alerts,prompts,card,R:ctx.SCL292};
}
test('pharmacy actual costs use server totals, with full-year estimate kept separate',async()=>{
 const rows=[{year:2026,month:9,category:'base',amount:40.42,status:'finalized',description:'Πάγιο'},{year:2026,month:10,category:'base',amount:40.41,status:'planned',description:'Πάγιο'},{year:2026,month:11,category:'base',amount:40.42,status:'planned',description:'Πάγιο'}];
 const x=fixture('pharmacy',{rows,requests:[],history:[]});await x.R.loadFinance();
 const cards=[...x.document.querySelectorAll('#economicsGrid > .scl292-grid .scl292-card strong')].map(x=>x.textContent);
 assert.equal(cards[1],new Intl.NumberFormat('el-GR',{style:'currency',currency:'EUR'}).format(121.25));
 assert.match(x.document.getElementById('economicsGrid').textContent,/Εκτίμηση εσόδων — πλήρες έτος/);
 assert.equal(x.calls[0].args.p_year,2026);assert.equal(x.calls[0].args.p_token,'fixture-token');
});
test('HQ January filter retains month zero; completion persists independently of finance',async()=>{
 const rows=[{pharmacy_id:'ph',pharmacy_name:'Test',billing_code:'1',year:2026,month:0,category:'custom',amount:15,status:'finalized',description:'A'},{pharmacy_id:'ph',pharmacy_name:'Test',year:2026,month:11,category:'deal',amount:30,status:'planned',description:'B'}];
 const x=fixture('hq',{rows,requests:[],history:[]});await x.R.loadFinance();x.R.filters.month='0';x.R.renderBilling();
 assert.equal(x.document.querySelectorAll('#scl212Page-billing tbody tr').length,1);
 assert.match(x.document.getElementById('scl212Page-billing').textContent,/Ιαν 2026/);
 const key=Core.taskKey({pharmacy_id:'ph',position_id:'base-1',year:2026,month:0,final_title:'A'});
 x.ctx.SCL212.done[key]=true;await x.R.saveDone();await x.R.saveDone();
 assert.equal(x.calls.filter(c=>c.name==='scl292_set_done').length,1);
 assert.equal(x.calls.filter(c=>c.name==='scl292_finance').length,1);
 x.ctx.SCL212.done[key]=false;await x.R.saveDone();assert.equal(x.calls.filter(c=>c.name==='scl292_set_done').length,2);
});
test('initial programme completeness and approved reset run through existing lock function',()=>{
 const x=fixture(),schedule=Array(12).fill('');schedule[9]='A';schedule[10]='B';
 assert.equal(x.ctx.lockInitialPlan(x.card,'own','',schedule),false);assert.match(x.alerts[0],/Δεκ/);
 schedule[11]='C';assert.equal(x.ctx.lockInitialPlan(x.card,'own','',schedule),true);
 const before=[...x.card.basicSchedule];x.card._scl292Reset={id:'req',fromMonth:11};
 assert.equal(x.ctx.lockInitialPlan(x.card,'own','',Array(12).fill('Z')),true);
 assert.deepEqual(x.card.basicSchedule.slice(0,11),before.slice(0,11));assert.equal(x.card.basicSchedule[11],'Z');assert.equal(x.card._scl292ResetApplied,'req');
});
test('reset request saves first and leaves the locked programme intact',async()=>{
 const x=fixture();x.prompts.push('1','Αλλαγή προγράμματος');const before=JSON.stringify(x.card);await x.R.requestReset();
 assert.equal(JSON.stringify(x.card),before);assert.equal(x.calls[0].name,'save');assert.equal(x.calls[1].name,'scl292_request_reset');
 assert.equal(x.calls[1].args.p_position,'base-1');assert.match(x.document.getElementById('scl292Status').textContent,/Το αίτημα στάλθηκε/);
});
