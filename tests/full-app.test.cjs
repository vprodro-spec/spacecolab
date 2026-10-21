const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8');
test('whole published app boots without browser in locked, HQ and installed pharmacy routes',async t=>{
 for(const mode of ['locked','hq','pharmacy'])await t.test(mode,async()=>{
  const x=await smoke(html,mode);assert.deepEqual(x.errors,[]);assert.equal(x.state.mode,mode);
  if(mode!=='locked'){assert.equal(x.state.financeLoaded,true);assert.ok(x.calls.includes('scl292_finance'));}
  if(mode==='hq')assert.ok(x.calls.includes('scl292_get_done'));
  if(mode==='pharmacy')assert.equal(x.state.cloudReady,true);
 });
});
test('full app applies cutoff after legacy wrappers and allows next-year January',async()=>{
 const card={id:'base-1',type:'base',title:'Θέση 1',initialPlanLocked:true,initialPlanType:'own',basicSchedule:Array(12).fill('Ανοσοποιητικό'),simpleSchedule:Array(12).fill('Ανοσοποιητικό'),pendingSimpleSchedule:Array(12).fill('Ανοσοποιητικό'),simpleConfirmed:true,confirmedDeals:[],sponsoredShelves:[]};
 const x=await smoke(html,'pharmacy',{turnover:500000,setupLocked:true,totalCounters:2,cards:[card]});assert.deepEqual(x.errors,[]);
 assert.equal(vm.runInContext('operationalMonthEditable(10)',x.ctx),false);
 assert.equal(vm.runInContext('operationalMonthEditable(11)',x.ctx),true);
 assert.equal(vm.runInContext("isCustomReadOnlyMonth(state.cards.find(c=>c.id==='base-1'),10)",x.ctx),true);
 assert.equal(vm.runInContext("firstAvailableDealStart(state.cards.find(c=>c.id==='base-1'))",x.ctx),11);
 vm.runInContext('state.programYear=2027',x.ctx);
 assert.equal(vm.runInContext('operationalMonthEditable(0)',x.ctx),true);
 assert.equal(vm.runInContext("firstAvailableDealStart(state.cards.find(c=>c.id==='base-1'))",x.ctx),0);
});
test('legacy periodic HQ code preserves selected year and campaign years in the DOM',async()=>{
 const x=await smoke(html,'hq');
 const select=x.document.getElementById('scl212Year');
 Object.defineProperty(select,'value',{value:'2027',writable:true,configurable:true});
 const title=x.document.createElement('span');title.textContent='Καμπάνια 2027 · ιστορικό 2025';
 x.document.getElementById('sclHqShell').append(title);
 for(let i=0;i<3;i++)vm.runInContext('sclForceHqYearTextV191()',x.ctx);
 assert.equal(select.value,'2027');
 assert.equal(title.textContent,'Καμπάνια 2027 · ιστορικό 2025');
 assert.equal([...select.options].find(o=>o.value==='2027').textContent,'2027');
});
test('changing HQ year clears the old campaign editor and loads the selected year',async()=>{
 const x=await smoke(html,'hq');
 const select=x.document.getElementById('scl212Year');
 Object.defineProperty(select,'value',{value:'2027',writable:true,configurable:true});
 await vm.runInContext("SCL300.start('create','2027-01-01')",x.ctx);assert.ok(x.document.getElementById('scl300Dialog')); 
 vm.runInContext(`
  SCL231.campaigns=[{month:0,title:'Old campaign'}];SCL231.selectedMonth=0;
  window.campaignYears=[];window.campaignRequests=[];
  const originalTestRpc=sb.rpc;
  sb.rpc=async function(name,args){
   if(name==='scl300_pp_hq'){
    campaignYears.push(args.p_year);
    return new Promise(resolve=>campaignRequests.push(resolve));
   }
   return originalTestRpc(name,args);
  };
 `,x.ctx);
 const first=vm.runInContext('SCL292.reloadCampaignYear()',x.ctx);
 assert.equal(vm.runInContext('SCL231.campaigns.length',x.ctx),0);
 assert.equal(x.document.getElementById('scl300Dialog'),null);
 assert.equal(vm.runInContext('SCL231.selectedMonth',x.ctx),null);
 select.value='2028';
 const second=vm.runInContext('SCL292.reloadCampaignYear()',x.ctx);
 vm.runInContext("campaignRequests[1]({data:{year:2028,records:[{month_on:'2028-01-01',campaign_id:'c',campaign:{title:'2028 campaign'},thematic:{}}],pharmacies:[],history:[],today:'2026-10-20'},error:null})",x.ctx);await second;
 vm.runInContext("campaignRequests[0]({data:{year:2027,records:[{month_on:'2027-01-01',campaign_id:'c',campaign:{title:'Late 2027 campaign'},thematic:{}}],pharmacies:[],history:[],today:'2026-10-20'},error:null})",x.ctx);await first;
 assert.deepEqual(Array.from(vm.runInContext('campaignYears',x.ctx)),[2027,2028]);
 assert.equal(vm.runInContext('SCL231.campaigns[0].title',x.ctx),'2028 campaign');
});
