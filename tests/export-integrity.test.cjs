// v331.8.1 — Εξαγωγή αρχείου συσκευών / χρεώσεων: κάθε γραμμή παίρνει τον κωδικό τιμολόγησης του δικού της φαρμακείου,
// η σειρά είναι σταθερή, και αν κάτι δεν συμφωνεί δεν δημιουργείται αρχείο.
// Τρέχει τον πραγματικό κώδικα του index.html (εξάγεται από το αρχείο), χωρίς browser και χωρίς βάση.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.resolve(__dirname,'../index.html'),'utf8');
function grab(startMarker){const i=html.indexOf(startMarker);assert.ok(i>=0,'δεν βρέθηκε: '+startMarker);let d=0,j=html.indexOf('{',i),k=j;for(;k<html.length;k++){const c=html[k];if(c==='{')d++;else if(c==='}'){d--;if(!d)break;}}return html.slice(i,k+1);}
const exportSrc=grab('  async function exportPlayers(selectedOnly=false)');
const csvSrc=grab('    csv(rows){').replace(/^\s*csv\(rows\)/,'function csv(rows)');
const guardSrc=html.slice(html.indexOf('U.billingCodeProblems=function(){'),html.indexOf('\n',html.indexOf('U.billingCodeProblems=function(){')));
// τα 15 φαρμακεία με συσκευές (κωδικός τιμολόγησης → όνομα players)· το πλήθος θέσεων όπως στη βάση
const PH=[['106589','MANIKAROS',3],['115967','LIGNOS',3],['118407','MARTSOYKA_LYKOVRISI',3],['115001','MARTSOYKAS_MARIOS',3],['118416','MARTSOUKAS_GIANNIS',3],['111541','PAPANIKOLAOU_VYRONAS',3],['118410','PAPANIKOLAOU_PEIRAIAS',3],['115485','AGGELAKOPOYLOY',6],['116273','RES',3],['115875','ROYSSOY_FALIRO',3],['115875 1','ROYSSOY_PEIRAIAS',3],['118414','TREMOULIARIS_KALAMPOKA',3],['117653','TREMOYLIARIS_RODOKANAKI',3],['115801','TREMOYLIARIS_RIZARIOU',3],['116776','PAPANIKOLAOY_ELVETIAS',3]];
function fixture(){const registry=[],installations=[];PH.forEach(([code,pre,n],i)=>{const pid='pid-'+i;registry.push({id:'reg-'+i,pharmacy_id:pid,billing_code:code,name:'Φαρμακείο '+pre,address:'Οδός '+i,area:'Περιοχή '+i,player_prefix:pre});installations.push({pharmacy_id:pid,positions:Array.from({length:n},(_,k)=>({id:'p'+k,ordinal:k%3,category:k>=3?'PROMO':undefined,playerCode:pre+'_ADV'+k+'_P',contentCode:pre+'_ADV'+k+'_P',screenFormat:k%2?'horizontal':'vertical'}))});});return{registry,installations};}
function setup(hq,opts={}){const out={downloads:[],notices:[]};
 const R={hq,selected:new Set(opts.selected||[])},C={title:(o,c)=>'Θέση '+o+(c?' '+c:''),csv:null};
 const ctx={R,C,out,SCL292Core:{today:()=>'2026-11-18'},Intl,Date,String,Map,Set,Array,Object,Number,
  loadHQ:async()=>{if(opts.refreshFails)throw Error('offline');if(opts.after)opts.after(R);return R.hq;},
  configFor:pid=>(R.hq?.installations||[]).find(x=>String(x.pharmacy_id)===String(pid))||null,
  notice:(t,bad,src)=>out.notices.push({t,bad:!!bad,src}),download:(n,t)=>out.downloads.push({name:n,text:t})};
 vm.createContext(ctx);vm.runInContext(csvSrc+';C.csv=csv;'+exportSrc+';this.exportPlayers=exportPlayers;',ctx);
 return {out,run:sel=>ctx.exportPlayers(sel),R};}
