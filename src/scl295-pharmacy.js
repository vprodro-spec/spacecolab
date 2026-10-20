/* v295 — pharmacy navigation, onboarding and readable programmes. */
(function(root){
'use strict';
if(typeof sclMode!=='function'||sclMode()!=='pharmacy')return;
const E=esc,$=id=>document.getElementById(id),C=SCL292Core,L=SCL293,LC=SCL293Core;
const V=root.SCL295={mounted:false,entered:false,page:'planner',selected:null,turnoverDraft:null,turnoverEditing:false,busy:false,contexts:{},campaigns:{},loads:{},loadErrors:{},initialBaseline:null};
const y=()=>Number(state.programYear),today=()=>C.today(),now=()=>({year:Number(today().slice(0,4)),month:Number(today().slice(5,7))-1});
const next=()=>{const d=now();return {year:d.year+(d.month===11?1:0),month:(d.month+1)%12};};
const configured=()=>!!SCL290.context?.installation,loaded=()=>!!SCL_ROUTING.ready&&!!SCL290.context;
const turnoverReady=()=>Number(state.turnover)>0;
const name=c=>c.type==='hq'?'Pharmaplus':SCL290Core.title(SCL290Core.ordinal(c.id)??0);
const fmt=f=>f==='vertical'?'Κάθετη οθόνη':f==='horizontal'?'Οριζόντια οθόνη':'Αναμονή προσανατολισμού';
const period=(m,yr=y())=>MONTHS[m]+' '+yr;
const dateLabel=s=>s?period(Number(s.slice(5,7))-1,Number(s.slice(0,4))):'Υπάρχουσα εγκατάσταση';
const button=(text,a,attrs='')=>'<button type="button" data-scl295="'+a+'" '+attrs+'>'+E(text)+'</button>';
const active=(c,m,yr=y())=>C.active(c,yr,m);
const activeYear=c=>Array.from({length:12},(_,m)=>m).some(m=>active(c,m));
const local=()=>state.cards.filter(c=>c.type!=='hq'&&activeYear(c));
const pending=()=>local().filter(c=>!c.initialPlanLocked);
const title=k=>root.scl293Title?root.scl293Title(k):k;
const statusNames={basic:'Βασικό πρόγραμμα',custom:'Εξατομίκευση',deal:'Συμφωνία προμηθευτή',pending:'Εκκρεμεί αρχικό πρόγραμμα'};
const api=async(n,args)=>{const r=await sb.rpc(n,args);if(r.error)throw Error(r.error.message);return r.data;};
function notice(t,bad=false){const box=$('scl295Notice');if(box){box.textContent=t;box.hidden=!t;box.classList.toggle('error',bad);}}
function attrs(c,m){return 'data-card="'+E(c.id)+'" data-month="'+m+'"';}
function installFor(c,yr=y(),m=now().month){return SCL290Core.at(c,yr,m);}
function inactiveLabel(c,m,yr=y()){return c.stopsOn&&c.stopsOn.slice(0,7)<=yr+'-'+String(m+1).padStart(2,'0')?'Η θέση έχει παύσει':'Πριν την εγκατάσταση';}
function snapshotCard(c,yr){if(yr===y())return c;return V.contexts[yr]?.state_json?.cards?.find(x=>x.id===c.id)||null;}
function row(c,m,yr=y()){
 if(!active(c,m,yr))return {kind:'inactive',label:inactiveLabel(c,m,yr),type:''};
 const resolved=snapshotCard(c,yr);
 if(c.type==='hq'){
  const rows=V.campaigns[yr],p=rows?.find(r=>Number(r.month)===m);
  const kind=p?.display_kind==='main'?'campaign':p?.display_kind==='fallback'?'thematic':'pending';
  return {kind,label:rows?(p?.display_title||'Προσεχώς'):(V.loadErrors['pp'+yr]?'Δεν φορτώθηκε το πρόγραμμα':'Φόρτωση…'),type:kind==='campaign'?'Καμπάνια Pharmaplus':kind==='thematic'?'Θεματική Pharmaplus':'',source:p};
 }
 if(!resolved)return {kind:'pending',label:V.contexts[yr]?'Εκκρεμεί αρχικό πρόγραμμα':V.loadErrors['year'+yr]?'Δεν φορτώθηκε το πρόγραμμα':'Φόρτωση…',type:''};
 if(!resolved.initialPlanLocked)return {kind:'pending',label:'Εκκρεμεί αρχικό πρόγραμμα',type:''};
 const d=dealForMonth(resolved,m);
 if(d)return {kind:'deal',label:[d.brand||d.supplier,d.monthlyContentChanges!==false?d.monthlySublines?.[m]||d.subline:d.subline].filter(Boolean).join(' · ')||'Συμφωνία προμηθευτή',type:statusNames.deal,source:d};
 const basic=resolved.basicSchedule?.[m]||'',selected=resolved.simpleConfirmed?(resolved.simpleSchedule?.[m]||basic):basic;
 const custom=resolved.simpleConfirmed&&(selected!==basic||(resolved.simpleMechanism?.[m]&&resolved.simpleMechanism[m]!==PROMO_MECHANISMS[0]));
 return {kind:custom?'custom':'basic',label:title(selected)||'Δεν έχει οριστεί θεματική',type:custom?statusNames.custom:statusNames.basic};
}
function badges(c,m){
 if(c.type==='hq'||!active(c,m))return '';
 const pres=preagreementsForMonth(c,m),shelves=sponsoredForMonth(c,m);
 return '<div class="scl295-badges">'+pres.map(p=>'<span class="scl295-badge pre">Προσυμφωνία · '+E(p.brand||p.supplier||'Προμηθευτής')+'</span>').join('')+shelves.map(s=>'<span class="scl295-badge shelf">Χορηγία ραφιών · '+E(s.brand||'Χωρίς μάρκα')+'</span>').join('')+'</div>';
}
function inactiveGroups(c){const groups=[];for(let m=0;m<12;m++){if(active(c,m))continue;const label=inactiveLabel(c,m),prev=groups.at(-1);if(prev&&prev.end===m-1&&prev.label===label)prev.end=m;else groups.push({start:m,end:m,label});}return groups;}
function groupText(g){return MONTHS[g.start]+(g.end!==g.start?'–'+MONTHS[g.end]:'')+' '+y()+': '+g.label;}
function mount(){
 if(V.mounted)return;const shell=document.querySelector('.shell'),nav=document.querySelector('.sticky-nav');if(!shell||!nav)return;
 V.mounted=true;document.body.classList.add('scl295-pharmacy');
 const logo=nav.querySelector('.hero-logo')?.outerHTML||'<strong>SpaceCoLab</strong>';
 nav.innerHTML='<div class="scl295-brand">'+logo+'<div><strong id="scl295Name">Φαρμακείο</strong><span>SpaceCoLab · v295</span></div></div><nav class="scl295-nav" aria-label="Πλοήγηση φαρμακείου">'+[['planner','Προγραμματισμός'],['overview','Το φαρμακείο μου'],['economics','Οικονομικά'],['estimate','Εκτίμηση εσόδων'],['guide','Οδηγός']].map(([p,t])=>button(t,'page','data-page-value="'+p+'"')).join('')+'</nav><div id="yearControls"></div>';
 const econ=$('economicsGrid'),econNote=$('economicsNote');
 $('overviewPage').innerHTML='<section class="scl295-section"><h1>Το φαρμακείο μου</h1><div id="scl295Profile"></div></section><section class="scl295-section"><h2>Οι οθόνες μου</h2><div id="scl295Installation"></div></section><div id="setupStatus" hidden></div><section class="scl295-section" id="scl295RequestHost"></section>';
 $('plannerPage').innerHTML='<section class="scl295-section"><div class="scl295-section-head"><h1>Προγραμματισμός</h1><span id="scl295ProgramYear"></span></div><div id="scl295Pending"></div><div id="cards" class="scl295-cards"></div></section><section id="scl295PositionSection" class="scl295-section" hidden><div id="plannerRoot"></div></section><section class="scl295-section"><h2>Ετήσιο πρόγραμμα</h2><div id="timelineGrid" class="scl295-timeline"></div></section>';
 const ep=document.createElement('div');ep.id='economicsPage';ep.className='page';ep.innerHTML='<section class="scl295-section"><h1>Οικονομικά · <span data-scl295-year></span></h1></section>';ep.firstChild.append(econNote,econ);shell.append(ep);
 const estimate=document.createElement('div');estimate.id='estimatePage';estimate.className='page';estimate.innerHTML='<section class="scl295-section"><h1>Εκτίμηση εσόδων</h1><div id="scl295Estimate"></div></section>';shell.append(estimate);
 $('guidePage').innerHTML='<section class="scl295-section scl295-guide"><h1>Οδηγός</h1><h2>Το πρόγραμμά σου</h2><p>Οι οθόνες, οι κωδικοί συσκευών και ο προσανατολισμός ορίζονται από τα κεντρικά. Συμπλήρωσε τον τζίρο σου και οργάνωσε το αρχικό πρόγραμμα για κάθε τοπική θέση.</p><dl><dt>Βασικό πρόγραμμα</dt><dd>Το πρόγραμμα που επιλέγεις ή συνθέτεις και οριστικοποιείς για τους μήνες λειτουργίας της θέσης.</dd><dt>Εξατομίκευση</dt><dd>Αλλαγή θεματικής σε μήνες του βασικού προγράμματος. Πριν επιβεβαιώσεις βλέπεις την επίπτωση στις δωρεάν ή χρεώσιμες αλλαγές.</dd><dt>Συμφωνία προμηθευτή</dt><dd>Η συμφωνία σου με προμηθευτή για προβολή στην οθόνη και στη θέση. Η προσυμφωνία παραμένει χωριστή μέχρι να οριστικοποιηθεί.</dd><dt>Χορηγία ραφιών</dt><dd>Η καταχώριση που κρατάς για τα ράφια σου. Δεν αλλάζει το περιεχόμενο της οθόνης.</dd><dt>Καμπάνια Pharmaplus / Θεματική Pharmaplus</dt><dd>Το περιεχόμενο που ορίζουν τα κεντρικά για τη θέση Pharmaplus.</dd></dl><h2>Προθεσμίες και ιστορικό</h2><p>Οι αλλαγές μελλοντικών μηνών επιβεβαιώνονται έως και τις 15 του προηγούμενου μήνα. Το ιστορικό παραμένει διαθέσιμο για προβολή. Η επαναφορά οριστικοποιημένου προγράμματος χρειάζεται έγκριση από τα κεντρικά.</p><h2>Πλανόγραμμα</h2><p>Δες τα προϊόντα και τους τρεις τρόπους στησίματος με τον προσανατολισμό της οθόνης σου, πριν επιλέξεις θεματική.</p></section>';
 const n=document.createElement('div');n.id='scl295Notice';n.hidden=true;n.setAttribute('role','status');shell.prepend(n);
}
function renderYears(){if(!V.mounted)return;const years=[...new Set([...(state.availableYears||[]),y()])].sort((a,b)=>a-b);$('yearControls').innerHTML='<div class="scl295-years"><label>Έτος προγράμματος <select id="scl295Year">'+years.map(yr=>'<option value="'+yr+'" '+(yr===y()?'selected':'')+'>'+yr+'</option>').join('')+'</select></label>'+button('Πρόγραμμα '+(Math.max(...years)+1),'new-year')+(y()<now().year?'<span>Ιστορικό · μόνο προβολή</span>':'')+'</div>';document.querySelectorAll('[data-scl295-year]').forEach(e=>e.textContent=y());}
function renderNavigation(){if(!V.mounted)return;for(const p of ['planner','overview','economics','estimate','guide'])$(p+'Page')?.classList.toggle('active',V.page===p);document.querySelectorAll('[data-page-value]').forEach(b=>{b.classList.toggle('active',b.dataset.pageValue===V.page);b.setAttribute('aria-current',b.dataset.pageValue===V.page?'page':'false');});state.currentPage=V.page;}
function renderProfile(){
 if(!V.mounted)return;const ctx=SCL290.context,r=ctx?.registry||{},cfg=ctx?.installation;
 $('scl295Name').textContent=ctx?.pharmacy_name||'Φαρμακείο';
 if(!loaded()){$('scl295Profile').innerHTML='<p>Φόρτωση φαρμακείου…</p>';return;}
 const edit=V.turnoverEditing||!turnoverReady(),draft=V.turnoverDraft,choices=[500000,1000000,1500000,2000000,2500000,3000000,3500000,4000000];
 const previous=state.turnover;let suggested=null,sponsored=null;if(draft>0){try{state.turnover=draft;suggested=suggestedPrice();sponsored=sponsoredBasePrice();}finally{state.turnover=previous;}}
 $('scl295Profile').innerHTML='<p>'+E([r.address,r.area].filter(Boolean).join(' · '))+'</p>'+(r.billing_code?'<p>Κωδικός τιμολόγησης: '+E(r.billing_code)+'</p>':'')+(edit?'<h2>Ετήσιος τζίρος</h2><p>Επίλεξε τον ετήσιο τζίρο σου για να δεις ενδεικτικές τιμές συμφωνιών και χορηγιών. Η συμπλήρωση είναι υποχρεωτική.</p><div class="scl295-turnover">'+button('−','turnover-minus','aria-label="Μείωση τζίρου"')+choices.map(n=>button(compactTurnover(n),'turnover','data-value="'+n+'" aria-pressed="'+(draft===n)+'"')).join('')+button('+','turnover-plus','aria-label="Αύξηση τζίρου"')+'</div><p class="scl295-turnover-value">'+(draft>0?E(euro(draft)):'Επίλεξε ποσό')+'</p>'+(draft>0?'<div class="scl295-price-preview"><span>Συμφωνία προμηθευτή <strong>'+E(euro(suggested))+' / μήνα</strong></span><span>Χορηγία ραφιών <strong>'+E(euro(sponsored))+' / μήνα</strong></span></div><p class="scl295-muted">Ενδεικτικές τιμές ανά τοπική θέση. Η τελική τιμή καταχωρίζεται στη συμφωνία ή στη χορηγία.</p>':'')+'<div class="scl295-actions">'+button(turnoverReady()?'Αποθήκευση τζίρου':'Οργάνωσε το πρόγραμμά σου','save-turnover',draft>0&&cfg&&!V.busy&&y()>=now().year?'':'disabled')+(turnoverReady()?button('Ακύρωση','cancel-turnover'):'')+'</div>':'<div class="scl295-profile-row"><div>Ετήσιος τζίρος<strong>'+E(euro(state.turnover))+'</strong></div>'+button('Αλλαγή τζίρου','edit-turnover',y()<now().year?'disabled':'')+'</div><p class="scl295-muted">Η αλλαγή τζίρου ενημερώνει τις προτάσεις για νέες καταχωρίσεις. Τα ήδη αποθηκευμένα ποσά διατηρούνται.</p>');
 const positions=cfg?.positions||[],at=now(),count=positions.filter(p=>active(p,at.month,at.year));
 $('scl295Installation').innerHTML=cfg?'<p>'+count.length+' οθόνες: '+count.filter(p=>p.type!=='hq').length+' τοπικές + '+count.filter(p=>p.type==='hq').length+' Pharmaplus</p><div class="scl295-installations">'+positions.map(p=>'<article><h3>'+E(name(p))+'</h3><code>'+E(p.playerCode||'')+'</code><p>'+E(fmt(p.screenFormat))+'</p><p>Έναρξη: '+E(dateLabel(p.startsOn))+'</p>'+(p.stopsOn?'<p>Παύση από '+E(dateLabel(p.stopsOn))+'</p>':'')+'</article>').join('')+'</div><p class="scl295-muted">Για προσθήκη οθόνης ή διόρθωση εγκατάστασης επικοινώνησε με τα κεντρικά.</p>':'<p>Αναμονή εγκατάστασης από τα κεντρικά.</p>';
}
function renderCards295(){
 if(!V.mounted)return;const ready=loaded()&&configured();$('scl295ProgramYear').textContent=y();
 $('scl295Pending').innerHTML=!ready?'<p>Αναμονή ρύθμισης οθονών από τα κεντρικά.</p>':!turnoverReady()?'<p>Συμπλήρωσε πρώτα τον ετήσιο τζίρο σου.</p>'+button('Συμπλήρωση τζίρου','profile'):pending().length?'<p><strong>Εκκρεμεί αρχικό πρόγραμμα:</strong> '+pending().map(c=>E(name(c))).join(', ')+'.</p>':'<p class="scl295-muted">'+(local().length?'Τα αρχικά προγράμματα των τοπικών θέσεων έχουν οριστικοποιηθεί.':'Δεν απαιτείται αρχικό πρόγραμμα για το επιλεγμένο έτος.')+'</p>';
 const a=now(),b=next();$('cards').innerHTML=state.cards.map(c=>'<article class="scl295-position-card"><header><h2>'+E(name(c))+'</h2><span>'+E(fmt(c.screenFormat))+'</span></header><code>'+E(c.playerCode||'Αναμονή κωδικού συσκευής')+'</code>'+[[a,'Τώρα'],[b,'Επόμενο']].map(([d,t])=>{const r=row(c,d.month,d.year);return '<div class="scl295-now-next"><span>'+t+' · '+period(d.month,d.year)+'</span><strong>'+E(r.label)+'</strong>'+(r.type?'<small>'+E(r.type)+'</small>':'')+'</div>';}).join('')+button('Προγραμματισμός','position','data-card="'+E(c.id)+'" '+(!turnoverReady()||!ready?'disabled':''))+'</article>').join('');
}
function renderTimeline295(){
 if(!V.mounted)return;let out='',group=null;
 const flush=()=>{if(group){out+='<p class="scl295-inactive">'+E(groupText(group))+'</p>';group=null;}};
 for(let m=0;m<12;m++){
  const cards=state.cards.filter(c=>active(c,m));if(!cards.length){const label=state.cards.length&&state.cards.every(c=>inactiveLabel(c,m)==='Πριν την εγκατάσταση')?'Πριν την εγκατάσταση':'Χωρίς θέσεις σε λειτουργία';if(group&&group.label===label)group.end=m;else{flush();group={start:m,end:m,label};}continue;}flush();
  out+='<section class="scl295-month '+(y()===now().year&&m===now().month?'current':'')+'"><h3>'+period(m)+'</h3>'+cards.map(c=>{const r=row(c,m);return '<button type="button" class="scl295-timeline-entry '+r.kind+'" data-scl295="position" '+attrs(c,m)+' '+(!turnoverReady()?'disabled':'')+'><span>'+E(name(c))+'</span><strong>'+E(r.label)+'</strong>'+(r.type?'<small>'+E(r.type)+'</small>':'')+badges(c,m)+'</button>';}).join('')+'</section>';
 }flush();$('timelineGrid').innerHTML=out;
}
function canEditMonth(c,m){return y()>=now().year&&active(c,m)&&operationalMonthEditable(m);}
function canEditAgreement(c,d){return [...monthsForNegotiation(d)].every(m=>canEditMonth(c,m));}
function agreements(c){
 const pres=preagreementList(c),deals=confirmedDealList(c),anyFuture=Array.from({length:12},(_,m)=>m).some(m=>canEditMonth(c,m)&&!dealForMonth(c,m));
 const list=(items,pre)=>items.map((d,i)=>'<article class="scl295-agreement"><div><span class="scl295-badge '+(pre?'pre':'deal')+'">'+(pre?'Προσυμφωνία':'Συμφωνία προμηθευτή')+'</span><strong>'+E([d.supplier,d.brand,d.subline].filter(Boolean).join(' · '))+'</strong><span>'+E(contiguousLabel(monthsForNegotiation(d)))+' '+y()+'</span></div>'+(canEditAgreement(c,d)?'<button type="button" data-edit-'+(pre?'preagreement':'confirmed-deal')+'="'+E(c.id)+'" data-'+(pre?'preagreement-index':'confirmed-index')+'="'+i+'">Άνοιγμα</button>':button('Προβολή','agreement-view','data-card="'+E(c.id)+'" data-index="'+i+'" data-pre="'+pre+'"'))+'</article>').join('');
 return '<section class="scl295-agreements"><h3>Συμφωνίες προμηθευτή</h3>'+button('Νέα συμφωνία προμηθευτή','new-deal','data-card="'+E(c.id)+'" '+(anyFuture?'':'disabled'))+(pres.length||deals.length?list(pres,true)+list(deals,false):'<p class="scl295-muted">Δεν υπάρχουν συμφωνίες ή προσυμφωνίες.</p>')+'</section>';
}
function renderPosition(){
 if(!V.mounted)return;const c=state.cards.find(c=>c.id===V.selected),section=$('scl295PositionSection');section.hidden=!c;if(!c)return;
 const readonly=y()<now().year;let body='';
 const groups=inactiveGroups(c);let already=new Set();
 for(let m=0;m<12;m++){
  if(!active(c,m)){const g=groups.find(g=>m>=g.start&&m<=g.end);if(g&&!already.has(g.start)){already.add(g.start);body+='<p class="scl295-inactive">'+E(groupText(g))+'</p>';}continue;}
  const r=row(c,m),historic=period(m)!==period(now().month,now().year)&&y()*12+m<now().year*12+now().month;
  let actions='';
  if(c.type==='hq')actions=button('Στοιχεία','pp-view',attrs(c,m));
  else if(c.initialPlanLocked){
   const info=planogramInfo(c,m);if(info)actions+='<button type="button" data-open-planogram="'+E(c.id)+'" data-planogram-month="'+m+'">Πλανόγραμμα</button>';
   if(r.kind==='deal')actions+=button('Στοιχεία συμφωνίας','deal-month',attrs(c,m));
   if(sponsoredForMonth(c,m).length&&!canEditMonth(c,m))actions+=button('Χορηγία ραφιών','shelf-view',attrs(c,m));
   else if(canEditMonth(c,m)&&sponsoredEligible(c,m))actions+='<button type="button" data-open-sponsored="'+E(c.id)+'" data-sponsored-month="'+m+'">Χορηγία ραφιών'+(sponsoredForMonth(c,m).length?' ✓':'')+'</button>';
  }
  body+='<article class="scl295-position-month '+(V.focusMonth===m?'focused':'')+'"><div><h3>'+period(m)+'</h3>'+(historic?'<small>Ιστορικό · μόνο προβολή</small>':'')+'</div><div><strong>'+E(r.label)+'</strong>'+(r.type?'<span class="scl295-type '+r.kind+'">'+E(r.type)+'</span>':'')+badges(c,m)+'</div><div class="scl295-actions">'+actions+'</div></article>';
 }
 const unfinished=c.type!=='hq'&&!c.initialPlanLocked&&activeYear(c);
 $('plannerRoot').innerHTML='<div class="scl295-section-head"><div><h2>'+E(name(c))+' · '+y()+'</h2><code>'+E(c.playerCode||'')+'</code><p>'+E(fmt(c.screenFormat))+'</p></div>'+button('Κλείσιμο θέσης','close-position')+'</div>'+(unfinished?'<div class="scl295-callout"><h3>Εκκρεμεί αρχικό πρόγραμμα</h3><p>Επίλεξε έτοιμο πρόγραμμα ή ξεκίνησε από την αρχή. Συμπλήρωσε όλους τους μήνες λειτουργίας μέχρι το τέλος του έτους.</p>'+button('Οργάνωσε το πρόγραμμα της θέσης','initial','data-card="'+E(c.id)+'" '+(readonly||!turnoverReady()?'disabled':''))+'</div>':'')+body+(c.type!=='hq'&&c.initialPlanLocked?'<div class="scl295-actions scl295-position-actions">'+button('Εξατομίκευση','custom','data-card="'+E(c.id)+'" '+(!Array.from({length:12},(_,m)=>m).some(m=>!isCustomReadOnlyMonth(c,m))?'disabled':''))+'</div>'+agreements(c):'');
 bindEvents();
}
function splitEconomics(){if(!V.mounted)return;const estimate=[...$('economicsGrid').querySelectorAll('details')].find(d=>d.querySelector('summary')?.textContent.startsWith('Εκτίμηση εσόδων'));if(estimate){$('scl295Estimate').replaceChildren(estimate);estimate.open=true;}}
function moveRequests(){const box=$('scl292Requests');if(box&&V.mounted)$('scl295RequestHost').appendChild(box);}
function renderAll(){if(!V.mounted)return;renderYears();renderProfile();renderCards295();renderTimeline295();renderPosition();renderNavigation();moveRequests();splitEconomics();}
async function loadRelated(){
 if(!loaded()||!configured())return;const years=new Set([y(),now().year,next().year]);
 for(const yr of years){
  if(yr!==y()&&!V.contexts[yr]&&!V.loads['year'+yr]&&!V.loadErrors['year'+yr])V.loads['year'+yr]=api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:yr}).then(d=>V.contexts[yr]=d).catch(e=>V.loadErrors['year'+yr]=e.message).finally(()=>{delete V.loads['year'+yr];renderCards295();});
  if(!V.campaigns[yr]&&!V.loads['pp'+yr]&&!V.loadErrors['pp'+yr])V.loads['pp'+yr]=api('pharmacy_get_pharmaplus_campaigns',{p_pharmacy_token:SCL_ROUTING.pharmacyToken,p_year:yr}).then(d=>V.campaigns[yr]=d||[]).catch(e=>V.loadErrors['pp'+yr]=e.message).finally(()=>{delete V.loads['pp'+yr];renderCards295();renderTimeline295();renderPosition();});
 }
}
function enter(){if(!loaded())return;if(!V.entered){V.entered=true;V.page=turnoverReady()?'planner':'overview';}if(!turnoverReady()&&V.page!=='guide')V.page='overview';renderAll();loadRelated();}
function readDialog(heading,content){$('scl295Dialog')?.remove();const box=document.createElement('div');box.id='scl295Dialog';box.className='scl295-overlay';box.innerHTML='<section role="dialog" aria-modal="true" aria-label="'+E(heading)+'"><header><h2>'+E(heading)+'</h2>'+button('Κλείσιμο','close-dialog')+'</header>'+content+'</section>';document.body.append(box);}
function detailList(d){return '<dl class="scl295-details">'+[['Προμηθευτής',d.supplier],['Μάρκα',d.brand],['Σειρά',d.subline],['Προϊόντα',d.products],['Περίοδος',contiguousLabel(monthsForNegotiation(d))+' '+y()],['Συμφωνημένο μηνιαίο έσοδο',euro(Number(d.soldMonthlyPrice)||0)]].filter(x=>x[1]).map(([k,v])=>'<dt>'+E(k)+'</dt><dd>'+E(v)+'</dd>').join('')+'</dl>';}
async function action(b){
 const a=b.dataset.scl295,c=state.cards.find(c=>c.id===b.dataset.card),m=Number(b.dataset.month);
 if(a==='page'){if(!turnoverReady()&&!['overview','guide'].includes(b.dataset.pageValue)){V.page='overview';notice('Συμπλήρωσε πρώτα τον ετήσιο τζίρο.');}else V.page=b.dataset.pageValue;renderNavigation();}
 else if(a==='profile'){V.page='overview';renderNavigation();}
 else if(a==='position'){if(!turnoverReady())return;V.selected=c?.id;state.selectedCardId=c?.id;V.focusMonth=Number.isFinite(m)?m:null;V.page='planner';renderPosition();renderNavigation();$('scl295PositionSection')?.scrollIntoView?.({behavior:'smooth',block:'start'});}
 else if(a==='close-position'){V.selected=null;renderPosition();}
 else if(a==='turnover'||a==='turnover-minus'||a==='turnover-plus'){V.turnoverDraft=a==='turnover'?Number(b.dataset.value):Math.max(100000,Number(V.turnoverDraft||state.turnover||500000)+(a==='turnover-plus'?100000:-100000));renderProfile();}
 else if(a==='edit-turnover'){V.turnoverEditing=true;V.turnoverDraft=Number(state.turnover);renderProfile();}
 else if(a==='cancel-turnover'){V.turnoverEditing=false;V.turnoverDraft=null;renderProfile();}
 else if(a==='save-turnover'){
  if(!(V.turnoverDraft>0)||!configured())return;const old=state.turnover;V.busy=true;renderProfile();state.turnover=V.turnoverDraft;SCL290.dirty=true;
  try{await sclSaveNow();V.turnoverEditing=false;V.turnoverDraft=null;V.page='planner';refresh(false);notice('Ο τζίρος αποθηκεύτηκε.');}catch(e){state.turnover=old;throw e;}finally{V.busy=false;renderProfile();}
 }
 else if(a==='initial'){if(turnoverReady()&&c)renderInitialPlanModal(c.id);}
 else if(a==='custom'){const first=Array.from({length:12},(_,m)=>m).find(m=>!isCustomReadOnlyMonth(c,m));if(first===undefined)return;state.customEditorMonth=first;renderCustomModal(c.id);}
 else if(a==='new-deal'){const first=Array.from({length:12},(_,m)=>m).find(m=>canEditMonth(c,m)&&!dealForMonth(c,m));if(first===undefined)return;state.editingNegotiation=null;c.negotiation=defaultNegotiation(c.defaultProgram||'OTC1');c.negotiation.startMonth=first;state.negotiationEditorMonth=first;renderNegotiationModal(c.id);}
 else if(a==='agreement-view'){const d=(b.dataset.pre==='true'?preagreementList(c):confirmedDealList(c))[Number(b.dataset.index)];if(d)readDialog(b.dataset.pre==='true'?'Προσυμφωνία':'Συμφωνία προμηθευτή',detailList(d));}
 else if(a==='deal-month'){const d=dealForMonth(c,m);if(d)readDialog('Συμφωνία προμηθευτή · '+period(m),detailList(d));}
 else if(a==='shelf-view')readDialog('Χορηγία ραφιών · '+period(m),sponsoredForMonth(c,m).map(s=>'<h3>'+E(s.brand||'Χορηγία ραφιών')+'</h3><p>'+E(s.products||'')+'</p><p>'+E(s.shelves||'')+'</p><p>'+E(euro(Number(s.price)||0))+'</p>').join(''));
 else if(a==='pp-view'){
  const r=row(c,m),d=r.source||{};readDialog(r.type||'Pharmaplus', '<h3>'+E(r.label)+'</h3><p>'+period(m)+'</p>'+[['Προμηθευτής',d.display_kind==='main'?d.supplier:''],['Παροχή προς το φαρμακείο',d.display_kind==='main'?d.company_benefit:''],['Προϊόντα καμπάνιας',d.display_kind==='main'?d.products_text:''],...([1,2,3,4].map(n=>['Ράφι '+n,d.display_kind==='main'?d['shelf_'+n]:'']))].filter(x=>x[1]).map(([k,v])=>'<h4>'+E(k)+'</h4><p class="scl295-multiline">'+E(v)+'</p>').join(''));
 }
 else if(a==='close-dialog')$('scl295Dialog')?.remove();
 else if(a==='new-year'){await createNextProgramYear();V.selected=null;V.contexts={};refresh(false);}
}
V.confirmInitial=async function(){
 const d=L.initial,c=state.cards.find(c=>c.id===d?.card);if(!c||V.busy)return;
 const sched=d.refs.map(r=>LC.theme(L.data,r?.theme)?.key||''),from=c._scl292Reset?C.resetFrom(c._scl292Reset,y()):0;
 const missing=Array.from({length:12},(_,m)=>m).filter(m=>m>=from&&active(c,m)&&!sched[m]);
 const error=t=>{let n=$('scl295InitialError');if(!n){n=document.createElement('p');n.id='scl295InitialError';n.setAttribute('role','alert');$('programModalBody').prepend(n);}n.textContent=t;};
 if(!turnoverReady()){error('Συμπλήρωσε πρώτα τον ετήσιο τζίρο.');return;}if(y()<now().year){error('Το προηγούμενο έτος παραμένει μόνο για προβολή.');return;}
 if(missing.length){error('Συμπλήρωσε τους μήνες: '+missing.map(m=>MONTHS[m]).join(', ')+'.');return;}
 const prior=clone(state.cards),dirty=SCL290.dirty;
 if(!lockInitialPlan(c,d.program?'network':'manual',d.program||'MANUAL',sched))return;
 V.busy=true;SCL290.dirty=true;document.querySelectorAll('#programModal button').forEach(b=>b.disabled=true);
 try{await sclSaveNow();L.initial=null;V.initialBaseline=null;closeModal('programModal');V.selected=c.id;refresh(false);notice('Το πρόγραμμα της '+name(c)+' οριστικοποιήθηκε.');}
 catch(e){state.cards=prior;SCL290.dirty=dirty;error('Δεν οριστικοποιήθηκε: '+e.message);}
 finally{V.busy=false;document.querySelectorAll('#programModal button').forEach(b=>b.disabled=false);}
};
const previousApply=applyYearSnapshot;applyYearSnapshot=function(data){const r=previousApply.apply(this,arguments);if(data)state.turnover=Math.max(0,Number(data.turnover)||0);return r;};
const previousRefresh=refresh;refresh=function(){mount();const r=previousRefresh.apply(this,arguments);enter();return r;};
const previousPages=renderPageTabs;renderPageTabs=function(){if(V.mounted)return renderNavigation();return previousPages.apply(this,arguments);};
renderControls=function(){};renderCards=renderCards295;renderTimeline=renderTimeline295;renderΠρογραμματισμός=renderPosition;renderΠρογραμματισμόςTimeline=function(){};renderWorkflow=function(){};renderFutureExpansion=function(){};renderYearControls=renderYears;renderPlannerYearContext=function(){};
const previousEconomic=SCL292.renderEconomics;SCL292.renderEconomics=function(){const r=previousEconomic.apply(this,arguments);splitEconomics();return r;};
const previousRequests=SCL292.renderRequests;SCL292.renderRequests=function(){const r=previousRequests.apply(this,arguments);moveRequests();return r;};
const previousInitial=renderInitialPlanModal;renderInitialPlanModal=function(id){if(!turnoverReady()){V.page='overview';renderNavigation();notice('Συμπλήρωσε πρώτα τον ετήσιο τζίρο.');return;}const c=state.cards.find(c=>c.id===id);if(c?.initialPlanLocked&&!c._scl292Reset){notice('Η επαναφορά του προγράμματος απαιτεί έγκριση από τα κεντρικά.');return;}return previousInitial.apply(this,arguments);};
const previousPicker=L.initialPicker;L.initialPicker=function(){const result=previousPicker.apply(this,arguments),d=L.initial,c=state.cards.find(c=>c.id===d?.card);if(!c)return result;if(V.initialBaseline===null)V.initialBaseline=JSON.stringify(d.refs);const info=document.createElement('div');info.className='scl295-initial-note';info.innerHTML='<p>Το πρόγραμμα οριστικοποιείται μόνο για αυτή τη θέση. Οι επιλογές δεν αποθηκεύονται ως πρόχειρο.</p>'+inactiveGroups(c).map(g=>'<p>'+E(groupText(g))+'</p>').join('');$('programModalBody').prepend(info);return result;};
const previousBind=bindEvents;bindEvents=function(){const r=previousBind.apply(this,arguments);const modal=$('programModal');if(modal)modal.onclick=e=>{if(e.target===modal)closeModal('programModal');};return r;};
const previousClose=closeModal;closeModal=function(id){if(id==='programModal'&&L.initial){if(V.busy)return;if(V.initialBaseline!==null&&JSON.stringify(L.initial.refs)!==V.initialBaseline&&!confirm('Έξοδος χωρίς οριστικοποίηση; Οι επιλογές σου δεν θα αποθηκευτούν.'))return;L.initial=null;V.initialBaseline=null;}return previousClose.apply(this,arguments);};
const previousLibraryLoad=L.load;L.load=async function(){const d=await previousLibraryLoad.apply(this,arguments);if(V.mounted){renderCards295();renderTimeline295();renderPosition();}return d;};
const previousPlanogram=renderPlanogramModal;renderPlanogramModal=function(id,m,setup){const c=state.cards.find(c=>c.id===id);if(c&&active(c,Number(m))){const info=planogramInfo(c,Number(m)),found=LC.resolve(L.data,c,Number(m),c.simpleConfirmed?c.simpleSchedule?.[m]||c.basicSchedule?.[m]:c.basicSchedule?.[m]);if(info&&found){const historical=SCL290Core.at(c,y(),Number(m));return L.previewTheme(found.theme,found.variant.id,historical.screenFormat,setup||LC.styles[0]);}}return previousPlanogram.apply(this,arguments);};
document.addEventListener('click',async e=>{const b=e.target.closest?.('[data-scl295]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();if(b.disabled)return;b.disabled=true;try{await action(b);}catch(err){notice(err.message,true);}finally{b.disabled=false;}},true);
document.addEventListener('change',async e=>{if(e.target.id!=='scl295Year')return;try{await loadYear(Number(e.target.value));V.selected=null;V.contexts={};refresh(false);}catch(err){notice(err.message,true);}});
const style=document.createElement('style');style.id='scl295-style';style.textContent=`
body.scl295-pharmacy{background:#f3f5f4;color:#203a32}body.scl295-pharmacy .shell{max-width:1280px;padding:24px!important;margin:auto}body.scl295-pharmacy .sticky-nav{position:static!important;width:auto!important;max-width:none!important;transform:none!important;margin:0 0 24px!important;padding:20px!important;background:#fff;border:1px solid #dce5df;border-radius:14px;box-shadow:none!important}body.scl295-pharmacy .page{display:none}body.scl295-pharmacy .page.active{display:block}.scl295-brand{display:flex;gap:20px;align-items:center;margin-bottom:20px}.scl295-brand img{width:190px;max-width:40%;height:auto;object-fit:contain}.scl295-brand>div{display:grid;gap:4px}.scl295-brand strong{font-size:17px}.scl295-brand span{font-size:12px;color:#65786d}.scl295-nav{display:flex;gap:8px;flex-wrap:wrap}.scl295-pharmacy button{cursor:pointer}.scl295-pharmacy button[data-scl295],.scl295-pharmacy #plannerRoot button,.scl295-years select{font:inherit;font-size:14px;border:1px solid #c4d4ca;border-radius:7px;background:#fff;color:#24513d;padding:9px 13px;line-height:1.4}.scl295-pharmacy button[data-scl295].active,.scl295-pharmacy button[aria-pressed=true],.scl295-pharmacy [data-scl295=save-turnover],.scl295-pharmacy [data-scl295=initial]{background:#176446!important;color:#fff!important;border-color:#176446!important}.scl295-pharmacy button:disabled{cursor:default;opacity:.5}.scl295-years{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin-top:16px}.scl295-years label{display:flex;align-items:center;gap:10px;font-size:14px}.scl295-years span{font-size:13px;color:#5d7066}.scl295-section{background:#fff;border:1px solid #dce5df;border-radius:12px;padding:24px;margin-bottom:20px;min-width:0}.scl295-section h1{font-size:24px;margin:0 0 18px}.scl295-section h2{font-size:19px;margin:0 0 16px}.scl295-section h3{font-size:16px;margin:0 0 10px}.scl295-section p{line-height:1.6}.scl295-section-head{display:flex;gap:16px;align-items:start;justify-content:space-between;margin-bottom:16px}.scl295-section code{font-size:12px;color:#496257;overflow-wrap:anywhere}.scl295-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}.scl295-position-card{padding:18px;border:1px solid #dbe5df;border-radius:10px}.scl295-position-card header{display:flex;align-items:baseline;gap:10px;justify-content:space-between}.scl295-position-card header h2{margin:0 0 8px;font-size:18px}.scl295-position-card header span{font-size:12px;color:#63776b}.scl295-now-next{border-top:1px solid #e7ece9;padding:14px 0;display:grid;gap:6px}.scl295-now-next:first-of-type{margin-top:14px}.scl295-now-next>span,.scl295-now-next>small{font-size:12px;color:#5b7365}.scl295-now-next strong{font-size:15px;line-height:1.5;overflow-wrap:anywhere}.scl295-position-card>button{width:100%;margin-top:4px}.scl295-timeline{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}.scl295-month{border:1px solid #dce5df;border-radius:10px;padding:16px;min-width:0}.scl295-month.current{border-color:#22865d;background:#f6fbf7}.scl295-timeline-entry{display:block;width:100%;text-align:left;font:inherit;color:#233d31;background:#fff;border:0;border-top:1px solid #e2e9e4;padding:13px 0;cursor:pointer;white-space:normal}.scl295-timeline-entry>span,.scl295-timeline-entry>strong,.scl295-timeline-entry>small{display:block;line-height:1.5;overflow-wrap:anywhere}.scl295-timeline-entry>span{font-size:12px;color:#62786a}.scl295-timeline-entry>strong{font-size:14px;margin:4px 0}.scl295-timeline-entry>small{font-size:11px;color:#386950}.scl295-badges{display:flex;gap:6px;flex-wrap:wrap;margin-top:7px}.scl295-badge{font-size:11px;line-height:1.5;border-radius:5px;padding:4px 7px;background:#edf3ef;display:inline-block;white-space:normal;overflow-wrap:anywhere}.scl295-badge.pre{background:#fff4d8;color:#795715}.scl295-badge.shelf{background:#f2eafb;color:#66428c}.scl295-badge.deal{background:#e8f3df;color:#3b6124}.scl295-inactive{grid-column:1/-1;background:#f0f3f1;padding:12px 14px;border-radius:7px;color:#54695d;font-size:13px;margin:0 0 8px}.scl295-position-month{display:grid;grid-template-columns:130px minmax(0,1fr) auto;gap:18px;padding:18px 0;border-bottom:1px solid #e3eae5;opacity:1!important}.scl295-position-month h3{margin:0 0 6px}.scl295-position-month small{font-size:11px;color:#64776a}.scl295-position-month strong{font-size:15px;line-height:1.5;overflow-wrap:anywhere}.scl295-type{display:block;margin-top:5px;font-size:12px;color:#326b4d}.scl295-position-month.focused{background:#f1f8f2;outline:2px solid #bad7c2;border-radius:6px;padding-left:10px;padding-right:10px}.scl295-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.scl295-position-actions{margin-top:20px}.scl295-callout{border-left:3px solid #d0a344;background:#fff9eb;padding:16px;margin:10px 0 20px}.scl295-agreements{margin-top:24px;padding-top:20px;border-top:1px solid #dce5df}.scl295-agreement{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 0;border-bottom:1px solid #e1e8e3}.scl295-agreement>div{display:grid;gap:6px}.scl295-agreement strong{font-size:14px}.scl295-agreement>div>span:last-child{font-size:12px;color:#5e7265}.scl295-installations{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}.scl295-installations article{padding:16px;border:1px solid #dce5df;border-radius:8px}.scl295-installations p{margin:8px 0;font-size:13px}.scl295-muted{font-size:13px;color:#5d7265}.scl295-turnover{display:flex;gap:8px;flex-wrap:wrap}.scl295-turnover-value{font-size:24px;font-weight:650}.scl295-price-preview{display:flex;gap:24px;flex-wrap:wrap}.scl295-price-preview span{display:grid;gap:7px;font-size:13px}.scl295-price-preview strong{font-size:20px}.scl295-profile-row{display:flex;gap:20px;justify-content:space-between;align-items:center}.scl295-profile-row strong{display:block;font-size:24px;margin-top:8px}.scl295-guide{max-width:880px}.scl295-guide dt{font-weight:650;margin-top:18px}.scl295-guide dd{margin:8px 0;line-height:1.65}.scl295-guide h2{margin-top:28px}.scl295-overlay{position:fixed;inset:0;background:#12271daa;z-index:10050;display:flex;align-items:center;justify-content:center;padding:20px}.scl295-overlay>section{background:#fff;border-radius:12px;padding:24px;max-width:720px;width:100%;max-height:88vh;overflow:auto}.scl295-overlay header{display:flex;justify-content:space-between;gap:18px}.scl295-overlay h2{font-size:20px}.scl295-details dt{font-weight:650;margin-top:14px}.scl295-details dd{margin:6px 0;white-space:pre-wrap}.scl295-multiline{white-space:pre-wrap}.scl295-initial-note{font-size:13px;line-height:1.6;color:#586c5f}.scl295-pharmacy #flowToast,.scl295-pharmacy #setupStatus,.scl295-pharmacy #sclPharmacyPill{display:none!important}#scl295Notice{background:#e7f4ed;padding:12px 16px;border-radius:8px;margin-bottom:14px}#scl295Notice.error,#scl295InitialError{color:#962525;background:#fff0ef;padding:12px;border-radius:8px}.scl295-pharmacy [hidden]{display:none!important}.scl295-pharmacy .shell .page{margin-top:0!important;padding-top:0!important}.scl295-pharmacy #plannerRoot{font-size:14px}.scl295-pharmacy #scl295Estimate>details{border:0;padding:0}.scl295-pharmacy #scl295Estimate>details>summary{display:none}
body.scl295-pharmacy .shell{max-width:1280px!important;background:transparent!important;border:0!important;box-shadow:none!important}body.scl295-pharmacy .sticky-nav{background:#fff!important;border-radius:14px!important}.scl295-pharmacy .scl295-brand .hero-logo{width:220px!important;max-width:40%!important;height:auto!important;background:#176446;padding:14px;border-radius:8px}.scl295-pharmacy #sclLanding::before,.scl295-pharmacy #sclLanding::after{content:none!important;display:none!important}
@media(max-width:720px){body.scl295-pharmacy .shell{padding:12px!important}.scl295-section{padding:16px}.scl295-brand{align-items:start;gap:12px}.scl295-pharmacy .scl295-brand .hero-logo{width:150px!important;padding:10px}.scl295-brand strong{font-size:14px}.scl295-nav{gap:6px}.scl295-nav button{font-size:12px!important;padding:8px!important}.scl295-cards,.scl295-timeline{grid-template-columns:1fr}.scl295-position-month{grid-template-columns:1fr;gap:9px}.scl295-position-month>.scl295-actions{margin-top:4px}.scl295-section-head{flex-wrap:wrap}.scl295-agreement{align-items:start}.scl295-profile-row{align-items:start;flex-direction:column}.scl295-turnover button{font-size:12px!important}.scl295-years{gap:8px}.scl295-overlay{padding:12px}}
`;document.head.append(style);
mount();enter();
})(window);
