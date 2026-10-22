(function(root){
'use strict';
const C=root.SCL293Core,E=esc,$=id=>document.getElementById(id),hq=()=>sclMode()==='hq';
const L=root.SCL293={data:null,promise:null,error:'',section:'themes',filter:'available',query:'',editing:null,usage:[],initial:null,preview:null};
const statuses={available:'Διαθέσιμη',draft:'Υπό προετοιμασία',withdrawn:'Αποσυρμένη'};
const api=async(name,args)=>{const r=await sb.rpc(name,args);if(r.error)throw Error(r.error.message);return r.data;};
const key=()=>({p_token:hq()?null:SCL_ROUTING.pharmacyToken,p_hq_key:hq()?SCL_ROUTING.hqKey:null});
const note=t=>{let b=$('scl293Notice');if(!b){b=document.createElement('div');b.id='scl293Notice';b.className='scl293-notice';document.body.prepend(b);}b.textContent=t;b.hidden=!t;};
const btn=(label,action,attrs='')=>'<button type="button" data-scl293="'+action+'" '+attrs+'>'+E(label)+'</button>';
const opts=(items,val)=>items.map(([v,t])=>'<option value="'+E(v)+'" '+(v===val?'selected':'')+'>'+E(t)+'</option>').join('');
const field=(label,html)=>'<label class="scl293-field"><span>'+E(label)+'</span>'+html+'</label>';
const lines=s=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const title=k=>C.title(L.data,k);
root.scl293Title=title;
L.load=async function(force=false){
 if(!sb||!SCL_ROUTING?.ready&&!hq()||hq()&&!SCL_ROUTING.hqKey)return null;
 if(L.promise)return L.promise;if(L.data&&!force)return L.data;
 L.promise=api('scl293_library',key()).then(d=>{if(!d||!Array.isArray(d.themes)||!Array.isArray(d.programs))throw Error('Μη έγκυρη βιβλιοθήκη');L.data=d;L.error='';L.attachPP();L.render();return d;}).catch(e=>{L.error=e.message;L.render();throw e;}).finally(()=>L.promise=null);return L.promise;
};
L.attachPP=function(){const input=$('scl231FallbackTitle');if(!input||!L.data)return;let list=$('scl293PPThemes');if(!list){list=document.createElement('datalist');list.id='scl293PPThemes';input.after(list);}list.innerHTML=C.available(L.data).map(t=>'<option value="'+E(t.title)+'"></option>').join('');input.setAttribute('list','scl293PPThemes');};
L.mount=function(){
 const tabs=document.querySelector('.scl212-tabs');if(!tabs||$('scl212Page-library'))return;
 tabs.insertAdjacentHTML('beforeend','<button class="scl212-tab" data-tab="library" data-scl293="open">Βιβλιοθήκη</button>');
 const host=$('scl212Page-pharmacies')?.parentNode;if(host){const p=document.createElement('div');p.id='scl212Page-library';p.className='scl212-page';host.appendChild(p);}
};
L.render=function(){
 if(!hq())return;L.mount();const page=$('scl212Page-library');if(!page)return;
 if(!L.data){page.innerHTML='<h3>Βιβλιοθήκη</h3><p>'+E(L.error||'Φόρτωση βιβλιοθήκης…')+'</p>'+btn('Ανανέωση','reload');return;}
 if(L.editing)return;
 const items=L.data[L.section].filter(t=>t.status===L.filter&&t.title.toLocaleLowerCase('el').includes(L.query.toLocaleLowerCase('el')));
 page.innerHTML='<div class="scl293-heading"><h3>Βιβλιοθήκη</h3>'+btn('Ανανέωση','reload')+'</div><div class="scl293-toolbar">'+btn('Θεματικές','section','data-value="themes" aria-pressed="'+(L.section==='themes')+'"')+btn('Έτοιμα προγράμματα','section','data-value="programs" aria-pressed="'+(L.section==='programs')+'"')+'</div><div class="scl293-toolbar">'+field('Αναζήτηση τίτλου','<input id="scl293Search" value="'+E(L.query)+'" placeholder="Γράψτε τίτλο…">')+field('Κατάσταση','<select id="scl293Filter">'+opts(Object.entries(statuses).map(([k,v])=>[k,L.section==='programs'?({available:'Διαθέσιμα',draft:'Υπό προετοιμασία',withdrawn:'Αποσυρμένα'}[k]):({available:'Διαθέσιμες',draft:'Υπό προετοιμασία',withdrawn:'Αποσυρμένες'}[k])]),L.filter)+'</select>')+btn(L.section==='themes'?'Νέα θεματική':'Νέο πρόγραμμα','new')+'</div><div class="scl293-list">'+(items.length?items.map(t=>'<article><div><strong>'+E(t.title)+'</strong><small>'+E(L.section==='themes'?t.variants.length>1?t.variants.length+' παραλλαγές πλανογράμματος':'3 τρόποι στησίματος':'12 μήνες')+'</small></div><div class="scl293-actions">'+btn('Επεξεργασία','edit','data-id="'+E(t.id)+'"')+(L.section==='themes'?btn('Πλανόγραμμα','preview','data-theme="'+E(t.id)+'"'):btn('Αντιγραφή','copy','data-id="'+E(t.id)+'"'))+btn(t.status==='available'?'Απόσυρση':'Διάθεση στη βιβλιοθήκη','status','data-id="'+E(t.id)+'" data-value="'+(t.status==='available'?'withdrawn':'available')+'"')+'</div></article>').join(''):'<p>Δεν υπάρχουν καταχωρίσεις.</p>')+'</div>';
};
L.edit=async function(id,copy=false){
 const kind=L.section==='themes'?'theme':'program';let d=C.clone(L.data[L.section].find(x=>x.id===id)||{});
 if(!id||copy){const generated=typeof crypto!=='undefined'&&crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+Math.random().toString(36).slice(2);d={...d,id:kind+'-'+generated,title:copy?d.title+' — αντίγραφο':'',status:'draft',revision:0};if(kind==='theme')Object.assign(d,{key:'',legacySlots:[],files:{vertical:'',horizontal:''},variants:[{id:'variant-1',label:'Στήσιμο 1',setups:Object.fromEntries(C.styles.map(n=>[n,{title:'',topBrand:'',products:[],shelves:[[],[],[],[]]}]))}]});else if(!copy)d.months=Array(12).fill(null);}
 L.editing={kind,data:d};L.usage=[];L.renderEditor();
 if(id&&kind==='theme'){try{const rows=await api('scl293_usage',{p_hq_key:SCL_ROUTING.hqKey,p_theme_id:id});if(L.editing?.data.id===id){L.usage=rows;L.renderUsage();}}catch(e){note(e.message);}}
};
L.renderUsage=function(){const box=$('scl293Usage');if(!box)return;box.innerHTML='<summary>Χρήση σε οριστικοποιημένα προγράμματα ('+L.usage.length+' μήνες / θέσεις)</summary>'+(L.usage.length?L.usage.map(u=>'<p>'+E(u.name)+' · '+E(u.position)+' · '+MONTHS[u.month]+' '+u.year+'</p>').join(''):'<p>Δεν χρησιμοποιείται σε οριστικοποιημένο τοπικό πρόγραμμα.</p>');};
L.renderEditor=function(){
 const {kind,data:d}=L.editing,page=$('scl212Page-library');
 let body=field(kind==='theme'?'Τίτλος θεματικής':'Όνομα προγράμματος','<input name="title" required value="'+E(d.title)+'">');
 if(kind==='theme'){
  body+='<details id="scl293Usage" class="scl293-box"></details><p class="scl293-help">Οι αλλαγές προϊόντων ενημερώνουν τα αντίστοιχα πλανογράμματα στα φαρμακεία. Δεν αλλάζουν το πρόγραμμα και δεν χρεώνονται ως Εξατομίκευση.</p>';
  for(const [vi,v] of d.variants.entries()){
   if(d.variants.length>1)body+='<h4>'+E(v.label)+' · '+E(d.legacySlots.filter(x=>x.variant===v.id).map(x=>(PROGRAM_LABELS[x.program]||x.program)+' / '+MONTHS[x.month]).join(', '))+'</h4>';
   for(const n of C.styles){const setup=v.setups[n],sid=vi+'-'+C.styles.indexOf(n);body+='<details class="scl293-box"><summary>'+E(n)+'</summary><div data-setup="'+sid+'">'+field('Τίτλος στησίματος','<input data-field="title" value="'+E(setup.title||'')+'">')+field('Κύρια μάρκα','<input data-field="topBrand" value="'+E(setup.topBrand||'')+'">')+field('Προϊόντα — μία ονομασία ανά γραμμή','<textarea data-field="products" rows="4">'+E((setup.products||[]).join('\n'))+'</textarea>')+'<div class="scl293-shelves">'+C.shelves(setup,n).map((items,i)=>field('Ράφι '+(i+1)+' — από πάνω','<textarea data-shelf="'+i+'" rows="3">'+E(items.map(x=>x.text).join('\n'))+'</textarea>')).join('')+'</div></div></details>';}
   body+=btn('Προεπισκόπηση πλανογράμματος','preview-editor','data-variant="'+E(v.id)+'"');
  }
  body+='<h4>Ονόματα αρχείων στο Product Me</h4><p class="scl293-help">Καταχωρίστε το ακριβές όνομα του αρχείου. Τα βίντεο παραμένουν στο Product Me.</p><div class="scl293-shelves">'+field('portrait','<input name="file_vertical" value="'+E(d.files?.vertical||'')+'" placeholder="ΑΝΟΣΟΠΟΙΗΤΙΚΟ_PORTRAIT.mp4">')+field('landscape','<input name="file_horizontal" value="'+E(d.files?.horizontal||'')+'" placeholder="ΑΝΟΣΟΠΟΙΗΤΙΚΟ_LANDSCAPE.mp4">')+'</div>'+field('Η αλλαγή αρχείου αφορά','<select name="mediaMode"><option value="correction">Διόρθωση ονομασίας του ίδιου αρχείου</option><option value="replacement">Αντικατάσταση με νέο υλικό</option></select>')+'<div id="scl293ReplaceFormats" hidden><p>Ποιο υλικό αντικαθίσταται;</p><label><input type="checkbox" name="replace_vertical"> portrait</label> <label><input type="checkbox" name="replace_horizontal"> landscape</label></div>';
 }else{
  body+='<p class="scl293-help">Οι αλλαγές θα ισχύουν για νέες επιλογές. Τα ήδη οριστικοποιημένα προγράμματα των φαρμακείων διατηρούνται.</p><div class="scl293-months">'+MONTHS.map((m,i)=>field(m,'<select data-program-month="'+i+'">'+opts([['','Επιλογή θεματικής'],...C.available(L.data).flatMap(t=>t.variants.map(v=>[t.id+'|'+v.id,t.title+(t.variants.length>1?' — '+v.label:'')]))],d.months[i]?d.months[i].theme+'|'+d.months[i].variant:'')+'</select>')).join('')+'</div>';
 }
 page.innerHTML='<div class="scl293-heading"><h3>'+E(d.title||(kind==='theme'?'Νέα θεματική':'Νέο πρόγραμμα'))+'</h3>'+btn('Πίσω στη βιβλιοθήκη','back')+'</div><form id="scl293Editor">'+body+'<div class="scl293-actions scl293-save"><button type="submit">Αποθήκευση'+(d.status==='draft'?' υπό προετοιμασία':'')+'</button>'+(d.status!=='available'?btn('Αποθήκευση και διάθεση','publish'):'')+'</div><p id="scl293FormError" role="alert"></p></form>';L.renderUsage();
};
L.readEditor=function(){
 const f=$('scl293Editor'),d=C.clone(L.editing.data);d.title=f.querySelector('[name="title"]').value.trim();
 if(L.editing.kind==='theme'){
  for(const [vi,v] of d.variants.entries())for(const [si,n] of C.styles.entries()){
   const box=f.querySelector('[data-setup="'+vi+'-'+si+'"]'),s=v.setups[n];for(const prop of ['title','topBrand'])s[prop]=box.querySelector('[data-field="'+prop+'"]').value.trim();s.products=lines(box.querySelector('[data-field="products"]').value);s.shelves=[...box.querySelectorAll('[data-shelf]')].map(x=>lines(x.value));
  }
  d.files={vertical:f.querySelector('[name="file_vertical"]').value.trim(),horizontal:f.querySelector('[name="file_horizontal"]').value.trim()};
  d.replacementFormats=['vertical','horizontal'].filter(k=>f.querySelector('[name="replace_'+k+'"]').checked);
 }else d.months=[...f.querySelectorAll('[data-program-month]')].map(x=>{const [theme,variant]=x.value.split('|');return theme?{theme,variant}:null;});return d;
};
L.save=async function(publish=false){
 const d=L.readEditor(),kind=L.editing.kind;if(!d.title)throw Error('Συμπληρώστε τίτλο.');if(publish)d.status='available';
 const mode=$('scl293Editor').querySelector('[name="mediaMode"]')?.value||'correction';
 if(mode==='replacement'&&!d.replacementFormats.length)throw Error('Επιλέξτε υλικό portrait ή landscape για αντικατάσταση.');
 await api('scl293_save',{p_hq_key:SCL_ROUTING.hqKey,p_kind:kind,p_id:d.id,p_revision:d.revision||0,p_data:d,p_media_mode:mode});L.editing=null;await L.load(true);note('Η βιβλιοθήκη αποθηκεύτηκε.');
};
L.previewTheme=function(theme,variant,format='vertical',setup=C.styles[0]){
 const v=theme.variants.find(x=>x.id===variant)||theme.variants[0],s=v.setups[setup]||{},vertical=format==='vertical';L.preview={theme,variant:v.id,format,setup};
 const body=$('planogramModalBody');document.querySelector('#planogramModal .modal-title').textContent='Πλανόγραμμα — '+theme.title;document.querySelector('#planogramModal .small').textContent='Προεπισκόπηση των τριών τρόπων στησίματος.';
 body.innerHTML='<div class="scl293-toolbar">'+(hq()?['vertical','horizontal'].map(f=>btn(f==='vertical'?'portrait':'landscape','preview-format','data-value="'+f+'" aria-pressed="'+(format===f)+'"')).join(''):'<strong>'+'Προσανατολισμός: '+(vertical?'portrait':'landscape')+'</strong>')+(theme.variants.length>1?field('Παραλλαγή','<select id="scl293PreviewVariant">'+opts(theme.variants.map(v=>[v.id,v.label]),v.id)+'</select>'):'')+'</div><div class="planogram-tabs">'+C.styles.map(n=>'<button type="button" class="pg-tab '+(n===setup?'active':'')+'" data-scl293="preview-setup" data-value="'+E(n)+'">'+E(n)+'</button>').join('')+'</div><div class="planogram-stage"><div class="stand-wrap"><div class="stand-fixture"><div class="screen-device '+(vertical?'vertical':'horizontal')+'"><div class="screen-content '+(vertical?'vertical':'horizontal')+'"><div class="screen-theme-zone"><div class="screen-theme-text">'+E(theme.title)+'</div></div></div></div><div class="shelf-unit '+(vertical?'vertical':'horizontal')+'">'+C.shelves(s,setup).map((items,i)=>'<div class="shelf-row-visual"><div class="shelf-nr">Ράφι '+(i+1)+'</div><div class="shelf-track">'+(items.map(x=>'<div class="product-block '+x.cls+'">'+E(productShortName(x.text))+'</div>').join('')||'<div class="product-block mixed">—</div>')+'</div></div>').join('')+'</div></div></div><div class="planogram-side"><h4>'+E(s.topBrand||s.title||setup)+'</h4><div class="pg-product-grid">'+(s.products||[]).map(p=>'<div class="pg-product-pill">'+E(p)+'</div>').join('')+'</div><p class="scl293-help">Τα ράφια αριθμούνται από πάνω προς τα κάτω.</p></div></div>';openModal('planogramModal');bindEvents();
};
const oldInfo=planogramInfo;planogramInfo=function(card,m){
 if(!L.data)return oldInfo.apply(this,arguments);const row=monthStatus(card,m);if(row.owner==='deal'||card.type==='hq')return null;
 const key=card.initialPlanLocked?(row.owner==='custom'?card.simpleSchedule?.[m]:baseTheme(card,m)):card.pendingInitialSchedule?.[m],found=C.resolve(L.data,card,m,key);if(!found)return null;
 return {program:card.defaultProgram,theme:found.theme.title,owner:row.owner,data:{theme:found.theme.title,setups:found.variant.setups}};
};
planogramShelves=C.shelves;
const oldPreview=renderPlanogramModal;renderPlanogramModal=function(){const args=arguments;return L.load(true).then(()=>oldPreview.apply(this,args)).catch(e=>note(e.message));};
const oldProgramLabel=programLabel;programLabel=function(p){return p==='MANUAL'?'Δικό μου πρόγραμμα':L.data?.programs.find(x=>x.id===p)?.title||oldProgramLabel(p);};
const oldSchedule=schedule;schedule=function(p){return L.data?.programs.some(x=>x.id===p)?C.schedule(L.data,p):oldSchedule(p);};
const oldLock=lockInitialPlan;lockInitialPlan=function(c,type,p,sched){
 if(!L.data){note('Περιμένετε να φορτωθεί η βιβλιοθήκη.');return false;}
 const from=c._scl292Reset?SCL292Core.resetFrom(c._scl292Reset,state.programYear):0,prior=C.clone(c.libraryRefs||[]);
 const oldProgram=c.defaultProgram,oldBasic=C.clone(c.basicSchedule||[]);
 const unavailable=sched.some((k,m)=>m>=from&&SCL292Core.active(c,state.programYear,m)&&C.theme(L.data,k)?.status!=='available');if(unavailable){note('Επιλέξτε διαθέσιμη θεματική για κάθε μήνα λειτουργίας.');return false;}
 const ok=oldLock.apply(this,arguments);if(ok){const prog=L.data.programs.find(x=>x.id===p);c.libraryRefs=sched.map((k,m)=>m<from?prior[m]||C.ref(L.data,oldBasic[m],oldProgram,m):L.initial?.card===c.id&&L.initial.refs[m]?.theme===C.theme(L.data,k)?.id?C.clone(L.initial.refs[m]):prog&&C.theme(L.data,prog.months[m]?.theme)?.key===k?C.clone(prog.months[m]):C.ref(L.data,k,null,m));}return ok;
};
L.initialPicker=function(){
 const d=L.initial,c=state.cards.find(x=>x.id===d.card);if(!c)return;const t=C.theme(L.data,d.refs[d.month]?.theme),from=c._scl292Reset?SCL292Core.resetFrom(c._scl292Reset,state.programYear):0;
 const active=m=>m>=from&&SCL292Core.active(c,state.programYear,m);
 document.querySelector('#programModal .modal-title').textContent='Αρχικό πρόγραμμα — '+c.title;
 document.querySelector('#programModal .small').textContent='Προσανατολισμός: '+(c.screenFormat==='vertical'?'portrait':'landscape')+' · '+state.programYear;
 $('programModalBody').innerHTML='<div class="scl293-toolbar">'+field('Έτοιμο πρόγραμμα / αφετηρία','<select id="scl293InitialProgram">'+opts([['','Επιλογή προγράμματος'],...C.programs(L.data).map(p=>[p.id,p.title])],d.program||'')+'</select>')+btn('Από την αρχή','initial-blank')+'</div><div class="custom-layout"><div class="month-list">'+MONTHS.map((m,i)=>active(i)?'<button type="button" class="month-item '+(d.month===i?'active':'')+'" data-scl293="initial-month" data-value="'+i+'"><strong>'+m+'</strong><div>'+E(C.theme(L.data,d.refs[i]?.theme)?.title||'Επιλογή θεματικής')+'</div></button>':'').join('')+'</div><div class="editor-panel"><h4>'+MONTHS[d.month]+'</h4>'+L.picker('initial',d.query||'',t?.id,c.screenFormat)+'</div></div><div class="scl293-save">'+btn('Οριστικοποίηση προγράμματος','initial-lock')+'</div>';openModal('programModal');bindEvents();
};
L.picker=function(context,q,current,format,disabled=false){return '<input data-scl293-search="'+context+'" value="'+E(q)+'" placeholder="Αναζήτηση θεματικής ή προϊόντος…" aria-label="Αναζήτηση βιβλιοθήκης"><div class="scl293-themes">'+C.available(L.data).filter(t=>(t.title+' '+t.variants.flatMap(v=>C.styles.flatMap(n=>v.setups[n].products)).join(' ')).toLocaleLowerCase('el').includes(q.toLocaleLowerCase('el'))).map(t=>'<article><strong>'+E(t.title)+'</strong><small>'+E([...new Set(t.variants.flatMap(v=>C.styles.flatMap(n=>v.setups[n].products)))].slice(0,4).join(' · ')||'Δεν έχουν οριστεί προϊόντα')+'</small><div class="scl293-actions">'+btn(current===t.id?'Επιλεγμένη':'Επιλογή',context+'-select','data-theme="'+t.id+'" '+(disabled?'disabled':'')+' aria-pressed="'+(current===t.id)+'"')+btn('Πλανόγραμμα','preview','data-theme="'+t.id+'" data-format="'+format+'"')+'</div></article>').join('')+'</div>';};
renderInitialPlanModal=function(id){
 const c=state.cards.find(x=>x.id===id);if(!c?.screenFormat){note('Η οθόνη χρειάζεται ρύθμιση από τα κεντρικά.');return;}if(!Array.from({length:12},(_,m)=>m).some(m=>SCL292Core.active(c,state.programYear,m))){note('Δεν απαιτείται πρόγραμμα: η θέση δεν λειτουργεί στο επιλεγμένο έτος.');return;}
 if(!L.data){L.load().then(()=>renderInitialPlanModal(id)).catch(e=>note(e.message));return;}
 const from=c._scl292Reset?SCL292Core.resetFrom(c._scl292Reset,state.programYear):0;
 const m=Array.from({length:12},(_,i)=>i).find(i=>i>=from&&SCL292Core.active(c,state.programYear,i));if(m===undefined){note('Δεν υπάρχουν μήνες λειτουργίας για προγραμματισμό.');return;}
 const saved=root.SCL290?.context?.state_json?.cards?.find(x=>x.id===id),proposal=c._scl292Reset?c.basicSchedule:(saved?.pendingInitialSchedule||[]);
 L.initial={card:id,month:m,program:'',refs:Array.from({length:12},(_,i)=>proposal[i]?C.clone(c.libraryRefs?.[i]||C.ref(L.data,proposal[i],c.defaultProgram,i)):null),query:''};if(root.SCL295)root.SCL295.initialBaseline=null;L.initialPicker();
};
const oldCustom=renderCustomModal;renderCustomModal=function(id){
 const result=oldCustom.apply(this,arguments),c=state.cards.find(x=>x.id===id),panel=$('customModalBody')?.querySelector('.editor-panel');if(!c||!panel)return result;
 if(!L.data){panel.innerHTML='<p>Φόρτωση βιβλιοθήκης…</p>';L.load().then(()=>renderCustomModal(id)).catch(e=>note(e.message));return;}
 document.querySelector('#customModal .small').textContent='Οι αλλαγές αποθηκεύονται μόνο με επιβεβαίωση. Οι μήνες με Συμφωνία προμηθευτή παραμένουν κλειδωμένοι.';
 $('customModalBody').querySelectorAll('.mini-badge').forEach(x=>{if(x.textContent==='Locked')x.textContent='Κλειδωμένος';});const reset=$('customModalBody').querySelector('[data-reset-custom]');if(reset)reset.textContent='Επαναφορά επιλογών';
 const m=state.customEditorMonth||0,locked=isCustomReadOnlyMonth(c,m),current=c.pendingSimpleSchedule?.[m]||c.simpleSchedule?.[m]||baseTheme(c,m);
 const reason=root.SCL295?.customReason?.(c,m)||'Ο μήνας δεν επιδέχεται Εξατομίκευση.';
 document.querySelector('#customModal .modal-title').textContent='Εξατομίκευση — '+c.title+' · '+state.programYear;
 panel.innerHTML='<h4>'+MONTHS[m]+' — Εξατομίκευση</h4><p>Βασικό πρόγραμμα: '+E(title(baseTheme(c,m)))+'<br>Τρέχουσα επιλογή: '+E(title(c.simpleConfirmed?c.simpleSchedule?.[m]:baseTheme(c,m)))+'</p>'+(locked?'<p class="scl296-access-note">'+E(reason)+'</p>':'')+L.picker('custom',L.customQuery||'',C.theme(L.data,current)?.id,c.screenFormat,locked);
 if(root.SCL295?.customReason){const list=$('customModalBody').querySelector('.month-list');list.innerHTML=MONTHS.map((month,i)=>{if(!SCL292Core.active(c,state.programYear,i))return '';const why=root.SCL295.customReason(c,i);return '<button type="button" class="month-item '+(i===m?'active ':'')+(why?'locked':'')+'" data-custom-month="'+i+'" data-card-id="'+E(id)+'"><strong>'+month+' '+state.programYear+'</strong><div>'+E(title(c.pendingSimpleSchedule?.[i]||baseTheme(c,i)))+'</div><small>'+E(why||'Διαθέσιμος για Εξατομίκευση')+'</small></button>';}).join('');const confirm=$('customModalBody').querySelector('[data-confirm-custom]');if(confirm)confirm.disabled=!MONTHS.some((_,i)=>!root.SCL295.customReason(c,i));bindEvents();}
 L.customCard=id;return result;
};
root.scl293FileHtml=function(r){const fmt=r.position_orientation==='vertical'?'vertical':'horizontal',file=C.filename(L.data,r.final_title,fmt);return file?'<div class="scl293-file">'+E(file)+'</div>':'';};
const oldChanges=scl212VisibleChanges;scl212VisibleChanges=function(){const rows=oldChanges.apply(this,arguments);return C.mediaRows(L.data,SCL212.months||[],rows,scl212Year(),SCL292Core.today());};
const oldHQLoad=scl212Load;scl212Load=async function(){const result=await oldHQLoad.apply(this,arguments);if(hq())await L.load(true).catch(e=>note(e.message));return result;};
const oldHQRender=scl212Render;scl212Render=function(){const result=oldHQRender.apply(this,arguments);if(hq()){L.mount();if(SCL212.tab==='library')L.render();}return result;};
async function action(b){
 const a=b.dataset.scl293,id=b.dataset.id;
 if(a==='open'){scl212SetTab('library');await L.load();L.render();}
 else if(a==='reload'){L.editing=null;await L.load(true);}
 else if(a==='section'){L.section=b.dataset.value;L.query='';L.render();}
 else if(a==='new')await L.edit();else if(a==='edit')await L.edit(id);else if(a==='copy')await L.edit(id,true);
 else if(a==='back'){if(confirm('Έξοδος χωρίς αποθήκευση των αλλαγών;')){L.editing=null;L.render();}}
 else if(a==='publish')await L.save(true);
 else if(a==='status'){const d=C.clone(L.data[L.section].find(x=>x.id===id));if(!confirm((b.dataset.value==='withdrawn'?'Απόσυρση από νέες επιλογές; Τα υπάρχοντα προγράμματα διατηρούνται.':'Διάθεση στη βιβλιοθήκη;')))return;d.status=b.dataset.value;await api('scl293_save',{p_hq_key:SCL_ROUTING.hqKey,p_kind:L.section==='themes'?'theme':'program',p_id:id,p_revision:d.revision,p_data:d,p_media_mode:'correction'});await L.load(true);}
 else if(a==='preview'){const t=C.theme(L.data,b.dataset.theme);L.previewTheme(t,t.variants[0].id,b.dataset.format||'vertical');}
 else if(a==='preview-editor'){const t=L.readEditor();L.previewTheme(t,b.dataset.variant);}
 else if(a==='preview-format'||a==='preview-setup'){const p=L.preview;L.previewTheme(p.theme,p.variant,a==='preview-format'?b.dataset.value:p.format,a==='preview-setup'?b.dataset.value:p.setup);}
 else if(a==='initial-blank'){L.initial.refs=Array(12).fill(null);L.initial.program='';L.initialPicker();}
 else if(a==='initial-month'){L.initial.month=Number(b.dataset.value);L.initialPicker();}
 else if(a==='initial-select'){const t=C.theme(L.data,b.dataset.theme);L.initial.refs[L.initial.month]={theme:t.id,variant:t.variants[0].id};L.initial.program='';L.initialPicker();}
 else if(a==='initial-lock'){if(root.SCL295?.confirmInitial)return root.SCL295.confirmInitial();const d=L.initial,c=state.cards.find(x=>x.id===d.card),sched=d.refs.map(r=>C.theme(L.data,r?.theme)?.key||'');if(lockInitialPlan(c,d.program?'network':'manual',d.program||'MANUAL',sched)){closeModal('programModal');L.initial=null;refresh();}}
 else if(a==='custom-select'){const c=state.cards.find(x=>x.id===L.customCard),m=state.customEditorMonth||0;if(isCustomReadOnlyMonth(c,m))return;c.pendingSimpleSchedule[m]=C.theme(L.data,b.dataset.theme).key;renderCustomModal(c.id);}
}
document.addEventListener('click',async e=>{const b=e.target.closest?.('[data-scl293]');if(!b||['actions-select','pp-select'].includes(b.dataset.scl293))return;e.preventDefault();e.stopImmediatePropagation();if(b.disabled)return;const restore=b.dataset.scl293.endsWith('-select')?root.SCL306?.rememberPicker(b):null;b.disabled=true;try{await action(b);}catch(err){if($('scl293FormError'))$('scl293FormError').textContent=err.message;else note(err.message);}finally{b.disabled=false;restore?.();}},true);
document.addEventListener('submit',async e=>{if(e.target.id!=='scl293Editor')return;e.preventDefault();e.stopImmediatePropagation();const b=e.target.querySelector('[type="submit"]');b.disabled=true;try{await L.save();}catch(err){$('scl293FormError').textContent=err.message;}finally{b.disabled=false;}},true);
document.addEventListener('change',e=>{
 if(e.target.id==='scl293Filter'){L.filter=e.target.value;L.render();}
 if(e.target.name==='mediaMode')$('scl293ReplaceFormats').hidden=e.target.value!=='replacement';
 if(e.target.id==='scl293PreviewVariant'){const p=L.preview;L.previewTheme(p.theme,e.target.value,p.format,p.setup);}
 if(e.target.id==='scl293InitialProgram'){const p=L.data.programs.find(x=>x.id===e.target.value);if(p){L.initial.refs=C.clone(p.months);L.initial.program=p.id;L.initialPicker();}}
});
document.addEventListener('input',e=>{
 const context=e.target.dataset?.scl293Search;if(e.target.id==='scl293Search'){const pos=e.target.selectionStart;L.query=e.target.value;L.render();$('scl293Search')?.focus();$('scl293Search')?.setSelectionRange?.(pos,pos);}
 if(context==='initial'||context==='custom'){const q=e.target.value,pos=e.target.selectionStart;if(context==='initial'){L.initial.query=q;L.initialPicker();}else{L.customQuery=q;renderCustomModal(L.customCard);}const x=document.querySelector('[data-scl293-search="'+context+'"]');x?.focus();x?.setSelectionRange?.(pos,pos);}
});
const style=document.createElement('style');style.textContent=`
#scl212Page-library{max-width:1120px}.scl293-heading,.scl293-toolbar,.scl293-actions{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.scl293-heading{justify-content:space-between}.scl293-toolbar{margin:16px 0;align-items:end}.scl293-field{display:grid;gap:6px;margin:10px 0;min-width:0}.scl293-field span{font-size:13px;font-weight:600}.scl293-field input,.scl293-field textarea,.scl293-field select,[data-scl293-search]{box-sizing:border-box;max-width:100%;width:100%;border:1px solid #cbd5d1;border-radius:7px;padding:9px;font:inherit;background:#fff}.scl293-field textarea{resize:vertical}.scl293-toolbar .scl293-field{flex:1;min-width:180px;margin:0}.scl293-list article,.scl293-themes article{border:1px solid #dce4df;border-radius:10px;padding:16px;background:white}.scl293-list article{display:flex;justify-content:space-between;gap:15px;margin:10px 0}.scl293-list small,.scl293-themes small{display:block;color:#58675e;margin:7px 0;line-height:1.5}.scl293-themes{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px;margin-top:12px;max-height:55vh;overflow:auto}.scl293-box{border:1px solid #dce4df;background:white;border-radius:8px;padding:14px;margin:12px 0}.scl293-box summary{cursor:pointer;font-weight:600}.scl293-shelves,.scl293-months{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.scl293-help{font-size:13px;line-height:1.6;color:#52615b}.scl293-save{border-top:1px solid #ddd;margin-top:24px;padding:18px 0}.scl293-notice{position:relative;padding:10px;background:#e7f4ed;color:#173d2a;z-index:10001}button[data-scl293],#scl293Editor button{font:inherit;cursor:pointer;padding:8px 12px;border:1px solid #bdcec4;background:white;border-radius:7px}button[data-scl293][aria-pressed=true],#scl293Editor button[type=submit]{background:#186547;color:white;border-color:#186547}button[data-scl293]:disabled{opacity:.5;cursor:default}.scl293-file{font-size:12px;overflow-wrap:anywhere;color:#15523c;margin-top:4px}#scl293FormError{color:#9f2020}#programModal .month-item{width:100%;text-align:left;cursor:pointer;font:inherit}#programModal:has(.scl293-themes){z-index:10010}#planogramModal{z-index:10020}@media(max-width:680px){.scl293-list article{display:block}.scl293-shelves,.scl293-months{grid-template-columns:1fr}.scl293-heading{align-items:start}.scl293-themes{grid-template-columns:1fr}.scl293-list .scl293-actions{margin-top:12px}}
`;document.head.appendChild(style);
L.mount();setTimeout(()=>L.load().catch(e=>note(e.message)),1400);
})(window);