function parse(text){const lines=text.replace(/^﻿/,'').split('\r\n');return lines.map(l=>l.slice(1,-1).split('";"'));}
function shuffle(a,seed){let s=seed;const r=()=>(s=(s*1664525+1013904223)%4294967296)/4294967296;for(let i=a.length-1;i>0;i--){const j=Math.floor(r()*(i+1));[a[i],a[j]]=[a[j],a[i]];}return a;}

test('κάθε γραμμή έχει τον κωδικό τιμολόγησης του δικού της φαρμακείου και συσκευές με το δικό του όνομα players',async()=>{
 const f=fixture(),t=setup(f);await t.run(false);
 assert.equal(t.out.downloads.length,1);const rows=parse(t.out.downloads[0].text);assert.equal(rows.length,1+48);
 const owner=new Map(PH.map(([c,p])=>[c,p]));
 for(const r of rows.slice(1)){assert.ok(owner.has(r[0]),'άγνωστος κωδικός '+r[0]);assert.ok(r[5].startsWith(owner.get(r[0])+'_'),r[0]+' ↔ '+r[5]);assert.equal(r[1],'Φαρμακείο '+owner.get(r[0]));}
 assert.match(t.out.downloads[0].name,/^Pharmaplus_players_2026-11-18_\d{4}\.csv$/);
});
test('η σειρά είναι σταθερή όποια σειρά κι αν επιστρέψει η βάση',async()=>{
 const ref=await(async()=>{const t=setup(fixture());await t.run(false);return t.out.downloads[0].text;})();
 for(let seed=1;seed<=60;seed++){const f=fixture();shuffle(f.registry,seed);shuffle(f.installations,seed+7);const t=setup(f);await t.run(false);assert.equal(t.out.downloads[0].text,ref,'seed '+seed);}
 const codes=parse(ref).slice(1).map(r=>r[0]),uniq=[...new Set(codes)];assert.deepEqual(uniq,[...uniq].sort((a,b)=>a.localeCompare(b,'el',{numeric:true})));
});
test('η εξαγωγή διαβάζει ξανά τη βάση: αλλαγή κωδικού μετά τη φόρτωση φαίνεται στο αρχείο',async()=>{
 const f=fixture(),t=setup(f,{after:R=>{R.hq.registry.find(r=>r.billing_code==='116273').billing_code='999001';}});await t.run(false);
 const rows=parse(t.out.downloads[0].text);assert.ok(rows.some(r=>r[0]==='999001'&&r[5].startsWith('RES_')));assert.ok(!rows.some(r=>r[0]==='116273'));
});
test('αν η ανανέωση αποτύχει δεν γίνεται εξαγωγή από παλιά δεδομένα',async()=>{const t=setup(fixture(),{refreshFails:true});await t.run(false);assert.equal(t.out.downloads.length,0);assert.match(t.out.notices.at(-1).t,/παλιά δεδομένα/);assert.equal(t.out.notices.at(-1).bad,true);});
test('λείπει κωδικός τιμολόγησης → σταματά, λέει ποιο φαρμακείο, δεν δημιουργεί αρχείο',async()=>{const f=fixture();f.registry.find(r=>r.billing_code==='116273').billing_code=null;const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,0);assert.match(t.out.notices.at(-1).t,/Λείπει κωδικός τιμολόγησης: Φαρμακείο RES/);});
test('ίδιος κωδικός σε 2 φαρμακεία → σταματά',async()=>{const f=fixture();f.registry.find(r=>r.billing_code==='116273').billing_code='115801';const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,0);assert.match(t.out.notices.at(-1).t,/115801 υπάρχει σε 2 φαρμακεία/);});
test('ίδιος κωδικός συσκευής δύο φορές → σταματά',async()=>{const f=fixture();f.installations[1].positions[0].playerCode=f.installations[0].positions[0].playerCode;const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,0);assert.match(t.out.notices.at(-1).t,/εμφανίζεται δύο φορές/);});
test('κενός κωδικός συσκευής → σταματά',async()=>{const f=fixture();f.installations[2].positions[1].playerCode='';const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,0);assert.match(t.out.notices.at(-1).t,/Λείπει κωδικός συσκευής/);});
test('συσκευή με άλλο όνομα players → κατεβαίνει αλλά με ορατή προειδοποίηση',async()=>{const f=fixture();f.installations[0].positions[0].playerCode='ALLO_ADV0_P';const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,1);assert.match(t.out.notices.at(-1).t,/Προσοχή: ALLO_ADV0_P/);});
test('εξαγωγή επιλεγμένων: μόνο τα επιλεγμένα, με σωστούς κωδικούς',async()=>{const f=fixture(),t=setup(f,{selected:['reg-7','reg-10']});await t.run(true);const rows=parse(t.out.downloads[0].text).slice(1);assert.equal(rows.length,9);assert.deepEqual([...new Set(rows.map(r=>r[0]))],['115485','115875 1']);assert.match(t.out.downloads[0].name,/_selected_/);});
test('σταματημένες θέσεις δεν εξάγονται, και φαρμακείο χωρίς ενεργές θέσεις δεν ζητά κωδικό',async()=>{const f=fixture();f.installations[0].positions.forEach(p=>p.stopsOn='2026-10-01');f.registry[0].billing_code=null;const t=setup(f);await t.run(false);assert.equal(t.out.downloads.length,1);assert.equal(parse(t.out.downloads[0].text).length,1+45);});
test('το κείμενο CSV ξεκινά με BOM, χωρίζει με ; και κάθε γραμμή έχει 10 στήλες',async()=>{const t=setup(fixture());await t.run(false);const txt=t.out.downloads[0].text;assert.equal(txt.charCodeAt(0),0xFEFF);for(const r of parse(txt))assert.equal(r.length,10);});

