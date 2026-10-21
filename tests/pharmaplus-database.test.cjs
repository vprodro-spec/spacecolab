const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');const {bootstrap}=require('./fixtures/database-bootstrap.cjs');const C=require('../src/scl300-pharmaplus-core');
const migration=fs.readFileSync('supabase/migrations/20261021110137_pharmaplus_annual_programme.sql','utf8');
const legacySchema=`CREATE SCHEMA scl_private;CREATE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE AS $$SELECT date '2026-10-21'$$;
CREATE TABLE pharmaplus_campaigns(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),year integer,month integer,campaign_type text,title text,supplier text,company_benefit text,products_text text,shelf_instructions text,shelf_1 text,shelf_2 text,shelf_3 text,shelf_4 text,fallback_title text,scope_mode text DEFAULT 'all',scope_pharmacy_ids uuid[] DEFAULT '{}');
CREATE TABLE scl293_themes(id text PRIMARY KEY,data jsonb);CREATE TABLE scl293_media_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),theme_id text,orientation text,created_at timestamptz DEFAULT now());`;
test('Pharmaplus database: cross-year periods, participation, history and atomic preview',async t=>{
 const db=new PGlite();await db.exec(bootstrap+legacySchema);
 await db.exec("INSERT INTO pharmaplus_campaigns(year,month,title,supplier,fallback_title) VALUES(2026,9,'October history','Supplier','Autumn'),(2026,11,'Legacy December','Supplier','Winter');");
 for(const signature of [...migration.matchAll(/REVOKE ALL ON FUNCTION public\.(hq_(?:upsert|delete)_pharmaplus_campaign\([^)]*\))/g)].map(m=>m[1]))await db.exec('CREATE FUNCTION public.'+signature+' RETURNS void LANGUAGE sql AS $$SELECT$$');
 await db.exec(migration);
 await db.exec(fs.readFileSync('supabase/migrations/20261021115851_pharmaplus_save_guard.sql','utf8'));
 await t.test('all revision writes have a singleton WHERE clause for API safeupdate sessions',async()=>{
  for(const fn of ['public.scl300_pp_save(text,jsonb,text,boolean)','scl_private.pp_library_sync()','scl_private.pp_media_sync()']){
   const definition=(await db.query('SELECT pg_get_functiondef($1::regprocedure) definition',[fn])).rows[0].definition;
   const updates=[...definition.matchAll(/UPDATE scl_private\.pp_meta[^;]+;/g)];assert.equal(updates.length,1);assert.match(updates[0][0],/WHERE singleton=true/);
  }
 });
 const phs=[];
 for(const [name,start] of [['A','2026-11-01'],['B','2026-12-01'],['C','2027-02-01']]){
  const pid=(await db.query('INSERT INTO pharmacies(name,token) VALUES($1,$2) RETURNING id',[name,'token-'+name])).rows[0].id;
  const rid=(await db.query('INSERT INTO scl290_registry(name,pharmacy_id,billing_code) VALUES($1,$2,$1) RETURNING id',[name,pid])).rows[0].id;
  const pos={id:'hq',type:'hq',screenFormat:'vertical',playerCode:name+'_ADV0_P',startsOn:start};
  await db.query('INSERT INTO scl290_installations(pharmacy_id,service_from,positions) VALUES($1,$2,$3)',[pid,start,JSON.stringify([pos])]);phs.push({id:pid,registry_id:rid,name,active:true,positions:[pos]});
 }
 await db.query("INSERT INTO scl293_themes VALUES('winter',$1)",[JSON.stringify({title:'Winter theme',status:'available',files:{vertical:'WINTER_P.mp4',horizontal:'WINTER_L.mp4'}})]);
 const hq=async y=>(await db.query("SELECT scl300_pp_hq('test-hq',$1) d",[y])).rows[0].d;
 const preview=async req=>(await db.query("SELECT scl300_pp_preview('test-hq',$1) d",[JSON.stringify(req)])).rows[0].d;
 const save=async(req,p=null,replace=false)=>(await db.query("SELECT scl300_pp_save('test-hq',$1,$2,$3) d",[JSON.stringify(req),(p||await preview(req)).fingerprint,replace])).rows[0].d;
 const pharmacy=async(name,y)=>(await db.query('SELECT scl300_pp_pharmacy($1,$2) d',['token-'+name,y])).rows[0].d;
 const campaign={title:'Winter campaign',supplier:'Supplier',scope:{mode:'all',ids:[]},files:{vertical:'CAMPAIGN_P.mp4',horizontal:'CAMPAIGN_L.mp4'},shelf_1:'Products'};
 let cid;
 await t.test('migration keeps legacy campaign, independent fallback and complete archive',async()=>{
  const d=await hq(2026);assert.equal(d.records.length,2);assert.equal(d.records[0].campaign.title,'October history');assert.equal(d.records[0].thematic.title,'Autumn');assert.equal((await db.query('SELECT count(*)::int n FROM scl_private.pp_legacy_archive')).rows[0].n,2);
 });
 for(const month_on of ['2026-11-01','2026-12-01','2027-01-01','2027-02-01','2027-03-01'])await save({action:'theme',month_on,data:{theme_id:'winter'}});
 await t.test('one Nov–Feb campaign requires explicit replacement and commits all months atomically',async()=>{
  const req={action:'create',month_on:'2026-11-01',duration:4,data:campaign},p=await preview(req);
  assert.equal(p.months.length,4);assert.equal(p.affected_pharmacies,3);assert.equal(p.conflicts.length,1);
  assert.equal(p.months[0].affected,1);assert.equal(p.months[3].affected,3);
  await assert.rejects(save(req,p),/ρητή επιβεβαίωση/);assert.equal((await hq(2026)).records.find(s=>s.month_on==='2026-11-01').campaign_id,null);
  cid=(await save(req,p,true)).campaign_id;
  const slots=(await hq(2027)).records.filter(s=>s.campaign_id===cid);assert.equal(slots.length,4);assert.ok(slots.every(s=>s.starts_on==='2026-11-01'&&s.ends_on==='2027-02-01'));assert.ok(slots.every(s=>s.thematic.title==='Winter theme'));
  assert.equal((await pharmacy('A',2026))[10].display_title,'Winter campaign');assert.equal((await pharmacy('A',2027))[0].campaign_id,cid);assert.equal((await pharmacy('B',2026))[10].display_kind,'inactive');assert.equal((await pharmacy('C',2027))[0].display_kind,'inactive');
 });
 await t.test('same campaign crosses January with no duplicate HQ task; new installations get one',async()=>{
  const d=await hq(2027),rows=C.rows(d,2027);assert.equal(rows.filter(r=>r.pharmacy_id===phs[0].id&&r.month===0).length,0);assert.equal(rows.filter(r=>r.pharmacy_id===phs[2].id&&r.month===1).length,1);assert.equal(C.rows(d,2026).find(r=>r.pharmacy_id===phs[0].id).month_label,'Νοε 2026 – Φεβ 2027');
 });
 await t.test('monthly participation override leaves other months and the underlying theme intact',async()=>{
  await save({action:'scope',month_on:'2027-01-01',campaign_id:cid,scope:{mode:'only',ids:[phs[0].registry_id]},inherit:false});
  const b=await pharmacy('B',2027);assert.equal(b[0].display_kind,'fallback');assert.equal(b[1].display_kind,'main');assert.equal((await pharmacy('A',2027))[0].display_kind,'main');
  assert.equal((await db.query("SELECT * FROM pharmacy_get_pharmaplus_campaigns('token-B',2027)")).rows[0].display_title,'Winter theme');
  assert.equal((await db.query("SELECT * FROM hq_get_pharmaplus_campaigns('test-hq',2027) WHERE month=0")).rows[0].scope_pharmacy_ids[0],phs[0].id);
  const rows=C.rows(await hq(2027),2027).filter(r=>r.pharmacy_id===phs[1].id);assert.deepEqual(rows.slice(0,3).map(r=>r.month),[0,1,2]);
 });
 await t.test('editing one month or the campaign tail preserves previous records and overrides',async()=>{
  const before=(await hq(2027)).records.find(s=>s.month_on==='2026-11-01');
  await save({action:'edit',month_on:'2027-01-01',campaign_id:cid,range:'tail',data:{...campaign,title:'Updated winter'}});
  const d=await hq(2027);assert.deepEqual(d.records.find(s=>s.month_on==='2026-11-01'),before);assert.equal(d.records.find(s=>s.month_on==='2027-01-01').scope_override.mode,'only');assert.equal(d.records.find(s=>s.month_on==='2027-02-01').campaign.title,'Updated winter');
  await save({action:'edit',month_on:'2027-01-01',campaign_id:cid,range:'month',data:{...campaign,title:'January only'}});assert.equal((await pharmacy('A',2027))[1].display_title,'Updated winter');
 });
 await t.test('cancellation restores each month theme and records the previous campaign in history',async()=>{
  await save({action:'cancel',month_on:'2027-02-01',campaign_id:cid,range:'tail'});
  assert.equal((await pharmacy('A',2027))[1].display_title,'Winter theme');assert.equal((await pharmacy('A',2027))[0].display_title,'January only');
  const d=await hq(2027),event=d.history.find(x=>x.action==='cancel');assert.equal(event.before_data.campaign_id,cid);assert.equal(event.after_data.campaign_id,null);assert.equal(event.after_data.thematic.title,'Winter theme');
 });
 await t.test('current and elapsed months reject all mutations; cancellation warns when fallback is absent',async()=>{
  for(const action of ['theme','create','edit','cancel','scope'])await assert.rejects(preview({action,month_on:'2026-10-01',data:campaign,duration:1,campaign_id:cid}),/μελλοντικούς/);
  const req={action:'create',month_on:'2027-04-01',duration:1,data:campaign},created=await save(req);
  const p=await preview({action:'cancel',month_on:'2027-04-01',campaign_id:created.campaign_id});assert.equal(p.missing_content,3);assert.ok(p.months[0].pharmacies.every(ph=>ph.after==='Προσεχώς'));
 });
 await t.test('stale preview fails after another edit or an installation change; no partial save',async()=>{
  const req={action:'theme',month_on:'2027-05-01',data:{title:'New theme'}},p=await preview(req);
  await save({action:'theme',month_on:'2027-06-01',data:{title:'Other edit'}});await assert.rejects(save(req,p),/προεπισκόπηση άλλαξε/);
  const p2=await preview(req);await db.query("UPDATE scl290_installations SET positions=jsonb_set(positions,'{0,screenFormat}','\"horizontal\"') WHERE pharmacy_id=$1",[phs[0].id]);await assert.rejects(save(req,p2),/προεπισκόπηση άλλαξε/);
  assert.equal((await hq(2027)).records.some(s=>s.month_on==='2027-05-01'),false);
 });
 await t.test('library updates propagate forward; past programme snapshots and old video references stay',async()=>{
  await db.exec("CREATE OR REPLACE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE AS $$SELECT date '2027-02-10'$$");
  await db.query("UPDATE scl293_themes SET data=jsonb_set(data,'{title}','\"Updated theme\"') WHERE id='winter'");
  const d=await hq(2027);assert.equal(d.records.find(s=>s.month_on==='2027-01-01').thematic.title,'Winter theme');assert.equal(d.records.find(s=>s.month_on==='2027-02-01').thematic.title,'Updated theme');
  await db.exec("INSERT INTO scl293_media_events(theme_id,orientation) VALUES('winter','vertical')");assert.ok((await hq(2027)).records.find(s=>s.month_on==='2027-02-01').thematic.media_revision.vertical);
 });
 await t.test('HQ checks, pharmacy token checks and private helper/table permissions are enforced',async()=>{
  await assert.rejects(db.query("SELECT scl300_pp_hq('wrong',2027)"),/Unauthorized/);await assert.rejects(db.query("SELECT scl300_pp_pharmacy('wrong',2027)"),/Invalid token/);
  await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT * FROM scl_private.pp_months'),/permission denied/);await db.exec('RESET ROLE');
  assert.equal((await db.query("SELECT has_function_privilege('anon','hq_delete_pharmaplus_campaign(text,integer,integer)','EXECUTE') allowed")).rows[0].allowed,false);
  assert.equal((await db.query("SELECT has_function_privilege('anon','scl_private.pp_preview(jsonb)','EXECUTE') allowed")).rows[0].allowed,false);
 });
 await db.close();
});
