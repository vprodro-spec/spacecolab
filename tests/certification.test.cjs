const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const {bootstrap}=require('./fixtures/database-bootstrap.cjs');
const Core=require('../src/scl292-core.js');
test('certification: deadline boundaries, expired approval, history and tenant isolation',async t=>{
 const db=new PGlite();t.after(()=>db.close());await db.exec(bootstrap);
 await db.exec(`CREATE FUNCTION public.create_pharmacy(p_name text) RETURNS SETOF pharmacies LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$INSERT INTO public.pharmacies(name,token) VALUES(p_name,gen_random_uuid()::text) RETURNING *$$;
 CREATE FUNCTION public.cert_hq_create(k text,n text) RETURNS SETOF pharmacies LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$BEGIN PERFORM public.scl290_assert_hq(k);RETURN QUERY SELECT * FROM public.create_pharmacy(n);END$$;`);
 await db.exec(fs.readFileSync('tests/fixtures/v290-normalization.sql','utf8'));
 for(const file of fs.readdirSync('supabase/migrations').filter(f=>f.includes('programme_finance_history')||f.includes('certification_guards')).sort())await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 const today=async d=>db.exec(`CREATE OR REPLACE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE SET search_path='' AS $$SELECT date '${d}'$$`);
 await today('2026-10-15');
 const make=async token=>{
  const pid=(await db.query('INSERT INTO pharmacies(name,token) VALUES($1,$1) RETURNING id',[token])).rows[0].id;
  await db.query("INSERT INTO scl290_registry(pharmacy_id,name,billing_code) VALUES($1,$2,$2)",[pid,token]);
  await db.query("INSERT INTO scl290_installations(pharmacy_id,service_from,positions) VALUES($1,'2026-01-01',$2)",[pid,JSON.stringify([{id:'base-1',type:'base',title:'Θέση 1',startsOn:'2026-01-01'}])]);
  const card={id:'base-1',type:'base',title:'Θέση 1',installationStart:'2026-01-01',initialPlanLocked:true,basicSchedule:Array(12).fill('A'),simpleSchedule:Array(12).fill('A'),simpleConfirmed:true,confirmedDeals:[]};
  await db.query('INSERT INTO scl290_snapshots(pharmacy_id,year,state_json) VALUES($1,2026,$2)',[pid,JSON.stringify({cards:[card],turnover:500000})]);return pid;
 };
 const pid=await make('cert-a'),other=await make('cert-b');
 const snapshot=async (id=pid)=>(await db.query('SELECT * FROM scl290_snapshots WHERE pharmacy_id=$1 AND year=2026',[id])).rows[0];
 const save=async snap=>db.query("SELECT scl290_save_program('cert-a',2026,1,$1,$2,'[]','[]')",[snap.revision,JSON.stringify(snap.state_json)]);
 await t.test('15th is editable; next day the same month is immutable',async()=>{
  let s=await snapshot();s.state_json.cards[0].simpleSchedule[10]='B';await save(s);
  await today('2026-10-16');s=await snapshot();s.state_json.cards[0].simpleSchedule[10]='C';
  await assert.rejects(save(s),/HISTORY_LOCKED/);
 });
 await t.test('future changes work; stale saves cannot overwrite them',async()=>{
  const s=await snapshot();s.state_json.cards[0].simpleSchedule[11]='D';await save(s);
  await assert.rejects(save(s),/PROGRAM_CHANGED/);
 });
 await t.test('approved reopening cannot rewrite a month whose deadline expired after approval',async()=>{
  const req=(await db.query("SELECT scl292_request_reset('cert-a',2026,'base-1','Certification') r")).rows[0].r;
  await db.query("SELECT scl292_decide_reset('test-hq',$1,true,'')",[req.id]);await today('2026-11-16');
  const s=await snapshot(),c=s.state_json.cards[0];c.basicSchedule[11]='Z';c.simpleSchedule[11]='Z';c._scl292ResetApplied=req.id;
  await assert.rejects(save(s),/HISTORY_LOCKED/);
  assert.equal((await db.query('SELECT status FROM scl292_reset_requests WHERE id=$1',[req.id])).rows[0].status,'approved');
  await today('2026-10-20');
 });
 await t.test('token scopes finance; invalid credentials and history writes are rejected',async()=>{
  const f=(await db.query("SELECT scl292_finance(2026,'cert-a',NULL) f")).rows[0].f;
  assert.ok(f.rows.length);assert.ok(f.rows.every(r=>r.pharmacy_id===pid));assert.ok(!f.rows.some(r=>r.pharmacy_id===other));
  await assert.rejects(db.query("SELECT scl292_finance(2026,NULL,'wrong')"),/Unauthorized/);
  await assert.rejects(db.query("SELECT scl290_save_program('cert-a',2025,1,0,'{}','[]','[]')"),/HISTORY_LOCKED/);
 });
 await t.test('anonymous creation is closed; HQ-authorized internal creation still works',async()=>{
  await db.exec('SET ROLE anon');
  try {
   await assert.rejects(db.query("SELECT * FROM create_pharmacy('unauthorized')"),/permission denied/);
   await assert.rejects(db.query("SELECT * FROM cert_hq_create('wrong','unauthorized')"),/Unauthorized/);
   assert.equal((await db.query("SELECT * FROM cert_hq_create('test-hq','Authorized fixture')")).rows.length,1);
   await assert.rejects(db.query('SELECT * FROM scl292_charge_events'),/permission denied/);
  } finally {await db.exec('RESET ROLE');}
 });
 await t.test('monthly agreement content for closed months is protected while future content can change',async()=>{
  await today('2026-08-15');let s=await snapshot();
  s.state_json.cards[0].confirmedDeals=[{id:'deal-1',confirmed:true,supplier:'Supplier',brand:'Brand',startMonth:8,duration:4,monthlyContentChanges:true,monthlyProducts:Array(12).fill('Product'),schedule:Array(12).fill('Video'),soldMonthlyPrice:150}];await save(s);
  await today('2026-10-20');s=await snapshot();s.state_json.cards[0].confirmedDeals[0].monthlyProducts[11]='New';await save(s);
  s=await snapshot();s.state_json.cards[0].confirmedDeals[0].monthlyProducts[9]='Rewrite';await assert.rejects(save(s),/HISTORY_LOCKED/);
 });
});
test('task completion must be invalidated for changed supplier content, format or file',()=>{
 const row={pharmacy_id:'p',position_id:'base-1',year:2026,month:10,final_title:'Brand',final_type:'deal',deal_id:'d',final_detail:'Product A',position_orientation:'vertical',file_name:'A.mp4'};
 for(const patch of [{final_detail:'Product B'},{position_orientation:'horizontal'},{file_name:'B.mp4'}])assert.notEqual(Core.taskKey(row),Core.taskKey({...row,...patch}));
 assert.equal(Core.taskKey(row),Core.taskKey({...row,done:true,amount:30,updated_at:'2026-10-20'}));
});
