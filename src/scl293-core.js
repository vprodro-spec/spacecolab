(function(root){
'use strict';
const C={
 styles:['Στήσιμο Μάρκας','Υβριδικό Στήσιμο','Μικτό Στήσιμο'],
 clone:x=>JSON.parse(JSON.stringify(x)),
 theme(lib,key){return lib?.themes?.find(t=>t.id===key||t.key===key||t.title===key||(t.aliases||[]).includes(key))||null;},
 title(lib,key){return C.theme(lib,key)?.title||key||'';},
 available(lib){return (lib?.themes||[]).filter(t=>t.status==='available');},
 programs(lib){return (lib?.programs||[]).filter(p=>p.status==='available'&&p.months.length===12&&p.months.every(r=>C.theme(lib,r?.theme)?.status==='available'));},
 schedule(lib,id){return (lib?.programs?.find(p=>p.id===id)?.months||[]).map(r=>C.theme(lib,r?.theme)?.key||'');},
 ref(lib,key,program,month){const t=C.theme(lib,key);if(!t)return null;return {theme:t.id,variant:t.legacySlots?.find(s=>s.program===program&&s.month===month)?.variant||t.variants[0]?.id};},
 resolve(lib,card,month,key){const t=C.theme(lib,key);if(!t)return null;const ref=card.basicSchedule?.[month]===key&&card.libraryRefs?.[month]?.theme===t.id?card.libraryRefs[month]:C.ref(lib,key,card.basicSchedule?.[month]===key?card.defaultProgram:null,month);return {theme:t,variant:t.variants.find(v=>v.id===ref?.variant)||t.variants[0]};},
 shelves(setup,name){
  if(Array.isArray(setup?.shelves))return Array.from({length:4},(_,i)=>(setup.shelves[i]||[]).map(x=>typeof x==='string'?{text:x,cls:name==='Στήσιμο Μάρκας'?'brand':name==='Υβριδικό Στήσιμο'&&i<2?'hybrid-main':'mixed'}:x));
  const ps=(setup?.products||[]).filter(Boolean),main=setup?.topBrand||setup?.title||ps[0]||'Top brand',out=[[],[],[],[]];
  if(name==='Μικτό Στήσιμο')(ps.length?ps:[setup?.title||'Προτεινόμενος κωδικός']).slice(0,8).forEach((p,i)=>out[Math.floor(i/2)].push({text:p,cls:'mixed'}));
  else if(name==='Υβριδικό Στήσιμο'){out[0].push({text:'Top Brand: '+main,cls:'hybrid-main'});out[1].push({text:main,cls:'hybrid-main'});(ps.length?ps:[setup?.title||'Συμπληρωματικοί κωδικοί']).slice(0,4).forEach((p,i)=>out[2+Math.floor(i/2)].push({text:p,cls:'mixed'}));}
  else for(let i=0;i<4;i++)out[i].push({text:ps[i]||main,cls:'brand'});
  return out;
 },
 filename(lib,key,format){return C.theme(lib,key)?.files?.[format]||'';},
 /* Replacement events create operational tasks only. Filename corrections and shelf edits do not. */
 mediaRows(lib,all,normal,year,today){
  const result=normal.map(r=>({...r})),seen=new Set(result.map(r=>[r.pharmacy_id,r.position_id,r.month].join('|')));
  for(const e of lib?.media_events||[]){
   const groups=new Map(),t=C.theme(lib,e.theme_id);if(!t)continue;
   for(const r of all){
    const date=String(year)+'-'+String(Number(r.month)+1).padStart(2,'0')+'-01';
    if(date.slice(0,7)<String(today).slice(0,7)||date.slice(0,7)<e.created_at.slice(0,7)||r.final_type==='deal'||r.position_orientation!==e.orientation||![t.key,t.title,...(t.aliases||[])].includes(r.final_title))continue;
    const k=[r.pharmacy_id,r.position_id].join('|');if(!groups.has(k)||Number(r.month)<Number(groups.get(k).month))groups.set(k,r);
   }
   for(const r of groups.values()){
    const k=[r.pharmacy_id,r.position_id,r.month].join('|');let row=result.find(x=>[x.pharmacy_id,x.position_id,x.month].join('|')===k);
    if(!row){row={...r,content_change_required:true,billing_change_applies:false,content_change_reason:'Αντικατάσταση υλικού θεματικής'};result.push(row);seen.add(k);}
    row.content_revision='library:'+e.id;
   }
  }
  return result;
 }
};root.SCL293Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
