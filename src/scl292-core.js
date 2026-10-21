/* Shared, deterministic presentation helpers. Actual charges come from Supabase. */
(function(root){
  'use strict';
  const Core={
    today(now=new Date()) { return new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Athens',year:'numeric',month:'2-digit',day:'2-digit'}).format(now); },
    year(value,now=new Date()) { const y=Number(value);return Number.isInteger(y)&&y>=2000&&y<=2200?y:Number(Core.today(now).slice(0,4)); },
    cutoff(year,month) { const d=new Date(Date.UTC(year,month-1,15));return d.toISOString().slice(0,10); },
    editable(year,month,now=new Date()) { return Core.today(now)<=Core.cutoff(year,month); },
    active(p,year,month) { const ym=`${year}-${String(month+1).padStart(2,'0')}`;return (!p.startsOn&&!p.installationStart||String(p.startsOn||p.installationStart).slice(0,7)<=ym)&&(!p.stopsOn||String(p.stopsOn).slice(0,7)>ym); },
    fixed(config,year,fullYear=false) {
      if(!config)return [];
      const out=[];let n=0;
      for(let m=0;m<12;m++){
        const ym=`${year}-${String(m+1).padStart(2,'0')}`;
        if(!fullYear&&config.service_from&&config.service_from.slice(0,7)>ym)continue;
        const before=Math.round(n*48500/12);n++;
        out.push({month:m,category:'base',amount:(Math.round(n*48500/12)-before)/100});
        const count=(config.positions||[]).filter(p=>p.type!=='hq'&&(fullYear||Core.active(p,year,m))).length;
        if(count>2)out.push({month:m,category:'extra',amount:(count-2)*8});
      }
      return out;
    },
    // Keep deployed completion identities when generated orientation suffixes change.
    taskFile(r) { const f=r.task_file!==undefined?r.task_file:r.file_name||r.content_filename||'';return r.final_type==='deal'?f.replace(/_PORTRAIT(?=\.mp4$)/i,'_ΚΑΘΕΤΟ').replace(/_LANDSCAPE(?=\.mp4$)/i,'_ΟΡΙΖΟΝΤΙΟ'):f; },
    taskKey(r) { return ['v292',r.pharmacy_id,r.position_id,Core.year(r.year),Number(r.month),r.final_type||'',r.final_title||'',r.deal_id||'',r.content_change_reason||'',r.content_code||r.player_code||'',r.content_revision||'',r.final_detail||'',r.supplier||'',r.brand||'',r.products_text||r.product_codes||'',r.position_orientation||'',Core.taskFile(r)].map(x=>encodeURIComponent(String(x??''))).join('|'); },
    resetFrom(approval,year,now=new Date()) { return Array.from({length:12},(_,m)=>m).find(m=>m>=Number(approval.fromMonth)&&Core.editable(year,m,now))??-1; },
    total(rows) {return Math.round((rows||[]).reduce((s,r)=>s+Number(r.amount||0),0)*100)/100;},
    category: {base:'Πάγιο υπηρεσίας',extra:'Επιπλέον οθόνες',custom:'Εξατομίκευση',deal:'Συμφωνία προμηθευτή',report:'Αναφορά αποτελεσμάτων — ιστορικό'},
    status: {planned:'Προγραμματισμένη',finalized:'Οριστικοποιημένη',cancelled:'Ακυρωμένη'},
    applyReset(card,type,program,schedule,originalLock) {
      const approval=card._scl292Reset;
      if(!approval)return originalLock(card,type,program,schedule);
      const old=JSON.parse(JSON.stringify(card)),from=Number(approval.fromMonth);
      const merged=Array.from({length:12},(_,m)=>m<from?old.basicSchedule?.[m]:schedule[m]);
      if(!originalLock(card,type,program,merged))return false;
      for(const key of ['simpleSchedule','pendingSimpleSchedule','simpleMechanism','pendingSimpleMechanism']){
        for(let m=0;m<from;m++)card[key][m]=old[key]?.[m]??card[key][m];
      }
      card.confirmedDeals=old.confirmedDeals||[];
      card.negotiation=old.negotiation;
      card.preagreements=old.preagreements||[];
      card.simpleConfirmed=old.simpleConfirmed;
      card.sponsoredShelves=(old.sponsoredShelves||[]).filter(s=>Number(s.month)<from||merged[Number(s.month)]===(old.simpleConfirmed?old.simpleSchedule?.[Number(s.month)]:old.basicSchedule?.[Number(s.month)]));
      card._scl292ResetApplied=approval.id;
      delete card._scl292Reset;
      return true;
    }
  };
  root.SCL292Core=Core;
  if(typeof module!=='undefined'&&module.exports)module.exports=Core;
})(typeof window!=='undefined'?window:globalThis);
