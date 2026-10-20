const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const {bootstrap}=require('./fixtures/database-bootstrap.cjs');
const migration='supabase/migrations/20261020190310_hq_registry_screens.sql';
test('HQ registry lifecycle: activation, installation, pause, correction and full deactivation',async t=>{
 const db=new PGlite();await db.exec(bootstrap);
 await db.exec(`
 ALTER TABLE scl290_registry ADD PRIMARY KEY(id),ADD UNIQUE(pharmacy_id),ADD UNIQUE(billing_code),ADD COLUMN player_prefix text,ADD COLUMN revision bigint DEFAULT 1,ADD COLUMN updated_at timestamptz DEFAULT now();
 ALTER TABLE scl290_registry ALTER COLUMN legacy SET DEFAULT false,ADD FOREIGN KEY(pharmacy_id) REFERENCES pharmacies(id) ON DELETE SET NULL;
 ALTER TABLE scl290_installations ADD FOREIGN KEY(pharmacy_id) REFERENCES pharmacies(id) ON DELETE CASCADE;
 ALTER TABLE scl290_snapshots ADD FOREIGN KEY(pharmacy_id) REFERENCES pharmacies(id) ON DELETE CASCADE;
 ALTER TABLE pharmacy_state ADD FOREIGN KEY(pharmacy_id) REFERENCES pharmacies(id) ON DELETE CASCADE;
 CREATE FUNCTION create_pharmacy(p_name text) RETURNS SETOF pharmacies LANGUAGE sql AS $$INSERT INTO pharmacies(name,token) VALUES(p_name,gen_random_uuid()::text) RETURNING *$$;
 CREATE FUNCTION hq_get_position_months(k text) RETURNS TABLE(pharmacy_id uuid,year integer) LANGUAGE sql AS $$SELECT NULL::uuid,NULL::int WHERE false$$;
 CREATE FUNCTION hq_get_deals(k text) RETURNS TABLE(pharmacy_id uuid,year integer) LANGUAGE sql AS $$SELECT NULL::uuid,NULL::int WHERE false$$;
 CREATE FUNCTION hq_delete_pharmacy(k text,p uuid) RETURNS void LANGUAGE plpgsql AS $$BEGIN PERFORM public.scl290_assert_hq(k);DELETE FROM public.pharmacies WHERE id=p;END$$;
 `);
 await db.exec(fs.readFileSync('tests/fixtures/v290-normalization.sql','utf8'));
 await db.exec(fs.readFileSync('tests/fixtures/v290-registry.sql','utf8'));
 for(const f of ['20261020165150_programme_finance_history.sql','20261020174619_certification_guards.sql','20261020190310_hq_registry_screens.sql','20261020191752_paused_position_sponsorship_guard.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
 await db.exec(`CREATE OR REPLACE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE SET search_path='' AS $$SELECT date '2026-10-20'$$`);
 const rpc=async(name,params)=>(await db.query(`SELECT ${name}(${params.map((_,i)=>'$'+(i+1)).join(',')}) d`,params)).rows[0].d;
 let reg,ph,cfg;
 const record={name:'Test Pharmacy',billing_code:'B001',address:'Test street 1',area:'Athens'};
 await t.test('new pharmacy is inactive; four required fields and unique billing identity',async()=>{
  await assert.rejects(rpc('scl290_hq_registry_save',['wrong',null,0,record]),/Unauthorized/);
  await assert.rejects(rpc('scl290_hq_registry_save',['test-hq',null,0,{...record,address:''}]),/τέσσερα|Συμπληρώστε/);
  reg=await rpc('scl290_hq_registry_save',['test-hq',null,0,record]);assert.equal(reg.pharmacy_id,null);
  await assert.rejects(rpc('scl290_hq_registry_save',['test-hq',null,0,record]),/unique/);
  ph=await rpc('scl290_hq_activate',['test-hq',reg.id,null]);assert.ok(ph.token);
  assert.equal((await rpc('scl290_get_pharmacy',[ph.token,2026])).installation,null);
 });
 const position=(n,startsOn='2026-09-01')=>({id:n===0?'hq':n<=2?'base-'+n:'extra-'+(n-2),ordinal:n,type:n===0?'hq':n<=2?'base':'extra',screenFormat:n===2?'horizontal':'vertical',startsOn});
 await t.test('HQ assigns stable codes and orientation; pharmacy cannot overwrite them',async()=>{
  cfg=await rpc('scl290_hq_install',['test-hq',reg.id,0,2026,'PAPADOPOULOS','2026-09-01',[0,1,2,3].map(n=>position(n))]);
  assert.equal(cfg.positions[0].playerCode,'PAPADOPOULOS_ADV0_P');assert.equal(cfg.positions[2].playerCode,'PAPADOPOULOS_ADV2_L');
  let ctx=await rpc('scl290_get_pharmacy',[ph.token,2026]);
  ctx.state_json.cards.forEach(c=>{c.initialPlanLocked=true;c.basicSchedule=Array(12).fill('A');c.simpleSchedule=Array(12).fill('A');c.screenFormat='horizontal';});
  const extra=ctx.state_json.cards.find(c=>c.id==='extra-1');extra.confirmedDeals=[{id:'future',confirmed:true,startMonth:11,duration:1,supplier:'Test',brand:'Brand',soldMonthlyPrice:150,monthlyContentChanges:false}];
  const rows=cfg.positions.flatMap(p=>[8,9,10,11].map(month=>({position_id:p.id,month,final_title:'A',final_type:'basic'})));
  await rpc('scl290_save_program',[ph.token,2026,cfg.version,ctx.snapshot_revision,ctx.state_json,rows,[]]);
  ctx=await rpc('scl290_get_pharmacy',[ph.token,2026]);assert.equal(ctx.state_json.cards[0].screenFormat,'vertical');
  const f=await rpc('scl292_finance',[2026,ph.token,null]);assert.ok(f.rows.some(x=>x.category==='deal'&&x.status==='planned'));
 });
 let before;
 await t.test('pause preserves schedules and finalized charges, removes future work and variable cost',async()=>{
  before=await rpc('scl290_get_pharmacy',[ph.token,2026]);
  await db.query("INSERT INTO scl292_charge_events(pharmacy_id,year,position_id,position_name,category,event_key,start_month,end_month,description,amount,source_revision) VALUES($1,2026,'extra-1','Θέση 3','custom','history-charge',8,8,'Historical',15,1)",[ph.id]);
  const positions=structuredClone(cfg.positions);positions[3].stopsOn='2026-12-01';
  cfg=await rpc('scl290_hq_install',['test-hq',reg.id,cfg.version,2026,'PAPADOPOULOS','2026-09-01',positions]);
  const after=await rpc('scl290_get_pharmacy',[ph.token,2026]);assert.deepEqual(after.state_json.cards[3].confirmedDeals,before.state_json.cards[3].confirmedDeals);assert.deepEqual(after.state_json.cards[3].basicSchedule,before.state_json.cards[3].basicSchedule);
  const s=(await db.query('SELECT months_json FROM scl290_snapshots WHERE pharmacy_id=$1',[ph.id])).rows[0];assert.equal(s.months_json.some(x=>x.position_id==='extra-1'&&x.month===11),false);assert.ok(s.months_json.some(x=>x.position_id==='extra-1'&&x.month===8));
  const f=await rpc('scl292_finance',[2026,ph.token,null]);assert.ok(f.rows.some(x=>x.event_key==='history-charge'&&Number(x.amount)===15));assert.equal(f.rows.some(x=>x.category==='deal'&&x.status==='planned'),false);assert.equal(f.rows.some(x=>x.category==='extra'&&x.month===11),false);
  await assert.rejects(rpc('scl290_save_program',[ph.token,2026,1,before.snapshot_revision,before.state_json,[],[]]),/INSTALLATION_CHANGED/);
  const bad=structuredClone(cfg.positions);bad[2].stopsOn='2026-09-01';await assert.rejects(rpc('scl290_hq_install',['test-hq',reg.id,cfg.version,2026,'PAPADOPOULOS','2026-09-01',bad]),/μελλοντικό/);
  const shelfState=structuredClone(after.state_json);shelfState.cards[3].sponsoredShelves=[{month:11,price:80,brand:'Test'}];await assert.rejects(rpc('scl290_save_program',[ph.token,2026,cfg.version,after.snapshot_revision,shelfState,[],[]]),/POSITION_PAUSED/);
  after.state_json.cards[3].confirmedDeals[0].brand='Changed';await assert.rejects(rpc('scl290_save_program',[ph.token,2026,cfg.version,after.snapshot_revision,after.state_json,[],[]]),/POSITION_PAUSED/);
 });
 await t.test('adding after a pause uses the next ordinal and leaves old position intact',async()=>{
  const positions=[...cfg.positions,position(4,'2026-11-01')];cfg=await rpc('scl290_hq_install',['test-hq',reg.id,cfg.version,2026,'PAPADOPOULOS','2026-09-01',positions]);assert.equal(cfg.positions[3].stopsOn,'2026-12-01');assert.equal(cfg.positions[4].playerCode,'PAPADOPOULOS_ADV4_P');
  await assert.rejects(rpc('scl290_hq_install',['test-hq',reg.id,cfg.version,2026,'PAPADOPOULOS','2026-09-01',positions.slice(0,4)]),/Δεν αφαιρούνται/);
 });
 await t.test('special correction changes current codes, preserves prior-month format and schedule',async()=>{
  const formats=Object.fromEntries(cfg.positions.map(p=>[p.id,p.screenFormat]));formats['base-1']='horizontal';
  const ctx=await rpc('scl290_get_pharmacy',[ph.token,2026]);
  cfg=await rpc('scl294_correct_installation',['test-hq',reg.id,cfg.version,'PAPADOPOULOS_CENTER',formats,'2026-10-01']);
  assert.equal(cfg.positions[1].playerCode,'PAPADOPOULOS_CENTER_ADV1_L');
  const past=await rpc('scl_private.position_at',[cfg.positions[1],2026,8]);assert.equal(past.playerCode,'PAPADOPOULOS_ADV1_P');
  const after=await rpc('scl290_get_pharmacy',[ph.token,2026]);assert.deepEqual(after.state_json.cards[1].basicSchedule,ctx.state_json.cards[1].basicSchedule);
  const ms=(await db.query('SELECT months_json FROM scl290_snapshots WHERE pharmacy_id=$1',[ph.id])).rows[0].months_json;assert.equal(ms.find(x=>x.position_id==='base-1'&&x.month===8).position_orientation,'vertical');assert.equal(ms.find(x=>x.position_id==='base-1'&&x.month===9).position_orientation,'horizontal');
  await assert.rejects(rpc('scl294_correct_installation',['wrong',reg.id,cfg.version,'OTHER',formats,'2026-10-01']),/Unauthorized/);
  const other=await rpc('scl290_hq_registry_save',['test-hq',null,0,{...record,billing_code:'B002'}]);await rpc('scl290_hq_activate',['test-hq',other.id,null]);
  await assert.rejects(rpc('scl290_hq_install',['test-hq',other.id,0,2026,'PAPADOPOULOS_CENTER','2026-10-01',[position(0,'2026-10-01')]]),/πρόθεμα/);
 });
 await t.test('deactivation requires name and revision; restores registry, revokes token and clears activation data',async()=>{
  reg=(await db.query('SELECT * FROM scl290_registry WHERE id=$1',[reg.id])).rows[0];
  await rpc('scl292_set_done',['test-hq','v292|'+ph.id+'|base-1|2026|10',true]);
  await assert.rejects(rpc('scl294_deactivate',['test-hq',reg.id,reg.revision,'wrong']),/επωνυμία/);
  await assert.rejects(rpc('scl294_deactivate',['test-hq',reg.id,1,reg.name]),/REGISTRY_CHANGED/);
  const reset=await rpc('scl294_deactivate',['test-hq',reg.id,reg.revision,reg.name]);assert.equal(reset.pharmacy_id,null);assert.equal(reset.player_prefix,null);assert.equal(reset.billing_code,'B001');assert.equal(reset.legacy,false);
  await assert.rejects(rpc('scl290_get_pharmacy',[ph.token,2026]),/Invalid token/);
  for(const table of ['scl290_installations','scl290_snapshots','pharmacy_state','scl292_charge_events','scl292_program_history','scl292_reset_requests','scl294_installation_history'])assert.equal((await db.query(`SELECT count(*)::int n FROM ${table} WHERE pharmacy_id=$1`,[ph.id])).rows[0].n,0,table);
  assert.equal((await db.query('SELECT count(*)::int n FROM hq_changes_done')).rows[0].n,0);assert.equal((await db.query('SELECT count(*)::int n FROM scl292_completion_history')).rows[0].n,0);
  const again=await rpc('scl290_hq_activate',['test-hq',reg.id,null]);assert.notEqual(again.token,ph.token);assert.equal((await rpc('scl290_get_pharmacy',[again.token,2026])).installation,null);
  assert.equal((await db.query("SELECT has_table_privilege('anon','scl294_installation_history','SELECT') p")).rows[0].p,false);
 });
 await db.close();
});
