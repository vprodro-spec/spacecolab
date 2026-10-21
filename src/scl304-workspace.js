/* Connected HQ workflow: exact file source, material receipt, readable history. */
(function(root){
'use strict';
const C=SCL304Core,E=esc,$=id=>document.getElementById(id),hq=()=>sclMode()==='hq',y=()=>scl212Year();
const W=root.SCL304={materials:new Map(),loading:new Map(),origin:null,editing:null,busy:false,error:''};
const button=(t,a,attrs='',cls='')=>'<button type="button" class="scl303-btn '+cls+'" data-scl304="'+a+'" '+attrs+'>'+E(t)+'</button>';
const api=async(n,args={})=>{const r=await sb.rpc(n,{p_hq_key:SCL_ROUTING.hqKey,...args});if(r.error)throw Error(r.error.message);return r.data;};
const date=d=>d?new Date(d).toLocaleString('el-GR',{timeZone:'Europe/Athens',dateStyle:'short',...(d.includes('T')?{timeStyle:'short'}:{})}):'—';
const period=(a,b,year)=>MONTHS[a]+(a!==b?'–'+MONTHS[b]:'')+' '+year;
W.periodLabel=()=>{const ms=SCL303.common.months;return (ms===null?'Όλοι οι μήνες':ms.length?ms.map(m=>MONTHS[m]).join(', '):'Καμία επιλογή μήνα')+' '+y();};
W.scopeOverview=function(full){
 const context=SCL303.common,all=full.all.filter(t=>C.matches(t,context,false)),open=all.filter(t=>!t.complete),selected=all.filter(t=>t.year===y()&&(['initial','reset'].includes(t.kind)||C.matches(t,context))),pharmacies=full.pharmacies.filter(r=>C.matches(r,context,false));
 return {...full,all:selected,open:selected.filter(t=>!t.complete),changes:selected.filter(t=>t.row),monthTasks:selected,overdue:open.filter(t=>t.overdue),pharmacies,completed:pharmacies.filter(p=>p.installed&&!p.pending.length).length,pending:pharmacies.filter(p=>p.pending.length).length,installation:pharmacies.filter(p=>!p.installed).length};
};
W.load=async function(year=y(),force=false){
 if(!hq())return;if(W.loading.has(year))return W.loading.get(year);if(W.materials.has(year)&&!force)return W.materials.get(year);
 const request=api('scl304_materials',{p_year:year}).then(d=>{if(!d||!Array.isArray(d.items))throw Error('Δεν φορτώθηκαν τα στοιχεία υλικού. Πατήστε Ανανέωση.');W.materials.set(year,d.items);W.error='';return d.items;}).catch(e=>{W.error=e.message;throw e;}).finally(()=>W.loading.delete(year));W.loading.set(year,request);return request;
};
function expected(row){const card=SCL302Core.snapshots(SCL290.hq||{}).get(row.pharmacy_id+'|'+row.year)?.state_json?.cards?.find(c=>c.id===row.position_id),deal=card&&SCL297Core.at(card,Number(row.month));return deal?SCL297Core.files({...card,screenFormat:row.position_orientation},deal,row.year).find(f=>row.month>=f.month&&row.month<=f.end):null;}
const oldRows=SCL303.rows;SCL303.rows=function(){return oldRows().map(r=>{const material=C.material(W.materials.get(Number(r.year)),r);return {...r,expected_file:r.final_type==='deal'?expected(r)?.file||r.file:'',materialRecord:material,file:r.final_type==='deal'?material?.filename||'':r.file};});};
W.fileControl=function(row){
 const r=row.materialRecord?row:SCL303.rows().find(r=>r.id===row.id)||row,file=r.file!==undefined?r.file:SCL303Core.filename(r,SCL293.data);
 const source=C.source(r,SCL300.data,SCL293.data),attrs='data-id="'+E(r.id||SCL292Core.taskKey(r))+'"';
 return (file?'<div class="scl303-copy"><code>'+E(file)+'</code>'+button('Αντιγραφή ονόματος αρχείου','copy','data-copy="'+E(file)+'"')+'</div>':'')+(source?button(file?(source.kind==='agreement'?'Στοιχεία υλικού':'Επεξεργασία αρχείου'):'Δεν έχει καταχωριστεί · Καταχώριση','file',attrs,file?'':'scl304-missing'):!file?'<small>Η θεματική δεν αντιστοιχεί σε καταχώριση βιβλιοθήκης.</small>':'');
};
W.historyControl=t=>button('Ιστορικό','task-history','data-id="'+E(t.id)+'"','scl304-history-link');
function row(id){return SCL303.rows().find(r=>r.id===id)||SCL302.model?.all.find(t=>t.id===id)?.row;}
function remember(){W.origin={tab:SCL212.tab,scroll:root.scrollY||0};}
function modal(title,body,foot=''){let d=$('scl304Dialog');if(!d){d=document.createElement('div');d.id='scl304Dialog';d.className='scl300-overlay';document.body.append(d);}d.innerHTML='<section role="dialog" aria-modal="true" aria-label="'+E(title)+'"><header class="scl300-dialog-head"><h2>'+E(title)+'</h2>'+button('Κλείσιμο','close')+'</header><div class="scl300-dialog-body">'+body+'</div>'+(foot?'<footer class="scl300-dialog-foot">'+foot+'</footer>':'')+'<p id="scl304Error" role="alert"></p></section>';d.querySelector('button')?.focus();}
function field(label,input){return '<label class="scl300-field"><span>'+E(label)+'</span>'+input+'</label>';}
async function returnToOrigin(){const origin=W.origin;W.origin=null;W.editing=null;$('scl304Dialog')?.remove();$('scl304Return')?.remove();SCL302.render();SCL303.renderChanges();SCL303.renderBilling();if(origin){scl212SetTab(origin.tab);root.scrollTo?.({top:origin.scroll,behavior:'instant'});}}
W.returnToOrigin=returnToOrigin;
W.openFile=async function(r){
 if(!r)throw Error('Η εργασία άλλαξε. Ανανεώστε τη λίστα.');const source=C.source(r,SCL300.data,SCL293.data);if(!source)throw Error('Δεν βρέθηκε η καταχώριση περιεχομένου.');remember();$('scl302Dialog')?.remove();
 if(source.kind==='agreement'){await W.load(Number(r.year));return W.openMaterial(r);}
 if(source.kind==='theme'){
  await SCL293.load();const theme=SCL293.data.themes.find(t=>t.id===source.id);if(!theme)throw Error('Η θεματική δεν είναι διαθέσιμη στη βιβλιοθήκη.');
  scl212SetTab('library');SCL293.section='themes';await SCL293.edit(theme.id);W.editing={kind:'library',id:theme.id};
  const input=$('scl293Editor')?.querySelector('[name="file_'+r.position_orientation+'"]');input?.closest('label')?.classList.add('scl304-target');input?.scrollIntoView?.({block:'center'});input?.focus();
  $('scl293Editor')?.insertAdjacentHTML('afterbegin','<div id="scl304Return" class="scl304-context"><p>'+E(r.pharmacy_name||'')+' · '+E(r.position_name||SCL303Core.position(r.position_id))+' · Προσανατολισμός: '+E(SCL303Core.format(r.position_orientation))+'</p>'+button('Επιστροφή χωρίς αποθήκευση','return')+'</div>');return;
 }
 scl212SetTab('pharmaplus');
 if(source.kind==='pp-month'){W.origin=null;SCL300.showMonth(source.date);return;}
 const kind=source.kind==='campaign'?'campaign':'thematic',slot=SCL300Core.slot(SCL300.data,source.date),data=slot[kind],fmt=r.position_orientation;
 const affected=SCL300.data.records.filter(s=>s.month_on.slice(0,7)>=SCL292Core.today().slice(0,7)&&(kind!=='campaign'||s.campaign_id===slot.campaign_id)&&JSON.stringify(s[kind])===JSON.stringify(data));
 W.editing={kind:'pp',source,row:r,slot,property:kind,revision:SCL300.data.revision};
 modal((kind==='campaign'?'Καμπάνια':'Θεματική')+' Pharmaplus · '+data.title,'<p>'+E(SCL300Core.label(source.date))+' · Προσανατολισμός: '+E(SCL303Core.format(fmt))+'</p><p>Καταχώριση ή διόρθωση ονόματος του ίδιου αρχείου. Η αλλαγή ενημερώνει τις ακόλουθες καταχωρίσεις:</p><p>'+affected.map(s=>E(SCL300Core.label(s.month_on))).join(', ')+'</p><form id="scl304FileForm">'+field('Ακριβές όνομα αρχείου στο Product Me','<input name="filename" required maxlength="255" value="'+E(data.files?.[fmt]||'')+'" placeholder="ΟΝΟΜΑ_'+(fmt==='vertical'?'PORTRAIT':'LANDSCAPE')+'.mp4">')+'<p>Για αντικατάσταση με διαφορετικό υλικό χρησιμοποιήστε την επεξεργασία της καμπάνιας/θεματικής.</p><button class="scl303-btn primary" type="submit">Αποθήκευση και επιστροφή</button></form>');
};
W.openMaterial=function(r){
 const item=C.material(W.materials.get(Number(r.year)),r);if(!item)throw Error('Δεν βρέθηκε η τρέχουσα συμφωνία. Ανανεώστε τη λίστα.');
 const requested=expected(r),past=String(item.year)+'-'+String(item.end_month+1).padStart(2,'0')<SCL292Core.today().slice(0,7);
 W.editing={kind:'material',row:r,item};
 modal('Υλικό Συμφωνίας προμηθευτή','<h3>'+E(r.pharmacy_name||item.pharmacy_name)+' · '+E(SCL303Core.position(r.position_id))+'</h3><p>'+E(item.description)+'</p><p>'+E(period(item.start_month,item.end_month,item.year))+' · Προσανατολισμός: '+E(SCL303Core.format(item.orientation))+'</p><div class="scl304-context"><p><strong>Ζητούμενο όνομα αρχείου</strong></p><code>'+E(requested?.file||'Δεν έχει οριστεί')+'</code>'+(requested?'<p>Ή στατική εικόνα: <code>'+E(SCL305Core.variants(requested.file).image)+'</code> / <code>'+E(SCL305Core.variants(requested.file).jpeg)+'</code></p>':'')+'<p>Η οθόνη λειτουργεί χωρίς ήχο.</p><p>Παράδοση έως '+E(date(item.deadline))+' στο emitropoulou@pharmaplus.gr</p>'+button('Αντιγραφή οδηγιών παράδοσης','instructions')+'</div><form id="scl304MaterialForm">'+field('Ακριβές όνομα αρχείου στο Product Me','<input name="filename" maxlength="255" value="'+E(item.filename||'')+'" placeholder="'+E(requested?.file||'')+'" '+(past?'readonly':'')+'>')+(!past&&requested?button('Χρήση ζητούμενου ονόματος','use-requested'):'')+field('Κατάσταση υλικού','<select name="status" '+(past?'disabled':'')+'>'+Object.entries(C.status).map(([v,t])=>'<option value="'+v+'" '+(v===item.status?'selected':'')+'>'+t+'</option>').join('')+'</select>')+'<p>Η παραλαβή και η ετοιμασία υλικού καταγράφονται εδώ. Η υλοποίηση στη συσκευή δηλώνεται από το «Έγινε η αλλαγή στο Product Me».</p>'+(past?'<p>Ιστορικό · μόνο προβολή</p>':'<button type="submit" class="scl303-btn primary">Αποθήκευση υλικού</button>')+'</form>'+W.historyControl({...r,id:r.id||SCL292Core.taskKey(r)}));
};
function instructions(r,item){const request=expected(r);return ['Οδηγίες παράδοσης υλικού Συμφωνίας προμηθευτή','Φαρμακείο: '+(r.pharmacy_name||item.pharmacy_name),'Θέση: '+SCL303Core.position(r.position_id),'Κωδικός συσκευής: '+(r.player_code||'—'),'Περίοδος: '+period(item.start_month,item.end_month,item.year),'Προσανατολισμός: '+SCL303Core.format(item.orientation),'Βίντεο MP4: '+(request?.file||'—'),'Στατική εικόνα JPEG: '+(request?SCL305Core.variants(request.file).image+' ή '+SCL305Core.variants(request.file).jpeg:'—'),'Προδιαγραφές: '+(item.orientation==='vertical'?'1080 × 1920 pixels (9:16)':'1920 × 1080 pixels (16:9)')+'. Η οθόνη δεν υποστηρίζει ήχο. Το βίντεο πρέπει να παραδοθεί χωρίς ηχητικό κανάλι.','Αποστολή στο emitropoulou@pharmaplus.gr έως '+date(item.deadline)+'.','Στο email παράδοσης αναφέρετε το φαρμακείο, τον κωδικό συσκευής, την περίοδο και το ακριβές όνομα του αρχείου.'].join('\n\n');}
async function materialList(){await W.load();const items=W.materials.get(y()).filter(i=>C.matches(i,SCL303.common,false)&&(SCL303.common.months===null||SCL303.common.months.some(m=>m>=i.start_month&&m<=i.end_month)));
 modal('Υλικά Συμφωνιών προμηθευτή · '+y(),items.length?items.map((i,index)=>'<article class="scl304-history-item"><h3>'+E(i.pharmacy_name)+' · '+E(SCL303Core.position(i.position_id))+'</h3><p>'+E(period(i.start_month,i.end_month,i.year))+' · '+E(C.status[i.status])+'</p><p>'+E(i.description)+'</p>'+button('Στοιχεία υλικού','material-item','data-index="'+index+'"')+'</article>').join(''):'<p>Δεν υπάρχουν συμφωνίες για τα επιλεγμένα φαρμακεία και την περίοδο.</p>');W.list=items;
}
async function taskHistory(id){const t=SCL302.model?.all.find(t=>t.id===id),r=row(id);if(!r||!t)throw Error('Το ιστορικό ανοίγει από τη σχετική εργασία αλλαγής.');
 const data=await api('scl304_task_history',{p_change_key:id,p_pharmacy_id:r.pharmacy_id,p_year:Number(r.year),p_position_id:r.position_id});
 const events=[...(data.completion||[]).map(h=>({date:h.created_at,title:h.done?'Έγινε η αλλαγή στο Product Me':'Επιστροφή στις εκκρεμείς',detail:(h.previous_done?'Έγινε η αλλαγή':'Εκκρεμούσε')+' → '+(h.done?'Έγινε η αλλαγή':'Εκκρεμεί αλλαγή')})),...(data.materials||[]).map(h=>({date:h.created_at,title:'Ενημέρωση υλικού Συμφωνίας προμηθευτή',detail:(C.status[h.before_data?.status]||'Χωρίς καταχώριση')+' → '+C.status[h.after_data.status]+' · '+(h.before_data?.filename||'Χωρίς αρχείο')+' → '+(h.after_data.filename||'Χωρίς αρχείο')}))].sort((a,b)=>b.date.localeCompare(a.date));
 modal('Ιστορικό · '+t.registry.name+' · '+t.position,'<p>'+E(r.month_label||period(r.month,r.month,r.year))+'</p>'+(events.length?events.map(e=>'<article class="scl304-history-item"><small>'+E(date(e.date))+'</small><h3>'+E(e.title)+'</h3><p>'+E(e.detail)+'</p></article>').join(''):'<p>Δεν έχουν καταγραφεί ολοκληρώσεις ή ενημερώσεις υλικού για αυτή τη θέση.</p>'));
}
function historyList(){const hs=(SCL292.data?.history||[]).filter(h=>!hq()||SCL303.common.pharmacies===null||SCL303.common.pharmacies.includes(h.pharmacy_id));modal('Ιστορικό προγράμματος · '+(hq()?y():state.programYear),hs.length?hs.map(h=>'<article class="scl304-history-item"><small>'+E(date(h.created_at))+'</small><h3>'+E(h.pharmacy_name||'Πρόγραμμα φαρμακείου')+'</h3><p>Αποθηκευμένη έκδοση '+E(h.revision)+'</p>'+button('Τι άλλαξε','programme-history','data-id="'+E(h.id)+'"')+'</article>').join(''):'<p>Δεν υπάρχουν προηγούμενες αποθηκεύσεις για το επιλεγμένο έτος.</p>');}
async function programmeHistory(id){const res=await sb.rpc('scl304_program_history',{p_id:id,p_hq_key:hq()?SCL_ROUTING.hqKey:null,p_token:hq()?null:SCL_ROUTING.pharmacyToken});if(res.error)throw Error(res.error.message);const d=res.data;
 const content=(c,m)=>{if(c.type==='hq')return 'Pharmaplus';const r=SCL297Core.content(c,m),shelves=(c.sponsoredShelves||[]).filter(s=>Number(s.month)===m).map(s=>'Χορηγία ραφιών · '+(s.brand||'')+' · '+Number(s.price||0).toLocaleString('el-GR')+'€').join('; ');const main=r.kind==='pending'?'Εκκρεμεί αρχικό πρόγραμμα':r.deal?'Συμφωνία προμηθευτή · '+[r.deal.supplier,r.deal.brand,r.deal.subline,r.deal.products,r.deal.monthlyContentChanges!==false?r.deal.schedule?.[m]:'',Number(r.deal.soldMonthlyPrice||0).toLocaleString('el-GR')+'€ / μήνα'].filter(Boolean).join(' · '):(SCL303Core.kinds[r.kind]||'')+' · '+(SCL293Core.title(SCL293.data,r.theme)||r.theme||'—');return [main,shelves].filter(Boolean).join(' · ');};
 const diff=C.diff(d.before,d.after,content);modal('Ιστορικό προγράμματος · '+d.year,'<p>'+E(date(d.created_at))+' · Αποθηκευμένη έκδοση '+E(d.revision)+'</p>'+(d.before?.turnover!==d.after?.turnover?'<p>Ετήσιος τζίρος: '+E(Number(d.before?.turnover||0).toLocaleString('el-GR'))+'€ → '+E(Number(d.after?.turnover||0).toLocaleString('el-GR'))+'€</p>':'')+(diff.length?'<div class="scl303-scroll"><table class="scl304-history-table"><thead><tr><th>Θέση / μήνας</th><th>Πριν</th><th>Μετά</th></tr></thead><tbody>'+diff.map(r=>'<tr><td>'+E(r.position)+' · '+MONTHS[r.month]+'</td><td>'+E(r.before)+'</td><td>'+E(r.after)+'</td></tr>').join('')+'</tbody></table></div>':'<p>Δεν άλλαξε το περιεχόμενο ή τα συμφωνημένα ποσά των μηνών.</p>')+'<details><summary>Πρόγραμμα πριν από την αλλαγή</summary>'+(d.before?.cards||[]).filter(c=>c.type!=='hq').map(c=>'<h3>'+E(c.title)+'</h3>'+MONTHS.map((m,i)=>'<p>'+m+' · '+E(content(c,i))+'</p>').join('')).join('')+'</details>');
}
async function action(b){const a=b.dataset.scl304;
 if(a==='file')return W.openFile(row(b.dataset.id));
 if(a==='return'){if(SCL293.editing){if(!confirm('Επιστροφή χωρίς αποθήκευση των αλλαγών;'))return;SCL293.editing=null;SCL293.render();}return returnToOrigin();}
 if(a==='close'){if(W.busy)return;$('scl304Dialog')?.remove();return;}
 if(a==='copy')return navigator.clipboard.writeText(b.dataset.copy||'');
 if(a==='instructions')return navigator.clipboard.writeText(instructions(W.editing.row,W.editing.item));
 if(a==='use-requested'){$('scl304MaterialForm').querySelector('[name="filename"]').value=expected(W.editing.row)?.file||'';return;}
 if(a==='materials')return materialList();
 if(a==='material-item'){const i=W.list[Number(b.dataset.index)],base=SCL303.rows().find(r=>r.pharmacy_id===i.pharmacy_id&&r.position_id===i.position_id&&r.month===i.start_month)||{pharmacy_id:i.pharmacy_id,pharmacy_name:i.pharmacy_name,position_id:i.position_id,position_orientation:i.orientation,year:i.year,month:i.start_month,final_type:'deal'};return W.openMaterial(base);}
 if(a==='task-history')return taskHistory(b.dataset.id);
 if(a==='history')return historyList();
 if(a==='programme-history')return programmeHistory(b.dataset.id);
}
document.addEventListener('click',async e=>{const b=e.target.closest?.('[data-scl304]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();if(W.busy)return;b.disabled=true;try{await action(b);}catch(err){if($('scl304Error'))$('scl304Error').textContent=err.message;else{SCL303.message=err.message;SCL303.renderChangesResult();}}finally{if(b.isConnected)b.disabled=false;}},true);
document.addEventListener('submit',async e=>{if(!['scl304FileForm','scl304MaterialForm'].includes(e.target.id))return;e.preventDefault();if(W.busy)return;const f=e.target,d=W.editing,b=f.querySelector('[type="submit"]');W.busy=true;b.disabled=true;try{
 const filename=f.querySelector('[name="filename"]').value.trim();
 if(d.kind==='material'){const i=d.item;await api('scl304_save_material',{p_pharmacy_id:i.pharmacy_id,p_year:Number(i.year),p_event_key:i.event_key,p_orientation:i.orientation,p_revision:Number(i.revision),p_filename:filename,p_status:f.querySelector('[name="status"]').value});await W.load(Number(i.year),true);}
 else{await api('scl304_pp_file',{p_month_on:d.source.date,p_kind:d.property,p_orientation:d.row.position_orientation,p_filename:filename,p_expected_revision:d.revision});await SCL300.load(true);}
 await returnToOrigin();SCL303.message='Τα στοιχεία υλικού αποθηκεύτηκαν και οι σχετικές εμφανίσεις ενημερώθηκαν.';SCL303.renderChangesResult();
 }catch(err){$('scl304Error').textContent=err.message;}finally{W.busy=false;if(b.isConnected)b.disabled=false;}},true);
const oldLibrarySave=SCL293.save;SCL293.save=async function(){const result=await oldLibrarySave.apply(this,arguments);if(hq()){await SCL300.load(true);SCL302.render();if(W.editing?.kind==='library')await returnToOrigin();}return result;};
W.headerControls=()=>button('Υλικά συμφωνιών','materials')+button('Ιστορικό προγράμματος','history');
const oldOverviewBuild=SCL302Core.build;SCL302Core.build=function(args){const model=oldOverviewBuild(args);for(const t of model.all){if(!t.row||t.row.final_type!=='deal')continue;const m=C.material(W.materials.get(Number(t.year)),t.row);if(m){t.material=!t.complete&&m.status==='awaiting';t.category=t.material?'material':'change';t.due=t.material?m.deadline:null;t.overdue=!t.complete&&(t.date<args.today.slice(0,7)||!!t.due&&t.due<args.today);}}model.overdue=model.open.filter(t=>t.overdue);return model;};
const oldLoad=scl212Load;scl212Load=async function(){const result=await oldLoad.apply(this,arguments);if(hq()){await W.load(y(),true).catch(()=>{});SCL302.render();}return result;};
const oldTab=scl212SetTab;scl212SetTab=function(name){const r=oldTab.apply(this,arguments);if(hq()){SCL303.persist();if(name==='changes')SCL303.renderChanges();if(name==='billing')SCL303.renderBilling();if(name==='overview')SCL302.render();if(name==='stats')SCL303.renderStats();if(name==='pharmacies')SCL290.renderRegistry();}return r;};
document.addEventListener('change',e=>{if(e.target.dataset?.scl303Multi||e.target.id==='scl212Year')SCL303.persist();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!W.busy)$('scl304Dialog')?.remove();});
})(window);
