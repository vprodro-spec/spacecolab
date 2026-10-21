/* HQ annual Pharmaplus programme. The legacy editor is replaced, not layered on it. */
(function(root){
'use strict';
const C=root.SCL300Core,E=esc,$=id=>document.getElementById(id),isHQ=()=>sclMode()==='hq';
const P=root.SCL300={data:null,error:'',pending:new Map(),selected:null,draft:null,preview:null,saving:false,last:0};
const year=()=>Number($('scl212Year')?.value||SCL292Core.today().slice(0,4));
const today=()=>P.data?.today||SCL292Core.today();
const api=async(n,a)=>{const r=await sb.rpc(n,a);if(r.error)throw Error(r.error.message);return r.data;};
const button=(t,a,attrs='')=>'<button type="button" class="scl231-btn'+(['preview','save'].includes(a)?' primary':'')+'" data-scl300="'+a+'" '+attrs+'>'+E(t)+'</button>';
const opts=(items,current)=>items.map(([v,t])=>'<option value="'+E(v)+'" '+(String(v)===String(current)?'selected':'')+'>'+E(t)+'</option>').join('');
const field=(t,html)=>'<label class="scl300-field"><span>'+E(t)+'</span>'+html+'</label>';
const input=(name,value='',attrs='')=>'<input name="'+name+'" value="'+E(value)+'" '+attrs+'>';
const area=(name,value='',rows=2)=>'<textarea name="'+name+'" rows="'+rows+'">'+E(value)+'</textarea>';
const notice=t=>{let el=$('scl300Notice');if(!el){el=document.createElement('div');el.id='scl300Notice';el.setAttribute('role','status');$('scl212Page-pharmaplus')?.before(el);}el.textContent=t;};
const key=()=>({p_hq_key:SCL_ROUTING.hqKey});
function safeRenderHQ(){root.__scl270ForceChanges=true;root.__scl270ChangeLastSig='';if(typeof scl212Render==='function')scl212Render();}
P.load=async function(force=false){
 if(!isHQ()||!sb||!SCL_ROUTING.hqKey)return;
 const y=year();if(!force&&P.data?.year===y&&Date.now()-P.last<30000)return P.data;
 if(P.pending.has(y))return P.pending.get(y);
 const promise=api('scl300_pp_hq',{...key(),p_year:y}).then(d=>{
  if(!d||!Array.isArray(d.records)||!Array.isArray(d.pharmacies))throw Error('Δεν φορτώθηκε το ετήσιο πρόγραμμα Pharmaplus.');
  if(year()!==y)return d;P.data=d;P.error='';P.last=Date.now();
  SCL231.campaigns=d.records.filter(r=>Number(r.month_on.slice(0,4))===y).map(r=>{const row=C.legacy(r);row.scope_pharmacy_ids=row.scope_pharmacy_ids.map(id=>d.pharmacies.find(ph=>ph.registry_id===id)?.id||id);return row;});SCL231.year=y;
  const select=$('scl212Year'),ys=new Set([y,Number(today().slice(0,4)),Number(today().slice(0,4))+1,...d.records.map(r=>Number(r.month_on.slice(0,4)))]);
  for(const yy of [...ys].sort())if(select&&!Array.from(select.options).some(o=>o.value===String(yy))){const o=document.createElement('option');o.value=String(yy);o.textContent=yy;select.append(o);}
  P.render();safeRenderHQ();return d;
 }).catch(e=>{if(year()===y){P.error=e.message;P.render();}throw e;}).finally(()=>P.pending.delete(y));
 P.pending.set(y,promise);return promise;
};
P.render=function(){
 if(!isHQ())return;const page=$('scl212Page-pharmaplus');if(!page)return;
 const d=P.data?.year===year()?P.data:null;
 page.innerHTML='<div class="scl231-head"><div><div class="scl212-sec">Pharmaplus</div><h2 class="scl300-title">Ετήσιο πρόγραμμα Pharmaplus · '+year()+'</h2><p class="scl231-sub">Η καμπάνια εφαρμόζεται στα συμμετέχοντα φαρμακεία. Η θεματική παραμένει για όσα δεν συμμετέχουν.</p></div><div class="scl300-actions">'+button('Νέα καμπάνια','new')+button('Ανανέωση','reload')+'</div></div>';
 if(P.error&&d)page.innerHTML+='<p role="alert">'+E(P.error)+'</p>';
 if(!d){page.innerHTML+='<p role="status">'+E(P.error||'Φόρτωση ετήσιου προγράμματος…')+'</p>';return;}
 page.innerHTML+='<div class="scl231-grid scl300-grid">'+C.months.map((label,m)=>{
  const date=C.month(year(),m),s=C.slot(d,date),n=C.counts(d,s),future=C.editable(date,today()),attrs='data-month-on="'+date+'"';
  return '<article class="scl231-month-card scl300-month" aria-label="'+E(C.label(date))+'"><header><h3>'+E(C.label(date))+'</h3>'+(!future?'<span class="scl300-muted">'+(date.slice(0,7)===today().slice(0,7)?'Τρέχων μήνας':'Ιστορικό')+'</span>':'')+'</header><div class="scl300-campaign"><span class="scl300-kind">Καμπάνια Pharmaplus</span><strong>'+E(s.campaign_id?s.campaign.title:'Δεν έχει οριστεί')+'</strong>'+(s.campaign_id?'<small>'+E(s.campaign.supplier||'')+'</small><small>'+E(C.period(s.starts_on,s.ends_on))+'</small><small>'+E(C.scopeLabel(s.scope_override||s.campaign.scope))+(s.scope_override?' · Εξαίρεση μήνα':'')+'</small>':'')+'</div><div class="scl300-theme"><span class="scl300-kind">Θεματική Pharmaplus</span><strong>'+E(s.thematic?.title||'Δεν έχει οριστεί')+'</strong>'+(s.thematic?.theme_id?'<small>Από τη βιβλιοθήκη</small>':'')+'</div><p class="scl300-counts">'+n.main+' καμπάνια · '+n.fallback+' θεματική'+(n.empty?' · '+n.empty+' Προσεχώς':'')+'</p><div class="scl300-actions">'+button(future?'Διαχείριση μήνα':'Προβολή','month',attrs)+'</div></article>';
 }).join('')+'</div><details class="scl300-history"><summary>Ιστορικό αλλαγών Pharmaplus</summary>'+(d.history?.length?d.history.map(h=>'<p>'+E(C.label(h.month_on))+' · '+E({create:'Καταχώριση καμπάνιας',edit:'Επεξεργασία καμπάνιας',cancel:'Ακύρωση καμπάνιας',theme:'Αλλαγή θεματικής',scope:'Εξαίρεση συμμετοχής'}[h.action]||h.action)+' · '+E(h.created_at?.slice(0,16).replace('T',' '))+'</p>').join(''):'<p>Δεν υπάρχουν νέες αλλαγές.</p>')+'</details>';
};
function overlay(title,body,footer=''){
 let box=$('scl300Dialog');if(!box){box=document.createElement('div');box.id='scl300Dialog';box.className='scl300-overlay';document.body.append(box);}
 box.innerHTML='<section role="dialog" aria-modal="true" aria-label="'+E(title)+'"><header class="scl300-dialog-head"><h2>'+E(title)+'</h2>'+button('Κλείσιμο','close')+'</header><div class="scl300-dialog-body">'+body+'</div><footer class="scl300-dialog-foot">'+footer+'</footer><p id="scl300Error" role="alert"></p></section>';
}
function close(){if(P.saving)return;$('scl300Dialog')?.remove();P.draft=null;P.preview=null;}
function showMonth(date){
 P.selected=date;P.draft=null;P.preview=null;const s=C.slot(P.data,date),future=C.editable(date,today()),n=C.counts(P.data,s);
 const attrs='data-month-on="'+date+'"';
 overlay('Pharmaplus · '+C.label(date),'<div class="scl300-two"><section class="scl300-panel"><h3>Καμπάνια Pharmaplus</h3><h4>'+E(s.campaign.title||'Δεν έχει οριστεί')+'</h4>'+(s.campaign_id?'<p>'+E(s.campaign.supplier||'')+'</p><p>'+E(C.period(s.starts_on,s.ends_on))+'</p><p>'+E(C.scopeLabel(s.scope_override||s.campaign.scope))+'</p>'+(s.scope_override?'<p class="scl300-warning">Εξαίρεση συμμετοχής μόνο για '+E(C.label(date))+'.</p>':'')+'<dl>'+[['Παροχή προμηθευτή',s.campaign.company_benefit],['Προϊόντα καμπάνιας',s.campaign.products_text],...[1,2,3,4].map(i=>['Ράφι '+i,s.campaign['shelf_'+i]])].filter(x=>x[1]).map(([k,v])=>'<dt>'+E(k)+'</dt><dd>'+E(v)+'</dd>').join('')+'</dl>':'')+(future?'<div class="scl300-actions">'+button(s.campaign_id?'Επεξεργασία καμπάνιας':'Νέα καμπάνια',s.campaign_id?'edit':'new',attrs)+(s.campaign_id?button('Συμμετοχή αυτού του μήνα','scope',attrs)+button('Ακύρωση καμπάνιας','cancel',attrs):'')+'</div>':'<p class="scl300-muted">Μόνο προβολή. Το ιστορικό διατηρείται.</p>')+'</section><section class="scl300-panel"><h3>Θεματική Pharmaplus</h3><h4>'+E(s.thematic?.title||'Δεν έχει οριστεί')+'</h4><p>Εμφανίζεται όπου δεν εφαρμόζεται καμπάνια.</p>'+(future?button('Επεξεργασία θεματικής','theme',attrs):'')+'</section></div><div class="scl300-panel"><h3>Τι θα δουν τα φαρμακεία</h3><p>'+n.main+' καμπάνια · '+n.fallback+' θεματική · '+n.empty+' Προσεχώς</p>'+P.data.pharmacies.filter(ph=>C.position(ph,date)).map(ph=>{const pos=C.position(ph,date),r=C.resolve(s,ph,pos.screenFormat);return '<p><strong>'+E(ph.name)+'</strong><br><code>'+E(pos.playerCode||'')+'</code> · '+E(r.title)+'</p>';}).join('')+'</div>');
}
function scopeFields(scope,prefix='scope'){
 return field('Συμμετοχή φαρμακείων','<select name="'+prefix+'_mode">'+opts([['all','Όλα τα φαρμακεία'],['only','Μόνο επιλεγμένα φαρμακεία'],['except','Όλα εκτός από τα επιλεγμένα']],scope?.mode||'all')+'</select>')+'<div class="scl300-scope" '+((scope?.mode||'all')==='all'?'hidden':'')+'>'+field('Αναζήτηση φαρμακείου',input('pharmacy_search','','placeholder="Επωνυμία ή κωδικός τιμολόγησης"'))+'<div class="scl300-scope-list">'+P.data.pharmacies.map(ph=>'<label data-scl300-pharmacy="'+E((ph.name+' '+ph.billing_code).toLocaleLowerCase('el'))+'"><input type="checkbox" name="'+prefix+'_ids" value="'+E(ph.registry_id)+'" '+((scope?.ids||[]).some(id=>id===ph.registry_id||id===ph.id)?'checked':'')+'><span>'+E(ph.name)+'<small>'+E(ph.billing_code||'')+(!ph.active?' · Προς ενεργοποίηση':'')+'</small></span></label>').join('')+'</div></div><p class="scl300-help">Η συμμετοχή ισχύει από την έναρξη της θέσης Pharmaplus. Στην επιλογή «Όλα», τα νέα φαρμακεία εντάσσονται αυτόματα.</p>';
}
function fileFields(d){return '<div class="scl300-two">'+field('Αρχείο portrait',input('file_vertical',d.files?.vertical||'','placeholder="ΟΝΟΜΑ_PORTRAIT.mp4"'))+field('Αρχείο landscape',input('file_horizontal',d.files?.horizontal||'','placeholder="ΟΝΟΜΑ_LANDSCAPE.mp4"'))+'</div><p class="scl300-help">Τα ονόματα αντιστοιχούν στα αρχεία του Product Me. Δεν ανεβάζουμε βίντεο εδώ.</p>';}
function rangeField(d){return field('Η αλλαγή αφορά','<select name="range">'+opts([['month','Μόνο αυτόν τον μήνα'],['tail','Αυτόν και τους επόμενους μήνες της καμπάνιας']],d.range||'month')+'</select>');}
function editor(){
 const d=P.draft,s=C.slot(P.data,d.month_on),data=d.data||{},act=d.action,period=act==='create'?C.period(d.month_on,C.add(d.month_on,Number(d.duration)-1)):C.label(d.month_on);
 let body='<form id="scl300Form"><p class="scl300-context">'+E(period)+'</p>';
 if(act==='create'||act==='edit'){
  body+='<section class="scl300-panel"><h3>Καμπάνια Pharmaplus</h3>'+field('Τίτλος καμπάνιας *',input('title',data.title,'required'))+field('Προμηθευτής *',input('supplier',data.supplier,'required'));
  body+=act==='create'?'<div class="scl300-two">'+field('Μήνας έναρξης',input('month_on',d.month_on.slice(0,7),'type="month" min="'+C.add(today().slice(0,7)+'-01',1).slice(0,7)+'" required'))+field('Διάρκεια σε ολόκληρους μήνες','<select name="duration">'+opts(Array.from({length:36},(_,i)=>[i+1,String(i+1)]),d.duration)+'</select>')+'</div><p id="scl300Period">Περίοδος: '+E(period)+'</p>':rangeField(d)+'<p class="scl300-help">Αρχική περίοδος καμπάνιας: '+E(C.period(s.starts_on,s.ends_on))+'. Οι προηγούμενοι μήνες διατηρούνται.</p>';
  body+=field('Παροχή προμηθευτή προς το φαρμακείο',area('company_benefit',data.company_benefit))+field('Προϊόντα καμπάνιας — ονομασίες / κωδικοί',area('products_text',data.products_text,3))+'<div class="scl300-two">'+[1,2,3,4].map(i=>field('Ράφι '+i+' — από πάνω',area('shelf_'+i,data['shelf_'+i]))).join('')+'</div>'+fileFields(data)+'</section><section class="scl300-panel"><h3>Συμμετοχή καμπάνιας</h3>'+scopeFields(data.scope)+(act==='edit'?'<p class="scl300-help">Οι υπάρχουσες εξαιρέσεις ανά μήνα διατηρούνται. Τις αλλάζετε από τη «Συμμετοχή αυτού του μήνα».</p>':'')+'</section>';
 }else if(act==='cancel'){
  body+='<section class="scl300-panel"><h3>Ακύρωση Καμπάνιας Pharmaplus</h3><strong>'+E(s.campaign.title)+'</strong>'+rangeField(d)+'<p>Η Θεματική Pharmaplus κάθε μήνα παραμένει και εμφανίζεται μετά την ακύρωση. Αν λείπει, θα εμφανίζεται «Προσεχώς».</p></section>';
 }else if(act==='scope'){
  body+='<section class="scl300-panel"><h3>Συμμετοχή · '+E(C.label(d.month_on))+'</h3><strong>'+E(s.campaign.title)+'</strong><p>Αυτή η εξαίρεση αφορά μόνο τον συγκεκριμένο μήνα.</p>'+field('Ρύθμιση συμμετοχής','<select name="inherit">'+opts([['true','Ακολουθεί τη συμμετοχή της καμπάνιας'],['false','Εξαίρεση μόνο για αυτόν τον μήνα']],String(d.inherit))+'</select>')+'<div id="scl300Override" '+(d.inherit?'hidden':'')+'>'+scopeFields(d.scope)+'</div></section>';
 }else{
  const themes=root.SCL293Core.available(root.SCL293?.data),oldTheme=root.SCL293Core.theme(root.SCL293?.data,data.theme_id);if(oldTheme&&!themes.includes(oldTheme))themes.push(oldTheme);
  body+='<section class="scl300-panel"><h3>Θεματική Pharmaplus</h3>'+field('Προέλευση','<select name="theme_source">'+opts([['library','Από τη βιβλιοθήκη'],['own','Δική μας θεματική']],d.source||'own')+'</select>')+(d.source==='library'?field('Θεματική βιβλιοθήκης','<select name="theme_id">'+opts([['','Επιλέξτε θεματική'],...themes.map(t=>[t.id,t.title])],data.theme_id||'')+'</select>')+'<p class="scl300-help">Ο τίτλος και τα ονόματα αρχείων ακολουθούν τη βιβλιοθήκη.</p>':field('Τίτλος θεματικής *',input('title',data.title,'required'))+fileFields(data))+'<p class="scl300-help">Η θεματική διατηρείται ακόμη και όταν υπάρχει καμπάνια στον ίδιο μήνα.</p></section>';
 }
 body+='</form>';
 overlay(act==='create'?'Νέα Καμπάνια Pharmaplus':act==='edit'?'Επεξεργασία Καμπάνιας Pharmaplus':act==='cancel'?'Ακύρωση Καμπάνιας Pharmaplus':act==='scope'?'Εξαίρεση συμμετοχής':'Θεματική Pharmaplus',body,button('Έλεγχος πριν την αποθήκευση','preview',''));
}
function read(){
 const f=$('scl300Form'),d=C.clone(P.draft),v=n=>f.querySelector('[name="'+n+'"]')?.value?.trim()||'',files=()=>({vertical:v('file_vertical'),horizontal:v('file_horizontal')}),scope=()=>({mode:v('scope_mode')||'all',ids:[...f.querySelectorAll('[name="scope_ids"]:checked')].map(x=>x.value)});
 if(d.action==='create'||d.action==='edit'){
  d.data={title:v('title'),supplier:v('supplier'),company_benefit:v('company_benefit'),products_text:v('products_text'),...Object.fromEntries([1,2,3,4].map(i=>['shelf_'+i,v('shelf_'+i)])),files:files(),scope:scope()};
  if(d.action==='create'){d.month_on=v('month_on')+'-01';d.duration=Number(v('duration'));}else d.range=v('range');
 }else if(d.action==='cancel')d.range=v('range');
 else if(d.action==='scope'){d.inherit=v('inherit')==='true';d.scope=scope();}
 else{d.source=v('theme_source');d.data=d.source==='library'?{theme_id:v('theme_id')}:{id:d.data?.id||'',title:v('title'),files:files()};}
 return d;
}
async function start(action,date){
 if(!P.data)await P.load(true);date=date||C.month(year(),0);if(!C.editable(date,today()))date=C.add(today().slice(0,7)+'-01',1);
 const slot=C.slot(P.data,date);P.selected=date;P.preview=null;
 if(action==='theme')await root.SCL293.load();
 P.draft={action,month_on:date,range:'month',...(action==='create'?{duration:1,data:{title:'',supplier:'',scope:{mode:'all',ids:[]},files:{}}}:action==='theme'?{source:slot.thematic?.theme_id?'library':slot.thematic?.title?'own':'library',data:C.clone(slot.thematic||{})}:{campaign_id:slot.campaign_id,data:C.clone(slot.campaign||{}),scope:C.clone(slot.scope_override||slot.campaign.scope||{mode:'all',ids:[]}),inherit:!slot.scope_override})};
 editor();
}
function review(){
 const p=P.preview;
 const body='<p>Ελέγξτε την επίδραση πριν αποθηκεύσετε.</p><div class="scl300-summary"><div><strong>'+p.months.length+'</strong><span>μήνες</span></div><div><strong>'+p.affected_pharmacies+'</strong><span>φαρμακεία με αλλαγή</span></div><div><strong>'+p.content_changes+'</strong><span>μήνες / θέσεις με αλλαγή περιεχομένου</span></div></div><p class="scl300-help">Οι συνεχόμενοι μήνες με ίδιο περιεχόμενο παραμένουν μία εργασία υλοποίησης.</p>'+(p.conflicts.length?'<div class="scl300-warning"><h3>Υπάρχουσες καμπάνιες στην περίοδο</h3>'+p.conflicts.map(x=>'<p>'+E(C.label(x.month_on))+' · '+E(x.title)+'</p>').join('')+'<label><input type="checkbox" id="scl300Replace"> Επιβεβαιώνω την αντικατάσταση των παραπάνω καμπανιών στους συγκεκριμένους μήνες.</label></div>':'')+(p.months.some(x=>!x.campaign_after&&!x.thematic)||p.missing_content?'<div class="scl300-warning">Σε μήνες χωρίς εφαρμόσιμη καμπάνια και χωρίς θεματική θα εμφανίζεται «Προσεχώς».</div>':'')+p.months.map(m=>'<section class="scl300-panel"><h3>'+E(C.label(m.month_on))+'</h3><p>Καμπάνια: '+E(m.campaign_before||'—')+' → '+E(m.campaign_after||'—')+'<br>Θεματική: '+E(m.thematic||'Δεν έχει οριστεί')+'</p>'+(m.scope_override?'<p>Ισχύει εξαίρεση συμμετοχής αυτού του μήνα.</p>':'')+'<strong>'+m.affected+' φαρμακεία επηρεάζονται</strong>'+(m.pharmacies.length?'<div class="scl300-impact"><table><thead><tr><th>Φαρμακείο / συσκευή</th><th>Πριν</th><th>Μετά</th></tr></thead><tbody>'+m.pharmacies.map(ph=>'<tr><td>'+E(ph.name)+'<small>'+E(ph.player_code||'')+'</small></td><td>'+E(ph.before)+'</td><td>'+E(ph.after)+'</td></tr>').join('')+'</tbody></table></div>':'<p class="scl300-help">Δεν αλλάζει το εμφανιζόμενο περιεχόμενο στα σημερινά ενεργά φαρμακεία.</p>')+'</section>').join('');
 overlay('Επιβεβαίωση αλλαγών Pharmaplus',body,button('Πίσω στην επεξεργασία','back')+button(P.draft.action==='cancel'?'Επιβεβαίωση ακύρωσης':'Αποθήκευση αλλαγών','save',''+(!p.months.length?'disabled':'')));
}
async function action(b){
 const a=b.dataset.scl300;
 if(a==='close'){close();return;}
 if(a==='reload'){await P.load(true);notice('Το πρόγραμμα ενημερώθηκε.');return;}
 if(a==='month'){showMonth(b.dataset.monthOn);return;}
 if(['new','edit','cancel','scope','theme'].includes(a)){await start(a==='new'?'create':a,b.dataset.monthOn);return;}
 if(a==='back'){P.preview=null;editor();return;}
 if(a==='preview'){
  P.draft=read();const d=P.draft;
  if(['create','edit'].includes(d.action)&&(!d.data.title||!d.data.supplier))throw Error('Συμπληρώστε τίτλο καμπάνιας και προμηθευτή.');
  if(d.action==='theme'&&!(d.source==='library'?d.data.theme_id:d.data.title))throw Error('Επιλέξτε ή συμπληρώστε θεματική.');
  const req=C.clone(d);delete req.source;P.preview=await api('scl300_pp_preview',{...key(),p_request:req});P.request=req;review();return;
 }
 if(a==='save'){
  if(P.saving)return;if(P.preview.conflicts.length&&!$('scl300Replace')?.checked)throw Error('Επιβεβαιώστε την αντικατάσταση των υπαρχουσών καμπανιών.');
  P.saving=true;
  try{await api('scl300_pp_save',{...key(),p_request:P.request,p_fingerprint:P.preview.fingerprint,p_replace:!!$('scl300Replace')?.checked});P.saving=false;close();await P.load(true);notice('Το πρόγραμμα Pharmaplus αποθηκεύτηκε. Οι σχετικές εργασίες ενημερώθηκαν.');}
  finally{P.saving=false;}
 }
}
document.addEventListener('click',async e=>{const b=e.target.closest?.('[data-scl300]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();if(P.saving)return;b.disabled=true;try{await action(b);}catch(err){if($('scl300Error'))$('scl300Error').textContent=err.message;else notice(err.message);}finally{if(b.isConnected)b.disabled=false;}},true);
document.addEventListener('change',e=>{
 if(e.target.closest?.('#scl300Form')){
  if(['scope_mode','inherit'].includes(e.target.name)){const scope=$('scl300Form').querySelector('.scl300-scope');if(scope)scope.hidden=$('scl300Form').querySelector('[name="scope_mode"]').value==='all';if($('scl300Override'))$('scl300Override').hidden=$('scl300Form').querySelector('[name="inherit"]').value==='true';}
  if(e.target.name==='theme_source'){P.draft=read();editor();}
  if(['month_on','duration'].includes(e.target.name)){const d=read();if(/^\d{4}-\d{2}-01$/.test(d.month_on)&&d.duration){$('scl300Period').textContent='Περίοδος: '+C.period(d.month_on,C.add(d.month_on,d.duration-1));$('scl300Form').querySelector('.scl300-context').textContent=C.period(d.month_on,C.add(d.month_on,d.duration-1));}}
 }
 if(e.target.id==='scl212Year'){close();P.error='';P.render();P.load(true).catch(()=>{});}
});
document.addEventListener('input',e=>{if(e.target.name!=='pharmacy_search'||!e.target.closest?.('#scl300Form'))return;const q=e.target.value.toLocaleLowerCase('el');$('scl300Form').querySelectorAll('[data-scl300-pharmacy]').forEach(x=>x.hidden=!x.dataset.scl300Pharmacy.includes(q));});

P.install=function(){
 if(!isHQ()||P.installed)return;P.installed=true;
 // Old observers find none of their editor controls; reads and routing use the new source.
 scl231RenderCards=P.render;scl212RenderPP=P.render;
 scl231LoadCampaigns=()=>P.load(true);
 scl231OpenEditor=m=>showMonth(C.month(year(),Number(m)));
 for(const f of [scl231RenderCards,scl231LoadCampaigns,scl231OpenEditor])Object.assign(f,{__v232:true,__scl242:true,__scl272:true,__scl275:true});
 const oldYear=SCL292.reloadCampaignYear;SCL292.reloadCampaignYear=async function(){close();return oldYear.apply(this,arguments);};
 const oldVisible=scl212VisibleChanges;scl212VisibleChanges=function(){const rows=oldVisible.apply(this,arguments)||[],local=rows.filter(r=>!['hq','pharmaplus'].includes(r.position_id)&&r.position_type!=='pharmaplus'&&r.final_type!=='pharmaplus');return local.concat(P.data?.year===year()?C.rows(P.data,year()):[]);};scl212VisibleChanges.__scl285=true;
 const oldFile=root.scl293FileHtml;root.scl293FileHtml=r=>r.file_name?'<div class="scl293-file">'+E(r.file_name)+'</div>':oldFile(r);
 P.render();setTimeout(()=>P.load().catch(()=>{}),1800);
};
const oldLoad=scl212Load;scl212Load=async function(){P.install();const r=await oldLoad.apply(this,arguments);if(isHQ())await P.load(true);return r;};
P.install();document.addEventListener('DOMContentLoaded',P.install);
P.start=start;P.showMonth=showMonth;P.read=read;P.review=review;
const style=document.createElement('style');style.textContent=`
#scl212Page-pharmaplus .scl300-title{margin:0;font-size:20px}.scl300-grid .scl300-month{cursor:default;background:#fff;padding:14px;border:1px solid #ddd;border-radius:10px;display:flex;flex-direction:column;min-width:0}.scl300-month header{display:flex;justify-content:space-between;gap:6px;align-items:center}.scl300-month h3{margin:0 0 10px;font-size:14px}.scl300-kind{display:block;font-size:10px;font-weight:700;color:#666;margin-bottom:6px}.scl300-campaign,.scl300-theme{padding:11px 9px;border-radius:7px;margin:4px 0;min-height:72px;overflow-wrap:anywhere}.scl300-campaign{background:#f3eff9;border-left:3px solid #7750a8}.scl300-theme{background:#f6f6f6;border-left:3px solid #aaa}.scl300-campaign strong,.scl300-theme strong{display:block;font-size:13px;line-height:1.4}.scl300-month small{display:block;margin-top:5px;font-size:10px;color:#666;line-height:1.4}.scl300-muted,.scl300-help,.scl300-counts{font-size:12px;color:#666;line-height:1.5}.scl300-counts{margin-top:auto;padding-top:10px}.scl300-actions{display:flex;gap:7px;flex-wrap:wrap}.scl300-history{margin-top:18px;padding:14px;border:1px solid #ddd;border-radius:8px}.scl300-history summary{cursor:pointer}.scl300-overlay{position:fixed;inset:0;z-index:10060;background:#14213d88;display:flex;align-items:center;justify-content:center;padding:18px}.scl300-overlay>section{background:white;border-radius:14px;width:100%;max-width:1040px;max-height:92vh;display:flex;flex-direction:column;box-shadow:0 18px 60px #0002}.scl300-dialog-head{padding:18px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e2e2e2;gap:12px}.scl300-dialog-head h2{margin:0;font-size:18px}.scl300-dialog-body{padding:18px;overflow:auto;min-height:0}.scl300-dialog-foot{padding:14px 18px;border-top:1px solid #ddd;display:flex;gap:10px;justify-content:flex-end}.scl300-dialog-foot .primary{background:#1d59d6;color:#fff;border-color:#1d59d6}.scl300-panel{border:1px solid #ddd;border-radius:10px;padding:16px;margin-bottom:16px;min-width:0}.scl300-panel h3{font-size:15px;margin:0 0 14px}.scl300-panel h4{margin:5px 0;font-size:16px}.scl300-panel dt{font-weight:600;margin-top:12px}.scl300-panel dd{margin:4px 0;white-space:pre-wrap}.scl300-field{display:grid;gap:6px;margin:12px 0;font-size:12px;font-weight:600;min-width:0}.scl300-field input,.scl300-field textarea,.scl300-field select{box-sizing:border-box;width:100%;min-width:0;border:1px solid #d2d2d2;border-radius:7px;padding:10px;background:white;font:inherit;font-weight:400;color:#222}.scl300-field textarea{resize:vertical}.scl300-two{display:grid;grid-template-columns:1fr 1fr;gap:16px}.scl300-context{background:#151515;color:white;border-radius:8px;padding:12px;font-weight:600}.scl300-scope-list{max-height:230px;overflow:auto;border:1px solid #ddd;border-radius:8px}.scl300-scope-list label{display:flex;gap:10px;align-items:flex-start;padding:9px;border-bottom:1px solid #eee;cursor:pointer}.scl300-scope-list small{display:block;color:#777;font-size:10px;margin-top:4px}.scl300-overlay [hidden]{display:none!important}.scl300-warning{padding:13px;background:#fff7df;border:1px solid #e4cc81;border-radius:8px;margin:12px 0;font-size:13px;line-height:1.5}.scl300-warning label{display:flex;align-items:flex-start;gap:9px}.scl300-summary{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.scl300-summary>div{border:1px solid #ddd;border-radius:8px;padding:14px}.scl300-summary strong{font-size:24px;display:block}.scl300-summary span{font-size:12px;color:#666}.scl300-impact{overflow:auto}.scl300-impact table{width:100%;border-collapse:collapse;font-size:12px}.scl300-impact th,.scl300-impact td{padding:10px 6px;text-align:left;vertical-align:top;border-bottom:1px solid #ddd}.scl300-impact small{display:block;color:#666;font-size:10px;margin-top:4px;overflow-wrap:anywhere}#scl300Error:empty{display:none}#scl300Error{margin:0;padding:12px 18px;background:#fff0ee;color:#9a2424}#scl300Notice:not(:empty){padding:12px;background:#e7f4ed;margin:10px 0;border-radius:8px}#scl300Dialog button:disabled{opacity:.55;cursor:default}@media(max-width:700px){.scl300-two{grid-template-columns:1fr}.scl300-summary{grid-template-columns:1fr}.scl300-overlay{padding:8px}.scl300-dialog-head h2{font-size:16px}.scl300-dialog-body{padding:12px}.scl300-dialog-foot{flex-wrap:wrap}.scl300-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}}`;
document.head.append(style);
})(window);
