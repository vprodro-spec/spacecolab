const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {PGlite}=require('@electric-sql/pglite');const C=require('../src/scl293-core.js');const seed=require('../data/library-seed.json');const {bootstrap}=require('./fixtures/database-bootstrap.cjs');const {smoke}=require('./fixtures/full-app.cjs');const html=fs.readFileSync('index.html','utf8');
test('library seed preserves all original month payloads, including repeated titles with different setups',()=>{
 const original=JSON.parse(html.match(/const PLANOGRAM_DATA=(.*);/)[1]);let total=0;
 for(const [id,entries] of Object.entries(original)){const p=seed.programs.find(p=>p.id===id);entries.forEach((entry,m)=>{const ref=p.months[m],theme=C.theme(seed,ref.theme),v=theme.variants.find(v=>v.id===ref.variant);assert.equal(theme.key,entry.theme);assert.deepEqual(v.setups,entry.setups);assert.deepEqual(C.ref(seed,entry.theme,id,m),ref);total++;});}
 assert.equal(total,36);assert.equal(seed.themes.length,38);assert.equal(C.theme(seed,'Πόνος').variants.length,2);
});
test('programme edits affect new selections and preserve existing schedules and variants',()=>{
 const lib=C.clone(seed),p=lib.programs[0],original=C.schedule(lib,p.id),card={defaultProgram:p.id,basicSchedule:original,libraryRefs:C.clone(p.months)};
 const painMonth=original.lastIndexOf('Πόνος'),old=C.resolve(lib,card,painMonth,'Πόνος');p.months[painMonth]=C.clone(lib.programs[1].months[0]);
 assert.notEqual(C.schedule(lib,p.id)[painMonth],original[painMonth]);assert.equal(C.resolve(lib,card,painMonth,'Πόνος').variant.id,old.variant.id);assert.deepEqual(card.basicSchedule,original);
 const t=C.theme(lib,original[0]);t.title='Νέος τίτλος';t.variants[0].setups[C.styles[0]].products=['Νέο προϊόν'];assert.equal(C.resolve(lib,card,0,original[0]).theme.title,'Νέος τίτλος');assert.deepEqual(card.basicSchedule,original);
 t.status='withdrawn';assert.ok(!C.available(lib).includes(t));assert.ok(!C.programs(lib).includes(p));assert.ok(C.resolve(lib,card,0,original[0]));
});
test('filename corrections and shelf edits create no task; actual material replacement creates a format-specific task',()=>{
 const lib=C.clone(seed),t=lib.themes[0],r={pharmacy_id:'p',position_id:'base-1',month:10,year:2026,final_title:t.key,final_type:'basic',position_orientation:'vertical',content_change_required:false};
 t.files.vertical='A.mp4';assert.deepEqual(C.mediaRows(lib,[r],[],2026,'2026-10-20'),[]);
 lib.media_events=[{id:'revision-1',theme_id:t.id,orientation:'vertical',created_at:'2026-10-20T12:00:00Z'}];
 const rows=C.mediaRows(lib,[r,{...r,month:11},{...r,position_id:'landscape',position_orientation:'horizontal'},{...r,position_id:'deal',final_type:'deal'}],[],2026,'2026-10-20');assert.equal(rows.length,1);assert.equal(rows[0].month,10);assert.equal(rows[0].billing_change_applies,false);assert.equal(rows[0].content_revision,'library:revision-1');
});
test('library database enforces access, revisions, publication rules and retains pharmacy state',async t=>{
 const db=new PGlite();await db.exec(bootstrap);await db.exec(fs.readFileSync('supabase/migrations/'+fs.readdirSync('supabase/migrations').find(x=>x.endsWith('_shared_library.sql')),'utf8'));
 const pid=(await db.query("INSERT INTO pharmacies(name,token) VALUES('Library pharmacy','test-token') RETURNING id")).rows[0].id;
 const state={cards:[{id:'base-1',title:'Θέση 1',initialPlanLocked:true,basicSchedule:C.schedule(seed,'OTC1'),simpleSchedule:C.schedule(seed,'OTC1')}]};await db.query('INSERT INTO scl290_snapshots(pharmacy_id,year,state_json) VALUES($1,2026,$2)',[pid,JSON.stringify(state)]);
 const get=async(hq=true)=>(await db.query('SELECT scl293_library($1,$2) d',[hq?null:'test-token',hq?'test-hq':null])).rows[0].d;
 const save=async(kind,d,mode='correction')=>(await db.query("SELECT scl293_save('test-hq',$1,$2,$3,$4,$5) d",[kind,d.id,d.revision||0,JSON.stringify(d),mode])).rows[0].d;
 let lib=await get();assert.equal(lib.themes.length,38);assert.equal(lib.programs.length,3);
 await t.test('invalid callers and direct table access are rejected',async()=>{
  await assert.rejects(db.query("SELECT scl293_library(null,'wrong')"),/Unauthorized/);await assert.rejects(db.query("SELECT scl293_library('wrong',null)"),/Invalid token/);
  await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT * FROM scl293_themes'),/permission denied/);await db.exec('RESET ROLE');
 });
 let draft={...C.clone(lib.themes[0]),id:'new-theme',title:'Νέα θεματική',status:'draft',revision:0};
 await t.test('drafts are HQ only; explicit publication then withdrawal retains existing content',async()=>{
  draft=await save('theme',draft);assert.ok(!(await get(false)).themes.some(x=>x.id===draft.id));draft.status='available';draft=await save('theme',draft);assert.ok((await get(false)).themes.some(x=>x.id===draft.id));draft.status='withdrawn';draft=await save('theme',draft);assert.ok((await get(false)).themes.some(x=>x.id===draft.id&&x.status==='withdrawn'));
 });
 await t.test('stale writes and incomplete ready programmes are rejected',async()=>{
  await assert.rejects(save('theme',{...draft,revision:1}),/άλλαξε/);await assert.rejects(save('program',{id:'empty',title:'Κενό',status:'available',months:Array(12).fill(null)}),/12 μήνες/);
  const p=await save('program',{id:'draft-program',title:'Υπό προετοιμασία',status:'draft',months:Array(12).fill(null)});assert.equal(p.status,'draft');
 });
 await t.test('planogram edits propagate through library only, without touching schedules or generating media events',async()=>{
  let d=C.theme(lib,seed.programs[0].months[0].theme);d.variants[0].setups[C.styles[0]].products=['Αλλαγμένο προϊόν'];d=await save('theme',d);assert.equal((await get()).media_events.length,0);
  const got=(await db.query('SELECT state_json FROM scl290_snapshots WHERE pharmacy_id=$1',[pid])).rows[0].state_json;assert.deepEqual(got,state);
  const usage=(await db.query("SELECT scl293_usage('test-hq',$1) u",[d.id])).rows[0].u;assert.ok(usage.length>0);lib=await get();
 });
 await t.test('filename correction leaves completions intact; explicit same-name replacement records a revision',async()=>{
  let d=C.theme(lib,seed.programs[0].months[0].theme);d.files.vertical='A.mp4';d=await save('theme',d);assert.equal((await get()).media_events.length,0);d.replacementFormats=['vertical'];d=await save('theme',d,'replacement');assert.equal((await get()).media_events.length,1);d.files.vertical='Corrected.mp4';await save('theme',d);assert.equal((await get()).media_events.length,1);
 });
 await db.close();
});
test('full application integrates HQ library, editor, initial programme and previews without changing saved state',async()=>{
 const x=await smoke(html,'hq');assert.deepEqual(x.errors,[]);assert.ok(x.document.querySelector('[data-tab="library"]'));
 await vm.runInContext('SCL293.load()',x.ctx);vm.runInContext("scl212SetTab('library')",x.ctx);assert.match(x.document.getElementById('scl212Page-library').textContent,/Βιβλιοθήκη/);
 await vm.runInContext('SCL293.edit(SCL293.data.themes[0].id)',x.ctx);assert.ok(x.document.getElementById('scl293Editor'));assert.equal(x.document.querySelectorAll('[data-setup]').length,3);
 const ph=await smoke(html,'pharmacy');await vm.runInContext('SCL293.load()',ph.ctx);vm.runInContext("renderInitialPlanModal('base-1')",ph.ctx);assert.match(ph.document.getElementById('programModalBody').textContent,/Από την αρχή/);
 const before=vm.runInContext('JSON.stringify(state.cards)',ph.ctx);vm.runInContext("SCL293.previewTheme(SCL293.data.themes[0],null,'vertical')",ph.ctx);assert.ok(ph.document.querySelector('#planogramModal .screen-device.vertical'));vm.runInContext("SCL293.previewTheme(SCL293.data.themes[0],null,'horizontal')",ph.ctx);assert.ok(ph.document.querySelector('#planogramModal .screen-device.horizontal'));assert.equal(vm.runInContext('JSON.stringify(state.cards)',ph.ctx),before);
});
