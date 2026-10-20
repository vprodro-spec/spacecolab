(function(root){
 'use strict';
 const C=root.SCL292Core,el=id=>document.getElementById(id),escape=esc;
 const R=root.SCL292={data:null,key:'',promise:null,error:'',last:0,done:{},doneSaving:null,filters:{month:'',pharmacy:'',category:'',status:''}};
 const isHQ=()=>typeof sclMode==='function'&&sclMode()==='hq';
 const isPh=()=>typeof sclMode==='function'&&sclMode()==='pharmacy';
 const currentYear=()=>C.year(isHQ()?el('scl212Year')?.value:state.programYear);
 const money=n=>new Intl.NumberFormat('el-GR',{style:'currency',currency:'EUR'}).format(Number(n)||0);
 const label=m=>MONTHS[Number(m)]||'';
 const api=async(name,args)=>{const result=await sb.rpc(name,args);if(result.error)throw Error(result.error.message);return result.data;};
 const notice=t=>{let n=el('scl292Status');if(!n){n=document.createElement('div');n.id='scl292Status';n.className='scl290-notice';document.body.prepend(n);}n.textContent=t;n.hidden=!t;};
 R.invalidate=()=>{R.last=0;};
 R.loadDone=async function(){if(!isHQ()||!SCL_ROUTING?.hqKey)return;const data=await api('scl292_get_done',{p_hq_key:SCL_ROUTING.hqKey});if(R.doneSaving)return;R.done=Object.fromEntries(data.map(x=>[x.change_key,x.done]));SCL212.done={...R.done};if(typeof scl212RenderChanges==='function')scl212RenderChanges();};
 R.saveDone=function(){
  if(R.doneSaving)return R.doneSaving;
  R.doneSaving=Promise.resolve().then(async()=>{try{while(true){const pending=Object.entries(SCL212.done||{}).find(([key,value])=>key.startsWith('v292|')&&!!R.done[key]!==!!value);if(!pending)break;const [key,value]=pending;await api('scl292_set_done',{p_hq_key:SCL_ROUTING.hqKey,p_change_key:key,p_done:!!value});R.done[key]=!!value;}}catch(e){SCL212.done={...R.done};notice('Δεν αποθηκεύτηκε η ολοκλήρωση: '+e.message);if(typeof scl212RenderChanges==='function')scl212RenderChanges();}finally{R.doneSaving=null;}});
  return R.doneSaving;
 };
 R.loadFinance=async function(force=false){
  if(!sb||!SCL_ROUTING?.ready&&!isHQ()||isHQ()&&!SCL_ROUTING?.hqKey)return;
  const y=currentYear(),key=(isHQ()?'hq':SCL_ROUTING.pharmacy?.id||'pharmacy')+':'+y;
  if(R.promise)return R.promise.then(()=>force||R.key!==key?R.loadFinance(force):R.data);
  if(!force&&R.key===key&&R.data&&Date.now()-R.last<30000)return R.data;
  R.promise=api('scl292_finance',{p_year:y,p_token:isPh()?SCL_ROUTING.pharmacyToken:null,p_hq_key:isHQ()?SCL_ROUTING.hqKey:null}).then(data=>{
   R.data=data;R.key=key;R.last=Date.now();R.error='';
   if(currentYear()===y){if(isPh())R.renderEconomics();if(isHQ())R.renderBilling();R.renderRequests();}return data;
  }).catch(e=>{R.error=e.message;notice('Δεν φορτώθηκαν τα οικονομικά: '+e.message);throw e;}).finally(()=>{R.promise=null;});
  return R.promise;
 };
 const ready=()=>R.data&&R.key===(isHQ()?'hq':SCL_ROUTING.pharmacy?.id||'pharmacy')+':'+currentYear();
 const rows=()=>ready()?R.data.rows:[];
 const summary=rs=>({final:C.total(rs.filter(r=>r.status==='finalized')),planned:C.total(rs.filter(r=>r.status==='planned')),total:C.total(rs)});
 const detail=r=>r.description+(r.end_month>r.month?' · '+label(r.month)+'–'+label(r.end_month):'')+(r.category==='custom'&&r.quota_index?' · '+(r.status==='planned'?'Αν παραμείνει: ':'')+(r.quota_index<=3?r.quota_index+'η από τις 3 δωρεάν':'Μετά τις 3 δωρεάν'):'');
 const card=(title,value,note='')=>'<div class="scl292-card"><span>'+escape(title)+'</span><strong>'+money(value)+'</strong><small>'+escape(note)+'</small></div>';
 function table(rs,pharmacy=false){return '<div class="scl292-scroll"><table class="scl212-table"><thead><tr><th>Μήνας / έτος</th>'+(pharmacy?'':'<th>Φαρμακείο / κωδικός</th>')+'<th>Θέση</th><th>Είδος / αιτιολογία</th><th>Κατάσταση</th><th>Ποσό</th></tr></thead><tbody>'+rs.map(r=>'<tr><td>'+label(r.month)+' '+r.year+'</td>'+(pharmacy?'':'<td>'+escape(r.pharmacy_name)+'<br><small>'+escape(r.billing_code||'—')+'</small></td>')+'<td>'+escape(r.position_name||'—')+'</td><td>'+escape(C.category[r.category]||r.category)+'<details><summary>Ανάλυση</summary>'+escape(detail(r))+(r.created_at?'<br>Καταγράφηκε: '+escape(new Date(r.created_at).toLocaleString('el-GR')):'')+'</details></td><td>'+escape(C.status[r.status]||r.status)+'</td><td>'+money(r.amount)+'</td></tr>').join('')+'</tbody></table></div>';}
 R.renderEconomics=function(){
  if(!isPh())return false;
  const grid=el('economicsGrid'),note=el('economicsNote');if(!grid)return true;
  if(!ready()){grid.innerHTML='<p>Φόρτωση οικονομικών…</p>';R.loadFinance().catch(()=>{});return true;}
  const all=rows(),sum=summary(all),local=state.cards.filter(c=>c.type!=='hq');
  const revenueDeals=local.reduce((a,c)=>a+dealRevenue(c),0),revenueShelves=local.reduce((a,c)=>a+sponsoredRevenue(c),0);
  const revenue=revenueDeals+revenueShelves;
  const config=SCL290?.context?.installation||{positions:local.map(c=>({type:c.type})),service_from:null};
  const theoryFixed=C.total(C.fixed(config,currentYear(),true)),theoryRevenue=suggestedPrice()*local.length*12,theoryCost=theoryFixed+local.length*12*30;
  if(note)note.textContent='Συμφωνημένα ποσά για το '+currentYear()+'. Περιλαμβάνονται επιβεβαιωμένες μελλοντικές συμφωνίες. Δεν πιστοποιούν είσπραξη ή εξόφληση.';
  grid.className='';grid.innerHTML='<div class="scl292-grid">'+card('Συμφωνημένα έσοδα',revenue,'Συμφωνίες '+money(revenueDeals)+' · Χορηγίες '+money(revenueShelves))+card('Κόστος διαχείρισης έτους',sum.total,'Οριστικοποιημένο '+money(sum.final)+' · Προγραμματισμένο '+money(sum.planned))+card('Κέρδος από την αξιοποίηση θέσεων',revenue-sum.total)+'</div>'+
   '<details class="scl292-panel"><summary>Ανάλυση κόστους και δωρεάν Εξατομικεύσεων</summary>'+local.map(c=>{const used=all.filter(r=>r.position_id===c.id&&r.category==='custom'&&r.status==='finalized');const consumed=Math.min(3,used.length);return '<p><b>'+escape(c.title)+'</b>: '+consumed+'/3 δωρεάν χρησιμοποιήθηκαν · '+(3-consumed)+' απομένουν · '+used.filter(r=>r.amount>0).length+' χρεώσιμες.</p>';}).join('')+table(all,true)+'</details>'+
   '<details class="scl292-panel"><summary>Εκτίμηση εσόδων — πλήρες έτος</summary><p>'+local.length+' τοπικές οθόνες × 12 μήνες × '+money(suggestedPrice())+' προτεινόμενη τιμή. Υπόθεση μηνιαίας ενεργοποίησης Συμφωνίας. Η Pharmaplus εξαιρείται.</p><div class="scl292-grid">'+card('Εκτιμώμενα έσοδα',theoryRevenue)+card('Εκτιμώμενο κόστος διαχείρισης',theoryCost,'Πάγιο / επιπλέον οθόνες '+money(theoryFixed)+' · Ενεργοποιήσεις '+money(local.length*12*30))+card('Εκτιμώμενο κέρδος',theoryRevenue-theoryCost)+'</div></details>';
  return true;
 };
 function filterRows(){const f=R.filters;return rows().filter(r=>(f.month===''||Number(f.month)===r.month)&&(!f.pharmacy||r.pharmacy_id===f.pharmacy)&&(!f.category||r.category===f.category)&&(!f.status||r.status===f.status));}
 function select(field,title,opts){return '<label>'+title+'<select data-scl292-filter="'+field+'"><option value="">Όλα</option>'+opts.map(([v,t])=>'<option value="'+escape(v)+'" '+(R.filters[field]===String(v)?'selected':'')+'>'+escape(t)+'</option>').join('')+'</select></label>';}
 R.renderBilling=function(){
  if(!isHQ())return false;const page=el('scl212Page-billing');if(!page)return true;
  if(!ready()){page.innerHTML='<p>Φόρτωση χρεώσεων…</p>';R.loadFinance().catch(()=>{});return true;}
  const rs=filterRows(),s=summary(rs),names=new Map(rows().map(r=>[r.pharmacy_id,r.pharmacy_name]));
  page.innerHTML='<h3>Χρεώσεις — '+currentYear()+'</h3><div class="scl292-filters">'+select('month','Μήνας',MONTHS.map((m,i)=>[String(i),m]))+select('pharmacy','Φαρμακείο',[...names])+select('category','Είδος',Object.entries(C.category))+select('status','Κατάσταση',Object.entries(C.status))+'<button type="button" data-scl292-export>Εξαγωγή οριστικοποιημένων</button></div><div class="scl292-grid">'+card('Οριστικοποιημένες χρεώσεις',s.final)+card('Προγραμματισμένες',s.planned,'Χωριστά από το οριστικοποιημένο σύνολο')+'</div>'+table(rs);
  return true;
 };
 R.renderRequests=function(){
  if(!ready())return;
  const host=isHQ()?el('scl212Page-overview'):el('setupStatus');if(!host)return;
  let box=el('scl292Requests');if(!box){box=document.createElement('div');box.id='scl292Requests';box.className='scl292-panel';host.appendChild(box);}
  const reqs=R.data.requests||[];
  box.innerHTML='<b>Αιτήματα επαναφοράς προγράμματος</b>'+(!isHQ()?'<p><button type="button" data-scl292-request>Νέο αίτημα επαναφοράς</button></p>':'')+
   (reqs.length?reqs.map(q=>'<div class="scl292-request"><strong>'+escape(q.pharmacy_name)+' · '+escape(q.position_id)+'</strong><div>'+label(q.from_month)+'–Δεκέμβριος '+q.year+' · '+escape({pending:'Αναμονή HQ',approved:'Εγκρίθηκε — αναμονή νέου προγράμματος',rejected:'Απορρίφθηκε',applied:'Ολοκληρώθηκε'}[q.status])+'</div><p>'+escape(q.reason)+'</p>'+(q.hq_note?'<p>'+escape(q.hq_note)+'</p>':'')+(isHQ()&&q.status==='pending'?'<button type="button" data-scl292-decision="approve" data-id="'+q.id+'">Έγκριση</button> <button type="button" data-scl292-decision="reject" data-id="'+q.id+'">Απόρριψη</button>':'')+(!isHQ()&&q.status==='approved'?'<button type="button" data-scl292-reopen="'+escape(q.position_id)+'">Σύνθεση νέου προγράμματος</button>':'')+'</div>').join(''):'<p>Δεν υπάρχουν αιτήματα.</p>')+
   '<details><summary>Ιστορικό αποθηκεύσεων ('+(R.data.history||[]).length+')</summary>'+(R.data.history||[]).map(h=>'<p>'+escape(new Date(h.created_at).toLocaleString('el-GR'))+' · '+escape(h.pharmacy_name)+' · '+escape(h.reason)+'</p>').join('')+'</details>';
 };
 R.requestReset=async function(){
  const list=state.cards.filter(c=>c.type!=='hq'&&c.initialPlanLocked);if(!list.length){notice('Δεν υπάρχει οριστικοποιημένη τοπική θέση.');return;}
  const selected=list.find(c=>c.id===state.selectedCardId)||list[0];
  const answer=prompt('Θέση για επαναφορά:\n'+list.map((c,i)=>(i+1)+'. '+c.title).join('\n'),String(list.indexOf(selected)+1));if(answer===null)return;
  const c=list[Number(answer)-1];if(!c)throw Error('Επιλέξτε μία από τις διαθέσιμες θέσεις.');
  const reason=prompt('Αιτία επαναφοράς για '+c.title+':');if(reason===null)return;
  await sclSaveNow();await api('scl292_request_reset',{p_token:SCL_ROUTING.pharmacyToken,p_year:currentYear(),p_position:c.id,p_reason:reason});
  notice('Το αίτημα στάλθηκε στα HQ. Το υπάρχον πρόγραμμα συνεχίζει μέχρι την έγκριση και τη νέα οριστικοποίηση.');await R.loadFinance(true);
 };
 root.sclResetCurrentPharmacyYearV190=R.requestReset;
 try{sclResetCurrentPharmacyYearV190=R.requestReset;}catch(e){}
 const oldLock=lockInitialPlan;
 lockInitialPlan=function(c,type,program,sched){
  const from=c._scl292Reset?.fromMonth??0;
  const missing=Array.from({length:12},(_,m)=>m).filter(m=>m>=from&&C.active(c,currentYear(),m)&&!String(sched?.[m]||'').trim());
  if(missing.length){alert('Συμπληρώστε: '+missing.map(label).join(', '));return false;}
  if(c._scl292Reset&&!confirm('Νέο Βασικό πρόγραμμα από '+label(from)+' '+currentYear()+'. Οι προηγούμενοι μήνες, οι Συμφωνίες και οι προηγούμενες χρεώσεις διατηρούνται. Εξατομικεύσεις των επόμενων μηνών αντικαθίστανται και χορηγίες μηνών με αλλαγή θεματικής αφαιρούνται. Συνέχεια;'))return false;
  return C.applyReset(c,type,program,sched,oldLock);
 };
 document.addEventListener('change',e=>{const field=e.target.dataset?.scl292Filter;if(field){R.filters[field]=e.target.value;R.renderBilling();}});
 document.addEventListener('click',async e=>{
  const b=e.target.closest?.('[data-scl292-request],[data-scl292-reopen],[data-scl292-decision],[data-scl292-export],#sclResetPharmacyYearBtn,[data-reset-year-data]');
  if(!b)return;e.preventDefault();e.stopImmediatePropagation();b.disabled=true;
  try{
   if(b.matches('[data-scl292-request],#sclResetPharmacyYearBtn,[data-reset-year-data]'))await R.requestReset();
   else if(b.dataset.scl292Reopen){await loadYear(currentYear());const c=state.cards.find(c=>c.id===b.dataset.scl292Reopen);if(!c?._scl292Reset)throw Error('Η έγκριση δεν είναι πλέον διαθέσιμη.');c.pendingInitialSchedule=clone(c.basicSchedule);state.initialEditorMonth=c._scl292Reset.fromMonth;renderInitialPlanModal(c.id);}
   else if(b.dataset.scl292Decision){const q=R.data.requests.find(q=>q.id===b.dataset.id),approve=b.dataset.scl292Decision==='approve';if(!confirm((approve?'Έγκριση':'Απόρριψη')+' αιτήματος για '+q.pharmacy_name+'; Το πρόγραμμα παραμένει μέχρι νέα οριστικοποίηση.'))return;const note=prompt('Σημείωση HQ (προαιρετικά):','');if(note===null)return;await api('scl292_decide_reset',{p_hq_key:SCL_ROUTING.hqKey,p_request_id:q.id,p_approve:approve,p_note:note});await R.loadFinance(true);}
   else if(b.hasAttribute('data-scl292-export')){const rs=filterRows().filter(r=>r.status==='finalized'),by=new Map();for(const r of rs){const k=r.billing_code||r.pharmacy_id;by.set(k,{code:r.billing_code||'',name:r.pharmacy_name,amount:(by.get(k)?.amount||0)+Number(r.amount)});}const csv=[['Σύνοψη ανά κωδικό τιμολόγησης'],['Κωδικός','Φαρμακείο','Ποσό'],...[...by.values()].map(x=>[x.code,x.name,C.total([x]).toFixed(2)]),[],['Έτος','Μήνας','Φαρμακείο','Κωδικός τιμολόγησης','Θέση','Είδος','Αιτιολογία','Ποσό'],...rs.map(r=>[r.year,r.month+1,r.pharmacy_name,r.billing_code,r.position_name,C.category[r.category],detail(r),Number(r.amount).toFixed(2)])];const a=document.createElement('a'),url=URL.createObjectURL(new Blob([SCL290Core.csv(csv)],{type:'text/csv;charset=utf-8'}));a.href=url;a.download='Pharmaplus_charges_'+currentYear()+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  }catch(err){notice(err.message);}finally{b.disabled=false;}
 },true);
 const oldCustomCost=customCost;customCost=function(c){return ready()&&isPh()?C.total(rows().filter(r=>r.category==='custom'&&r.position_id===c.id&&r.status==='finalized')):oldCustomCost(c);};
 const oldDealCost=dealCost;dealCost=function(c){return ready()&&isPh()?C.total(rows().filter(r=>r.category==='deal'&&r.position_id===c.id)):oldDealCost(c);};
 if(typeof renderNegotiationModal==='function'){const oldNegotiation=renderNegotiationModal;renderNegotiationModal=function(id){const c=state.cards.find(c=>c.id===id);if(c?.negotiation&&!c.negotiation.confirmed){c.negotiation.reportMode='none';c.negotiation.reportEnabled=false;}const result=oldNegotiation.apply(this,arguments);document.querySelectorAll('[data-neg-field="reportMode"]').forEach(e=>e.closest('.field')?.remove());return result;};}
 const oldRefresh=refresh;refresh=function(){const x=oldRefresh.apply(this,arguments);if(isPh()){R.renderRequests();document.querySelectorAll('[data-reset-year-data],#sclResetPharmacyYearBtn').forEach(b=>b.textContent='Αίτημα επαναφοράς');}return x;};
 const oldHQRender=scl212Render;scl212Render=function(){const x=oldHQRender.apply(this,arguments);R.renderRequests();return x;};
 const style=document.createElement('style');style.textContent='.scl292-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:12px 0}.scl292-card{background:white;border:1px solid #d9e3df;border-radius:12px;padding:16px;display:grid;gap:8px}.scl292-card strong{font-size:24px}.scl292-card small{color:#5c6864}.scl292-panel{background:#fff;border:1px solid #dde5e1;border-radius:10px;padding:14px;margin:12px 0}.scl292-panel summary{cursor:pointer;font-weight:600}.scl292-scroll{overflow:auto}.scl292-filters{display:flex;gap:12px;flex-wrap:wrap;align-items:end}.scl292-filters label{display:grid;gap:4px}.scl292-filters select{max-width:240px;padding:8px}.scl292-request{padding:12px 0;border-bottom:1px solid #eee}.scl292-scroll td{vertical-align:top}.scl292-scroll details{font-size:12px;margin-top:5px}';document.head.appendChild(style);
 document.addEventListener('click',e=>{const cb=e.target.closest?.('input[data-task]');if(cb&&cb.dataset.task.startsWith('v292|')&&!cb.checked&&!confirm('Αναίρεση ολοκλήρωσης; Η προηγούμενη ενέργεια θα παραμείνει στο ιστορικό.')){e.preventDefault();e.stopImmediatePropagation();}},true);
 const yearSelect=el('scl212Year');if(yearSelect){const now=C.year(null),ys=new Set([...yearSelect.options].map(x=>Number(x.value)));for(let y=now-1;y<=now+2;y++)ys.add(y);let chosen=now;try{const saved=localStorage.getItem('scl292.hqYear');if(saved)chosen=C.year(saved);}catch(e){}ys.add(chosen);yearSelect.innerHTML=[...ys].filter(y=>y>=2026).sort().map(y=>'<option value="'+y+'" '+(y===chosen?'selected':'')+'>'+y+'</option>').join('');yearSelect.addEventListener('change',()=>{try{localStorage.setItem('scl292.hqYear',yearSelect.value);}catch(e){}});}
 document.querySelectorAll('.scl212-tab[data-tab="billing"]').forEach(b=>b.textContent='Χρεώσεις');
 const oldHQLoad=scl212Load;scl212Load=async function(){const x=await oldHQLoad.apply(this,arguments);if(isHQ()){await Promise.all([R.loadFinance(true),R.loadDone()]);}return x;};
 setTimeout(()=>{R.loadFinance().catch(()=>{});R.loadDone().catch(e=>notice(e.message));},1200);
})(window);
