/* v299 — identical consecutive content is one operational period. */
(function(root){
'use strict';
const C=root.SCL297Core,A=root.SCL292Core;
const B=root.SCL299={};
const labels={initial_basic_setup:'Αρχική τοποθέτηση Βασικού προγράμματος',basic_month_change:'Αλλαγή θεματικής Βασικού προγράμματος',custom_start:'Έναρξη Εξατομίκευσης',custom_theme_change:'Αλλαγή θεματικής Εξατομίκευσης',return_to_basic_from_custom:'Επιστροφή στο Βασικό πρόγραμμα από Εξατομίκευση',deal_start:'Έναρξη οριστικής Συμφωνίας προμηθευτή',deal_monthly_change:'Αλλαγή περιεχομένου Συμφωνίας προμηθευτή',deal_end_return_to_basic:'Λήξη Συμφωνίας · επιστροφή στο Βασικό πρόγραμμα',deal_end_return_to_custom:'Λήξη Συμφωνίας · επιστροφή στην Εξατομίκευση'};
B.reason=value=>labels[value]||value;
function resolveRows(c,year,rows){
 return C.operationalRows(c,year,rows,A.active).map(r=>{
  const d=C.at(c,r.month),file=d?C.files(c,d,year).find(f=>r.month>=f.month&&r.month<=f.end):null;
  return {...r,month_label:MONTHS[r.block_start]+(r.block_end>r.block_start?'–'+MONTHS[r.block_end]:'')+' '+year,
   ...(file?{file_name:file.file,content_filename:file.file}:{})};
 });
}
// Future saves carry the same operational flags that HQ displays.
const oldBuild=scl206BuildPositionMonthsPayload;
scl206BuildPositionMonthsPayload=function(){
 const old=oldBuild.apply(this,arguments),local=state.cards.filter(c=>c.type!=='hq'),ids=new Set(local.map(c=>c.id));
 return old.filter(r=>!ids.has(r.position_id)).concat(local.flatMap(c=>resolveRows(c,Number(state.programYear),old.filter(r=>r.position_id===c.id))));
};
const oldVisible=scl212VisibleChanges;
B.rowsForYear=function(hq,year,old=[]){
 if(!hq)return old;
 const snapshots=(hq.snapshots||[]).filter(s=>Number(s.year)===year),states=(hq.base?.pharmacy_state||[]).filter(s=>Number(s.year)===year);
 const byPharmacy=new Map(states.map(s=>[s.pharmacy_id,s]));snapshots.forEach(s=>byPharmacy.set(s.pharmacy_id,s));
 const result=[],covered=new Set(),all=[];
 for(const [pid,s] of byPharmacy){
  const cfg=(hq.installations||[]).find(x=>x.pharmacy_id===pid),reg=(hq.registry||[]).find(x=>x.pharmacy_id===pid);
  if(reg&&!reg.legacy&&!cfg)continue;
  for(const saved of s.state_json?.cards||[]){
   if(saved.type==='hq')continue;
   covered.add(pid+'|'+saved.id);
   const pos=cfg?.positions?.find(p=>p.id===saved.id),c=pos?{...saved,installationStart:pos.startsOn,stopsOn:pos.stopsOn}:saved;
   const source=(hq.months||[]).filter(r=>r.pharmacy_id===pid&&r.position_id===c.id&&Number(r.year)===year);
   const rs=resolveRows(c,year,source).map(r=>{
    const p=pos?root.SCL290Core.at(pos,year,r.month):c;
    return {...r,pharmacy_id:pid,pharmacy_name:reg?.name||source[0]?.pharmacy_name||'',position_orientation:p.screenFormat||c.screenFormat,player_code:p.playerCode,content_code:p.contentCode};
   });
   all.push(...rs);
   result.push(...rs.filter(r=>r.content_change_required));
  }
 }
 result.push(...old.filter(r=>!covered.has(r.pharmacy_id+'|'+r.position_id)));
 // Keep explicit library media replacements even when the theme remains unchanged.
 const withMedia=root.SCL293Core.mediaRows(root.SCL293?.data,all,result,year,A.today());
 const active=new Set((hq.registry||[]).filter(r=>r.pharmacy_id).map(r=>r.pharmacy_id));
 return withMedia.filter(r=>active.has(r.pharmacy_id));
};
scl212VisibleChanges=function(){return B.rowsForYear(root.SCL290?.hq,scl212Year(),oldVisible.apply(this,arguments)||[]);};
// The legacy monthly enrichment must not reinstall itself after an async reload.
scl212VisibleChanges.__scl285=true;
B.resolveRows=resolveRows;
})(window);
