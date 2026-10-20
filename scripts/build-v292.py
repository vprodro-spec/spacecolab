from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
p = root / 'index.html'
s = p.read_text()
if '<!-- v292 integration -->' not in s:
    s=s.replace('function renderEconomics(){','function renderEconomics(){\n  if(window.SCL292&&window.SCL292.renderEconomics())return;',1)
    s=s.replace('function renderBilling(){','function renderBilling(){if(window.SCL292&&window.SCL292.renderBilling())return;')
    s=s.replace("const SCL_DEFAULT_YEAR_V190 = 2026;", "const SCL_DEFAULT_YEAR_V190 = Number(SCL292Core.today().slice(0,4));")
    s=s.replace("const SCL_DEFAULT_YEAR_V190=2026;", "const SCL_DEFAULT_YEAR_V190=Number(SCL292Core.today().slice(0,4));")
    s=re.sub(r'function sclForceDefaultYearV190\(\)\{.*?\n\}', "function sclForceDefaultYearV190(){\n  if(typeof state!=='undefined')state.programYear=SCL292Core.year(state.programYear);\n}",s,count=1,flags=re.S)
    s=s.replace("return Number(document.getElementById('scl212Year')?.value||2026)","return SCL292Core.year(document.getElementById('scl212Year')?.value)")
    s=re.sub(r'function isHistoryYear\(\)\{.*?\n\}',"function isHistoryYear(){return Number(state.programYear)<Number(SCL292Core.today().slice(0,4));\n}",s,count=1,flags=re.S)
    s=s.replace("copy.mode='basic';\n  return copy;", "copy.mode='basic';\n  copy.initialPlanLocked=copy.type==='hq';\n  copy.initialPlanType='';\n  copy.pendingInitialSchedule=clone(copy.basicSchedule||[]);\n  delete copy._scl292Reset;delete copy._scl292ResetApplied;\n  return copy;",1)
    s=s.replace("sclLoadPharmacyMode=function(){return loadPharmacy().catch(()=>{});};", "sclLoadPharmacyMode=function(){return loadPharmacy(SCL292Core.year(new URLSearchParams(location.search).get('year'))).catch(()=>{});};")
    s=s.replace("const context=await api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:y});", "let context=await api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:y});\n      const firstYear=Number(context.installation?.service_from?.slice(0,4));\n      if(!R.context&&firstYear>y){y=firstYear;context=await api('scl290_get_pharmacy',{p_token:SCL_ROUTING.pharmacyToken,p_year:y});}")
    s=s.replace("state.availableYears=Array.from(new Set([...(state.availableYears||[]),y])).sort();", "state.availableYears=Array.from(new Set([...(context.available_years||[]),y])).sort();")
    s=s.replace("if(installed())applyInstallation();\n      state.availableYears", "state.programYear=y;\n      if(installed())applyInstallation();\n      state.availableYears")
    s=s.replace("R.snapshots[y]=result.snapshot_revision;succeeded=true;", "R.snapshots[y]=result.snapshot_revision;succeeded=true;\n      state.cards.forEach(c=>{if(c._scl292ResetApplied){delete c._scl292ResetApplied;delete c._scl292Reset;}});\n      if(root.SCL292){root.SCL292.invalidate();root.SCL292.loadFinance(true).catch(()=>{});}")
    old="sclStatePayload=function(){const p=oldPayload.apply(this,arguments);if(installed())p._scl290InstallationVersion=R.context.installation.version;return p;};"
    new="sclStatePayload=function(){const p=oldPayload.apply(this,arguments);if(installed()){p._scl290InstallationVersion=R.context.installation.version;p.cards.forEach(c=>{if(!c.initialPlanLocked){const saved=R.context.state_json?.cards?.find(x=>x.id===c.id);c.pendingInitialSchedule=C.clone(saved?.pendingInitialSchedule||[]);}});}return p;};"
    assert old in s
    s=s.replace(old,new)
    s=s.replace("function fixedCosts(){return COST.platform+COST.basicAnnual+(window.scl290AnnualExtraCost?window.scl290AnnualExtraCost():extraCount()*COST.extraMonthly*12);}","function fixedCosts(){const cfg=window.SCL290?.context?.installation;return cfg?SCL292Core.total(SCL292Core.fixed(cfg,state.programYear)):COST.platform+COST.basicAnnual+extraCount()*COST.extraMonthly*12;}")
    # The installed v290 data guard is retained. The later reset implementation is replaced in-place.
    s=re.sub(r'  sclResetCurrentPharmacyYearV190=async function\(\)\{if\(!isPh\(\).*?\n  const oldSummary=',"  sclResetCurrentPharmacyYearV190=async function(){return root.SCL292?.requestReset();};\n  const oldSummary=",s,count=1)
    s=s.replace('<head>','<head>\n<!-- v292 integration -->',1)

for name in ['core','ui']:
    pattern=rf'<script id="scl292-{name}">[\s\S]*?</script>'
    s=re.sub(pattern,'',s)
if '<!-- v292 central completion -->' not in s:
    s=s.replace("function scl212TaskId(a){return a.filter(Boolean).join('|')}","function scl212TaskId(a){if(a[0]==='change'){const r=(typeof scl212VisibleChanges==='function'?scl212VisibleChanges():SCL212.months||[]).find(r=>String(r.pharmacy_id)===String(a[1])&&String(r.position_id)===String(a[2])&&Number(r.month)===Number(a[3]));if(r)return SCL292Core.taskKey({...r,year:r.year||scl212Year()});}return a.filter(x=>x!==null&&x!==undefined).join('|')}")
    s=re.sub(r'function scl213LoadDone\(\)\{.*?\n\}',"function scl213LoadDone(){if(window.SCL292)window.SCL292.loadDone().catch(()=>{});\n}",s,count=1,flags=re.S)
    s=re.sub(r'function scl213SaveDone\(\)\{.*?\n\}',"function scl213SaveDone(){return window.SCL292?.saveDone();\n}",s,count=1,flags=re.S)
    s=re.sub(r'  function taskId\(r\)\{try\{if\(typeof scl212TaskId.*?\n',"  function taskId(r){return SCL292Core.taskKey({...r,year:r.year||scl212Year()});}\n",s,count=1)
    s=s.replace('const visualDone=done||past;', 'const visualDone=done;')
    s=s.replace('${past?\'disabled title="Ιστορικό task — παρελθών μήνας"\':\'\'}','')
    s=re.sub(r"function asOfDate\(\)\{var v='';.*?return new Date\(\);\}", 'function asOfDate(){return new Date();}',s)
    s=s.replace('<head>','<head>\n<!-- v292 central completion -->',1)
s=s.replace('Κλείδωμα 5 μέρες πριν ξεκινήσει κάθε μήνας.','Αλλαγές έως και τις 15 του προηγούμενου μήνα.')
s=s.replace('Έχει περάσει το cut-off των 5 ημερών.','Έχει περάσει η προθεσμία της 15ης του προηγούμενου μήνα.')
core='<script id="scl292-core">\n'+(root/'src/scl292-core.js').read_text()+'\n</script>\n'
ui='<script id="scl292-ui">\n'+(root/'src/scl292-ui.js').read_text()+'\n</script>\n'
s=s.replace('<head>','<head>\n'+core,1)
end=s.rfind('</body>')
assert end>0
s=s[:end]+ui+s[end:]
p.write_text(s)
print('Built inline v292 modules; single-file delivery retained.')
