/* v297 — Explicit drafts and confirmed pharmacy actions. Product Me stays manual. */
(function(root){
'use strict';
const C=root.SCL297Core,A=root.SCL292Core,L=root.SCL293,E=esc,$=id=>document.getElementById(id),ph=()=>sclMode()==='pharmacy';
const F=root.SCL297={draft:null,busy:false,review:null,error:'',serial:0};
const cash=n=>Number(n||0).toLocaleString('el-GR',{minimumFractionDigits:0,maximumFractionDigits:2})+'€';
const year=()=>Number(state.programYear),card=id=>state.cards.find(c=>c.id===id),title=k=>root.scl293Title?.(k)||k||'—';
const month=m=>MONTHS[m]+' '+year(),range=ms=>contiguousLabel(ms)+' '+year();
const uid=()=>Date.now().toString(36)+'-'+(++F.serial);
const button=(label,a,attrs='')=>'<button type="button" class="action '+(/^(review|commit|save-pre)/.test(a)?'blue':'')+'" data-scl297="'+a+'" '+attrs+'>'+E(label)+'</button>';
const section=(n,label,body)=>'<section class="deal-section"><header class="deal-section-head"><span class="deal-step">'+n+'</span><h3 class="deal-section-title">'+E(label)+'</h3></header>'+body+'</section>';
const field=(label,html)=>'<label class="field"><span>'+E(label)+'</span>'+html+'</label>';
const input=(k,v,type='text',extra='')=>'<input data-scl297-field="'+k+'" type="'+type+'" value="'+E(v??'')+'" '+extra+'>';
const select=(k,v,options)=>'<select data-scl297-field="'+k+'">'+options.map(([value,label])=>'<option value="'+E(value)+'" '+(String(value)===String(v)?'selected':'')+'>'+E(label)+'</option>').join('')+'</select>';
const localReason=c=>!c?'Δεν βρέθηκε η θέση.':c.type==='hq'?'Η θέση Pharmaplus ορίζεται αποκλειστικά από τα κεντρικά.':!c.initialPlanLocked?'Οριστικοποίησε πρώτα το αρχικό πρόγραμμα της θέσης.':!(Number(state.turnover)>0)?'Συμπλήρωσε πρώτα τον ετήσιο τζίρο.':'';
const notify=s=>{let n=$('scl295Notice');if(!n){n=document.createElement('p');n.id='scl295Notice';document.body.prepend(n);}n.textContent=s;n.hidden=false;};
function reason(c,m){return localReason(c)||(!A.active(c,year(),m)?'Η θέση δεν λειτουργεί σε αυτόν τον μήνα.':!A.editable(year(),m)?'Η προθεσμία έληξε στις '+A.cutoff(year(),m).split('-').reverse().join('/')+'.':'');}
function start(kind,id,data,edit=null){
 const c=card(id),why=localReason(c);if(why){notify(why);return false;}
 if(F.draft&&changed()&&!confirm('Έξοδος χωρίς αποθήκευση των επιλογών;'))return false;
 F.draft={kind,card:id,year:year(),data:C.clone(data),baseline:JSON.stringify(data),cardBaseline:JSON.stringify(c),edit};F.error='';F.review=null;
 L.customCard=null;state.editingNegotiation=null;render();return true;
}
function changed(){return F.draft&&JSON.stringify(F.draft.data)!==F.draft.baseline;}
F.openCustom=function(id){
 const c=card(id),why=localReason(c);if(why){notify(why);return;}
 const first=Array.from({length:12},(_,m)=>m).find(m=>!SCL295.customReason(c,m));
 if(first===undefined){notify('Δεν υπάρχουν διαθέσιμοι μήνες για Εξατομίκευση.');return;}
 if(start('custom',id,{schedule:C.selected(c)})){F.draft.selected=[first];F.draft.focus=first;F.draft.query='';render();}
};
F.openDeal=function(id,type=null,index=0){
 const c=card(id);if(localReason(c)){notify(localReason(c));return;}
 const existing=type==='confirmed'?C.deals(c)[index]:type==='preagreement'?preagreementList(c)[index]:null;
 const free=Array.from({length:12},(_,m)=>m).find(m=>!reason(c,m)&&!C.at(c,m));
 if(!existing&&free===undefined){notify('Δεν υπάρχουν διαθέσιμοι μήνες για νέα Συμφωνία προμηθευτή.');return;}
 if(existing&&C.months(existing).some(m=>reason(c,m))){F.document(id,existing,type==='preagreement'?'proposal':'confirmation');return;}
 const d=existing?C.clone(existing):{...defaultNegotiation(c.defaultProgram),id:uid(),startMonth:free,duration:1,monthlyContentChanges:false,soldMonthlyPrice:suggestedPrice()};
 for(const k of ['supplier','brand','subline','products'])d[k]=String(d[k]??'');
 d.schedule=C.list(d.schedule);d.monthlySublines=C.list(d.monthlySublines);d.monthlyProducts=C.list(d.monthlyProducts);
 start('deal',id,d,existing?{type,id:existing.id,index}:null);
};
F.openShelf=function(id,m){
 const c=card(id),why=reason(c,m)||(C.at(c,m)?'Ο μήνας έχει Συμφωνία προμηθευτή.':'');if(why){notify(why);return;}
 const existing=sponsoredForMonth(c,m)[0];let grouped=existing?.groupId?(c.sponsoredShelves||[]).filter(s=>s.groupId===existing.groupId&&s.status!=='cancelled'):[existing].filter(Boolean);
 // An interrupted sponsorship is edited only as a consecutive, still-editable period.
 grouped=grouped.filter(s=>!reason(c,Number(s.month))).sort((a,b)=>a.month-b.month);
 const contiguous=grouped.length&&grouped.every((s,i)=>Number(s.month)===Number(grouped[0].month)+i);
 const entire=contiguous&&(!existing?.groupId||(c.sponsoredShelves||[]).filter(s=>s.groupId===existing.groupId).length===grouped.length);
 const startMonth=entire?Number(grouped[0].month):Number(m),duration=entire?grouped.length:1;
 const group=existing?(entire?existing.groupId||existing.id:null):null;
 const d={id:group||uid(),brand:existing?.brand||'',products:existing?.products||'',shelves:existing?.shelves||'2 πρώτα ράφια',price:existing?Number(existing.price):sponsoredBasePrice(),startMonth,duration};
 start('shelf',id,d,{groupId:group,existing:!!existing});
};
function modal(){return {custom:'customModal',deal:'negotiationModal',shelf:'sponsoredModal'}[F.draft?.kind];}
function common(c){const device=c.playerCode||c.deviceCode||c.device_code;return '<p class="scl298-position-strip"><strong>'+E(c.title)+' · '+year()+'</strong>'+(device?' · '+E(device):'')+' · '+'Προσανατολισμός: '+(c.screenFormat==='vertical'?'portrait':'landscape')+'</p>';}
function periodFields(d){return '<div class="field-grid">'+field('Μήνας έναρξης',select('startMonth',d.startMonth,MONTHS.map((m,i)=>[i,month(i)])))+field('Διάρκεια σε μήνες',select('duration',d.duration,Array.from({length:12-Number(d.startMonth)},(_,i)=>[i+1,String(i+1)])))+'</div><p>Περίοδος: <strong>'+E(range(C.months(d)))+'</strong>. Η καταχώριση αφορά το επιλεγμένο έτος.</p>';}
function customBody(c,d){
 const focus=d.focus??d.selected?.[0]??0,chosen=d.selected||[],current=C.selected(c),why=SCL295.customReason(c,focus),diff=C.custom(c,d.data.schedule);
 return '<p>Επίλεξε έναν ή περισσότερους διαθέσιμους μήνες και μετά τη θεματική. Αποθήκευση γίνεται μόνο με τελική επιβεβαίωση.</p><div class="scl297-months">'+MONTHS.map((_,m)=>A.active(c,year(),m)?'<div class="scl297-month">'+button(month(m),'custom-focus','data-month="'+m+'" aria-pressed="'+(focus===m)+'"')+'<label><input type="checkbox" data-scl297-month="'+m+'" '+(chosen.includes(m)?'checked':'')+' '+(SCL295.customReason(c,m)?'disabled':'')+'> Επιλογή μήνα</label><small>'+E(SCL295.customReason(c,m)||'Διαθέσιμος έως '+A.cutoff(year(),m).split('-').reverse().join('/'))+'</small></div>':'').join('')+'</div><h3>'+month(focus)+'</h3><div class="scl297-comparison"><p>Βασικό πρόγραμμα<strong>'+E(title(c.basicSchedule?.[focus]))+'</strong></p><p>Τρέχουσα επιβεβαιωμένη επιλογή<strong>'+E(title(current[focus]))+'</strong></p><p>Νέα επιλογή<strong>'+E(title(d.data.schedule[focus]))+'</strong></p></div>'+(why?'<p class="scl296-access-note">'+E(why)+'</p>':'')+'<p>Επιλεγμένοι μήνες: <strong>'+E(chosen.length?range(chosen):'Κανένας')+'</strong></p>'+button('Επιστροφή στο βασικό πρόγραμμα','custom-base',chosen.length?'':'disabled')+
 (L.data?L.picker('actions',d.query||'',SCL293Core.theme(L.data,d.data.schedule[focus])?.id,c.screenFormat,!chosen.length||!!why):'<p>Φόρτωση βιβλιοθήκης…</p>')+
 (diff.lost.length?'<p class="scl297-warning">Στους μήνες '+E(range([...new Set(diff.lost.map(s=>Number(s.month)))]))+' υπάρχει Χορηγία ραφιών που θα χαθεί αν επιβεβαιώσεις την αλλαγή.</p>':'')+'<div class="actionRow">'+button('Σύνοψη αλλαγών','review-custom',diff.changes.length?'':'disabled')+'</div>';
}
function dealBody(c,d){
 const n=d.data,monthly=n.monthlyContentChanges!==false,ms=C.months(n),cost=C.blocks({...c,confirmedDeals:[{...n,confirmed:true}],negotiation:null},year(),A.active).filter(b=>b.category==='deal').length*30,total=Number(n.soldMonthlyPrice||0)*Number(n.duration);
 const identity='<div class="field-grid">'+field('Προμηθευτής *',input('supplier',n.supplier))+field('Μάρκα *',input('brand',n.brand))+'</div>'+periodFields(n);
 const content=field('Περιεχόμενο',select('monthlyContentChanges',monthly?'monthly':'fixed',[['fixed','Ίδιο περιεχόμενο σε όλη την περίοδο'],['monthly','Περιεχόμενο ανά μήνα']]))+
 (monthly?ms.map(m=>'<fieldset><legend>'+month(m)+'</legend><div class="field-grid">'+field('Σειρά / υποσειρά — προαιρετικό',input('monthlySublines.'+m,n.monthlySublines[m]))+field('Προϊόντα — προαιρετικό',input('monthlyProducts.'+m,n.monthlyProducts[m]))+'</div>'+field('Περιεχόμενο μήνα — αναφορά υλικού',input('schedule.'+m,n.schedule[m]))+'</fieldset>').join(''):'<div class="field-grid">'+field('Σειρά / υποσειρά — προαιρετικό',input('subline',n.subline))+field('Προϊόντα — προαιρετικό',input('products',n.products))+'</div>');
 const finance=field('Συμφωνημένο μηνιαίο έσοδο φαρμακείου (€)',input('soldMonthlyPrice',n.soldMonthlyPrice,'number','min="0" step="0.01"'))+'<p>Προτεινόμενη τιμή: '+E(cash(suggestedPrice()))+' / μήνα. Η τελική τιμή είναι ελεύθερη.</p><div id="scl297DealTotals" class="scl297-comparison"><p>Έσοδο φαρμακείου<strong>'+E(cash(total))+'</strong></p><p>Κόστος διαχείρισης συμφωνίας<strong>'+E(cash(cost))+'</strong></p><p>Κέρδος συμφωνίας<strong>'+E(cash(total-cost))+'</strong></p></div><p>30€ ανά συνεχόμενη περίοδο ίδιου περιεχομένου. Το πάγιο υπηρεσίας εμφανίζεται στα Οικονομικά.</p>';
 return '<div class="scl299-agreement-status '+(d.edit?.type==='confirmed'?'confirmed':'pre')+'"><strong>'+ (d.edit?.type==='confirmed'?'Οριστική συμφωνία · έχει ήδη καταχωριστεί':d.edit?.type==='preagreement'?'Προσυμφωνία · δεν έχει κλείσει':'Νέα καταχώριση · δεν έχει αποθηκευτεί')+'</strong><p>'+(d.edit?.type==='confirmed'?'Η συμφωνία έχει ενταχθεί στο πρόγραμμα. Η παράδοση υλικού και η υλοποίηση από τα κεντρικά είναι ξεχωριστά βήματα.':d.edit?.type==='preagreement'?'Παραμένει εκτός προγράμματος, εργασιών των κεντρικών και χρεώσεων μέχρι να επιλέξεις «Μετατροπή σε οριστική συμφωνία» και να επιβεβαιώσεις.':'Αποθήκευσε προσυμφωνία αν συζητάς ακόμη με τον προμηθευτή ή καταχώρισε απευθείας οριστική συμφωνία αν έχετε ήδη συμφωνήσει.')+'</p></div>'+section(1,'Προμηθευτής και περίοδος',identity)+section(2,'Περιεχόμενο συμφωνίας',content)+section(3,'Οικονομικά συμφωνίας',finance)+'<div class="actionRow">'+(d.edit?.type==='confirmed'?'':button('Αποθήκευση προσυμφωνίας','save-pre'))+button('Πρόταση προς προμηθευτή','proposal')+button(d.edit?.type==='confirmed'?'Έλεγχος αλλαγών οριστικής συμφωνίας':d.edit?.type==='preagreement'?'Μετατροπή σε οριστική συμφωνία':'Καταχώριση οριστικής συμφωνίας','review-deal')+'</div>';
}
function shelfBody(c,d){const n=d.data,options=['1 ράφι από πάνω','2 πρώτα ράφια','4 ράφια από πάνω'];if(!options.includes(n.shelves))options.push(n.shelves);return '<p>Προσωπική καταχώριση του φαρμακείου για τα ράφια. Η οθόνη και οι εργασίες των κεντρικών δεν αλλάζουν.</p><div class="field-grid">'+field('Μάρκα',input('brand',n.brand))+field('Σειρά / προϊόντα',input('products',n.products))+'</div>'+periodFields(n)+field('Ράφια από πάνω',select('shelves',n.shelves,options.map(v=>[v,v])))+field('Συμφωνημένο μηνιαίο έσοδο (€)',input('price',n.price,'number','min="0" step="0.01"'))+'<p>Προτεινόμενη χορηγία: <strong>'+E(cash(sponsoredBasePrice()))+'</strong> / μήνα. Κατώτατη τιμή αναφοράς: 55€ — ενημερωτική, χωρίς περιορισμό καταχώρισης. Προτεινόμενη Συμφωνία προμηθευτή με οθόνη: <strong>'+E(cash(suggestedPrice()))+'</strong> / μήνα.</p><p>Δεν υπάρχει κόστος διαχείρισης Χορηγίας ραφιών.</p><div class="actionRow">'+button('Αποθήκευση χορηγίας','review-shelf')+(d.edit?.existing?button('Αφαίρεση χορηγίας','review-shelf-remove'):'')+'</div>';}
function showError(message){F.error=message;const box=$('scl297Error');if(box){box.textContent=message;box.hidden=!message;box.scrollIntoView?.({block:'nearest'});}else notify(message);}
function busy(value,label='Αποθήκευση…'){
 F.busy=value;const id=modal();if(!id)return;
 const box=$(id);box.setAttribute('aria-busy',String(value));
 box.querySelectorAll('button,input,select,textarea').forEach(b=>{if(value){b.dataset.scl298Disabled=String(b.disabled);b.disabled=true;}else if(b.dataset.scl298Disabled!==undefined){b.disabled=b.dataset.scl298Disabled==='true';delete b.dataset.scl298Disabled;}});
 const status=$('scl297Status');if(status){status.textContent=value?label:'';status.hidden=!value;}
}
function render(){
 const d=F.draft;if(!d)return;const c=card(d.card),id=modal();
 document.querySelector('#'+id+' .modal-title').textContent=({custom:'Εξατομίκευση',deal:'Συμφωνία προμηθευτή',shelf:'Χορηγία ραφιών'}[d.kind])+' — '+c.title+' · '+year();
 const sub=document.querySelector('#'+id+' .small');if(sub)sub.textContent='Οι επιλογές παραμένουν προσωρινές μέχρι την αποθήκευση.';
 $(id+'Body').innerHTML='<div class="scl297-form clearer-negotiation deal-flow" data-kind="'+d.kind+'">'+common(c)+'<div class="scl298-feedback"><p id="scl297Error" role="alert" '+(F.error?'':'hidden')+'>'+E(F.error)+'</p><p id="scl297Status" role="status" hidden></p></div>'+(F.review?reviewBody(c):d.kind==='custom'?customBody(c,d):d.kind==='deal'?dealBody(c,d):shelfBody(c,d))+'</div>';
 openModal(id);bindEvents();
 if(d.kind==='custom'&&!L.data)L.load().then(()=>{if(F.draft===d)render();}).catch(e=>showError(e.message));
}
function assertPeriod(c,d,ignore=null,allowDeal=false){
 if(!Number.isInteger(Number(d.startMonth))||!Number.isInteger(Number(d.duration))||Number(d.duration)<1||Number(d.startMonth)<0||Number(d.startMonth)+Number(d.duration)>12)throw Error('Επίλεξε έγκυρη περίοδο μέσα στο έτος.');
 for(const m of C.months(d)){const why=reason(c,m);if(why)throw Error(month(m)+': '+why);const other=C.at(c,m);if(!allowDeal&&other&&String(other.id)!==String(ignore))throw Error(month(m)+': υπάρχει Συμφωνία προμηθευτή.');}
}
function validate(kind,final=true){
 const d=F.draft,c=card(d.card);if(localReason(c))throw Error(localReason(c));if(d.year!==year())throw Error('Άλλαξε το έτος. Άνοιξε ξανά τη φόρμα.');
 if(kind==='custom'){
  const result=C.custom(c,d.data.schedule);if(!result.changes.length)throw Error('Δεν έχεις αλλάξει κάποια θεματική.');
  for(const x of result.changes){if(SCL295.customReason(c,x.month))throw Error(month(x.month)+': '+SCL295.customReason(c,x.month));if(x.after!==c.basicSchedule?.[x.month]&&SCL293Core.theme(L.data,x.after)?.status!=='available')throw Error('Η θεματική δεν είναι πλέον διαθέσιμη.');}return result;
 }
 const n=d.data;assertPeriod(c,n,d.edit?.type==='confirmed'?d.edit.id:null);
 if(kind==='deal'){
  if(final&&(!n.supplier.trim()||!n.brand.trim()))throw Error('Συμπλήρωσε και Προμηθευτή και Μάρκα.');
  if(!Number.isFinite(Number(n.soldMonthlyPrice))||Number(n.soldMonthlyPrice)<0||n.soldMonthlyPrice==='')throw Error('Συμπλήρωσε έγκυρο μηνιαίο ποσό.');
  const normalized=C.clone(n);normalized.supplier=normalized.supplier.trim();normalized.brand=normalized.brand.trim();normalized.soldMonthlyPrice=Number(n.soldMonthlyPrice);
  const result=C.agreement(c,normalized,d.edit,final);
  if(final){const reqs=C.files(c,normalized,year());result.deal.materialRequests=reqs.map(r=>({...r,status:(n.materialRequests||[]).find(x=>['file','deadline','subline','products','content'].every(k=>(x[k]||'')===(r[k]||'')))?.status||'awaiting',destination:'emitropoulou@pharmaplus.gr'}));}
  return result;
 }
 if(!n.brand.trim())throw Error('Συμπλήρωσε τη Μάρκα της χορηγίας.');
 if(n.price===''||!Number.isFinite(Number(n.price))||Number(n.price)<0)throw Error('Συμπλήρωσε έγκυρο μηνιαίο ποσό.');
 // Removing or shortening a group must not erase a closed month.
 for(const s of c.sponsoredShelves||[])if(d.edit?.groupId&&String(s.groupId||s.id)===String(d.edit.groupId)&&reason(c,Number(s.month)))throw Error('Η περίοδος περιλαμβάνει κλειδωμένο μήνα. Άνοιξε τη χορηγία του συγκεκριμένου μελλοντικού μήνα.');
 return C.shelf(c,n,d.edit?.groupId,kind==='shelf-remove');
}
async function review(kind){
 if(F.busy)return;const result=validate(kind);busy(true,'Υπολογισμός σύνοψης…');
 try{if(kind==='custom'||kind==='deal')await SCL292.loadFinance(true);F.review={kind,result};F.error='';}
 finally{busy(false);}
 render();document.querySelector('#'+modal()+' .scl297-form')?.scrollIntoView?.({block:'start'});
}
function forecastHtml(c,next){
 const rows=SCL292.data?.rows||[],old=C.forecast(c,year(),rows,A.active),after=C.forecast(next,year(),rows,A.active),sum=rs=>A.total(rs.filter(r=>r.status==='planned'));
 const used=Math.max(0,...rows.filter(r=>r.position_id===c.id&&r.category==='custom'&&r.status==='finalized').map(r=>Number(r.quota_index)||0));
 return '<h3>Επίπτωση στις χρεώσεις</h3><p>Προγραμματισμένο κόστος αλλαγών αυτής της θέσης: <strong>'+E(cash(sum(old)))+' → '+E(cash(sum(after)))+'</strong>.</p><p>'+Math.min(3,used)+' από τις 3 δωρεάν Εξατομικεύσεις έχουν οριστικοποιηθεί για αυτή την οθόνη και το έτος.</p>'+after.filter(r=>r.status==='planned').map(r=>'<p>'+E(range(Array.from({length:r.end-r.start+1},(_,i)=>r.start+i)))+' · '+(r.category==='custom'?'Εξατομίκευση · '+(r.quota<=3?r.quota+'η από τις 3 δωρεάν':'μετά τις 3 δωρεάν'):'Συμφωνία προμηθευτή')+' · <strong>'+E(cash(r.amount))+'</strong></p>').join('')+'<p>Οι προγραμματισμένες χρεώσεις οριστικοποιούνται με τους ισχύοντες κανόνες προθεσμίας. Οι παλαιότερες χρεώσεις διατηρούνται. Συνεχόμενοι μήνες με ίδιο περιεχόμενο υπολογίζονται μία φορά.</p>';
}
function reviewBody(c){
 const r=F.review,d=F.draft,n=d.data;let body='';
 if(r.kind==='custom')body='<h3>Σύνοψη Εξατομίκευσης</h3>'+r.result.changes.map(x=>'<p><strong>'+month(x.month)+'</strong>: '+E(title(x.before))+' → '+E(title(x.after))+'</p>').join('')+forecastHtml(c,r.result.card);
 else if(r.kind==='deal')body='<h3>'+(d.edit?.type==='preagreement'?'Προσυμφωνία → Οριστική συμφωνία':d.edit?.type==='confirmed'?'Αλλαγή οριστικής συμφωνίας':'Απευθείας οριστική συμφωνία')+'</h3><p>Με την τελική επιβεβαίωση η συμφωνία εντάσσεται στο πρόγραμμα, ενημερώνονται οι εργασίες HQ και υπολογίζονται οι αντίστοιχες χρεώσεις.</p><p>'+E(n.supplier+' · '+n.brand)+' · '+E(range(C.months(n)))+'</p>'+r.result.replaced.map(x=>'<p>'+month(x.month)+': '+E(x.type+' · '+title(x.title))+' → Συμφωνία προμηθευτή</p>').join('')+'<p>Συμφωνημένα έσοδα περιόδου: <strong>'+E(cash(Number(n.soldMonthlyPrice)*Number(n.duration)))+'</strong>.</p>'+forecastHtml(c,r.result.card)+'<p>Μετά την επιβεβαίωση θα είναι διαθέσιμο το έγγραφο προς τον προμηθευτή με τα ζητούμενα αρχεία και τις προθεσμίες παράδοσης στα κεντρικά.</p>';
 else body='<h3>'+(r.kind==='shelf-remove'?'Αφαίρεση χορηγίας':'Αποθήκευση χορηγίας')+'</h3><p>'+E(n.brand)+' · '+E(range(C.months(n)))+' · '+E(n.shelves)+'</p><p>Μηνιαίο έσοδο: '+E(cash(Number(n.price)))+' · Σύνολο περιόδου: '+E(cash(Number(n.price)*Number(n.duration)))+'</p><p>Δεν αλλάζει το περιεχόμενο της οθόνης και δεν δημιουργείται εργασία ή χρέωση στα κεντρικά.</p>'+(r.result.affected.length?'<p>Η αποθηκευμένη χορηγία στους επηρεαζόμενους μήνες θα ενημερωθεί. Το προηγούμενο στιγμιότυπο διατηρείται στο ιστορικό.</p>':'');
 if(r.result.lost?.length)body+='<p class="scl297-warning">Θα αφαιρεθούν οι Χορηγίες ραφιών: '+r.result.lost.map(s=>E(month(Number(s.month))+' · '+s.brand)).join(', ')+'. Το ιστορικό διατηρείται.</p>';
 return body+'<div class="actionRow">'+button('Πίσω στην επεξεργασία','back')+button(r.kind==='shelf-remove'?'Επιβεβαίωση αφαίρεσης':r.kind==='shelf'?'Αποθήκευση χορηγίας':r.kind==='deal'?(d.edit?.type==='confirmed'?'Αποθήκευση αλλαγών συμφωνίας':'Οριστικοποίηση συμφωνίας'):'Τελική επιβεβαίωση','commit')+'</div>';
}
async function commit(kind=F.review?.kind){
 if(F.busy||!F.draft)return;const d=F.draft,c=card(d.card),result=validate(kind==='pre'?'deal':kind,kind!=='pre');
 if(JSON.stringify(c)!==d.cardBaseline)throw Error('Τα δεδομένα της θέσης άλλαξαν όσο ήταν ανοικτή η φόρμα. Κλείσε και άνοιξέ την ξανά πριν αποθηκεύσεις.');
 if(!SCL_ROUTING.ready||!SCL290.context?.installation||SCL290.loading)throw Error('Η σύνδεση του φαρμακείου δεν είναι έτοιμη. Δοκίμασε ξανά.');
 const id=modal();F.error='';busy(true);let previous,dirty;
 try{
  if(SCL290.saving)await SCL290.saving;
  previous=C.clone(state.cards);dirty=SCL290.dirty;
  clearTimeout(SCL_ROUTING.saveTimer);state.cards=state.cards.map(x=>x.id===c.id?result.card:x);SCL290.dirty=true;
  await sclSaveNow();
 }catch(e){if(previous){state.cards=previous;SCL290.dirty=dirty;}showError('Δεν αποθηκεύτηκε: '+e.message+' Οι επιλογές σου παραμένουν στη φόρμα.');return;}
 finally{busy(false);}
 // Persistence succeeded. A rendering/document failure must never roll back a saved action.
 F.draft=null;F.review=null;closeModal(id);SCL295.selected=c.id;
 try{refresh(false);}catch(e){notify('Η καταχώριση αποθηκεύτηκε. Ανανέωσε τη σελίδα για να εμφανιστεί.');return;}
 notify(kind==='pre'?'Η προσυμφωνία αποθηκεύτηκε. Το πρόγραμμα και οι χρεώσεις δεν άλλαξαν.':kind==='deal'?'Η οριστική συμφωνία καταχωρίστηκε στο πρόγραμμα. Το έγγραφο είναι διαθέσιμο από το «Επιβεβαίωση προς προμηθευτή».':'Η καταχώριση αποθηκεύτηκε.');
 $('scl295PositionSection')?.scrollIntoView?.({block:'start'});
}
F.document=function(id,deal,type){
 const c=card(id),rows=C.files(c,deal,year()),confirmed=type==='confirmation',heading=confirmed?'Επιβεβαίωση Συμφωνίας προμηθευτή':'Πρόταση προς προμηθευτή';
 const pharmacy=SCL_ROUTING.pharmacy?.name||SCL290.context?.pharmacy_name||'',format=exportFormatLabel(c),period=range(C.months(deal));
 const lines=[heading,pharmacy,[deal.supplier,deal.brand].filter(Boolean).join(' · '),'Θέση: '+c.title,'Κωδικός συσκευής: '+(c.playerCode||'Δεν έχει οριστεί'),'Περίοδος: '+period,'Προσανατολισμός: '+format,'Χώρος προϊόντων: '+exportShelvesLabel(c),'Συμφωνημένο ποσό: '+cash(Number(deal.soldMonthlyPrice))+' / μήνα','Συνολική αξία: '+cash(Number(deal.soldMonthlyPrice)*Number(deal.duration)),confirmed?'Παρακαλούμε αποστείλετε τα ακόλουθα αρχεία στο emitropoulou@pharmaplus.gr.':'Μετά την τελική συμφωνία, το υλικό παραδίδεται στο emitropoulou@pharmaplus.gr.','Ονομασία αρχείων: παρακαλούμε χρησιμοποιήστε ακριβώς τα παρακάτω ονόματα, μαζί με την κατάληξη .mp4. Στο email παράδοσης αναφέρετε φαρμακείο, κωδικό συσκευής και περίοδο προβολής.',...rows.map(r=>range(Array.from({length:r.end-r.month+1},(_,i)=>r.month+i))+' | '+[r.subline,r.products,r.content].filter(Boolean).join(' · ')+' | Ακριβές όνομα αρχείου: '+r.file+' | Παράδοση έως '+r.deadline.split('-').reverse().join('/')),'Η προθεσμία είναι 14 ημέρες πριν από την έναρξη του αντίστοιχου μήνα. Όλα τα αρχεία μπορούν να παραδοθούν νωρίτερα, πριν από την πρώτη έναρξη.','Το φαρμακείο αποστέλλει αυτό το έγγραφο στον προμηθευτή. Η εφαρμογή δεν στέλνει email.'];
 F.documentText=lines.join('\n\n');
 document.querySelector('#briefModal .modal-title').textContent=heading;
 $('briefModalBody').innerHTML='<div class="actionRow">'+button('Αντιγραφή κειμένου','copy-document')+button('Εκτύπωση / Αποθήκευση PDF','print-document')+'</div><article class="export-sheet scl297-document"><h1>'+E(heading)+'</h1>'+lines.slice(1).map(s=>'<p>'+E(s)+'</p>').join('')+'</article>';openModal('briefModal');bindEvents();
};
function mutateField(el){
 const d=F.draft;if(!d||F.busy)return;const path=el.dataset.scl297Field.split('.');let value=el.value;
 if(path[0]==='monthlyContentChanges')value=value==='monthly';
 if(['duration','startMonth'].includes(path[0]))value=Number(value);
 if(path.length===2)d.data[path[0]][Number(path[1])]=value;else d.data[path[0]]=value;
 if(path[0]==='startMonth')d.data.duration=Math.min(Number(d.data.duration),12-value);
 F.review=null;F.error='';
 if(el.tagName==='SELECT')render();
 else if(d.kind==='deal'&&path[0]==='soldMonthlyPrice'){
  const n=d.data,c=card(d.card),blocks=C.blocks({...c,confirmedDeals:[{...n,confirmed:true}],negotiation:null},year(),A.active).filter(b=>b.category==='deal').length,total=Number(n.soldMonthlyPrice)*Number(n.duration);
  const values=$('scl297DealTotals')?.querySelectorAll('strong');if(values)Array.from(values).forEach((v,i)=>v.textContent=cash([total,blocks*30,total-blocks*30][i]));
 }
}
async function action(b){
 const a=b.dataset.scl297,d=F.draft,c=card(d?.card);
 if(a==='open-custom')return F.openCustom(b.dataset.card);
 if(a==='open-deal')return F.openDeal(b.dataset.card,b.dataset.type||null,Number(b.dataset.index)||0);
 if(a==='document'){const x=(b.dataset.pre==='true'?preagreementList(card(b.dataset.card)):C.deals(card(b.dataset.card)))[Number(b.dataset.index)];return F.document(b.dataset.card,x,b.dataset.pre==='true'?'proposal':'confirmation');}
 if(a==='copy-document'){await navigator.clipboard.writeText(F.documentText);b.textContent='Αντιγράφηκε';return;}
 if(a==='print-document'){const w=window.open('','_blank');if(!w)throw Error('Επίτρεψε το παράθυρο εκτύπωσης.');w.document.write('<!doctype html><html lang="el"><head><meta charset="utf-8"><title>Συμφωνία προμηθευτή</title><style>body{font:14px Arial;line-height:1.6;margin:32px}h1{font-size:23px}p{overflow-wrap:anywhere}@media print{body{margin:15mm}}</style></head><body>'+$('briefModalBody').querySelector('.export-sheet').outerHTML+'</body></html>');w.document.close();w.focus?.();setTimeout(()=>w.print?.(),250);return;}
 if(!d||F.busy)return;
 if(a==='custom-focus'){d.focus=Number(b.dataset.month);render();}
 else if(a==='custom-base'){for(const m of d.selected||[])if(!SCL295.customReason(c,m))d.data.schedule[m]=c.basicSchedule[m];render();}
 else if(a==='review-custom')await review('custom');else if(a==='review-deal')await review('deal');else if(a==='review-shelf')await review('shelf');else if(a==='review-shelf-remove')await review('shelf-remove');
 else if(a==='back'){F.review=null;render();}else if(a==='commit')await commit();
 else if(a==='save-pre'){validate('deal',false);await commit('pre');}
 else if(a==='proposal'){assertPeriod(c,d.data,d.edit?.type==='confirmed'?d.edit.id:null);F.document(c.id,d.data,'proposal');}
}
const oldClose=closeModal;closeModal=function(id){if(F.draft&&id===modal()){if(F.busy)return;if(changed()&&!confirm('Έξοδος χωρίς αποθήκευση; Οι προσωρινές επιλογές θα απορριφθούν.'))return;F.draft=null;F.review=null;F.error='';L.customCard=null;}return oldClose.apply(this,arguments);};
const oldBind=bindEvents;bindEvents=function(){const result=oldBind.apply(this,arguments);for(const id of ['customModal','negotiationModal','sponsoredModal'])if($(id))$(id).onclick=e=>{if(e.target===$(id))closeModal(id);};return result;};
renderCustomModal=F.openCustom;renderNegotiationModal=function(id){const edit=state.editingNegotiation;return F.openDeal(id,edit?.type,edit?.index||0);};renderSponsoredModal=F.openShelf;
document.addEventListener('click',async e=>{
 const pick=e.target.closest?.('[data-scl297],[data-scl293="actions-select"],[data-edit-preagreement],[data-edit-confirmed-deal],[data-close]');if(!pick||!ph())return;e.preventDefault();e.stopImmediatePropagation();if(pick.disabled||F.busy)return;
 try{
  if(pick.dataset.close){closeModal(pick.dataset.close);return;}
  if(pick.dataset.scl293==='actions-select'){const d=F.draft,c=card(d?.card),t=SCL293Core.theme(L.data,pick.dataset.theme);if(d?.kind!=='custom'||t?.status!=='available'||SCL295.customReason(c,d.focus))return;for(const m of d.selected||[])if(!SCL295.customReason(c,m))d.data.schedule[m]=t.key;render();}
  else if(pick.hasAttribute('data-edit-preagreement'))F.openDeal(pick.dataset.editPreagreement,'preagreement',Number(pick.dataset.preagreementIndex)||0);
  else if(pick.hasAttribute('data-edit-confirmed-deal'))F.openDeal(pick.dataset.editConfirmedDeal,'confirmed',Number(pick.dataset.confirmedIndex)||0);
  else await action(pick);
 }catch(err){showError(err.message);}
},true);
document.addEventListener('change',e=>{if(e.target.hasAttribute?.('data-scl297-field'))mutateField(e.target);const v=e.target.dataset?.scl297Month;if(v!==undefined&&F.draft?.kind==='custom'){const d=F.draft,m=Number(v);if(SCL295.customReason(card(d.card),m))return;d.selected=e.target.checked?[...new Set([...(d.selected||[]),m])].sort((a,b)=>a-b):(d.selected||[]).filter(x=>x!==m);d.focus=m;render();}});
document.addEventListener('input',e=>{if(e.target.hasAttribute?.('data-scl297-field')&&e.target.tagName!=='SELECT')mutateField(e.target);if(e.target.dataset?.scl293Search==='actions'&&F.draft?.kind==='custom'){const pos=e.target.selectionStart;F.draft.query=e.target.value;render();const x=document.querySelector('[data-scl293-search="actions"]');x?.focus();x?.setSelectionRange?.(pos,pos);}});
const style=document.createElement('style');style.id='scl298-actions-style';style.textContent='.scl297-form .field{display:grid;gap:6px;margin:12px 0}.scl297-form input:not([type=checkbox]),.scl297-form select,.scl297-form textarea{width:100%;box-sizing:border-box;font:inherit;padding:9px;border:1px solid var(--line);border-radius:8px;background:white}.scl297-form fieldset{border:1px solid var(--line);border-radius:10px;margin:12px 0;padding:12px}.scl297-form legend{font-weight:700}.scl297-months{display:flex;flex-wrap:wrap;gap:10px}.scl297-month{display:grid;align-content:start;gap:8px;flex:1 1 160px;max-width:260px;border:1px solid var(--line);border-radius:10px;padding:10px}.scl297-month small{line-height:1.5}.scl297-comparison{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}.scl297-comparison p{border:1px solid var(--line);padding:12px;border-radius:10px}.scl297-comparison strong{display:block;margin-top:8px}.scl297-warning{padding:12px;background:#fff7e7;border-left:4px solid #bb8a21}#scl297Error{color:#a51e24;font-weight:600}.scl297-form button[data-scl297],.scl297-month button{font:inherit;cursor:pointer;padding:9px 12px;border:1px solid var(--line);border-radius:9px;background:white}.scl297-form button[aria-pressed=true]{border-color:var(--blue);background:var(--blueSoft);color:var(--blue)}.scl297-form button:disabled{opacity:.5;cursor:default}.scl297-form .actionRow{margin-top:18px}.scl297-form .field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}@media(max-width:700px){.scl297-comparison,.scl297-form .field-grid{grid-template-columns:1fr}}';style.textContent+=`
.scl299-agreement-status{border:1px solid #ebd39a;background:#fff9e9;border-radius:10px;padding:12px}.scl299-agreement-status.confirmed{background:var(--greenSoft);border-color:#bde5ce}.scl297-form{gap:10px}.scl297-form p{margin:6px 0;line-height:1.5}.scl298-position-strip{background:var(--black);color:#fff;border-radius:10px;padding:10px 12px}.scl297-form .deal-section-head{justify-content:flex-start;align-items:center;margin:0 0 8px}.scl297-form .deal-section-title{margin:0;font-size:12px}.scl297-form .field{font-size:11px;margin:6px 0}.scl297-form .field>span{font-weight:800}.scl297-form .field-grid{gap:10px}.scl297-form .scl297-comparison p{background:#fbfcff;margin:0}.scl297-form[data-kind=deal] #scl297DealTotals p{background:var(--greenSoft);border-color:#bde5ce}.scl297-form .scl297-comparison strong{font-size:18px}.scl297-form .actionRow{position:sticky;bottom:-14px;background:white;padding:12px 0;margin-top:6px;border-top:1px solid var(--line);z-index:2;justify-content:flex-end}.scl297-form button[data-scl297],.scl297-document button{font-size:11px;font-weight:900}.scl297-form button.blue{background:var(--blueSoft);border-color:#c9dafd;color:#174dc2}.scl297-form button[data-scl297=commit]{background:var(--green);border-color:var(--green);color:white}.scl297-form .scl297-months{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:7px}.scl297-form .scl297-month{max-width:none;min-width:0;padding:8px;font-size:10px}.scl297-month button{padding:6px!important;font-size:11px!important}.scl298-feedback{position:sticky;top:-14px;z-index:3;background:white}.scl298-feedback:has(p:not([hidden])){padding:8px 0}#scl297Error{border:1px solid #f0bebe;background:#fff1f1;border-radius:10px;padding:12px}#scl297Status{background:var(--blueSoft);border:1px solid #c9dafd;border-radius:10px;padding:12px;font-weight:800}.scl297-form .deal-choice-note{margin:0}@media(max-width:850px){.scl297-form .scl297-months{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:500px){.scl297-form .scl297-months{grid-template-columns:repeat(2,minmax(0,1fr))}.scl297-form .actionRow{justify-content:stretch}.scl297-form .actionRow button{flex:1 1 auto}}
`;document.head.appendChild(style);
})(window);
