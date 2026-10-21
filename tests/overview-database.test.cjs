const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');const {bootstrap}=require('./fixtures/database-bootstrap.cjs');
test('HQ deadlines validate active local positions, preserve revisions/history, forbid public table access and clear on deactivation',async()=>{
 const db=new PGlite();await db.exec(bootstrap+`CREATE SCHEMA scl_private;CREATE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE AS $$SELECT date '2026-10-21'$$;CREATE TABLE scl292_reset_requests(id uuid,pharmacy_id uuid,year integer,requested_at timestamptz);`);
 await db.exec(fs.readFileSync('supabase/migrations/20261021122311_hq_overview_deadlines.sql','utf8'));
 const pid=(await db.query("INSERT INTO pharmacies(name) VALUES('Fixture') RETURNING id")).rows[0].id;
 await db.query("INSERT INTO scl290_registry(pharmacy_id,name) VALUES($1,'Fixture')",[pid]);
 await db.query('INSERT INTO scl290_installations(pharmacy_id,positions) VALUES($1,$2)',[pid,JSON.stringify([{id:'hq',type:'hq',startsOn:'2026-10-01'},{id:'base-1',type:'base',startsOn:'2026-10-01'}])]);
 const save=(key='test-hq',pos='base-1',date='2026-11-01',rev=0)=>db.query('SELECT scl302_set_initial_deadline($1,$2,2026,$3,$4,$5) d',[key,pid,pos,date,rev]);
 await assert.rejects(save('bad'),/Unauthorized/);await assert.rejects(save('test-hq','hq'),/Δεν απαιτείται/);await assert.rejects(save('test-hq','base-1','2026-10-01'),/μελλοντική/);
 assert.equal((await save()).rows[0].d.revision,1);await assert.rejects(save(),/προθεσμία άλλαξε/);
 assert.equal((await save('test-hq','base-1','2026-11-05',1)).rows[0].d.revision,2);
 assert.equal((await db.query('SELECT count(*)::int n FROM scl_private.initial_deadline_history')).rows[0].n,2);
 await db.query('INSERT INTO scl290_snapshots(pharmacy_id,year,state_json) VALUES($1,2026,$2)',[pid,JSON.stringify({cards:[{id:'base-1',initialPlanLocked:true}]})]);await assert.rejects(save('test-hq','base-1','2026-11-09',2),/οριστικοποιηθεί/);
 await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT * FROM scl_private.initial_deadlines'),/permission denied/);await assert.rejects(db.query("SELECT scl302_overview('bad')"),/Unauthorized/);assert.equal((await db.query("SELECT scl302_overview('test-hq') d")).rows[0].d.deadlines.length,1);await db.exec('RESET ROLE');
 await db.query('DELETE FROM pharmacies WHERE id=$1',[pid]);assert.equal((await db.query('SELECT count(*)::int n FROM scl_private.initial_deadlines')).rows[0].n,0);await db.close();
});
