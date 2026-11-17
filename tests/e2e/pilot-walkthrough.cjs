/* Έλεγχος «όλες οι οθόνες» με φαρμακείο τύπου πιλότου (ADV + PROMO + EXP), μόνο τοπικός browser, χωρίς βάση.
   Χρήση: NODE_PATH=$(npm root -g) node tests/e2e/pilot-walkthrough.cjs [index.html]
   Ελέγχει: σφάλματα σελίδας, κείμενα τύπου undefined/NaN/[object, οριζόντιο scroll, και ότι κάθε ενέργεια θέσης ανοίγει. */
const fs=require('fs'),path=require('path'),{chromium}=require('playwright'),assert=require('assert');
const file=path.resolve(process.argv[2]||path.join(__dirname,'../../index.html'));
const seed=JSON.parse(fs.readFileSync(path.join(__dirname,'../../data/library-seed.json'),'utf8'));
const themes=seed.themes.filter(t=>t.status==='available').map(t=>t.key);
const BAD=/undefined|NaN|\[object|\bnull\b|επόμενο στάδιο|TODO|OFFLINE|Invalid Date|\{\{|\}\}/i;
const pos=[
 {id:'hq',ordinal:0,type:'hq',title:'Pharmaplus',screenFormat:'vertical',startsOn:'2026-11-01',playerCode:'PILOT_ADV0_P'},
 {id:'base-1',ordinal:1,type:'base',title:'Θέση 1',screenFormat:'vertical',startsOn:'2026-10-01',playerCode:'PILOT_ADV1_P'},
 {id:'base-2',ordinal:2,type:'base',title:'Θέση 2',screenFormat:'horizontal',startsOn:'2026-10-01',stopsOn:'2027-09-01',playerCode:'PILOT_ADV2_L'},
 {id:'promo-1',ordinal:1,type:'promo',category:'PROMO',shelves:6,title:'Promotion 1',screenFormat:'vertical',startsOn:'2027-01-01',playerCode:'PILOT_PROMO1_P'},
 {id:'promo-2',ordinal:2,type:'promo',category:'PROMO',shelves:3,title:'Promotion 2',screenFormat:'horizontal',startsOn:'2027-01-01',playerCode:'PILOT_PROMO2_L'},
 {id:'exp-1',ordinal:1,type:'exp',category:'EXP',shelves:7,title:'Experience 1',screenFormat:'vertical',startsOn:'2027-01-01',playerCode:'PILOT_EXP1_P'}];
const cards=pos.map((p,i)=>{const s=Array.from({length:12},(_,m)=>themes[(m+i*2)%themes.length]);return {id:p.id,type:p.type,title:p.title,initialPlanLocked:p.id!=='exp-1',basicSchedule:s,simpleSchedule:s,simpleConfirmed:false,confirmedDeals:[],preagreements:[],sponsoredShelves:[],screenFormat:p.screenFormat,negotiation:null,installationStart:p.startsOn,stopsOn:p.stopsOn||null,category:p.category,shelves:p.shelves,playerCode:p.playerCode,contentCode:p.playerCode,installationManaged:true};});
(async()=>{
 const b=await chromium.launch({args:['--no-sandbox','--disable-gpu','--disable-dev-shm-usage']});const problems=[],log=[];
 const p=await b.newPage({viewport:{width:1440,height:900},reducedMotion:'reduce'});const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.clock.setFixedTime(new Date('2026-11-17T10:00:00Z'));
 await p.route('**/*',r=>r.request().url().startsWith('https://scl.test/')?r.fulfill({body:fs.readFileSync(file,'utf8'),contentType:'text/html; charset=utf-8'}):r.abort());
 await p.addInitScript(({pos,cards,seed})=>{window.__rpc=async(name,args)=>{let data=[];
  if(name==='scl293_library')data={...seed,media_events:[]};
  if(name==='scl292_finance')data={year:args?.p_year||2027,rows:[],requests:[],history:[]};
  if(name==='scl302_overview')data={today:'2026-11-17',deadlines:[],requests:[]};
  if(name==='scl290_get_pharmacy')data={pharmacy_id:'pilot',pharmacy_name:'Πιλότος',registry:{legacy:false},installation:{version:3,service_from:'2026-10-01',positions:pos},state_json:{turnover:550000,cards},snapshot_revision:5,available_years:[2026,2027]};
  return {data,error:null}};
  window.__client={rpc:async(...a)=>window.__rpc(...a),from:()=>{const x=new Proxy(()=>{},{get:(_,k)=>k==='then'?Promise.resolve({data:[],error:null}).then.bind(Promise.resolve({data:[],error:null})):()=>x});return x;}};window.supabase={createClient:()=>window.__client};
 },{pos,cards,seed});
 await p.goto('https://scl.test/?pharmacy=tok');await p.waitForTimeout(1800);
 const scanText=async label=>{const t=await p.evaluate(()=>{const m=[...document.querySelectorAll('.modal.open,[data-modal-card]')].filter(e=>e.offsetParent).map(e=>e.innerText).join('\n');const vis=[...document.querySelectorAll('body *')].filter(e=>e.offsetParent&&e.children.length===0&&e.innerText&&e.innerText.trim()).map(e=>e.innerText.trim()).join('\n');return vis+'\n'+m});
  for(const line of new Set(t.split('\n')))if(BAD.test(line)&&!/Σύντομα από τα κεντρικά/.test(line))problems.push(label+': '+line.slice(0,120));
  const sw=await p.evaluate(()=>document.documentElement.scrollWidth);if(sw>1440)problems.push(label+': οριζόντιο scroll '+sw)};
 for(const y of ['2026','2027']){
  await p.evaluate(y=>{const s=document.getElementById('scl295Year');s.value=y;s.dispatchEvent(new Event('change',{bubbles:true}))},y);await p.waitForTimeout(1500);
  for(const n of ['Το πρόγραμμά μου','Έσοδα','Το φαρμακείο μου','Πώς διαβάζεται']){
   await p.evaluate(n=>{const e=[...document.querySelectorAll('nav button,.sidebar button,aside button,aside a')].filter(e=>e.offsetParent).find(e=>((e.innerText||'')+(e.getAttribute('aria-label')||'')+(e.title||'')).includes(n));if(!e)throw Error('δεν βρέθηκε η σελίδα '+n);e.click()},n);await p.waitForTimeout(800);await scanText(y+' · '+n);}
 }
 await p.evaluate(n=>{const e=[...document.querySelectorAll('nav button,.sidebar button,aside button')].filter(e=>e.offsetParent)[0];e.click()});await p.waitForTimeout(500);
 await p.evaluate(()=>{const s=document.getElementById('scl295Year');s.value='2027';s.dispatchEvent(new Event('change',{bubbles:true}))});await p.waitForTimeout(1500);
 const tabs=await p.evaluate(()=>[...document.querySelectorAll('[role=tab]')].map(t=>t.innerText.trim().replace(/\s+/g,' ')));
 for(const want of ['Όλα 5','ADV 2','PROMO 2','EXP 1'])if(!tabs.some(t=>t.startsWith(want)))problems.push('λείπει η καρτέλα «'+want+'» (βρέθηκαν: '+tabs.join(' | ')+')');
 const plan=[['ADV',['hq','base-1','base-2']],['PROMO',['promo-1','promo-2']],['EXP',['exp-1']]];
 const actions={ADV:['[data-scl313="custom"]','[data-scl313="deal"]','[data-scl295="shelf"]','[data-scl295="planogram"]'],PROMO:['[data-scl313="custom"]','[data-scl313="deal"]','[data-scl295="shelf"]','[data-scl295="planogram"]'],EXP:['[data-scl295="initial"]']};
 for(const [tab,ids] of plan)for(const id of ids){
  await p.evaluate(t=>{const e=[...document.querySelectorAll('[role=tab]')].find(x=>x.innerText.trim().startsWith(t));e&&e.click()},tab);await p.waitForTimeout(500);
  const ok=await p.evaluate(id=>{const e=document.querySelector('[data-scl295="position"][data-card="'+id+'"],[data-scl295="pp-programme"][data-card="'+id+'"]');if(!e)return false;e.click();return true},id);await p.waitForTimeout(800);
  if(!ok){problems.push(id+': δεν βρέθηκε το κουμπί της θέσης');continue}
  await scanText(id);
  if(id==='hq')continue;
  for(const sel of actions[tab]){
   const r=await p.evaluate(sel=>{const e=document.querySelector('#plannerRoot '+sel);if(!e)return 'missing';if(e.disabled)return 'disabled';e.click();return 'clicked'},sel);
   log.push(id+' '+sel+' → '+r);
   if(r==='clicked'){await p.waitForTimeout(450);await scanText(id+' '+sel);
    const open=await p.evaluate(()=>[...document.querySelectorAll('.modal.open,[data-modal-card]')].some(e=>e.offsetParent));if(!open)problems.push(id+' '+sel+': δεν άνοιξε παράθυρο');
    await p.evaluate(()=>{['programModal','customModal','dealModal','sponsoredModal','planogramModal','negotiationModal'].forEach(i=>{try{closeModal(i)}catch(e){}})});await p.waitForTimeout(200);}
   else if(r==='missing'&&!(tab==='ADV'&&sel==='[data-scl295="planogram"]'))problems.push(id+' '+sel+': λείπει η ενέργεια');}
 }
 if(errors.length)problems.push('σφάλματα σελίδας: '+errors.slice(0,3).join(' | '));
 await b.close();
 console.log(log.join('\n'));
 if(problems.length){console.error('\nΠΡΟΒΛΗΜΑΤΑ ('+problems.length+'):\n'+problems.join('\n'));process.exit(1)}
 console.log('\nOK · όλες οι οθόνες και οι ενέργειες θέσεων ADV/PROMO/EXP άνοιξαν χωρίς σφάλμα');
})().catch(e=>{console.error(e);process.exit(1)});
