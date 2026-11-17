const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {smoke}=require('./fixtures/full-app.cjs');
const html=fs.readFileSync('index.html','utf8'),seed=JSON.parse(fs.readFileSync('data/library-seed.json','utf8'));
const theme=seed.themes.find(t=>t.status==='available').key;
const card=(id,title)=>({id,type:'base',title,initialPlanLocked:true,basicSchedule:Array(12).fill(theme),simpleSchedule:Array(12).fill(theme),simpleConfirmed:false,confirmedDeals:[],preagreements:[],sponsoredShelves:[]});
const tick=async()=>{for(let i=0;i<16;i++)await new Promise(r=>setImmediate(r));};

test('pharmacy cards show whether each position is active, starting soon or paused',async()=>{
 const cards=[card('base-1','Θέση 1'),card('base-2','Θέση 2'),card('base-3','Θέση 3'),card('base-4','Θέση 4')];
 const x=await smoke(html,'pharmacy',{turnover:500000,cards},async n=>{
  if(n==='scl290_get_pharmacy')return {data:{pharmacy_id:'fixture-pharmacy',pharmacy_name:'Fixture',registry:{legacy:false},installation:{version:1,service_from:'2026-01-01',positions:[
   {id:'hq',ordinal:0,type:'hq',title:'Pharmaplus',screenFormat:'vertical',startsOn:'2026-01-01'},
   {id:'base-1',ordinal:1,type:'base',title:'Θέση 1',screenFormat:'vertical',startsOn:'2026-01-01'},
   {id:'base-2',ordinal:2,type:'base',title:'Θέση 2',screenFormat:'vertical',startsOn:'2026-01-01',stopsOn:'2027-02-01'},
   {id:'base-3',ordinal:3,type:'base',title:'Θέση 3',screenFormat:'vertical',startsOn:'2026-01-01',stopsOn:'2026-10-01'},
   {id:'base-4',ordinal:4,type:'base',title:'Θέση 4',screenFormat:'vertical',startsOn:'2026-12-01'}]},state_json:{turnover:500000,cards},snapshot_revision:1,available_years:[2026]},error:null};
 });
 await tick();assert.deepEqual(x.errors.filter(e=>!/Node is not defined|matchMedia is not defined/.test(e.error)),[]);
 const chip=id=>{const c=x.document.querySelector('.scl295-position-card[data-scl330-id="'+id+'"],.scl295-position-card:has([data-card="'+id+'"])');return c?.querySelector('.scl3318-state');};
 const read=id=>({text:chip(id)?.textContent.trim(),state:chip(id)?.dataset.state});
 assert.deepEqual(read('base-1'),{text:'Ενεργή',state:'ok'});
 assert.deepEqual(read('base-2'),{text:'Ενεργή · παύση από Φεβ 2027',state:'warn'});
 assert.deepEqual(read('base-3'),{text:'Σε παύση από Οκτ 2026',state:'off'});
 assert.deepEqual(read('base-4'),{text:'Ξεκινά Δεκ 2026',state:'soon'});
});
