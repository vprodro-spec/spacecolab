const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const Core=require('../src/scl292-core.js');
const {bootstrap}=require('./fixtures/database-bootstrap.cjs');
test('database migration: real PostgreSQL rules, history, approval, quota and shared finance',async t=>{
 const db=new PGlite();await db.exec(bootstrap);await db.exec(fs.readFileSync('tests/fixtures/v290-normalization.sql','utf8'));
 const legacy='00000000-0000-4000-8000-000000000001';
 await db.query("INSERT INTO pharmacies(id,name,token) VALUES($1,'Legacy reports','legacy-token')",[legacy]);
 await db.query('INSERT INTO scl290_snapshots(pharmacy_id,year,state_json) VALUES($1,2020,$2)',[legacy,JSON.stringify({cards:[{id:'base-1',type:'base',title:'Legacy',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),confirmedDeals:[{id:'old-report',confirmed:true,startMonth:2,duration:2,reportMode:'perBlock',monthlyContentChanges:true}]}]})]);
 const migration=fs.readFileSync('supabase/migrations/20261020165150_programme_finance_history.sql','utf8');
 try{await db.exec(migration);}catch(e){throw new Error([e.message,e.where,'position '+e.position].filter(Boolean).join(' | '));}
 await db.exec(fs.readFileSync('supabase/migrations/20261020174619_certification_guards.sql','utf8'));
 await db.exec(`CREATE OR REPLACE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE SET search_path='' AS $$SELECT date '2026-10-20'$$`);
 await t.test('retired report charges are retained from existing confirmed history',async()=>{const r=(await db.query("SELECT sum(amount)::numeric total FROM scl292_charge_events WHERE pharmacy_id=$1 AND category='report'",[legacy])).rows[0];assert.equal(Number(r.total),120);});
 const pid=(await db.query("INSERT INTO pharmacies(name,token) VALUES('Test','test-token') RETURNING id")).rows[0].id;
 await db.query("INSERT INTO scl290_registry(pharmacy_id,name,billing_code) VALUES($1,'Test','B001')",[pid]);
 const positions=[{id:'hq',type:'hq',startsOn:'2026-10-01'},{id:'base-1',type:'base',startsOn:'2026-10-01'},{id:'base-2',type:'base',startsOn:'2026-10-01'},{id:'extra-1',type:'extra',startsOn:'2026-11-01'}];
 await db.query("INSERT INTO scl290_installations(pharmacy_id,service_from,positions) VALUES($1,'2026-10-01',$2)",[pid,JSON.stringify(positions)]);
 const card={id:'base-1',title:'Θέση 1',type:'base',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),simpleSchedule:['B','A','C','A','D','A','E','A','A','A','A','F'],simpleConfirmed:true,confirmedDeals:[],sponsoredShelves:[]};
 await db.query('INSERT INTO scl290_snapshots(pharmacy_id,year,state_json) VALUES($1,2026,$2)',[pid,JSON.stringify({cards:[card],turnover:500000})]);
 const finance=async(token='test-token',hq=null)=>(await db.query('SELECT scl292_finance(2026,$1,$2) f',[token,hq])).rows[0].f;
 await t.test('same finance in pharmacy and HQ; proration equals shared JS to cents',async()=>{
  const ph=await finance(),hq=await finance(null,'test-hq');assert.deepEqual(ph.rows,hq.rows);
  const base=ph.rows.filter(r=>r.category==='base'||r.category==='extra');
  assert.equal(Core.total(base),137.25);assert.equal(Core.total(base),Core.total(Core.fixed({positions,service_from:'2026-10-01'},2026)));
  const actual=ph.rows.filter(r=>r.category==='custom'&&r.status==='finalized');assert.deepEqual(actual.map(r=>r.amount),[0,0,0,15]);
  const planned=ph.rows.find(r=>r.category==='custom'&&r.status==='planned');assert.equal(planned.amount,15);assert.equal(planned.quota_index,5);
 });
 await t.test('unauthorized reset and direct baseline rewrite are rejected',async()=>{
  const reset=structuredClone(card);reset.initialPlanLocked=false;
  await assert.rejects(db.query('SELECT scl290_save_program($1,2026,1,1,$2,\'[]\',\'[]\')',['test-token',JSON.stringify({cards:[reset]})]),/HQ_APPROVAL_REQUIRED/);
  reset.initialPlanLocked=true;reset.basicSchedule[11]='Z';
  await assert.rejects(db.query('SELECT scl290_save_program($1,2026,1,1,$2,\'[]\',\'[]\')',['test-token',JSON.stringify({cards:[reset]})]),/HQ_APPROVAL_REQUIRED/);
 });
 let request;
 await t.test('HQ approval retains current programme until explicit resubmission',async()=>{
  request=(await db.query("SELECT scl292_request_reset('test-token',2026,'base-1','Νέο βασικό πρόγραμμα') r")).rows[0].r;
  assert.equal(request.from_month,11);
  await assert.rejects(db.query('SELECT scl292_decide_reset($1,$2,true,\'\')',['wrong',request.id]),/Unauthorized/);
  await db.query("SELECT scl292_decide_reset('test-hq',$1,true,'Εγκρίνεται')",[request.id]);
  const s=(await db.query('SELECT * FROM scl290_snapshots WHERE pharmacy_id=$1',[pid])).rows[0];
  assert.equal(s.state_json.cards.find(c=>c.id==='base-1').initialPlanLocked,true);assert.equal(s.state_json.cards.find(c=>c.id==='base-1').basicSchedule[11],'A');assert.equal(s.state_json.cards.find(c=>c.id==='base-1')._scl292Reset.id,request.id);
 });
 await t.test('approved replacement keeps charged 15€, free quota and archived history',async()=>{
  const s=(await db.query('SELECT * FROM scl290_snapshots WHERE pharmacy_id=$1',[pid])).rows[0];
  const c=s.state_json.cards.find(c=>c.id==='base-1');c.basicSchedule[11]='Z';c.simpleSchedule[11]='Z';c._scl292ResetApplied=request.id;delete c._scl292Reset;
  await db.query("SELECT scl290_save_program('test-token',2026,1,$1,$2,'[]','[]')",[s.revision,JSON.stringify(s.state_json)]);
  const fresh=(await db.query('SELECT * FROM scl290_snapshots WHERE pharmacy_id=$1',[pid])).rows[0];assert.equal(fresh.state_json.cards.find(c=>c.id==='base-1')._scl292ResetApplied,undefined);
  const f=await finance();assert.equal(Core.total(f.rows.filter(r=>r.category==='custom'&&r.status==='finalized')),15);assert.equal(f.requests[0].status,'applied');assert.ok(f.history.length>=2);
  assert.equal(f.rows.filter(r=>r.category==='custom'&&r.status==='planned').length,0);
  assert.deepEqual((await db.query('SELECT state_json FROM pharmacy_state WHERE pharmacy_id=$1',[pid])).rows[0].state_json,fresh.state_json);
 });
 await t.test('next year proposes previous basic without locking or fake 2026 insertion',async()=>{
  const next=(await db.query("SELECT scl290_get_pharmacy('test-token',2027) d")).rows[0].d;
  assert.equal(next.state_json.cards.find(c=>c.id==='base-1').initialPlanLocked,false);assert.equal(next.state_json.cards.find(c=>c.id==='base-1').pendingInitialSchedule[11],'Z');assert.equal(next.snapshot_revision,0);
 });
 await t.test('central completion is idempotent; undo adds history; access is checked',async()=>{
  await db.query("SELECT scl292_set_done('test-hq','v292|test|2026|0',true)");
  await db.query("SELECT scl292_set_done('test-hq','v292|test|2026|0',true)");
  assert.equal((await db.query('SELECT count(*)::int n FROM scl292_completion_history')).rows[0].n,1);
  assert.equal((await db.query("SELECT scl292_get_done('test-hq') d")).rows[0].d[0].done,true);
  await db.query("SELECT scl292_set_done('test-hq','v292|test|2026|0',false)");
  assert.equal((await db.query('SELECT count(*)::int n FROM scl292_completion_history')).rows[0].n,2);
  await assert.rejects(finance('wrong',null),/Invalid token/);
  const grants=(await db.query("SELECT has_function_privilege('anon','scl_private.capture_charges(uuid,integer,jsonb,bigint)','EXECUTE') helper,has_table_privilege('anon','scl292_charge_events','SELECT') tbl")).rows[0];assert.equal(grants.helper,false);assert.equal(grants.tbl,false);
 });
 await db.close();
});
