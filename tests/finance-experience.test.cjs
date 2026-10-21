const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const C=require('../src/scl305-finance-core'),A=require('../src/scl292-core'),{smoke}=require('./fixtures/full-app.cjs'),html=fs.readFileSync('index.html','utf8');
const card={id:'base-1',type:'base',title:'Θέση 1',screenFormat:'vertical',playerCode:'ALPHA_ADV1_P',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),startsOn:'2026-10-01'};
test('actual revenue counts only confirmed active months and stored sponsorship, never preagreements or PP',()=>{
 const c={...card,confirmedDeals:[{id:'a',confirmed:true,supplier:'S',brand:'B',startMonth:9,duration:2,soldMonthlyPrice:123.45},{id:'pre',confirmed:false,startMonth:11,duration:1,soldMonthlyPrice:999}],sponsoredShelves:[{month:8,price:50},{month:9,price:55},{month:11,price:50},{month:11,price:999,status:'cancelled'}]};
 const rows=C.revenues([c,{...c,id:'hq',type:'hq'}],2026,A.active);assert.equal(rows.length,3);assert.equal(C.sum(rows),296.9);assert.deepEqual(rows.map(r=>r.month),[9,10,11]);
 assert.equal(C.totals([{status:'finalized',amount:30},{status:'finalized',amount:-10},{status:'planned',amount:15},{status:'cancelled',amount:100}]).total,35);
});
test('original annual estimate preserves dynamic rates, full-year activation and reference-price comparison',()=>{
 const e=C.estimate(3,143,80,2);assert.equal(e.revenue,5148);assert.equal(e.base,485);assert.equal(e.extra,96);assert.equal(e.activation,1080);assert.equal(e.custom,30);assert.equal(e.cost,1691);assert.equal(e.referenceRevenue,3600);assert.equal(e.profit,3457);
});
test('one-month agreement hides monthly-content choice and preserves fields when shortened',async()=>{
 const x=await smoke(html,'pharmacy',{turnover:1000000,cards:[card]},null,{now:'2026-09-01T12:00:00Z'});assert.deepEqual(x.errors,[]);x.ctx.SCL297.openDeal('base-1');assert.equal(x.document.querySelector('[data-scl297-field="monthlyContentChanges"]'),null);
 const duration=x.document.querySelector('[data-scl297-field="duration"]');Object.defineProperty(duration,'value',{value:'2',configurable:true});duration.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));assert.ok(x.document.querySelector('[data-scl297-field="monthlyContentChanges"]'));
 const choose=x.document.querySelector('[data-scl297-field="monthlyContentChanges"]');Object.defineProperty(choose,'value',{value:'monthly',configurable:true});choose.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));const d=x.ctx.SCL297.draft;d.data.monthlyProducts[11]='Keep products';
 const shorten=x.document.querySelector('[data-scl297-field="duration"]');Object.defineProperty(shorten,'value',{value:'1',configurable:true});shorten.dispatchEvent(new x.ctx.Event('change',{bubbles:true}));assert.equal(x.document.querySelector('[data-scl297-field="monthlyContentChanges"]'),null);assert.equal(d.data.monthlyProducts[11],'Keep products');
});
test('supplier proposal and confirmation are pharmacy letters with JPEG, mute video and orientation-specific filenames',async()=>{
 const x=await smoke(html,'pharmacy',{turnover:1000000,cards:[card]});const d={supplier:'Supplier',brand:'Brand',startMonth:10,duration:2,monthlyContentChanges:true,schedule:{10:'First',11:'Second'},soldMonthlyPrice:150};
 x.ctx.SCL297.document('base-1',d,'proposal');const p=x.ctx.SCL297.documentText;assert.match(p,/Αγαπητή ομάδα Supplier/);assert.match(p,/Προτεινόμενο μηνιαίο ποσό/);assert.match(p,/JPEG \(\.jpg ή \.jpeg\)/);assert.match(p,/χωρίς ήχο/);assert.match(p,/1080 × 1920/);assert.match(p,/2026-11_PORTRAIT\.jpg/);assert.match(p,/2026-12_PORTRAIT\.mp4/);assert.doesNotMatch(p,/Κόστος διαχείρισης|Η εφαρμογή δεν στέλνει|Αναφορά Αποτελεσμάτων/);
 x.ctx.SCL297.document('base-1',d,'confirmation');assert.match(x.ctx.SCL297.documentText,/Επιβεβαιώνουμε τη συμφωνία/);assert.match(x.ctx.SCL297.documentText,/Συμφωνημένο μηνιαίο ποσό/);assert.match(x.ctx.SCL297.documentText,/17\/11\/2026/);
 vm.runInContext("state.cards.find(c=>c.id==='base-1').screenFormat='horizontal'",x.ctx);x.ctx.SCL297.document('base-1',d,'proposal');assert.match(x.ctx.SCL297.documentText,/1920 × 1080/);assert.match(x.ctx.SCL297.documentText,/_LANDSCAPE\.jpeg/);
});
test('economics totals open their underlying rows and exclude cancelled charges',async()=>{
 const rows=[{id:'base',position_id:'',year:2026,month:9,category:'base',status:'finalized',amount:40.42},{id:'cancel',position_id:'base-1',year:2026,month:11,category:'deal',status:'cancelled',amount:30}];
 const x=await smoke(html,'pharmacy',{turnover:1000000,cards:[{...card,confirmedDeals:[{confirmed:true,supplier:'S',brand:'B',startMonth:10,duration:2,soldMonthlyPrice:100}]}]},async(n,a)=>n==='scl292_finance'?{data:{year:a.p_year,rows,history:[],requests:[]},error:null}:undefined);assert.deepEqual(x.errors,[]);
 assert.match(x.document.getElementById('economicsGrid').textContent,/40,42/);assert.match(x.document.getElementById('scl295Estimate').textContent,/γενική τιμή αναφοράς/);
 await x.click(x.document.querySelector('#economicsGrid [data-kind="revenue"]'));assert.equal(x.document.querySelectorAll('#scl305Dialog tbody tr').length,2);
});
test('HQ correction requires a reason, reviews before saving and preserves a failed request for retry',async()=>{
 const row={id:'charge',pharmacy_id:'p',pharmacy_name:'Fixture',position_id:'base-1',year:2026,month:9,category:'deal',status:'finalized',amount:30,remaining_credit:30,adjustment_revision:0,entry_type:'charge'};
 const writes=[];let fail=true;
 const x=await smoke(html,'hq',null,async(n,a)=>{
  if(n==='scl292_finance')return {data:{year:a.p_year,rows:[row],history:[],requests:[]},error:null};
  if(n==='scl305_adjust_charge'){writes.push(a);return fail?{data:null,error:{message:'Temporary connection failure'}}:{data:{saved:true},error:null};}
 });
 x.ctx.SCL305.showCharge(row);await x.click(x.document.querySelector('[data-scl305="correct"]'));
 let form=x.document.getElementById('scl305CorrectionForm');form.dispatchEvent(new x.ctx.Event('submit',{bubbles:true}));assert.equal(writes.length,0);assert.match(x.document.getElementById('scl305Error').textContent,/αιτιολογία/);
 form.querySelector('[name="reason"]').value='Agreed correction';form.querySelector('[name="amount"]').value='10';form.dispatchEvent(new x.ctx.Event('submit',{bubbles:true}));assert.match(x.document.getElementById('scl305Dialog').textContent,/Επιβεβαίωση διόρθωσης/);assert.equal(writes.length,0);
 await x.click(x.document.querySelector('[data-scl305="save"]'));assert.match(x.document.getElementById('scl305Error').textContent,/Temporary/);assert.equal(x.ctx.SCL305.busy,false);
 fail=false;await x.click(x.document.querySelector('[data-scl305="save"]'));assert.equal(writes.length,2);assert.equal(writes[0].p_request_id,writes[1].p_request_id);assert.equal(writes[1].p_amount,10);assert.match(x.document.getElementById('scl305Dialog').textContent,/Η διόρθωση καταχωρίστηκε/);
});
test('credits and monetary cancellations do not restore already consumed free customizations',()=>{
 const q=C.quota([{position_id:'base-1',category:'custom',status:'cancelled',source_status:'finalized',quota_index:2,amount:0},{position_id:'base-1',category:'custom',entry_type:'credit',status:'finalized',quota_index:3,amount:-15},{position_id:'base-1',category:'custom',status:'planned',quota_index:3,amount:0}],'base-1');assert.equal(q.used,2);assert.equal(q.remaining,1);
});
