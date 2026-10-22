const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');

test('HQ refresh retains loaded data on network failure and clears its notice after recovery',async()=>{
 let offline=false;const calls=[];
 const x=await smoke(html,'hq',null,async(name)=>{
  calls.push(name);
  if(offline&&name==='scl290_hq_data')return {data:null,error:{message:'TypeError: Failed to fetch'}};
 });
 assert.deepEqual(x.errors,[]);
 const hq=x.ctx.SCL290.hq;
 offline=true;
 await assert.rejects(x.ctx.SCL290.refreshHQ());
 assert.equal(x.ctx.SCL290.hq,hq);
 const notice=x.document.getElementById('scl290Notice');
 assert.equal(notice.hidden,false);
 offline=false;
 await x.ctx.SCL290.refreshHQ();
 assert.equal(notice.hidden,true,'Recovered read must dismiss its stale connection error');
 assert.equal(x.ctx.SCL290.error,'');
 assert.equal(calls.some(n=>/save|update|delete|activate|deactivate/.test(n)),false);
});

test('repeated failed refreshes keep a visible, actionable error',async()=>{
 const x=await smoke(html,'hq',null,async(name)=>name==='scl290_hq_data'?{data:null,error:{message:'TypeError: Failed to fetch'}}:undefined);
 await assert.rejects(x.ctx.SCL290.refreshHQ());
 const notice=x.document.getElementById('scl290Notice');
 assert.equal(notice.hidden,false);
 assert.match(notice.textContent,/Δεν ολοκληρώθηκε η ανανέωση/);
 assert.match(notice.textContent,/Ανανέωση/);
 assert.equal(x.ctx.SCL290.hq,null);
});

test('successful background refresh does not dismiss a failed save or retry the write',async()=>{
 let writes=0;
 const x=await smoke(html,'hq',null,async(name)=>{
  if(name==='scl290_hq_registry_save'){writes++;return {data:null,error:{message:'Δεν αποθηκεύτηκε η αλλαγή.'}};}
 });
 vm.runInContext('sclCreatePharmacyFromHq()',x.ctx);
 x.document.getElementById('scl290Name').value='Δοκιμή';
 x.document.getElementById('scl290RegistryForm').dispatchEvent(new x.ctx.Event('submit',{bubbles:true,cancelable:true}));
 for(let i=0;i<12;i++)await new Promise(r=>setImmediate(r));
 const notice=x.document.getElementById('scl290DialogStatus');
 assert.match(notice.textContent,/Δεν αποθηκεύτηκε/);
 await x.ctx.SCL290.refreshHQ();
 assert.equal(notice.isConnected,true);
 assert.match(notice.textContent,/Δεν αποθηκεύτηκε/);
 assert.equal(x.document.getElementById('scl290Name').value,'Δοκιμή');
 assert.equal(writes,1);
});
