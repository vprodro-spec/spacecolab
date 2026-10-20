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
   const parts=[d.supplier,d.brand,d.subline,d.products];
   if(d.monthlyContentChanges!==false)parts.push(d.schedule?.[m],d.monthlySublines?.[m],d.monthlyProducts?.[m]);
   const key=parts.filter(v=>v!==null&&v!==undefined).map(String).join('|').toLowerCase();
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
 return (d.monthlyContentChanges===false?[ms[0]]:ms).map(m=>({month:m,end:d.monthlyContentChanges===false?ms.at(-1):m,file:name+(d.monthlyContentChanges===false?'':'_'+year+'-'+String(m+1).padStart(2,'0'))+'_'+format+'.mp4',deadline:deadline(year,m),subline:d.monthlyContentChanges===false?d.subline:d.monthlySublines?.[m]||d.subline,products:d.monthlyContentChanges===false?d.products:d.monthlyProducts?.[m]||d.products,content:d.schedule?.[m]||''}));
}
const C={clone,list,deals,months,at,selected,blocks,forecast,custom,agreement,shelf,deadline,files};
root.SCL297Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