// χρεώσεις
function chargeGuard(rows,registry){const root={SCL290:{hq:{registry}}},U={visibleCharges:()=>rows};vm.runInNewContext(guardSrc,{U,root,Set,Map,String});return U.billingCodeProblems();}
const REG=[{pharmacy_id:'a',billing_code:'111541'},{pharmacy_id:'b',billing_code:'118407'}];
test('χρεώσεις: σωστοί κωδικοί → κανένα πρόβλημα',()=>{assert.equal(JSON.stringify(chargeGuard([{status:'finalized',pharmacy_id:'a',billing_code:'111541',pharmacy_name:'A'},{status:'finalized',pharmacy_id:'b',billing_code:'118407',pharmacy_name:'B'},{status:'planned',pharmacy_id:'b',billing_code:'',pharmacy_name:'B'}],REG)),'[]');});
test('χρεώσεις: λείπει κωδικός, ή η χρέωση έχει άλλον κωδικό από το μητρώο, ή ίδιος κωδικός σε 2 φαρμακεία → πρόβλημα',()=>{
 assert.match(chargeGuard([{status:'finalized',pharmacy_id:'a',billing_code:'',pharmacy_name:'A'}],REG)[0],/Λείπει κωδικός/);
 assert.match(chargeGuard([{status:'finalized',pharmacy_id:'a',billing_code:'118407',pharmacy_name:'A'}],REG)[0],/έχει κωδικό 118407 ενώ το μητρώο έχει 111541/);
 assert.ok(chargeGuard([{status:'finalized',pharmacy_id:'a',billing_code:'111541',pharmacy_name:'A'},{status:'finalized',pharmacy_id:'b',billing_code:'111541',pharmacy_name:'B'}],[{pharmacy_id:'a',billing_code:'111541'},{pharmacy_id:'b',billing_code:'111541'}]).some(x=>/2 φαρμακεία/.test(x)));
});
