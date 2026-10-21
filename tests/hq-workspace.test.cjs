const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const C=require('../src/scl303-workspace-core'),A=require('../src/scl292-core');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');
test('filters combine month, pharmacy, actual file, orientation and state; none is distinct from all',()=>{
 const rows=[{month:9,pharmacy_id:'a',pharmacy_name:'Φαρμακείο Άλφα',file:'ANAPNOI_PORTRAIT.mp4',position_orientation:'vertical',complete:false,kind:'custom'},
 {month:10,pharmacy_id:'b',pharmacy_name:'Βήτα',file:'ANAPNOI_LANDSCAPE.mp4',position_orientation:'horizontal',complete:true,kind:'basic'}];
 const f=C.defaults(9);assert.equal(C.filter(rows,f).length,1);f.months=null;assert.equal(C.filter(rows,f).length,2);f.months=[];assert.equal(C.filter(rows,f).length,0);
 f.months=[9,10];f.pharmacies=[];assert.equal(C.filter(rows,f).length,0);f.pharmacies=null;f.query='αλφα';assert.equal(C.filter(rows,f)[0].pharmacy_id,'a');
 f.query='ANAPNOI';f.orientation='landscape';f.status='done';assert.equal(C.filter(rows,f)[0].pharmacy_id,'b');f.kind='custom';assert.equal(C.filter(rows,f).length,0);
 assert.deepEqual(C.toggle(null,9,false,[9,10]),[10]);assert.equal(C.toggle([10],9,true,[9,10]),null);
});
test('renamed generated suffix preserves completion; format or supplier content change still invalidates it',()=>{
 const r={pharmacy_id:'p',position_id:'base-1',year:2026,month:9,final_type:'deal',final_title:'Brand',file_name:'BRAND_2026-10_ΚΑΘΕΤΟ.mp4',position_orientation:'vertical'};
 const newer={...r,file_name:'BRAND_2026-10_PORTRAIT.mp4'};assert.equal(A.taskKey(r),A.taskKey(newer));
 assert.notEqual(A.taskKey(r),A.taskKey({...newer,position_orientation:'horizontal',file_name:'BRAND_2026-10_LANDSCAPE.mp4'}));
 assert.notEqual(A.taskKey(r),A.taskKey({...newer,products_text:'Different products'}));
 assert.equal(C.kind({final_type:'pharmaplus',pp_kind:'main'}),'campaign');assert.equal(C.kind({final_type:'pharmaplus',pp_kind:'fallback'}),'thematic');
 assert.equal(C.filename({final_type:'basic',final_title:'Missing',position_orientation:'vertical'},{themes:[]}),'');
});
test('financial totals and export use the same filtered finalized rows and preserve separate credits/planned amounts',async()=>{
 const rows=[{id:'1',pharmacy_id:'a',pharmacy_name:'Alpha',billing_code:'001',year:2026,month:9,category:'deal',amount:30,status:'finalized'},
 {id:'2',pharmacy_id:'a',pharmacy_name:'Alpha',billing_code:'001',year:2026,month:9,category:'deal',amount:-15,status:'finalized'},
 {id:'3',pharmacy_id:'a',pharmacy_name:'Alpha',billing_code:'001',year:2026,month:9,category:'deal',amount:60,status:'planned'},
 {id:'4',pharmacy_id:'b',pharmacy_name:'Beta',billing_code:'002',year:2026,month:10,category:'custom',amount:15,status:'cancelled'}];
 const x=await smoke(html,'hq',null,async n=>n==='scl292_finance'?{data:{rows,history:[],requests:[]},error:null}:undefined);assert.deepEqual(x.errors,[]);
 const u=x.ctx.SCL303;assert.deepEqual(C.sum(u.visibleCharges()),{charges:30,credits:-15,net:15,planned:60});
 const exported=JSON.parse(JSON.stringify(u.exportBillingRows()));assert.deepEqual(exported[2],['001','Alpha','30.00','-15.00','15.00']);assert.equal(exported.filter(r=>r.includes('Προγραμματισμένη χρέωση')).length,0);
 await x.click(x.document.querySelector('[data-scl303="charge-detail"][data-id="1"]'));assert.match(x.document.getElementById('scl303Dialog').textContent,/30,00/);
 u.billing.months=[10];u.renderBilling();assert.equal(x.document.querySelectorAll('#scl303BillingResult tbody tr').length,1);assert.equal(u.exportBillingRows().length,5);
 assert.equal(x.document.getElementById('scl212OpsMode'),null);assert.match(vm.runInContext('scl212OpsMode()',x.ctx),/manual_monthly/);
 assert.doesNotMatch(x.document.getElementById('sclLanding').textContent,/token|dashboard|reporting|Secure access|HQ Mode/);
});
test('explicit completion saves once, undo can be cancelled, successful undo preserves programme and charges',async()=>{
 const p={id:'base-1',ordinal:1,type:'base',startsOn:'2026-10-01',screenFormat:'vertical',playerCode:'ALPHA_ADV1_P',contentCode:'ALPHA_ADV1_P'};
 const data={api_version:290,registry:[{id:'r',pharmacy_id:'a',name:'Alpha',billing_code:'001'}],installations:[{pharmacy_id:'a',positions:[p]}],snapshots:[{pharmacy_id:'a',year:2026,state_json:{cards:[{...p,initialPlanLocked:true,basicSchedule:Array(12).fill('Base')}]}}],setup:[],months:[],deals:[],base:{pharmacies:[],pharmacy_state:[],reports:[]}};
 const writes=[],done=[];const x=await smoke(html,'hq',null,async(n,a)=>{
  if(n==='scl290_hq_data')return{data,error:null};if(n==='scl292_get_done')return{data:done,error:null};
  if(n==='scl292_set_done'){writes.push({n,a});const entry={change_key:a.p_change_key,done:a.p_done,updated_at:'2026-10-21T12:00:00Z'};done.splice(0,done.length,entry);return{data:entry,error:null};}
 });assert.deepEqual(x.errors,[]);const u=x.ctx.SCL303,run=s=>vm.runInContext(s,x.ctx),before=JSON.stringify(data);
 u.openChanges({month:9,status:''});assert.equal(u.visibleChanges().length,1);assert.match(x.document.getElementById('scl303Changes').textContent,/ALPHA_ADV1_P/);
 assert.doesNotMatch(x.document.querySelector('#scl303Changes thead').textContent,/Χρέωση|Billing/);
 await x.click(x.document.querySelector('#scl303Changes [data-scl303="complete"]'));assert.equal(writes.length,1);assert.equal(u.visibleChanges()[0].complete,true);
 assert.match(x.document.getElementById('scl303Changes').textContent,/21\/10\/26/);
 await x.click(x.document.querySelector('#scl303Changes [data-scl303="undo"]'));await x.click(x.document.querySelector('#scl303Dialog [data-scl303="close"]'));assert.equal(writes.length,1);assert.equal(u.visibleChanges()[0].complete,true);
 await x.click(x.document.querySelector('#scl303Changes [data-scl303="undo"]'));await x.click(x.document.querySelector('#scl303Dialog [data-scl303="confirm-undo"]'));assert.equal(writes.length,2);assert.equal(writes[1].a.p_done,false);assert.equal(u.visibleChanges()[0].complete,false);
 assert.equal(JSON.stringify(data),before);assert.equal(run('SCL292.data.rows.length'),0);assert.equal(u.exportChangesRows().length,2);
 const cb=x.document.querySelector('[data-scl303-multi="months"][value="9"]');cb.checked=false;cb.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));assert.equal(u.visibleChanges().length,0);assert.equal(u.exportChangesRows().length,1);
});
