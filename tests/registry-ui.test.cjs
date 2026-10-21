const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');
test('HQ interface: activation opens screens, progress excludes PP, selected export and deactivation preview',async()=>{
 const dataset={api_version:290,setup:[],months:[],deals:[],registry:[{id:'registry-a',name:'Test Pharmacy',billing_code:'A001',address:'Street 1',area:'Athens',revision:1,pharmacy_id:null}],installations:[],base:{pharmacies:[],pharmacy_state:[],hq_programs:[],hq_changes_done:[],reports:[]}};
 const calls=[];
 const x=await smoke(html,'hq',null,async(name,args)=>{
  calls.push({name,args});
  if(name==='scl300_pp_pharmacy')return{data:[{month:9,display_title:'Shared PP campaign',display_kind:'main'}],error:null};
  if(name==='scl290_hq_data')return{data:structuredClone(dataset),error:null};
  if(name==='scl290_hq_activate'){dataset.registry[0].pharmacy_id='ph-a';dataset.registry[0].token='fixture-token-a';return{data:{id:'ph-a'},error:null};}
 });assert.deepEqual(x.errors,[]);
 const click=sel=>{const e=x.document.querySelector(sel);assert.ok(e,sel);e.dispatchEvent(new x.ctx.Event('click',{bubbles:true}));};
 click('[data-scl290="view-inactive"]');click('[data-scl290="activate"]');
 Object.defineProperty(x.document.getElementById('scl290LinkExisting'),'value',{value:''});click('[data-scl290="activate-confirm"]');
 for(let i=0;i<12;i++)await new Promise(r=>setImmediate(r));
 assert.ok(x.document.getElementById('scl290InstallForm'));assert.equal(x.document.getElementById('scl290Link'),null);assert.match(x.document.getElementById('scl290PositionRows').textContent,/Pharmaplus/);
 click('[data-scl290="close"]');click('[data-scl290="link"]');assert.match(x.document.getElementById('scl290Dialog').textContent,/Εκκρεμεί εγκατάσταση/);click('[data-scl290="close"]');
 dataset.installations=[{pharmacy_id:'ph-a',version:1,service_from:'2026-10-01',positions:[{id:'hq',ordinal:0,type:'hq',screenFormat:'vertical',startsOn:'2026-10-01',playerCode:'TEST_ADV0_P',contentCode:'TEST_ADV0_P'},{id:'base-1',ordinal:1,type:'base',screenFormat:'horizontal',startsOn:'2026-10-01',playerCode:'TEST_ADV1_L',contentCode:'TEST_ADV1_L'}]}];
 dataset.setup=[{pharmacy_id:'ph-a',year:2026,positions_json:[{position_id:'hq',locked:true},{position_id:'base-1',locked:false}]}];dataset.registry[0].player_prefix='TEST';
 await vm.runInContext('SCL290.refreshHQ()',x.ctx);
 assert.match(x.document.getElementById('scl290RegistryRows').textContent,/0\/1 θέσεις με αρχικό πρόγραμμα/);
 click('[data-scl290="install"]');assert.ok(x.document.querySelector('[data-pos-format="1"]').hasAttribute('disabled'));assert.ok(x.document.querySelector('[data-pos-stop="1"]'));click('[data-scl290="correct"]');assert.ok(x.document.getElementById('scl294CorrectionForm'));assert.match(x.document.getElementById('scl290Dialog').textContent,/χειροκίνητη διόρθωση στο Product Me/);click('[data-scl290="close"]');
 click('[data-scl290="programme"]');for(let i=0;i<3;i++)await new Promise(r=>setImmediate(r));assert.match(x.document.getElementById('scl290Dialog').textContent,/Shared PP campaign/);assert.match(x.document.getElementById('scl290Dialog').textContent,/Ιαν–Σεπ/);click('[data-scl290="close"]');
 click('[data-scl290="link"]');assert.ok(x.document.querySelector('#scl290Dialog details input'));click('[data-scl290="close"]');
 dataset.registry.push({id:'registry-b',pharmacy_id:'ph-b',name:'Unselected',billing_code:'B001'});dataset.installations.push({pharmacy_id:'ph-b',positions:[{ordinal:0,type:'hq',playerCode:'UNSELECTED_ADV0_P'}]});
 await vm.runInContext('SCL290.refreshHQ()',x.ctx);
 const box=x.document.querySelector('[data-scl294-select="registry-a"]');box.checked=true;box.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));
 let exported;x.ctx.URL.createObjectURL=b=>{exported=b;return 'blob:test'};x.ctx.URL.revokeObjectURL=()=>{};x.ctx.HTMLElement.prototype.click=function(){};
 vm.runInContext('SCL290.exportPlayers(true)',x.ctx);const csv=await exported.text();assert.match(csv,/TEST_ADV1_L/);assert.doesNotMatch(csv,/UNSELECTED_ADV0/);
 click('[data-scl290="deactivate"][data-id="registry-a"]');assert.ok(x.document.getElementById('scl294ConfirmName'));assert.match(x.document.getElementById('scl290Dialog').textContent,/χρεώσεις/);assert.equal(calls.filter(x=>x.name==='scl294_deactivate').length,0);
});
test('paused position remains readable, blocks changes, and respects earlier-month orientation',async()=>{
 const card={id:'base-1',type:'base',title:'Θέση 1',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),simpleSchedule:Array(12).fill('A'),confirmedDeals:[],sponsoredShelves:[]};
 const x=await smoke(html,'pharmacy',{cards:[card],turnover:500000});assert.deepEqual(x.errors,[]);
 vm.runInContext(`SCL290.context.installation.positions[1].stopsOn='2026-12-01';SCL290.context.installation.positions[1].configurationHistory=[{until:'2026-10-01',screenFormat:'horizontal',playerCode:'OLD_ADV1_L'}];refresh(false)`,x.ctx);
 assert.equal(vm.runInContext("state.cards.find(c=>c.id==='base-1').stopsOn",x.ctx),'2026-12-01');
 assert.equal(vm.runInContext("isCustomReadOnlyMonth(state.cards.find(c=>c.id==='base-1'),11)",x.ctx),true);
 assert.equal(vm.runInContext("monthStatus(state.cards.find(c=>c.id==='base-1'),11).label",x.ctx),'Η θέση έχει παύσει');
 assert.equal(vm.runInContext("SCL290Core.at(state.cards.find(c=>c.id==='base-1'),2026,8).screenFormat",x.ctx),'horizontal');
 assert.ok(vm.runInContext("timelineSegments(state.cards.find(c=>c.id==='base-1')).some(s=>s.label==='Η θέση έχει παύσει')",x.ctx));
});
