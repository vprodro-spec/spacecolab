const fs=require('fs'),vm=require('vm'),cp=require('child_process');
const root=require('node:path').resolve(__dirname,'../..');
const {parseHTML}=require(root+'/node_modules/linkedom');
async function smoke(html,mode,fixtureState=null){
 const {document,HTMLElement,Event}=parseHTML(html);Object.defineProperty(document,'readyState',{value:'loading',writable:true});
 const errors=[],timers=[],calls=[],map=new Map();
 const storage={getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,String(v)),removeItem:k=>map.delete(k)};
 const loc=new URL('https://example.test/'+(mode==='hq'?'?hq=fixture-hq':mode==='pharmacy'?'?pharmacy=fixture-token':''));
 const client={rpc:async(name,args)=>{calls.push(name);let data=[];
 if(name==='hq_get_all_data')data={pharmacies:[],pharmacy_state:[],hq_programs:[],hq_changes_done:[],reports:[]};
 if(name==='scl290_hq_data')data={api_version:290,setup:[],months:[],deals:[],registry:[],installations:[],snapshots:[],base:{pharmacies:[],pharmacy_state:[],hq_programs:[],hq_changes_done:[],reports:[]}};
 if(name==='scl292_finance')data={year:args.p_year,rows:[],requests:[],history:[]};
 if(name==='get_pharmacy_by_token')data=[{id:'fixture-pharmacy',name:'Fixture',token:'fixture-token'}];
 if(name==='scl290_get_pharmacy')data={pharmacy_id:'fixture-pharmacy',pharmacy_name:'Fixture',registry:{legacy:false},installation:{version:1,service_from:'2026-10-01',positions:[{id:'hq',ordinal:0,type:'hq',screenFormat:'vertical',startsOn:'2026-10-01'},{id:'base-1',ordinal:1,type:'base',title:'Θέση 1',screenFormat:'vertical',startsOn:'2026-10-01'}]},state_json:fixtureState,snapshot_revision:fixtureState?1:0,available_years:[2026]};
 return{data,error:null};}};
 class Clock extends Date { constructor(...args){super(...(args.length?args:['2026-10-20T12:00:00Z']));} static now(){return new Date('2026-10-20T12:00:00Z').valueOf();} }
 const ctx={document,HTMLElement,Event,Date:Clock,Intl,URL,URLSearchParams,Blob,Map,Set,Promise,JSON,Array,Object,Number,String,Math,RegExp,console:{log:()=>{},warn:()=>{},error:()=>{}},location:loc,localStorage:storage,sessionStorage:storage,
 navigator:{clipboard:{writeText:async()=>{}},userAgent:'test'},supabase:{createClient:()=>client},setTimeout:(fn,ms,...args)=>{timers.push({fn,args,ms});return timers.length;},clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{},requestAnimationFrame:()=>0,cancelAnimationFrame:()=>{},
 addEventListener:()=>{},removeEventListener:()=>{},innerWidth:1280,innerHeight:900,getComputedStyle:()=>({display:'block',visibility:'visible',getPropertyValue:()=>''}),MutationObserver:class{observe(){}disconnect(){}},ResizeObserver:class{observe(){}disconnect(){}},
 alert:()=>{},confirm:()=>false,prompt:()=>null,print:()=>{},history:{replaceState:()=>{}},fetch:async()=>{throw Error('Network disabled in test')},open:()=>({document:{write:()=>{},close:()=>{}}})};ctx.window=ctx;ctx.globalThis=ctx;const c=vm.createContext(ctx);
 let i=0;for(const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){if(/\bsrc\s*=|application\/json/.test(m[1]))continue;try{new vm.Script(m[2],{filename:'script-'+(++i)}).runInContext(c,{timeout:2000});}catch(e){errors.push({phase:'script-'+i,error:e.message,stack:e.stack.split('\n').slice(0,4).join('\n')});}}
 try{vm.runInContext("SCL_ROUTING.hqAllowedKey='fixture-hq'",c);document.readyState='complete';document.dispatchEvent(new Event('DOMContentLoaded'));}catch(e){errors.push({phase:'domready',error:e.message});}
 for(let i=0;i<Math.min(45,timers.length);i++){const t=timers[i];if(t.ms>3500||typeof t.fn!=='function')continue;try{await t.fn(...t.args);}catch(e){errors.push({phase:'timer',error:e.message,stack:e.stack.split('\n').slice(0,4).join('\n')});}await new Promise(r=>setImmediate(r));}
 await new Promise(r=>setImmediate(r));
 try{if(mode==='hq')await vm.runInContext('scl212Load()',c);if(ctx.SCL292&&mode!=='locked')await ctx.SCL292.loadFinance(true);}catch(e){errors.push({phase:'load',error:e.message});}
 let state;try{state=vm.runInContext("({year:state.programYear,ready:!!window.SCL292,cloudReady:SCL_ROUTING.ready,financeLoaded:!!window.SCL292?.data,mode:sclMode()})",c);}catch(e){}
 return{ctx:c,document,mode,errors,state,notice:document.getElementById('scl290Notice')?.textContent,calls:[...new Set(calls)]};
}
module.exports={smoke};
