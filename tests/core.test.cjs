const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const C=require('../src/scl292-core.js');
const cfg={service_from:'2026-10-01',positions:[{id:'hq',type:'hq',startsOn:'2026-10-01'},{id:'base-1',type:'base',startsOn:'2026-10-01'},{id:'base-2',type:'base',startsOn:'2026-10-01'}]};
test('October actual base is 121.25; full-year estimate 485, monthly cents reconcile',()=>{
 assert.equal(C.total(C.fixed(cfg,2026)),121.25);
 assert.equal(C.total(C.fixed(cfg,2026,true)),485);
 assert.deepEqual(C.fixed(cfg,2026).map(r=>r.amount),[40.42,40.41,40.42]);
 assert.equal(C.total(C.fixed(cfg,2025)),0);
 assert.equal(C.total(C.fixed(cfg,2027)),485);
});
test('third local starts in November, PP excluded; cessation is prospective',()=>{
 const config=structuredClone(cfg);config.positions.push({id:'extra-1',type:'extra',startsOn:'2026-11-01',stopsOn:'2027-02-01'});
 assert.equal(C.total(C.fixed(config,2026).filter(r=>r.category==='extra')),16);
 assert.equal(C.total(C.fixed(config,2027).filter(r=>r.category==='extra')),8);
});
test('cutoff is prior-month 15 inclusive, using Athens date across year',()=>{
 assert.equal(C.cutoff(2027,0),'2026-12-15');
 assert.equal(C.editable(2027,0,new Date('2026-12-15T21:30:00Z')),true);
 assert.equal(C.editable(2027,0,new Date('2026-12-15T22:30:00Z')),false);
 assert.equal(C.year(2027),2027);
});
test('task identity distinguishes January, year and content, independent of done state',()=>{
 const row={pharmacy_id:'p',position_id:'base-1',year:2026,month:0,final_title:'A'};
 assert.notEqual(C.taskKey(row),C.taskKey({...row,year:2027}));
 assert.notEqual(C.taskKey(row),C.taskKey({...row,month:1}));
 assert.notEqual(C.taskKey(row),C.taskKey({...row,final_title:'B'}));
 assert.equal(C.taskKey(row),C.taskKey({...row,done:true}));
});
test('aged approval only reopens still-editable months; expired approval offers no month',()=>{
 assert.equal(C.resetFrom({fromMonth:10},2026,new Date('2026-10-15T12:00:00Z')),10);
 assert.equal(C.resetFrom({fromMonth:10},2026,new Date('2026-10-16T12:00:00Z')),11);
 assert.equal(C.resetFrom({fromMonth:10},2026,new Date('2026-11-16T12:00:00Z')),-1);
});
test('approved reopening preserves past selections, agreements and past sponsorship',()=>{
 const card={basicSchedule:Array(12).fill('A'),simpleSchedule:Array(12).fill('C'),pendingSimpleSchedule:Array(12).fill('C'),simpleMechanism:Array(12).fill('x'),pendingSimpleMechanism:Array(12).fill('x'),confirmedDeals:[{id:'keep'}],preagreements:[{id:'pre'}],negotiation:{confirmed:true},simpleConfirmed:true,sponsoredShelves:[{month:8},{month:11}],_scl292Reset:{id:'req',fromMonth:11}};
 const lock=(c,t,p,s)=>{Object.assign(c,{basicSchedule:[...s],simpleSchedule:[...s],pendingSimpleSchedule:[...s],simpleMechanism:Array(12).fill(''),pendingSimpleMechanism:Array(12).fill('')});return true;};
 assert.equal(C.applyReset(card,'own','',Array(12).fill('B'),lock),true);
 assert.equal(card.basicSchedule[10],'A');assert.equal(card.simpleSchedule[10],'C');assert.equal(card.basicSchedule[11],'B');
 assert.equal(card.confirmedDeals[0].id,'keep');assert.equal(card.sponsoredShelves.length,1);assert.equal(card._scl292ResetApplied,'req');
});
test('every inline script compiles; old year enforcement is removed',()=>{
 const ids=['scl290-installation','scl292-ui','scl293-ui','scl295-pharmacy','scl297-actions-core','scl297-actions-ui'];
 const built=fs.readFileSync('index.html','utf8');
 const offsets=ids.map(id=>{const marker='<script id="'+id+'">';assert.equal(built.split(marker).length-1,1,id);return built.indexOf(marker);});
 assert.deepEqual(offsets,[...offsets].sort((a,b)=>a-b),'UI dependencies must precede their consumers in every build');
 const html=fs.readFileSync('index.html','utf8');let count=0;
 for(const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
  if(/\bsrc\s*=|application\/json/.test(m[1]))continue;
  new vm.Script(m[2],{filename:'inline-script-'+(++count)});
 }
 assert.ok(count>5);assert.equal((html.match(/id="scl292-core"/g)||[]).length,1);assert.equal((html.match(/id="scl292-ui"/g)||[]).length,1);
 assert.ok(!html.includes('Number(state.programYear) > 2026'));
 assert.ok(!html.includes('const visualDone=done||past'));
 assert.ok(!html.includes("localStorage.setItem(key, JSON.stringify(SCL212?.done||{}))"));
});
