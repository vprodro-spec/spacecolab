/* One model for HQ overview counts, lists and overdue work. */
(function(root){
'use strict';
const C={
 month:(y,m)=>`${y}-${String(m+1).padStart(2,'0')}`,
 pp:r=>['hq','pharmaplus'].includes(r.position_id)||r.position_type==='pharmaplus'||r.final_type==='pharmaplus',
 snapshots(hq){const map=new Map((hq.base?.pharmacy_state||[]).map(s=>[s.pharmacy_id+'|'+s.year,s]));for(const s of hq.snapshots||[])map.set(s.pharmacy_id+'|'+s.year,s);return map;},
 positions(hq,pid,y,active){return (hq.installations||[]).find(i=>i.pharmacy_id===pid)?.positions.filter(p=>p.type!=='hq'&&Array.from({length:12},(_,m)=>m).some(m=>active(p,y,m)))||[];},
 progress(hq,pid,y,active){
  const positions=C.positions(hq,pid,y,active),s=C.snapshots(hq).get(pid+'|'+y),setup=(hq.setup||[]).find(s=>s.pharmacy_id===pid&&Number(s.year)===y);
  const locked=p=>s?(s.state_json?.cards||[]).some(c=>c.id===p.id&&c.initialPlanLocked===true):(setup?.positions_json||[]).some(c=>c.position_id===p.id&&c.locked===true);
  return {positions,pending:positions.filter(p=>!locked(p)),total:positions.length,done:positions.filter(locked).length};
 },
 build({hq,pp,meta,year,month,today,rows,done,taskKey,active,dealAt,dealFiles,positionTitle}){
  const pharmacies=(hq.registry||[]).filter(r=>r.pharmacy_id),ids=new Set(pharmacies.map(r=>r.pharmacy_id)),snaps=C.snapshots(hq),tasks=new Map();
  const now=today.slice(0,7),selected=C.month(year,month),byPh=new Map(pharmacies.map(r=>[r.pharmacy_id,r]));
  for(const row of rows){
   if(!ids.has(row.pharmacy_id)||row.content_change_required===false)continue;
   const y=Number(row.year),m=Number(row.month);if(!Number.isInteger(y)||m<0||m>11)continue;
   const cfg=(hq.installations||[]).find(i=>i.pharmacy_id===row.pharmacy_id),pos=cfg?.positions.find(p=>p.id===row.position_id);
   if(cfg&&(!pos||!active(pos,y,m)))continue;
   const id=taskKey(row),isPP=C.pp(row),card=snaps.get(row.pharmacy_id+'|'+y)?.state_json?.cards?.find(c=>c.id===row.position_id),deal=!isPP&&card?dealAt(card,m):null;
   const file=deal?dealFiles(card,deal,y).find(f=>m>=f.month&&m<=f.end):null;
   const req=deal?.materialRequests?.find(f=>m>=f.month&&m<=f.end),complete=!!done[id];
   const material=!!deal&&!complete&&!['received','ready'].includes(req?.status);
   const date=C.month(y,m),due=material?(req?.deadline||file?.deadline||null):null;
   tasks.set(id,{id,kind:isPP?'pharmaplus':'local',category:material?'material':'change',year:y,month:m,date,row,registry:byPh.get(row.pharmacy_id),position:positionTitle(pos?.ordinal??row.position_id),complete,material,due,overdue:!complete&&(date<now||!!due&&due<today)});
  }
  const years=new Set([year,...[...snaps.values()].map(s=>Number(s.year)),...(meta.deadlines||[]).map(d=>Number(d.year))]);
  for(const y of years)for(const reg of pharmacies){
   if(y>Math.max(year,Number(today.slice(0,4))))continue;
   for(const pos of C.progress(hq,reg.pharmacy_id,y,active).pending){
    const deadline=(meta.deadlines||[]).find(d=>d.pharmacy_id===reg.pharmacy_id&&Number(d.year)===y&&d.position_id===pos.id);
    const start=Math.max(0,...[Number(pos.startsOn?.slice(0,4))===y?Number(pos.startsOn.slice(5,7))-1:0]);
    const id=['initial',reg.pharmacy_id,y,pos.id].join('|');
    tasks.set(id,{id,kind:'initial',category:'initial',year:y,month:start,date:C.month(y,start),registry:reg,position:positionTitle(pos.ordinal),position_id:pos.id,player_code:pos.playerCode,due:deadline?.due_on||null,deadlineRevision:deadline?.revision||0,complete:false,overdue:!!deadline?.due_on&&deadline.due_on<today});
   }
  }
  for(const q of meta.requests||[]){if(!ids.has(q.pharmacy_id)||!['pending','approved'].includes(q.status))continue;const id='reset|'+q.id;
   tasks.set(id,{id,kind:'reset',category:'reset',year:Number(q.year),month:Number(q.from_month),date:C.month(q.year,q.from_month),registry:byPh.get(q.pharmacy_id),position:positionTitle(q.position_id),position_id:q.position_id,request:q,complete:false,overdue:C.month(q.year,q.from_month)<now});
  }
  const all=[...tasks.values()].sort((a,b)=>(a.due||a.date).localeCompare(b.due||b.date)||a.registry.name.localeCompare(b.registry.name,'el')||a.position.localeCompare(b.position,'el'));
  const open=all.filter(t=>!t.complete),overdue=open.filter(t=>t.overdue),changes=all.filter(t=>['local','pharmaplus'].includes(t.kind)&&t.date===selected);
  const progress=pharmacies.map(reg=>({...reg,...C.progress(hq,reg.pharmacy_id,year,active),installed:(hq.installations||[]).some(i=>i.pharmacy_id===reg.pharmacy_id)}));
  return {all,open,overdue,changes,pharmacies:progress,completed:progress.filter(p=>p.installed&&!p.pending.length).length,pending:progress.filter(p=>p.pending.length).length,installation:progress.filter(p=>!p.installed).length,
   monthTasks:all.filter(t=>t.date===selected||['initial','reset'].includes(t.kind)&&t.year===year),selected,year,month};
 },
 filter(model,kind='month',status='open'){
  let rows=kind==='month'?model.monthTasks:kind==='overdue'?model.overdue:kind==='all'?model.all:['local','pharmaplus'].includes(kind)?model.changes.filter(t=>t.kind===kind):model.all.filter(t=>t.category===kind);
  return rows.filter(t=>status==='all'||(status==='done'?t.complete:!t.complete));
 }
};root.SCL302Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
