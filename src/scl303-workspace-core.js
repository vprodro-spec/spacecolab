/* Presentation and filtering only; no programme or charge mutation. */
(function(root){
'use strict';
const C={
 format:value=>['vertical','portrait','P'].includes(value)?'portrait':['horizontal','landscape','L'].includes(value)?'landscape':'—',
 norm:value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('el').trim(),
 position(id){const n=id==='hq'||id==='pharmaplus'?0:/^base-\d+$/.test(id)?Number(id.split('-')[1]):/^extra-\d+$/.test(id)?Number(id.split('-')[1])+2:null;return n===0?'Pharmaplus':n?'Θέση '+n:'';},
 filename(row,library){if(row.file_name||row.content_filename)return row.file_name||row.content_filename;if(['deal','pharmaplus'].includes(row.final_type))return '';const t=library?.themes?.find(t=>[t.id,t.key,t.title,...(t.aliases||[])].includes(row.final_title));return t?.files?.[row.position_orientation]||'';},
 kind(row){return row.final_type==='pharmaplus'?(['main','campaign'].includes(row.pp_kind)?'campaign':row.pp_kind==='empty'?'empty':'thematic'):row.final_type;},
 kinds:{basic:'Βασικό πρόγραμμα',custom:'Εξατομίκευση',deal:'Συμφωνία προμηθευτή',campaign:'Καμπάνια Pharmaplus',thematic:'Θεματική Pharmaplus',empty:'Προσεχώς'},
 status:{planned:'Προγραμματισμένη χρέωση',finalized:'Οριστικοποιημένη χρέωση',cancelled:'Ακυρωμένη χρέωση'},
 defaults(month){return {months:[month],pharmacies:null,status:'',query:'',orientation:'',kind:'',reason:'',area:''};},
 filter(rows,f){return rows.filter(r=>(f.months===null||f.months.includes(Number(r.month)))&&(f.pharmacies===null||f.pharmacies.includes(r.pharmacy_id))&&(!f.status||f.status==='pending'&&!r.complete||f.status==='done'&&r.complete||f.status==='material'&&r.material||f.status===r.status)&&(!f.orientation||C.format(r.position_orientation)===f.orientation)&&(!f.kind||(r.kind||r.category)===f.kind)&&(!f.reason||r.reason===f.reason)&&(!f.query||C.norm([r.pharmacy_name,r.billing_code,r.player_code,r.file,r.final_title,r.description,r.position_name].join(' ')).includes(C.norm(f.query))));},
 sum(rows){const cents=a=>Math.round(Number(a||0)*100);const out={charges:0,credits:0,net:0,planned:0};for(const r of rows){if(r.status==='finalized'){if(Number(r.amount)<0)out.credits+=cents(r.amount);else out.charges+=cents(r.amount);}if(r.status==='planned')out.planned+=cents(r.amount);}out.net=out.charges+out.credits;return Object.fromEntries(Object.entries(out).map(([k,v])=>[k,v/100]));},
 /* Empty selection means no rows. Only an explicit null means all. */
 toggle(values,key,checked,options){const set=new Set(values===null?options:values);checked?set.add(key):set.delete(key);return options.every(x=>set.has(x))?null:[...set];}
};root.SCL303Core=C;if(typeof module!=='undefined')module.exports=C;
})(typeof window!=='undefined'?window:globalThis);
