/* Draft operations shared by pharmacy forms and regression tests. */
(function(root){
'use strict';
const clone=x=>JSON.parse(JSON.stringify(x));
const norm=x=>String(x??'').trim().toLowerCase();
const list=n=>Array.from({length:12},(_,m)=>n?.[m]??'');
const deals=c=>(c.confirmedDeals?.length?c.confirmedDeals:c.negotiation?.confirmed?[c.negotiation]:[]).filter(d=>d.confirmed);
const months=d=>Array.from({length:Math.max(0,Math.min(12,Number(d.duration)||1))},(_,i)=>(Number(d.startMonth)||0)+i);
const at=(c,m)=>deals(c).find(d=>months(d).includes(m));
const selected=c=>list(c.simpleConfirmed?c.simpleSchedule:c.basicSchedule);
// Same content identity as the database block calculation. The monthly option alone
// does not imply a change; actual values must differ.
function dealKey(d,m){
 const parts=[d.supplier,d.brand,d.subline,d.products];
 if(d.monthlyContentChanges!==false)parts.push(d.schedule?.[m],d.monthlySublines?.[m],d.monthlyProducts?.[m]);
 return parts.filter(v=>v!==null&&v!==undefined).map(String).join('|').toLowerCase();
}
function content(c,m){
 if(!c.initialPlanLocked)return {kind:'pending',key:'pending'};
 const d=at(c,m);if(d)return {kind:'deal',key:'deal|'+String(d.id||d.deal_uid||deals(c).indexOf(d))+'|'+dealKey(d,m),deal:d};
 const base=c.basicSchedule?.[m]||'',theme=c.simpleConfirmed?(c.simpleSchedule?.[m]||base):base,kind=c.simpleConfirmed&&theme!==base?'custom':'basic';
 return {kind,key:kind+'|'+norm(theme),theme};
}
function segments(c,year,active=()=>true){
 const out=[];for(let m=0;m<12;m++){
  const r=active(c,year,m)?content(c,m):{kind:'inactive',key:'inactive'};
  const prev=out.at(-1);if(prev&&prev.key===r.key&&prev.end===m-1)prev.end=m;
  else out.push({...r,start:m,end:m});
 }return out;
}
function operationalRows(c,year,rows,active=()=>true){
 const groups=segments(c,year,active),charges=blocks(c,year,active),out=[];
 for(const g of groups){
  if(['inactive','pending'].includes(g.kind))continue;
  const prev=groups.find(x=>x.end===g.start-1),initial=!prev||['inactive','pending'].includes(prev.kind);
  const why=initial?(g.kind==='basic'?'initial_basic_setup':g.kind+'_start'):g.kind==='deal'?(prev.kind==='deal'?(prev.deal===g.deal?'deal_monthly_change':'deal_start'):'deal_start'):prev.kind==='deal'?(g.kind==='custom'?'deal_end_return_to_custom':'deal_end_return_to_basic'):g.kind==='custom'?(prev.kind==='custom'?'custom_theme_change':'custom_start'):prev.kind==='custom'?'return_to_basic_from_custom':'basic_month_change';
  for(let m=g.start;m<=g.end;m++){
   const old=rows.find(r=>Number(r.month)===m)||{},d=g.deal;
   out.push({...old,year,month:m,position_id:c.id,position_name:c.title,final_type:g.kind,
    final_title:d?[d.brand||d.supplier,d.monthlyContentChanges!==false?d.monthlySublines?.[m]||d.subline:d.subline].filter(Boolean).join(' · ')||'Συμφωνία προμηθευτή':g.theme,
    deal_id:d?.id||d?.deal_uid||null,supplier:d?.supplier||'',brand:d?.brand||'',
    final_detail:d?(d.monthlyContentChanges!==false?d.monthlyProducts?.[m]||d.products:d.products)||'':'',
    content_change_required:m===g.start,content_change_reason:m===g.start?why:g.kind+'_continues',
    billing_change_applies:charges.some(b=>b.start===m),block_start:g.start,block_end:g.end,content_key:g.key});
  }
 }return out;
}
function blocks(c,year,active=()=>true){
 const out=[];let group;
 for(let m=0;m<12;m++){
  const theme=String(c.simpleSchedule?.[m]||'').trim(),base=String(c.basicSchedule?.[m]||'').trim();
  if(!c.initialPlanLocked||!c.simpleConfirmed||!active(c,year,m)||at(c,m)||!theme||theme===base){group=null;continue;}
  const key=norm(theme);
  if(group&&group.end===m-1&&group.key===key)group.end=m;
  else{group={category:'custom',start:m,end:m,key,description:theme};out.push(group);}
 }
 for(const d of deals(c)){
  group=null;
  for(const m of months(d).filter(m=>m>=0&&m<12&&active(c,year,m))){
   const key=dealKey(d,m);
   if(group&&group.end===m-1&&group.key===key)group.end=m;
   else{group={category:'deal',start:m,end:m,key,dealId:d.id,description:[d.supplier,d.brand,d.subline].filter(Boolean).join(' / ')};out.push(group);}
  }
 }
 return out.sort((a,b)=>a.start-b.start||a.category.localeCompare(b.category));
}
function forecast(c,year,rows,active){
 const locked=rows.filter(r=>r.position_id===c.id&&Number(r.year||year)===year&&r.status==='finalized');
 let quota=Math.max(0,...locked.filter(r=>r.category==='custom').map(r=>Number(r.quota_index)||0));
 return blocks(c,year,active).map(b=>{
  const old=locked.find(r=>r.category===b.category&&Number(r.month??r.start_month)===b.start);
  if(old)return {...b,status:'finalized',amount:Number(old.amount)||0,quota:Number(old.quota_index)||0};
  if(b.category==='custom')quota++;
  return {...b,status:'planned',amount:b.category==='deal'?30:quota<=3?0:15,quota:b.category==='custom'?quota:0};
 });
}
function custom(c,schedule){
 const out=clone(c),before=selected(c),changes=[];
 for(let m=0;m<12;m++)if(schedule[m]!==before[m])changes.push({month:m,before:before[m],after:schedule[m]});
 out.simpleSchedule=list(schedule);out.pendingSimpleSchedule=list(schedule);out.simpleConfirmed=true;
 out.simpleMechanism=list(c.simpleMechanism).map(x=>x||'Χωρίς μηχανισμό');
 for(const change of changes)out.simpleMechanism[change.month]='Χωρίς μηχανισμό';
 out.pendingSimpleMechanism=clone(out.simpleMechanism);
 const lost=(c.sponsoredShelves||[]).filter(s=>changes.some(x=>x.month===Number(s.month))&&s.status!=='cancelled');
 out.sponsoredShelves=(c.sponsoredShelves||[]).filter(s=>!lost.includes(s));
 return {card:out,changes,lost};
}
function agreement(c,draft,edit,confirmed){
 const out=clone(c),d=clone(draft),ms=months(d),replaced=[];
 out.confirmedDeals=clone(deals(c));
 d.confirmed=confirmed;d.pending=!confirmed;d.reportMode='none';d.reportEnabled=false;
 delete d.notes;
 if(confirmed){
  out.confirmedDeals=clone(deals(c)).filter(x=>!(edit?.type==='confirmed'&&String(x.id)===String(edit.id)));
  out.confirmedDeals.push(d);
  if(edit?.type==='preagreement')out.preagreements=(out.preagreements||[]).filter(x=>String(x.id)!==String(edit.id));
  const prior=selected(c);out.simpleSchedule=prior;out.simpleMechanism=list(c.simpleMechanism).map(x=>x||'Χωρίς μηχανισμό');
  for(const m of ms){
   const old=at(c,m);replaced.push({month:m,type:old?'Συμφωνία προμηθευτή':prior[m]!==c.basicSchedule?.[m]?'Εξατομίκευση':'Βασικό πρόγραμμα',title:old?[old.supplier,old.brand].filter(Boolean).join(' · '):prior[m]});
   out.simpleSchedule[m]=c.basicSchedule?.[m]||'';out.simpleMechanism[m]='Χωρίς μηχανισμό';
  }
  out.pendingSimpleSchedule=clone(out.simpleSchedule);out.pendingSimpleMechanism=clone(out.simpleMechanism);
  out.sponsoredShelves=(out.sponsoredShelves||[]).filter(s=>!ms.includes(Number(s.month)));
 }else{
  out.preagreements=(out.preagreements||[]).filter(x=>!(edit?.type==='preagreement'&&String(x.id)===String(edit.id)));
  out.preagreements.push(d);
 }
 out.negotiation={...(out.negotiation||{}),confirmed:false,pending:false};
 return {card:out,deal:d,replaced,lost:confirmed?(c.sponsoredShelves||[]).filter(s=>ms.includes(Number(s.month))&&s.status!=='cancelled'):[]};
}
function shelf(c,draft,groupId,remove=false){
 const out=clone(c),ms=months(draft),existing=c.sponsoredShelves||[];
 const belongs=s=>groupId&&(String(s.groupId||s.id)===String(groupId));
 const affected=existing.filter(s=>belongs(s)||ms.includes(Number(s.month)));
 out.sponsoredShelves=existing.filter(s=>!belongs(s)&&!(ms.includes(Number(s.month))&&(!remove||!groupId)));
 if(!remove)for(const m of ms)out.sponsoredShelves.push({id:draft.id+'-'+m,groupId:draft.id,month:m,brand:draft.brand.trim(),products:draft.products.trim(),shelves:draft.shelves,price:Number(draft.price),status:'confirmed',reportMode:'none',startMonth:Number(draft.startMonth),duration:Number(draft.duration)});
 return {card:out,affected};
}
function deadline(year,month){const d=new Date(Date.UTC(year,month,1));d.setUTCDate(d.getUTCDate()-14);return d.toISOString().slice(0,10);}
function files(c,d,year){
 const safe=s=>String(s||'').trim().replace(/\s+/g,'_').replace(/[^\wΑ-Ωα-ωΆ-ώ0-9_-]/g,'');
 const name=safe([d.supplier,d.brand,d.subline].filter(Boolean).join('_'))||'ΣΥΜΦΩΝΙΑ',format=c.screenFormat==='vertical'?'ΚΑΘΕΤΟ':'ΟΡΙΖΟΝΤΙΟ',ms=months(d);
 const groups=[];for(const m of ms){const key=dealKey(d,m),p=groups.at(-1);if(p&&p.key===key&&p.end===m-1)p.end=m;else groups.push({month:m,end:m,key});}
 return groups.map(({month:m,end})=>({month:m,end,file:name+(d.monthlyContentChanges===false?'':'_'+year+'-'+String(m+1).padStart(2,'0'))+'_'+format+'.mp4',deadline:deadline(year,m),subline:d.monthlyContentChanges===false?d.subline:d.monthlySublines?.[m]||d.subline,products:d.monthlyContentChanges===false?d.products:d.monthlyProducts?.[m]||d.products,content:d.schedule?.[m]||''}));
}
const C={clone,list,deals,months,at,selected,dealKey,content,segments,operationalRows,blocks,forecast,custom,agreement,shelf,deadline,files};
root.SCL297Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
