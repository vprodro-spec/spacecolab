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
