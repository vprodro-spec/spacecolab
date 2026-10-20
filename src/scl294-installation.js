
/* v294 — HQ-owned registry and installation. Existing programme/billing model retained. */
(function(root){
  'use strict';
  const C={
    id:n=>n===0?'hq':n<=2?'base-'+n:'extra-'+(n-2),
    ordinal:id=>id==='hq'||id==='pharmaplus'?0:/^base-\d+$/.test(id)?Number(id.split('-')[1]):/^extra-\d+$/.test(id)?Number(id.split('-')[1])+2:null,
    title:n=>n===0?'Pharmaplus':'Θέση '+n,
    type:n=>n===0?'hq':n<=2?'base':'extra',
    clone:x=>JSON.parse(JSON.stringify(x)),
    active:(pos,year,month)=>SCL292Core.active(pos,year,month),
    at(pos,year,month){const ym=`${year}-${String(month+1).padStart(2,'0')}`;const h=(pos?.configurationHistory||[]).filter(h=>h.until.slice(0,7)>ym).sort((a,b)=>a.until.localeCompare(b.until))[0];return h?Object.assign({},pos,h):pos;},
    code:(prefix,n,fmt)=>prefix+'_ADV'+n+'_'+(fmt==='vertical'?'P':fmt==='horizontal'?'L':'?'),
    slug(value){const map={Α:'A',Β:'V',Γ:'G',Δ:'D',Ε:'E',Ζ:'Z',Η:'I',Θ:'TH',Ι:'I',Κ:'K',Λ:'L',Μ:'M',Ν:'N',Ξ:'X',Ο:'O',Π:'P',Ρ:'R',Σ:'S',Τ:'T',Υ:'Y',Φ:'F',Χ:'CH',Ψ:'PS',Ω:'O'};return String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().split('').map(x=>map[x]||x).join('').replace(/[^A-Z0-9]+/g,'_').replace(/^_+|_+$/g,'').slice(0,60);},
    position(config,id){return (config?.positions||[]).find(p=>p.id===(id==='pharmaplus'?'hq':id))||null;},
    merge(cards,config,year,make){
      if(!config)return C.clone(cards||[]);
      return config.positions.filter(p=>!p.startsOn||p.startsOn.slice(0,7)<=`${year}-12`).map(p=>{
        const old=(cards||[]).find(c=>c.id===p.id);
        let c=old?C.clone(old):make(p);
        const fmt=year<Number(p.configuredYear||year)&&c.screenFormat?c.screenFormat:p.screenFormat;
        return Object.assign(c,{id:p.id,type:p.type,title:C.title(p.ordinal),screenFormat:fmt,pendingScreenFormat:fmt,
          playerCode:p.playerCode,contentCode:p.contentCode,installationStart:p.startsOn||null,stopsOn:p.stopsOn||null,configurationHistory:p.configurationHistory||[],installationManaged:true});
      });
    },
    csv(rows){return '\uFEFF'+rows.map(r=>r.map(v=>{let s=String(v??'');if(/^[\s]*[=+\-@]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';}).join(';')).join('\r\n');}
  };
  root.SCL290Core=C;
  if(typeof module!=='undefined'&&module.exports){module.exports=C;return;}
  if(root.__scl290Installed)return;root.__scl290Installed=true;
  const R=root.SCL290={hq:null,hqPromise:null,hqAt:0,context:null,loading:false,dirty:false,saving:null,
    registryView:'active',search:'',selected:new Set(),dialog:null,available:false,error:'',snapshots:{},turnoverEdit:false};
  const el=id=>document.getElementById(id),html=esc,year=()=>Number(state.programYear)||new Date().getFullYear();
  const isPh=()=>sclMode()==='pharmacy',isHQ=()=>sclMode()==='hq';
  const raw=sb?sb.rpc.bind(sb):null;
  const msg=e=>String(e?.message||e||'Αποτυχία αποθήκευσης');
  const installed=()=>!!R.context?.installation;
  function currentMonth(y=year()){const d=new Date();return `${y}-${String(y===d.getFullYear()?d.getMonth()+1:1).padStart(2,'0')}`;}
  async function api(name,args){if(!raw)throw Error('Δεν υπάρχει σύνδεση με τη βάση');const res=await raw(name,args);if(res.error)throw res.error;return res.data;}
  function notice(text,bad=false){R.error=bad?text:'';let box=el('scl290Notice');if(!box){box=document.createElement('div');box.id='scl290Notice';box.setAttribute('role','status');document.body.prepend(box);}box.className=bad?'scl290-notice error':'scl290-notice';box.textContent=text;box.hidden=!text;}
  function failure(e){const text=msg(e);notice(/scl290_|schema cache|PGRST202/i.test(text)?'Η έκδοση v290 χρειάζεται την ενημέρωση βάσης που συνοδεύει το αρχείο. Δεν έχει γίνει αποθήκευση.':text,true);return text;}
  async function loadHQ(force=false){
    if(R.hqPromise)return R.hqPromise;
    if(!force&&R.hq&&Date.now()-R.hqAt<1800)return R.hq;
    R.hqPromise=api('scl290_hq_data',{p_hq_key:SCL_ROUTING.hqKey}).then(d=>{if(d?.api_version!==290)throw Error('Μη συμβατή ενημέρωση βάσης');R.hq=d;R.hqAt=Date.now();R.available=true;if(root.SCL285){root.SCL285.stateData=d.base;root.SCL285.lastLoad=Date.now();}renderRegistry();return d;}).catch(e=>{failure(e);throw e;}).finally(()=>{R.hqPromise=null;});
    return R.hqPromise;
  }
  function configFor(pid){return (R.hq?.installations||[]).find(x=>String(x.pharmacy_id)===String(pid))||null;}
  function regFor(pid){return (R.hq?.registry||[]).find(x=>String(x.pharmacy_id)===String(pid))||null;}
  root.scl290PlayerFor=function(row){const p=C.position(configFor(row?.pharmacy_id),row?.position_id);return p?C.at(p,Number(row.year)||scl212Year(),Number(row.month)||0):null;};
  root.scl290PlayerLabel=function(row){const p=root.scl290PlayerFor(row);return p?'<span class="scl290-player-label"><small>Device / Content</small><br>'+html(p.playerCode)+'</span>':'';};
  root.scl290PositionActive=function(card,month,y=year()){return C.active(card,y,Number(month));};
  root.scl290BillingPositionCount=function(pid,m,y){const cfg=configFor(pid);if(!cfg)return null;return cfg.positions.filter(p=>p.type!=='hq'&&C.active(p,y,m)).length;};
  root.scl290BillingServiceActive=function(pid,m,y){const r=regFor(pid),cfg=configFor(pid);if(!r)return true;if(!cfg)return !!r.legacy;return !cfg.service_from||cfg.service_from.slice(0,7)<=`${y}-${String(m+1).padStart(2,'0')}`;};
  root.scl290AnnualExtraCost=function(){if(!installed())return extraCount()*COST.extraMonthly*12;return Array.from({length:12},(_,m)=>Math.max(0,R.context.installation.positions.filter(p=>p.type!=='hq'&&C.active(p,year(),m)).length-2)*COST.extraMonthly).reduce((a,b)=>a+b,0);};
  function make(p){if(p.type==='hq')return {id:'hq',type:'hq',title:'Pharmaplus',mode:'fixed',defaultProgram:'HQ',initialPlanLocked:true,basicSchedule:Array(12).fill('Pharmaplus')};return makePositionCard({id:p.id,type:p.type,title:p.title,p:null,fallbackProgram:p.ordinal===2?'OTC2':'OTC1'});}
  function applyInstallation(){if(!installed())return;state.cards=C.merge(state.cards,R.context.installation,year(),make).map(c=>{if(c.type==='hq')return c;const fallback=C.ordinal(c.id)===2?'OTC2':'OTC1';const ready=makePositionCard({id:c.id,type:c.type,title:c.title,p:c,fallbackProgram:fallback});if(!ready.initialPlanLocked&&!ready.pendingInitialSchedule?.some(Boolean))ready.pendingInitialSchedule=schedule(fallback);return ready;});state.totalCounters=state.cards.length;state.setupLocked=true;state._scl290InstallationVersion=R.context.installation.version;if(!state.cards.some(c=>c.id===state.selectedCardId&&c.type!=='hq'))state.selectedCardId=state.cards.find(c=>c.type!=='hq')?.id||'hq';}
  async function loadPharmacy(y=year(),keepLocal=false){
    if(R.loading)return;R.loading=true;SCL_ROUTING.suppressSave=true;clearTimeout(SCL_ROUTING.saveTimer);
    const retained=keepLocal?yearSnapshot():null;
    try{
      let context=await api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:y});
      const firstYear=Number(context.installation?.service_from?.slice(0,4));
      if(!R.context&&firstYear>y){y=firstYear;context=await api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:y});}
      R.context=context;R.available=true;R.snapshots[y]=context.snapshot_revision;
      SCL_ROUTING.pharmacy={id:context.pharmacy_id,name:context.pharmacy_name};state.programYear=y;
      if(retained)sclApplyStatePayload(retained);
      else if(context.state_json&&Object.keys(context.state_json).length)sclApplyStatePayload(context.state_json);
      else {state.cards=[];state.totalCounters=0;state.turnover=0;state.setupLocked=false;}
      state.programYear=y;
      if(installed())applyInstallation();
      state.availableYears=Array.from(new Set([...(context.available_years||[]),y])).sort();
      SCL_ROUTING.ready=true;R.dirty=!!keepLocal;
      refresh(false);sclAttachPharmacyPill();if(typeof sclUpdatePharmacyIdentityV190==='function')sclUpdatePharmacyIdentityV190();
      if(state.cards.some(c=>c.type==='hq'))await sclLoadHQProgramReadOnly();
      pharmacyUI();notice(installed()?'':context.registry.legacy?'Οι υπάρχουσες θέσεις διατηρούνται. Η αντιστοίχιση players ολοκληρώνεται από τα κεντρικά.':'Αναμονή ρύθμισης οθονών από τα κεντρικά.');
    }catch(e){SCL_ROUTING.ready=false;failure(e);throw e;}
    finally{R.loading=false;SCL_ROUTING.suppressSave=!SCL_ROUTING.ready;}
  }
  async function saveManaged(){
    if(R.saving)return R.saving;
    if(!installed()||R.loading||!SCL_ROUTING.ready)return;
    const y=year(),revision=R.snapshots[y]||0;let succeeded=false;applyInstallation();
    const payload=sclStatePayload();const fingerprint=JSON.stringify(payload.cards)+String(payload.turnover);
    R.saving=api('scl290_save_program',{p_token:SCL_ROUTING.pharmacyToken,p_year:y,
      p_installation_version:R.context.installation.version,p_snapshot_revision:revision,
      p_state:payload,p_months:scl206BuildPositionMonthsPayload(),p_deals:scl206BuildDealsPayload()}).then(result=>{
      R.snapshots[y]=result.snapshot_revision;succeeded=true;
      state.cards.forEach(c=>{if(c._scl292ResetApplied){delete c._scl292ResetApplied;delete c._scl292Reset;}});
      if(root.SCL292){root.SCL292.invalidate();root.SCL292.loadFinance(true).catch(()=>{});}
      const now=sclStatePayload();R.dirty=fingerprint!==JSON.stringify(now.cards)+String(now.turnover);
      sclAutosaveStatusV201('Αποθηκεύτηκε · '+new Date().toLocaleTimeString('el-GR',{hour:'2-digit',minute:'2-digit'}));
      notice('');return result;
    }).catch(e=>{R.dirty=true;failure(e);sclAutosaveStatusV201(msg(e),'err');if(/INSTALLATION_CHANGED/.test(msg(e)))showConflict('installation');else if(/PROGRAM_CHANGED/.test(msg(e)))showConflict('programme');throw e;})
      .finally(()=>{R.saving=null;if(succeeded&&R.dirty)sclQueueSave();});
    return R.saving;
  }
  if(sb){sb.rpc=async function(name,args,options){
    try{
      if(isHQ()&&['hq_get_all_data','hq_get_setup_summaries','hq_get_position_months','hq_get_deals'].includes(name)){
        const d=await loadHQ();return {data:d[{'hq_get_all_data':'base','hq_get_setup_summaries':'setup','hq_get_position_months':'months','hq_get_deals':'deals'}[name]],error:null};
      }
      if(isPh()&&installed()){
        if(name==='upsert_pharmacy_state_by_token'){await saveManaged();return {data:true,error:null};}
        if(['upsert_pharmacy_setup_summary_by_token','upsert_pharmacy_position_months_by_token','upsert_pharmacy_deals_by_token'].includes(name))return {data:true,error:null};
      }
      if(isPh()&&R.context&&!R.context.registry.legacy&&!installed()&&name.startsWith('upsert_pharmacy_'))return {data:null,error:{message:'Αναμονή ρύθμισης οθονών από τα κεντρικά'}};
      return raw(name,args,options);
    }catch(e){return {data:null,error:{message:msg(e)}};}
  };}
  async function flushManaged(){while(R.dirty||R.saving){await saveManaged();if(R.loading||!SCL_ROUTING.ready)break;}}
  const oldSave=sclSaveNow;
  sclSaveNow=async function(){if(isPh()&&installed()){if(!R.dirty||R.loading)return;return flushManaged();}return oldSave.apply(this,arguments);};
  const oldQueue=sclQueueSave;
  sclQueueSave=function(){if(isPh()&&installed()){if(R.loading||SCL_ROUTING.suppressSave||!R.dirty)return;clearTimeout(SCL_ROUTING.saveTimer);SCL_ROUTING.saveTimer=setTimeout(()=>sclSaveNow().catch(()=>{}),1200);return;}return oldQueue.apply(this,arguments);};
  const oldReset290=sclResetCurrentPharmacyYearV190;
  sclResetCurrentPharmacyYearV190=async function(){return root.SCL292?.requestReset();};
  const oldSummary=scl204UpsertSetupSummary,oldContracts=scl206UpsertPlanContracts;
  scl204UpsertSetupSummary=async function(){if(isPh()&&installed())return;return oldSummary.apply(this,arguments);};
  scl206UpsertPlanContracts=async function(){if(isPh()&&installed()){R.dirty=true;return saveManaged();}return oldContracts.apply(this,arguments);};
  const oldPayload=sclStatePayload;
  sclStatePayload=function(){const p=oldPayload.apply(this,arguments);if(installed()){p._scl290InstallationVersion=R.context.installation.version;p.cards.forEach(c=>{if(!c.initialPlanLocked){const saved=R.context.state_json?.cards?.find(x=>x.id===c.id);c.pendingInitialSchedule=C.clone(saved?.pendingInitialSchedule||[]);}});}return p;};
  sclLoadPharmacyMode=function(){return loadPharmacy(SCL292Core.year(new URLSearchParams(location.search).get('year'))).catch(()=>{});};
  const oldRefresh=refresh;
  refresh=function(persist=true){if(isPh()&&installed()){applyInstallation();if(persist&&!R.loading)R.dirty=true;}const r=oldRefresh.apply(this,arguments);if(isPh())pharmacyUI();return r;};
  const oldInitial=renderInitialPlanModal;
  renderInitialPlanModal=function(id){
    const c=state.cards.find(x=>x.id===id);if(isPh()&&(!c?.screenFormat||(!installed()&&!R.context?.registry.legacy))){notice('Ο προσανατολισμός της θέσης πρέπει να οριστεί από τα κεντρικά.',true);return;}
    if(isPh())c.pendingScreenFormat=c.screenFormat;
    oldInitial.apply(this,arguments);
    if(isPh()){const body=el('programModalBody'),box=body?.querySelector('.planner-card');if(box)box.innerHTML='<div class="scl290-format"><strong>Format θέσης: '+html(formatMeta(c.screenFormat))+'</strong><span>Ορισμένο από τα κεντρικά</span></div>';const intro=body?.querySelector('.compact');if(intro)intro.textContent='Επίλεξε το αρχικό ετήσιο πρόγραμμα της θέσης. Ο προσανατολισμός έχει οριστεί από τα κεντρικά.';}
  };
  const oldLock=lockInitialPlan;
  lockInitialPlan=function(card){if(isPh()){const p=C.position(R.context?.installation,card.id);card.pendingScreenFormat=p?.screenFormat||card.screenFormat;if(!card.pendingScreenFormat){notice('Αναμονή προσανατολισμού από τα κεντρικά.',true);return false;}}return oldLock.apply(this,arguments);};
  const oldPlanogram=renderPlanogramModal;
  renderPlanogramModal=function(id,m){const c=state.cards.find(x=>x.id===id);if(c&&(!c.screenFormat||!C.active(c,year(),m))){notice('Το πλανόγραμμα εμφανίζεται μετά την έναρξη λειτουργίας της θέσης και τον ορισμό format.');return;}const format=c?.screenFormat;if(c)c.screenFormat=C.at(c,year(),Number(m)||0).screenFormat;try{return oldPlanogram.apply(this,arguments);}finally{if(c)c.screenFormat=format;}};
  const oldStatus=monthStatus;
  monthStatus=function(c,m){if(!C.active(c,year(),m))return {owner:'pending',label:c.stopsOn&&c.stopsOn.slice(0,7)<=`${year()}-${String(m+1).padStart(2,'0')}`?'Η θέση έχει παύσει':'Πριν την εγκατάσταση'};return oldStatus.apply(this,arguments);};
  const oldReadOnly=isCustomReadOnlyMonth;
  isCustomReadOnlyMonth=function(c,m){return !C.active(c,year(),m)||oldReadOnly.apply(this,arguments);};
  const oldSegments=timelineSegments;
  timelineSegments=function(c){const base=oldSegments.apply(this,arguments),out=[];for(const seg of base){let chunk=null;for(let m=seg.start;m<=seg.end;m++){const active=C.active(c,year(),m),label=active?seg.label:monthStatus(c,m).label,cls=active?seg.cls:'pending';if(chunk&&chunk.label===label&&chunk.cls===cls){chunk.end=m;chunk.span++;}else{chunk={...seg,start:m,end:m,span:1,cls,label,finance:active?seg.finance:null};out.push(chunk);}}}return out;};
  const oldDealRevenue=dealRevenue,oldSponsoredRevenue=sponsoredRevenue;
  dealRevenue=function(c){if(!c.stopsOn)return oldDealRevenue(c);return confirmedDealList(c).reduce((total,d)=>total+(Number(d.soldMonthlyPrice)||0)*Array.from({length:Math.max(1,Number(d.duration)||1)},(_,n)=>Number(d.startMonth||0)+n).filter(m=>m<12&&C.active(c,year(),m)).length,0);};
  sponsoredRevenue=function(c){if(!c.stopsOn)return oldSponsoredRevenue(c);return sponsoredList(c).filter(x=>C.active(c,year(),Number(x.month))).reduce((n,x)=>n+(Number(x.price)||0),0);};
  const oldBuild=buildCards;
  buildCards=function(){if(isPh()&&installed()){applyInstallation();return;}return oldBuild.apply(this,arguments);};
  const oldVisible=scl212VisibleChanges;
  scl212VisibleChanges=function(){return (oldVisible.apply(this,arguments)||[]).filter(r=>{
    const reg=regFor(r.pharmacy_id),cfg=configFor(r.pharmacy_id),p=C.position(cfg,r.position_id);
    if(reg&&!reg.legacy&&!cfg)return false;
    return !p||C.active(p,Number(r.year)||scl212Year(),Number(r.month));
  }).map(r=>{const p=root.scl290PlayerFor(r);return p?Object.assign(r,{player_code:p.playerCode,content_code:p.contentCode,position_orientation:Number(r.year)<Number(p.configuredYear)&&r.position_orientation?r.position_orientation:p.screenFormat}):r;});};
  const oldLoadYear=loadYear;
  loadYear=async function(y){if(!isPh()||!R.context)return oldLoadYear(y);try{if(installed())await flushManaged();else if(R.dirty)await sclSaveNow();await loadPharmacy(Number(y));}catch(e){failure(e);}};
  const oldCreateYear=createNextProgramYear;
  createNextProgramYear=async function(){if(!isPh()||!installed())return oldCreateYear();try{
    await flushManaged();const next=Math.max(...(state.availableYears||[year()]))+1;
    const template=yearSnapshot();template.cards=template.cards.map(resetYearOperationalData);
    await loadPharmacy(next);if(!R.context.snapshot_revision&&!R.context.had_saved_state){sclApplyStatePayload(template);applyInstallation();R.dirty=true;refresh(false);await saveManaged();}
  }catch(e){failure(e);}};
  function pharmacyUI(){
    if(!isPh())return;const ready=installed()||!!R.context?.registry.legacy;
    document.querySelectorAll('[data-counters],#countersMinus,#countersPlus,[data-toggle-setup],[data-select-format]').forEach(x=>{x.disabled=true;x.hidden=true;});
    const status=el('setupStatus');if(status)status.innerHTML='<div class="scl290-setup"><div><strong>'+(ready?'Θέσεις ορισμένες από τα κεντρικά':'Αναμονή εγκατάστασης')+'</strong><div>'+html(String(state.cards.filter(c=>c.type!=='hq').length))+' θέσεις φαρμακείου · PharmaPlus ADV0</div></div><button type="button" data-scl290="refresh-install">Ανανέωση θέσεων</button><button type="button" data-scl290="turnover">'+(R.turnoverEdit?'Ολοκλήρωση τζίρου':'Ενημέρωση τζίρου')+'</button></div>';
    const ctr=el('setupControls');if(ctr)ctr.classList.toggle('hidden',!R.turnoverEdit);
    document.querySelectorAll('[data-turnover],#turnoverMinus,#turnoverPlus').forEach(b=>{b.disabled=!R.turnoverEdit;b.onclick=()=>{if(!R.turnoverEdit)return;state.turnover=b.dataset.turnover?Number(b.dataset.turnover):Math.max(0,(Number(state.turnover)||0)+(b.id==='turnoverPlus'?100000:-100000));refresh();};});
    document.querySelectorAll('.planner-note').forEach(x=>{if(x.textContent.includes('Πρώτα όρισε μόνιμο format'))x.textContent='Ο προσανατολισμός έχει οριστεί από τα κεντρικά. Επίλεξε το αρχικό ετήσιο πρόγραμμα.';});
    if(!ready){const planner=el('plannerRoot');if(planner)planner.innerHTML='<div class="scl290-empty">Τα κεντρικά θα ορίσουν τις οθόνες και τον προσανατολισμό. Στη συνέχεια θα εμφανιστούν εδώ οι θέσεις για προγραμματισμό.</div>';}
  }
  function closeDialog(){el('scl290Dialog')?.remove();R.dialog=null;}
  function dialog(title,body,kind){closeDialog();R.dialog={kind};const box=document.createElement('div');box.id='scl290Dialog';box.className='scl290-overlay';box.innerHTML='<section class="scl290-dialog" role="dialog" aria-modal="true" aria-label="'+html(title)+'"><header><h2>'+html(title)+'</h2><button type="button" data-scl290="close" aria-label="Κλείσιμο">×</button></header><div class="scl290-dialog-body">'+body+'</div><div id="scl290DialogStatus" role="status"></div></section>';document.body.appendChild(box);box.querySelector('input,select,button')?.focus();return R.dialog;}
  function field(label,id,value='',type='text',extra=''){return '<label>'+html(label)+'<input id="'+id+'" type="'+type+'" value="'+html(value)+'" '+extra+'></label>';}
  function editRegistry(id){const r=R.hq.registry.find(x=>x.id===id)||{};const d=dialog(r.id?'Στοιχεία φαρμακείου':'Νέο φαρμακείο',
    '<form id="scl290RegistryForm"><div class="scl290-fields">'+field('Επωνυμία','scl290Name',r.name)+field('Κωδικός τιμολόγησης','scl290Billing',r.billing_code,'text','maxlength="80"')+field('Διεύθυνση','scl290Address',r.address)+field('Περιοχή','scl290Area',r.area)+'</div><p>Η εγγραφή αποθηκεύεται στο μητρώο. Η ενεργοποίηση δημιουργεί το προσωπικό link.</p><button type="submit" class="primary">Αποθήκευση στοιχείων</button></form>','registry');d.record=r;}
  function activation(id){const r=R.hq.registry.find(x=>x.id===id);if(!r)return;const existing=R.hq.registry.filter(x=>x.pharmacy_id&&x.legacy&&!x.billing_code);
    const d=dialog('Ενεργοποίηση φαρμακείου','<p><strong>'+html(r.name)+'</strong><br>'+html(r.address)+' · '+html(r.area)+'</p><label>Σύνδεση με υπάρχον φαρμακείο<select id="scl290LinkExisting"><option value="">Νέο φαρμακείο — δημιουργία token / link</option>'+existing.map(x=>'<option value="'+html(x.pharmacy_id)+'">'+html(x.name)+'</option>').join('')+'</select></label><p>Αν υπάρχει ήδη στην εφαρμογή, επίλεξέ το για να διατηρηθούν το link και όλα τα προγράμματά του.</p><button type="button" class="primary" data-scl290="activate-confirm">Ενεργοποίηση</button>','activate');d.record=r;
  }
  function initialPositions(reg){
    const cfg=configFor(reg.pharmacy_id);if(cfg)return C.clone(cfg.positions);
    const rows=(R.hq.base.pharmacy_state||[]).filter(x=>x.pharmacy_id===reg.pharmacy_id).sort((a,b)=>Number(b.year)-Number(a.year));
    const chosen=rows.find(x=>Number(x.year)===scl212Year());if(chosen){rows.splice(rows.indexOf(chosen),1);rows.unshift(chosen);}
    const by=new Map();rows.forEach(s=>(s.state_json?.cards||[]).forEach(c=>{if(!by.has(c.id))by.set(c.id,c);}));
    const max=Math.max(0,...Array.from(by.keys()).map(C.ordinal).filter(x=>x!==null));
    return Array.from({length:max+1},(_,n)=>{const c=by.get(C.id(n));return {id:C.id(n),ordinal:n,type:C.type(n),title:C.title(n),screenFormat:c?.screenFormat||'',startsOn:c?null:currentMonth(scl212Year())+'-01',legacy:!!c};});
  }
  function nextMonth(){const d=new Date(SCL292Core.today()+'T12:00:00Z');d.setUTCMonth(d.getUTCMonth()+1,1);return d.toISOString().slice(0,7);}
  function monthLabel(v){if(!v)return 'Υπάρχουσα';const [y,m]=String(v).split('-');return (MONTHS[Number(m)-1]||m)+' '+y;}
  function progress(reg,cfg){
    const y=scl212Year(),positions=(cfg?.positions||[]).filter(p=>p.type!=='hq'&&Array.from({length:12},(_,m)=>m).some(m=>C.active(p,y,m)));
    const setup=R.hq.setup.find(s=>s.pharmacy_id===reg.pharmacy_id&&Number(s.year)===y);
    const cards=setup?.positions_json||[];
    return {total:positions.length,done:positions.filter(p=>cards.some(c=>c.position_id===p.id&&c.locked===true)).length};
  }
  function installDialog(id){
    const r=R.hq.registry.find(x=>x.id===id);if(!r?.pharmacy_id)return;
    const cfg=configFor(r.pharmacy_id);
    const d=dialog('Οθόνες — '+r.name,'<form id="scl290InstallForm"><div class="scl290-fields">'+field('Ονομασία για τους players','scl290Prefix',r.player_prefix||C.slug(r.name.split(/\s+/)[0]),'text',cfg?'readonly':'required')+(r.legacy?'<div class="scl290-help">Υπάρχον φαρμακείο · διατηρείται το ιστορικό.</div>':field('Έναρξη υπηρεσίας','scl290Service',cfg?.service_from?.slice(0,7)||currentMonth(scl212Year()),'month',cfg?'readonly':'required'))+'</div><p class="scl290-help">ADV0 = Pharmaplus · ADV1 = Θέση 1 · ADV2 = Θέση 2. Για υποκατάστημα ή συνωνυμία πρόσθεσε περιοχή ή κωδικό τιμολόγησης στην ονομασία.</p><div id="scl290PositionRows"></div><div class="scl290-actions"><button type="button" data-scl290="add-position">Προσθήκη θέσης</button><button type="submit" class="primary">Αποθήκευση οθονών</button>'+(cfg?'<button type="button" data-scl290="correct" data-id="'+r.id+'">Διόρθωση εγκατάστασης</button>':'')+'</div></form>','install');
    d.record=r;d.config=cfg;d.positions=initialPositions(r);renderPositionRows();
  }
  function renderPositionRows(){
    const d=R.dialog;if(d?.kind!=='install')return;
    el('scl290PositionRows').innerHTML=d.positions.map((p,n)=>{
      const locked=!!d.config?.positions.find(x=>x.id===p.id),stopped=!!p.stopsOn;
      return '<article class="scl294-screen"><div class="scl294-screen-head"><strong>'+html(C.title(p.ordinal))+'</strong><code data-player-preview="'+n+'"></code></div><div class="scl290-fields"><label>Προσανατολισμός<select data-pos-format="'+n+'" '+(locked?'disabled':'required')+'><option value="">Επίλεξε</option><option value="vertical" '+(p.screenFormat==='vertical'?'selected':'')+'>Κάθετο · P</option><option value="horizontal" '+(p.screenFormat==='horizontal'?'selected':'')+'>Οριζόντιο · L</option></select></label><label>Έναρξη'+(p.startsOn===null?'<span>Υπάρχουσα θέση</span>':'<input type="month" data-pos-start="'+n+'" value="'+html((p.startsOn||'').slice(0,7))+'" '+(locked?'readonly':'required')+'>')+'</label>'+(locked?'<label>Παύση από<input type="month" data-pos-stop="'+n+'" min="'+nextMonth()+'" value="'+html((p.stopsOn||'').slice(0,7))+'" '+(d.config.positions.find(x=>x.id===p.id)?.stopsOn?'readonly':'')+'></label>':'')+'</div>'+(locked?'<p class="scl290-help">'+(stopped?'Από '+html(monthLabel(p.stopsOn))+' η θέση δεν χρησιμοποιείται. Το ιστορικό και η αρίθμηση διατηρούνται.':'Η παύση εφαρμόζεται από τον επιλεγμένο μελλοντικό μήνα. Η αλλαγή στο Product Me γίνεται χειροκίνητα.')+'</p>':'')+(!locked&&n>0&&!p.legacy&&n===d.positions.length-1?'<button type="button" data-scl290="remove-draft">Αφαίρεση νέας θέσης</button>':'')+'</article>';
    }).join('');updatePreviews();
  }
  function updatePreviews(){const d=R.dialog;if(d?.kind!=='install')return;const prefix=C.slug(el('scl290Prefix').value);document.querySelectorAll('[data-player-preview]').forEach(x=>{const n=Number(x.dataset.playerPreview);x.textContent=C.code(prefix,d.positions[n].ordinal,d.positions[n].screenFormat);});}
  function renderRegistry(){
    if(!isHQ())return;const target=el('scl213CreatePharmacyCard');if(!target)return;
    if(!el('scl290RegistryRoot'))target.innerHTML='<div id="scl290RegistryRoot"><div class="scl290-toolbar"><h2>Φαρμακεία</h2><button type="button" data-scl290="new">Νέο φαρμακείο</button><button type="button" data-scl290="export">Εξαγωγή όλων των players</button><button type="button" data-scl290="export-selected" id="scl294ExportSelected">Εξαγωγή επιλεγμένων</button><button type="button" data-scl290="reload">Ανανέωση</button></div><div class="scl290-toolbar"><button type="button" data-scl290="view-active" id="scl290ActiveTab"></button><button type="button" data-scl290="view-inactive" id="scl290InactiveTab"></button><input id="scl290Search" aria-label="Αναζήτηση φαρμακείων" type="search" placeholder="Επωνυμία, κωδικός, διεύθυνση ή περιοχή"></div><div id="scl290RegistryRows"></div></div>';
    if(!R.hq){el('scl290RegistryRows').textContent='Φόρτωση μητρώου…';return;}
    const active=R.hq.registry.filter(x=>x.pharmacy_id),inactive=R.hq.registry.filter(x=>!x.pharmacy_id);
    el('scl290ActiveTab').textContent='Ενεργά ('+active.length+')';el('scl290InactiveTab').textContent='Προς ενεργοποίηση ('+inactive.length+')';
    el('scl290ActiveTab').classList.toggle('primary',R.registryView==='active');el('scl290InactiveTab').classList.toggle('primary',R.registryView==='inactive');
    const q=R.search.toLocaleLowerCase('el'),rows=(R.registryView==='active'?active:inactive).filter(r=>[r.name,r.billing_code,r.address,r.area].join(' ').toLocaleLowerCase('el').includes(q)).sort((a,b)=>a.name.localeCompare(b.name,'el'));
    const button=(r,a,t)=>'<button type="button" data-scl290="'+a+'" data-id="'+r.id+'">'+t+'</button>';
    el('scl290RegistryRows').innerHTML=rows.length?rows.map(r=>{
      const cfg=configFor(r.pharmacy_id),pr=progress(r,cfg),ym=SCL292Core.today().slice(0,7),positions=(cfg?.positions||[]).filter(p=>!p.stopsOn||p.stopsOn.slice(0,7)>ym);
      const info=cfg?positions.filter(p=>p.type!=='hq').length+' τοπικές οθόνες + '+positions.filter(p=>p.type==='hq').length+' Pharmaplus · Έναρξη υπηρεσίας: '+monthLabel(cfg.service_from):'Εκκρεμεί εγκατάσταση';
      return '<article class="scl294-pharmacy"><div class="scl294-pharmacy-info">'+(r.pharmacy_id?'<label class="scl294-select"><input type="checkbox" data-scl294-select="'+r.id+'" '+(R.selected.has(r.id)?'checked':'')+' aria-label="Επιλογή '+html(r.name)+'"></label>':'')+'<div><strong>'+html(r.name)+'</strong><div>'+html([r.address,r.area].filter(Boolean).join(' · '))+'</div><small>Κωδικός τιμολόγησης: '+html(r.billing_code||'εκκρεμεί')+'</small>'+(r.pharmacy_id?'<p class="scl294-summary">'+html(info)+'</p>'+(cfg?'<span class="scl294-state">'+(pr.total?pr.done+'/'+pr.total+' θέσεις με αρχικό πρόγραμμα · '+scl212Year():'Δεν απαιτείται αρχικό πρόγραμμα για το '+scl212Year())+'</span>':''):'')+'</div></div><div class="scl290-actions">'+(r.pharmacy_id?button(r,'programme','Προβολή προγράμματος'):'')+button(r,'edit','Στοιχεία')+(r.pharmacy_id?button(r,'install','Οθόνες')+button(r,'link','Πρόσβαση')+button(r,'deactivate','Απενεργοποίηση'):'<button type="button" class="primary" data-scl290="activate" data-id="'+r.id+'" '+(!r.billing_code?'disabled title="Συμπληρώστε τον κωδικό τιμολόγησης"':'')+'>Ενεργοποίηση</button>')+'</div></article>';
    }).join(''):'<div class="scl290-empty">Δεν βρέθηκαν φαρμακεία.</div>';
    const count=[...R.selected].filter(id=>active.some(r=>r.id===id)).length;
    el('scl294ExportSelected').textContent='Εξαγωγή επιλεγμένων ('+count+')';el('scl294ExportSelected').disabled=count===0;
    // Supersede the duplicate legacy directory; its detail view remains reachable.
    const old=el('scl212Overview');if(old)old.closest('table')?.classList.add('scl294-old-directory');
  }
  function showLink(r){
    if(!configFor(r.pharmacy_id)){const d=dialog('Πρόσβαση — '+r.name,'<p>Εκκρεμεί εγκατάσταση. Όρισε πρώτα τις οθόνες για να δώσεις πρόσβαση στο φαρμακείο.</p><button type="button" data-scl290="install" data-id="'+r.id+'">Ρύθμιση οθονών</button>','link');return;}
    const link=sclBuildPharmacyLink(r.token),d=dialog('Πρόσβαση — '+r.name,'<label>Σύνδεσμος φαρμακείου<input id="scl290Link" readonly value="'+html(link)+'"></label><div class="scl290-actions"><button type="button" data-scl290="copy-link">Αντιγραφή συνδέσμου</button><a class="scl294-open" href="'+html(link)+'" target="_blank" rel="noopener">Άνοιγμα εφαρμογής</a></div><details><summary>Λεπτομέρειες πρόσβασης</summary><label>Token<input readonly value="'+html(r.token)+'"></label></details>','link');d.link=link;
  }
  function showProgramme(r){
    const cfg=configFor(r.pharmacy_id);if(!cfg)return installDialog(r.id);
    const y=scl212Year(),rows=R.hq.months.filter(x=>x.pharmacy_id===r.pharmacy_id&&Number(x.year)===y);
    const d=dialog('Πρόγραμμα — '+r.name,'<p>Έτος '+y+'</p>'+cfg.positions.filter(p=>!p.startsOn||p.startsOn.slice(0,4)<=String(y)).map(p=>'<section class="scl294-screen"><strong>'+html(C.title(p.ordinal))+'</strong> <code>'+html(p.playerCode)+'</code><div class="scl294-programme">'+Array.from({length:12},(_,m)=>{const row=rows.find(x=>(x.position_id===p.id||(p.id==='hq'&&x.position_id==='pharmaplus'))&&Number(x.month)===m);const label=!C.active(p,y,m)?(p.stopsOn&&p.stopsOn.slice(0,7)<=y+'-'+String(m+1).padStart(2,'0')?'Η θέση έχει παύσει':'Πριν την εγκατάσταση'):row?(root.scl293Title?.(row.final_title||row.basic_theme)||row.final_title||row.basic_theme||'Εκκρεμεί πρόγραμμα'):'Εκκρεμεί πρόγραμμα';return '<div><span>'+html(MONTHS[m])+'</span><strong>'+html(label)+'</strong></div>';}).join('')+'</div></section>').join(''),'programme');d.record=r;
  }
  function deactivateDialog(id){
    const r=R.hq.registry.find(x=>x.id===id);if(!r?.pharmacy_id)return;
    const d=dialog('Απενεργοποίηση — '+r.name,'<form id="scl294DeactivateForm"><p>Το φαρμακείο θα επιστρέψει στη λίστα «Προς ενεργοποίηση», διατηρώντας μόνο την επωνυμία, τον κωδικό τιμολόγησης, τη διεύθυνση και την περιοχή.</p><p><strong>Διαγράφονται τα δεδομένα ενεργοποίησης:</strong> οθόνες, προγράμματα και ιστορικό, συμφωνίες, χορηγίες, χρεώσεις, αιτήματα επαναφοράς και ολοκληρώσεις εργασιών. Ο παλιός σύνδεσμος παύει να λειτουργεί.</p><p>Οι πραγματικοί players χρειάζονται ξεχωριστή απενεργοποίηση στο Product Me.</p>'+field('Πληκτρολόγησε την επωνυμία: '+r.name,'scl294ConfirmName','','text','required autocomplete="off"')+'<button type="submit" class="scl294-danger">Απενεργοποίηση και καθαρισμός</button></form>','deactivate');d.record=r;
  }
  function correctionDialog(id){
    const r=R.hq.registry.find(x=>x.id===id),cfg=configFor(r?.pharmacy_id);if(!cfg)return;
    const d=dialog('Διόρθωση εγκατάστασης — '+r.name,'<form id="scl294CorrectionForm"><p>Η διόρθωση ισχύει από '+html(monthLabel(SCL292Core.today()))+'. Τα προγράμματα διατηρούνται.</p>'+field('Νέα ονομασία players','scl294CorrectionPrefix',r.player_prefix,'text','required')+cfg.positions.map(p=>'<div class="scl294-screen"><strong>'+html(C.title(p.ordinal))+'</strong><label>Προσανατολισμός<select data-correction-format="'+p.id+'"><option value="vertical" '+(p.screenFormat==='vertical'?'selected':'')+'>Κάθετο · P</option><option value="horizontal" '+(p.screenFormat==='horizontal'?'selected':'')+'>Οριζόντιο · L</option></select></label><div><code>'+html(p.playerCode)+'</code> → <code data-correction-code="'+p.id+'"></code></div></div>').join('')+'<p><strong>Χρειάζεται αντίστοιχη χειροκίνητη διόρθωση στο Product Me.</strong> Η αποθήκευση εδώ ενημερώνει την εφαρμογή, τους κωδικούς στις εργασίες και την επιλογή σωστού αρχείου. Δεν παραμετροποιεί τον πραγματικό player.</p><button type="submit" class="primary">Αποθήκευση διόρθωσης</button></form>','correction');d.record=r;d.config=cfg;correctionPreview();
  }
  function correctionPreview(){const d=R.dialog;if(d?.kind!=='correction')return;const prefix=C.slug(el('scl294CorrectionPrefix').value);for(const p of d.config.positions){const f=document.querySelector('[data-correction-format="'+p.id+'"]')?.value;document.querySelector('[data-correction-code="'+p.id+'"]').textContent=C.code(prefix,p.ordinal,f);}}
  async function refreshHQ(){R.hqAt=0;await loadHQ(true);if(typeof scl212Load==='function')await scl212Load();if(typeof sclLoadHqShell==='function')await sclLoadHqShell();renderRegistry();}
  function download(name,text,type){const a=document.createElement('a'),u=URL.createObjectURL(new Blob([text],{type}));a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);}
  function exportPlayers(selectedOnly=false){const rows=[['Κωδικός τιμολόγησης','Επωνυμία','Διεύθυνση','Περιοχή','Θέση εφαρμογής','Device PRODUCT.ME','Content PRODUCT.ME','Προσανατολισμός','Έναρξη','Παύση από']];for(const r of R.hq.registry){if(selectedOnly&&!R.selected.has(r.id))continue;for(const p of configFor(r.pharmacy_id)?.positions||[]){if(p.stopsOn&&p.stopsOn.slice(0,7)<=SCL292Core.today().slice(0,7))continue;rows.push([r.billing_code,r.name,r.address,r.area,C.title(p.ordinal),p.playerCode,p.contentCode,p.screenFormat==='vertical'?'Κάθετο / P':'Οριζόντιο / L',p.startsOn||'Υπάρχουσα',p.stopsOn||'']);}}if(rows.length===1){notice('Δεν υπάρχουν αποθηκευμένες οθόνες για εξαγωγή.');return;}download('Pharmaplus_players'+(selectedOnly?'_selected':'')+'.csv',C.csv(rows),'text/csv;charset=utf-8');}
  function showConflict(kind){if(el('scl290Dialog'))return;const body='<p>'+(kind==='installation'?'Τα κεντρικά άλλαξαν τις θέσεις.':'Το πρόγραμμα αποθηκεύτηκε από άλλη καρτέλα.')+' Οι δικές σου επιλογές παραμένουν στη σελίδα. Αποθήκευσε αντίγραφο πριν φορτώσεις το νεότερο πρόγραμμα.</p><button type="button" data-scl290="export-draft">Αποθήκευση αντιγράφου επιλογών</button><button type="button" data-scl290="reload-program">Φόρτωση αποθηκευμένου προγράμματος</button>';dialog('Το πρόγραμμα χρειάζεται ανανέωση',body,'conflict');}
  async function busy(fn){const box=el('scl290Dialog'),buttons=Array.from(box?.querySelectorAll('button')||[]);if(box?.dataset.busy)return;if(box)box.dataset.busy='1';buttons.forEach(b=>b.disabled=true);try{await fn();}catch(e){const x=el('scl290DialogStatus');if(x)x.textContent=msg(e);else failure(e);}finally{if(box)delete box.dataset.busy;buttons.forEach(b=>b.disabled=false);}}
  document.addEventListener('submit',e=>{
    if(e.target.id==='scl294DeactivateForm'){e.preventDefault();busy(async()=>{const r=R.dialog.record;await api('scl294_deactivate',{p_hq_key:SCL_ROUTING.hqKey,p_registry_id:r.id,p_expected_revision:r.revision,p_confirmation:el('scl294ConfirmName').value});R.selected.delete(r.id);R.registryView='inactive';closeDialog();await refreshHQ();notice('Το φαρμακείο επέστρεψε στο μητρώο. Ο παλιός σύνδεσμος καταργήθηκε.');});}
    if(e.target.id==='scl294CorrectionForm'){e.preventDefault();busy(async()=>{const d=R.dialog,formats={};document.querySelectorAll('[data-correction-format]').forEach(x=>formats[x.dataset.correctionFormat]=x.value);await api('scl294_correct_installation',{p_hq_key:SCL_ROUTING.hqKey,p_registry_id:d.record.id,p_expected_version:d.config.version,p_prefix:C.slug(el('scl294CorrectionPrefix').value),p_formats:formats,p_from:SCL292Core.today().slice(0,7)+'-01'});closeDialog();await refreshHQ();notice('Η διόρθωση αποθηκεύτηκε. Ολοκλήρωσε την αντίστοιχη αλλαγή στο Product Me.');});}

    if(e.target.id==='scl290RegistryForm'){e.preventDefault();busy(async()=>{const r=R.dialog.record;await api('scl290_hq_registry_save',{p_hq_key:SCL_ROUTING.hqKey,p_id:r.id||null,p_expected_revision:r.revision||0,p_record:{name:el('scl290Name').value,billing_code:el('scl290Billing').value,address:el('scl290Address').value,area:el('scl290Area').value}});R.registryView=r.pharmacy_id?'active':'inactive';closeDialog();await refreshHQ();});}
    if(e.target.id==='scl290InstallForm'){e.preventDefault();busy(async()=>{const d=R.dialog,prefix=C.slug(el('scl290Prefix').value);if(!/^[A-Z][A-Z0-9_]{1,59}$/.test(prefix))throw Error('Συμπληρώστε την ονομασία για τους players');if(d.positions.some(p=>!p.screenFormat))throw Error('Επιλέξτε προσανατολισμό σε όλες τις θέσεις');const paused=d.positions.filter(p=>p.stopsOn&&!d.config?.positions.find(x=>x.id===p.id)?.stopsOn);if(paused.length&&!confirm('Παύση θέσεων: '+paused.map(p=>C.title(p.ordinal)+' από '+monthLabel(p.stopsOn)).join(', ')+'. Το ιστορικό και οι οριστικοποιημένες χρεώσεις διατηρούνται. Οι εργασίες και τα προγραμματισμένα κόστη μετά την παύση σταματούν. Απαιτείται χειροκίνητη αλλαγή στο Product Me. Συνέχεια;'))return;await api('scl290_hq_install',{p_hq_key:SCL_ROUTING.hqKey,p_registry_id:d.record.id,p_expected_version:d.config?.version||0,p_year:scl212Year(),p_prefix:prefix,p_service_from:el('scl290Service')?.value?el('scl290Service').value+'-01':null,p_positions:d.positions});closeDialog();await refreshHQ();notice('Οι οθόνες αποθηκεύτηκαν. Ο σύνδεσμος βρίσκεται στην «Πρόσβαση».');});}
  });
  document.addEventListener('input',e=>{if(e.target.id==='scl290Search'){R.search=e.target.value;renderRegistry();}if(e.target.id==='scl290Prefix')updatePreviews();if(e.target.id==='scl294CorrectionPrefix')correctionPreview();});
  document.addEventListener('change',e=>{if(e.target.dataset.scl294Select){e.target.checked?R.selected.add(e.target.dataset.scl294Select):R.selected.delete(e.target.dataset.scl294Select);renderRegistry();}if(e.target.dataset.correctionFormat)correctionPreview();const d=R.dialog;if(d?.kind==='install'){if(e.target.dataset.posFormat!==undefined){d.positions[Number(e.target.dataset.posFormat)].screenFormat=e.target.value;updatePreviews();}if(e.target.dataset.posStop!==undefined)d.positions[Number(e.target.dataset.posStop)].stopsOn=e.target.value?e.target.value+'-01':null;if(e.target.dataset.posStart!==undefined)d.positions[Number(e.target.dataset.posStart)].startsOn=e.target.value?e.target.value+'-01':'';}});
  document.addEventListener('click',e=>{const b=e.target.closest?.('[data-scl290]');if(!b)return;const action=b.dataset.scl290;e.preventDefault();
    if(action==='close')return closeDialog();if(action==='new')return R.available?editRegistry():failure('Περιμένετε τη φόρτωση του μητρώου');
    if(action==='view-active'||action==='view-inactive'){R.registryView=action==='view-active'?'active':'inactive';return renderRegistry();}
    if(action==='edit')return editRegistry(b.dataset.id);if(action==='activate')return activation(b.dataset.id);if(action==='install')return installDialog(b.dataset.id);
    if(action==='link')return showLink(R.hq.registry.find(r=>r.id===b.dataset.id));
    if(action==='copy-link')return navigator.clipboard.writeText(R.dialog.link).then(()=>{el('scl290DialogStatus').textContent='Το link αντιγράφηκε';}).catch(()=>{el('scl290Link').select();});
    if(action==='export')return exportPlayers();if(action==='export-selected')return exportPlayers(true);if(action==='programme')return showProgramme(R.hq.registry.find(r=>r.id===b.dataset.id));if(action==='deactivate')return deactivateDialog(b.dataset.id);if(action==='correct')return correctionDialog(b.dataset.id);if(action==='reload')return refreshHQ().catch(failure);
    if(action==='activate-confirm')return busy(async()=>{const d=R.dialog;await api('scl290_hq_activate',{p_hq_key:SCL_ROUTING.hqKey,p_id:d.record.id,p_existing_pharmacy_id:el('scl290LinkExisting').value||null});R.registryView='active';const id=d.record.id;closeDialog();await refreshHQ();installDialog(id);});
    if(action==='add-position'){const d=R.dialog,n=d.positions.length;d.positions.push({id:C.id(n),ordinal:n,type:C.type(n),title:C.title(n),screenFormat:'',startsOn:currentMonth(scl212Year())+'-01'});return renderPositionRows();}
    if(action==='remove-draft'){R.dialog.positions.pop();return renderPositionRows();}
    if(action==='turnover'){R.turnoverEdit=!R.turnoverEdit;return pharmacyUI();}
    if(action==='refresh-install')return (async()=>{try{if(installed())await flushManaged();else if(R.dirty)await sclSaveNow();await loadPharmacy();}catch(e){failure(e);}})();
    if(action==='export-draft')return download('Pharmaplus_programme_draft_'+year()+'.json',JSON.stringify(yearSnapshot(),null,2),'application/json');
    if(action==='reload-program')return busy(async()=>{closeDialog();await loadPharmacy();});
  });
  // Capture obsolete controls before existing listeners, including setup-unlock shortcuts.
  document.addEventListener('click',e=>{if(!isPh())return;const b=e.target.closest?.('[data-counters],#countersMinus,#countersPlus,[data-toggle-setup],[data-select-format]');if(b){e.preventDefault();e.stopImmediatePropagation();return;}
    const deal=e.target.closest?.('[data-confirm-neg],[data-save-preagreement],[data-save-neg-edit]');if(deal){const id=deal.dataset.confirmNeg||deal.dataset.savePreagreement||deal.dataset.saveNegEdit;const c=state.cards.find(c=>c.id===id);if(c&&!C.active(c,year(),Number(c.negotiation?.startMonth)||0)){e.preventDefault();e.stopImmediatePropagation();notice('Η συμφωνία πρέπει να ξεκινά από τον μήνα εγκατάστασης της θέσης ή αργότερα.',true);}}
  },true);
  document.addEventListener('keydown',e=>{if(e.key==='Escape')closeDialog();});
  root.addEventListener('beforeunload',e=>{if(R.dirty){e.preventDefault();e.returnValue='';}});
  // Preserve legacy function entry points without leaving the old one-field creation path available.
  sclCreatePharmacyFromHq=function(){if(R.available)editRegistry();else loadHQ(true).then(()=>editRegistry()).catch(failure);};
  const oldHQRender=scl212Render;
  scl212Render=function(){const r=oldHQRender.apply(this,arguments);if(isHQ())renderRegistry();return r;};
  const oldDetail290=scl212RenderDetail;
  scl212RenderDetail=function(){const result=oldDetail290.apply(this,arguments);if(!isHQ())return result;const pid=SCL212.open,reg=regFor(pid),cfg=configFor(pid),host=el('scl212Detail');if(!reg||!host)return result;
    if(!cfg&&!reg.legacy){host.innerHTML='<div class="scl212-detail"><div class="dh"><span>'+html(reg.name)+'</span></div><div class="scl290-empty">Αναμονή εγκατάστασης από τα κεντρικά. Ορίστε τις οθόνες και τον προσανατολισμό για να ξεκινήσει ο προγραμματισμός.</div><button type="button" data-scl290="install" data-id="'+reg.id+'">Ρύθμιση οθονών</button></div>';return result;}
    if(cfg){el('scl290DetailInstall')?.remove();const box=document.createElement('div');box.id='scl290DetailInstall';box.className='scl290-detail-install';box.innerHTML='<strong>Εγκατάσταση & αντιστοίχιση PRODUCT.ME</strong><div class="scl290-install-list">'+cfg.positions.map(p=>'<div><b>'+html(C.title(p.ordinal))+'</b><code>'+html(p.playerCode)+'</code><span>'+html(p.screenFormat==='vertical'?'Κάθετο · P':'Οριζόντιο · L')+(p.startsOn?' · από '+html(p.startsOn.slice(0,7)):'')+'</span></div>').join('')+'</div>';host.prepend(box);}return result;};
  R.renderRegistry=renderRegistry;R.installDialog=installDialog;R.exportPlayers=exportPlayers;R.refreshHQ=refreshHQ;
  const css=document.createElement('style');css.textContent=`
.scl294-pharmacy{border:1px solid #d7e2dc;border-radius:10px;padding:18px;background:#fff;margin:12px 0}.scl294-pharmacy-info{display:flex;gap:12px;align-items:start}.scl294-pharmacy-info strong{font-size:16px}.scl294-pharmacy-info small{display:block;color:#53655b;margin-top:6px}.scl294-pharmacy .scl290-actions{margin-top:14px}.scl294-select input{width:18px!important;height:18px;margin-top:3px}.scl294-summary{margin:10px 0 6px}.scl294-state{display:inline-block;font-size:12px;color:#225a40;background:#edf5ef;padding:5px 9px;border-radius:5px}.scl294-screen{padding:16px;border:1px solid #d7e2dc;border-radius:9px;margin:14px 0}.scl294-screen-head{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:10px}.scl294-screen code{overflow-wrap:anywhere}.scl294-old-directory{display:none!important}.scl294-danger{color:#9b2626!important;border-color:#c68e8e!important}.scl294-programme{margin-top:12px}.scl294-programme>div{display:grid;grid-template-columns:140px 1fr;gap:10px;border-top:1px solid #edf0ee;padding:8px}.scl294-programme strong{font-size:13px}.scl294-open{display:inline-block;padding:9px;text-decoration:none}.scl290-dialog details{margin-top:18px}.scl290-dialog summary{cursor:pointer}.scl290-dialog{max-height:90vh;overflow:auto}.scl290-fields input,.scl290-fields select{min-width:0;width:100%;box-sizing:border-box}#scl290RegistryRoot h2{margin:0;font-size:20px}@media(max-width:680px){.scl294-programme>div{grid-template-columns:95px 1fr}.scl294-pharmacy{padding:12px}.scl290-fields{grid-template-columns:1fr!important}.scl290-dialog{width:94vw!important}.scl290-toolbar input{width:100%}}
`;document.head.append(css);
  function boot(){if(isHQ())loadHQ(true).then(()=>{renderRegistry();return scl212Load();}).catch(()=>{});if(isPh())pharmacyUI();}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})(typeof window!=='undefined'?window:globalThis);

