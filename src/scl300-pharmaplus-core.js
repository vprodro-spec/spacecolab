/* Shared Pharmaplus resolution and cross-year operational periods. */
(function(root){
'use strict';
const C={
 months:['Ιαν','Φεβ','Μαρ','Απρ','Μάι','Ιουν','Ιουλ','Αυγ','Σεπ','Οκτ','Νοε','Δεκ'],
 clone:x=>JSON.parse(JSON.stringify(x)),
 month:(y,m)=>String(y)+'-'+String(m+1).padStart(2,'0')+'-01',
 add(date,n){const [y,m]=date.split('-').map(Number),d=new Date(Date.UTC(y,m-1+n,1));return d.toISOString().slice(0,10);},
 label(date){return date?C.months[Number(date.slice(5,7))-1]+' '+date.slice(0,4):'';},
 period(a,b){return !b||a===b?C.label(a):a.slice(0,4)===b.slice(0,4)?C.months[Number(a.slice(5,7))-1]+'–'+C.label(b):C.label(a)+' – '+C.label(b);},
 editable(date,today){return date.slice(0,7)>today.slice(0,7);},
 slot(data,date){return data?.records?.find(r=>r.month_on===date)||{month_on:date,campaign:{},thematic:{}};},
 position(ph,date){return ph?.active?(ph.positions||[]).find(p=>p.type==='hq'&&(!p.startsOn||p.startsOn.slice(0,7)<=date.slice(0,7))&&(!p.stopsOn||p.stopsOn.slice(0,7)>date.slice(0,7))):null;},
 includes(scope,ph){const hit=(scope?.ids||[]).some(id=>id===ph.id||id===ph.registry_id);return (scope?.mode||'all')==='all'||scope.mode==='only'&&hit||scope.mode==='except'&&!hit;},
 resolve(slot,ph,format){
  const main=slot.campaign_id&&C.includes(slot.scope_override||slot.campaign?.scope,ph),d=(main?slot.campaign:slot.thematic)||{},kind=main?'main':'fallback',file=d.files?.[format]||'';
  if(!d.title)return {kind:'empty',title:'Προσεχώς',key:'empty',file:'',data:{}};
  const identity=main?'campaign:'+slot.campaign_id:'theme:'+(d.theme_id||d.title);
  return {kind,title:d.title,file,data:d,campaign_id:main?slot.campaign_id:null,key:JSON.stringify([identity,d.title,d.theme_id?d.media_revision?.[format]||'':file]),starts_on:main?slot.starts_on:null,ends_on:main?slot.ends_on:null};
 },
 counts(data,slot){const out={main:0,fallback:0,empty:0,total:0};for(const ph of data?.pharmacies||[]){const pos=C.position(ph,slot.month_on);if(!pos)continue;out[C.resolve(slot,ph,pos.screenFormat).kind]++;out.total++;}return out;},
 scopeLabel(scope){return !scope||scope.mode==='all'?'Όλα τα φαρμακεία':scope.mode==='except'?'Όλα εκτός από '+scope.ids.length:scope.ids.length+' επιλεγμένα φαρμακεία';},
 legacy(slot){const sc=slot.scope_override||slot.campaign?.scope||{mode:'all',ids:[]};return {...slot.campaign,id:slot.campaign_id,year:Number(slot.month_on.slice(0,4)),month:Number(slot.month_on.slice(5,7))-1,fallback_title:slot.thematic?.title||'',scope_mode:sc.mode,scope_pharmacy_ids:sc.ids,pharmacy_billable:false};},
 rows(data,year){
  const out=[];
  for(const ph of data?.pharmacies||[]){
   for(let m=0;m<12;m++){
    const date=C.month(year,m),pos=C.position(ph,date);if(!pos)continue;
    const r=C.resolve(C.slot(data,date),ph,pos.screenFormat),prior=C.add(date,-1),prevPos=C.position(ph,prior),prev=prevPos?C.resolve(C.slot(data,prior),ph,prevPos.screenFormat):null;
    if(prev?.key===r.key||!prev&&r.kind==='empty')continue;
    let end=date;for(let i=0;r.kind!=='empty'&&i<36;i++){const next=C.add(end,1),np=C.position(ph,next);if(!np||C.resolve(C.slot(data,next),ph,np.screenFormat).key!==r.key)break;end=next;}
    const reason=!prev?'Αρχική τοποθέτηση Pharmaplus':r.kind==='empty'?'Λήξη περιεχομένου Pharmaplus · Προσεχώς':r.kind==='main'?(prev.kind!=='main'?'Έναρξη Καμπάνιας Pharmaplus':prev.campaign_id!==r.campaign_id?'Αλλαγή Καμπάνιας Pharmaplus':'Αλλαγή περιεχομένου Καμπάνιας Pharmaplus'):prev.kind==='main'?'Λήξη ή εξαίρεση Καμπάνιας · επιστροφή στη Θεματική Pharmaplus':'Αλλαγή Θεματικής Pharmaplus';
    out.push({pharmacy_id:ph.id,pharmacy_name:ph.name,position_id:pos.id||'hq',position_name:'Pharmaplus',position_type:'pharmaplus',position_orientation:pos.screenFormat,player_code:pos.playerCode,content_code:pos.contentCode,year,month:m,month_label:C.period(date,end),block_start:date,block_end:end,final_type:'pharmaplus',final_title:r.title,content_change_required:true,content_change_reason:reason,billing_change_applies:false,billing_reason:'Χωρίς χρέωση Pharmaplus',content_revision:r.key,file_name:r.file,content_filename:r.file,note:(prev?prev.title:'Αρχική τοποθέτηση')+' → '+r.title,pp_kind:r.kind});
   }
  }
  return out;
 }
};root.SCL300Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
