/* Shared navigation context and source-aware file links. No financial mutations. */
(function(root){
'use strict';
const C={
 context(value={},month=0){return {months:value.months===null?null:Array.isArray(value.months)?[...new Set(value.months.map(Number).filter(m=>Number.isInteger(m)&&m>=0&&m<12))].sort((a,b)=>a-b):[month],pharmacies:value.pharmacies===null||!Array.isArray(value.pharmacies)?null:[...new Set(value.pharmacies.filter(x=>typeof x==='string'))]};},
 matches(row,context,period=true){return (context.pharmacies===null||context.pharmacies.includes(row.pharmacy_id||row.registry?.pharmacy_id))&&(!period||context.months===null||context.months.includes(Number(row.month)));},
 source(row,pp,library){
  if(!row)return null;
  if(row.final_type==='deal')return {kind:'agreement',row};
  if(row.final_type==='pharmaplus'){
   const date=String(row.year)+'-'+String(Number(row.month)+1).padStart(2,'0')+'-01',slot=pp?.records?.find(s=>s.month_on===date);
   if(['main','campaign'].includes(row.pp_kind))return slot?.campaign_id?{kind:'campaign',date,id:slot.campaign_id,row}:null;
   if(slot?.thematic?.theme_id)return {kind:'theme',id:slot.thematic.theme_id,row};
   if(slot?.thematic?.title)return {kind:'pp-theme',date,row};
   return {kind:'pp-month',date,row};
  }
  const theme=library?.themes?.find(t=>[t.id,t.key,t.title,...(t.aliases||[])].includes(row.final_title));
  return theme?{kind:'theme',id:theme.id,row}:null;
 },
 material(items,row){return items?.find(i=>i.pharmacy_id===row.pharmacy_id&&Number(i.year)===Number(row.year)&&i.position_id===row.position_id&&Number(row.month)>=i.start_month&&Number(row.month)<=i.end_month&&i.orientation===row.position_orientation);},
 status:{awaiting:'Αναμονή υλικού',received:'Υλικό παραλήφθηκε',ready:'Έτοιμο για προβολή'},
 diff(before,after,content){const changes=[];for(const id of new Set([...(before?.cards||[]).map(c=>c.id),...(after?.cards||[]).map(c=>c.id)])){const c=before?.cards?.find(c=>c.id===id),next=after?.cards?.find(c=>c.id===id);for(let m=0;m<12;m++){const a=c?content(c,m):'Θέση εκτός προγράμματος',b=next?content(next,m):'Θέση εκτός προγράμματος';if(a!==b)changes.push({position:c?.title||next?.title||id,month:m,before:a,after:b});}}return changes;}
};root.SCL304Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
