from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
p = root / 'index.html'
s = p.read_text()
for name in ['core', 'ui']:
    s = re.sub(r'\s*<script id="scl297-actions-' + name + r'">[\s\S]*?</script>', '', s)
blocks = ''.join('<script id="scl297-actions-' + name + '">\n' + (root / ('src/scl297-actions-' + name + '.js')).read_text() + '\n</script>\n' for name in ['core', 'ui'])
s = re.sub(r'\s*<script id="scl299-blocks-ui">[\s\S]*?</script>', '', s)
blocks += '<script id="scl299-blocks-ui">\n' + (root / 'src/scl299-blocks-ui.js').read_text() + '\n</script>\n'
for name in ['core','ui']:
    s = re.sub(r'\s*<script id="scl300-pharmaplus-' + name + r'">[\s\S]*?</script>', '', s)
    blocks += '<script id="scl300-pharmaplus-' + name + '">\n' + (root / ('src/scl300-pharmaplus-' + name + '.js')).read_text() + '\n</script>\n'
end = s.rfind('</body>')
for name in ['core','ui']:
    s = re.sub(r'\s*<script id="scl302-overview-' + name + r'">[\s\S]*?</script>', '', s)
    blocks += '<script id="scl302-overview-' + name + '">\n' + (root / ('src/scl302-overview-' + name + '.js')).read_text() + '\n</script>\n'
end = s.rfind('</body>')
for module in ['scl304-workspace-core','scl303-workspace-core','scl303-hq-workspace','scl304-workspace','scl304-presentation','scl305-finance-core','scl305-finance-ui','scl306-polish']:
    s = re.sub(r'\s*<script id="' + module + r'">[\s\S]*?</script>', '', s)
    blocks += '<script id="' + module + '">\n' + (root / ('src/' + module + '.js')).read_text() + '\n</script>\n'
end = s.rfind('</body>')
s = s[:end] + blocks + s[end:]
# Always emit dependent UI modules in one canonical order, including on rebuilt downloads.
ordered = []
for script_id in ['scl290-installation', 'scl292-ui', 'scl293-ui', 'scl300-pharmaplus-core', 'scl295-pharmacy', 'scl297-actions-core', 'scl297-actions-ui', 'scl299-blocks-ui', 'scl300-pharmaplus-ui', 'scl302-overview-core', 'scl302-overview-ui', 'scl304-workspace-core', 'scl303-workspace-core', 'scl303-hq-workspace', 'scl304-workspace', 'scl304-presentation', 'scl305-finance-core', 'scl305-finance-ui','scl306-polish']:
    pattern = r'\s*<script id="' + script_id + r'">[\s\S]*?</script>'
    matches = re.findall(pattern, s)
    assert len(matches) == 1, f'Expected one {script_id}, found {len(matches)}'
    ordered.append(matches[0].strip())
    s = re.sub(pattern, '', s)
closing = re.search(r'</body>\s*</html>\s*$', s)
assert closing, 'Missing final document closing tags'
s = s[:closing.start()].rstrip() + '\n' + '\n'.join(ordered) + '\n</body>\n</html>\n'
s = re.sub(r'<title>.*?</title>', '<title>SpaceCoLab v306 · Pharmaplus</title>', s, count=1)
s = re.sub(r"content:'SpaceCoLab v(?:29[6789]|30[0123456])';", "content:'SpaceCoLab v306';", s)
for fn in ['renderOverviewRoom250','renderStats250','renderTodo250']:
    needle='function '+fn+'(){'
    guard='if(window.SCL302?.installed)return window.SCL302.render();'
    s=s.replace(needle+guard,needle).replace(needle,needle+guard)
# Disable only obsolete local enrichment; the canonical renderer and filters stay.
s = s.replace('function installChangesPatch(){var prev=', 'function installChangesPatch(){if(window.SCL299)return;var prev=')
s = s.replace('__change:change,', '__change:window.SCL299?window.SCL299.reason(change):change,')
# Retire the old mode without changing content-change detection or the billing ledger.
s = re.sub(r'<select id="scl212OpsMode"[\s\S]*?</select>', '', s, count=1)
s = s.replace("function scl212OpsMode(){return document.getElementById('scl212OpsMode')?.value||'manual_monthly'}", "function scl212OpsMode(){return 'manual_monthly'}")
old = 'function renderChanges(){\n    if(!isHQ())return;\n    ensureDefaultMonth();'
new = 'function renderChanges(){\n    if(window.SCL303?.installed)return window.SCL303.renderChanges();\n    if(!isHQ())return;\n    ensureDefaultMonth();'
s = s.replace(old, new)
# Preserve the hidden legacy target until its obsolete renderer is removed.
s = s.replace('<summary>Debug / Raw plan</summary>', '<summary>Αρχείο συμβατότητας</summary>')
s = s.replace("'Cloud OK'","'Συνδεδεμένο'").replace("'Cloud error'","'Σφάλμα σύνδεσης'").replace("'Cloud'}</strong>","'Σύνδεση'}</strong>").replace('HQ φορτώθηκε.','Τα στοιχεία των κεντρικών ενημερώθηκαν.').replace('Σφάλμα Supabase save: ','Σφάλμα αποθήκευσης: ').replace('σφάλμα save','σφάλμα αποθήκευσης')
s = s.replace('SpaceCoLab — HQ Mode','SpaceCoLab · Κεντρικά Pharmaplus').replace('Ανανέωση από cloud','Ανανέωση').replace('>auto 30s<','>Αυτόματη ενημέρωση<')
s = s.replace("function formatMeta(fmt){const f=SCREEN_FORMATS[fmt]||null;return f?`${f.label} • ${f.tag} • ${f.shelves}`:'Δεν έχει οριστεί format';}", "function formatMeta(fmt){return fmt==='vertical'?'portrait':fmt==='horizontal'?'landscape':'Δεν έχει οριστεί προσανατολισμός';}")
s = s.replace('Οριζόντια οθόνη • 16:9 • 1920×1080','landscape • 16:9 • 1920×1080').replace('Κάθετη οθόνη • 9:16 • 1080×1920','portrait • 9:16 • 1080×1920')
landing = '''<div id="sclLanding" class="scl-access-card">
  <div class="scl-landing-hero"><div class="scl-landing-logo-main">SPACE<span class="thin">COLL</span>AB</div><div class="scl-landing-logo-sub">Διαχείριση προγραμμάτων οθονών</div></div>
  <div class="scl-login-grid">
    <section class="scl-login-card primary"><h2 class="scl-login-title">Κεντρικά Pharmaplus</h2><div class="scl-login-form"><label for="sclHqKeyInput">Κωδικός πρόσβασης</label><input id="sclHqKeyInput" type="password" autocomplete="current-password" placeholder="Κωδικός πρόσβασης"><button id="sclOpenHqBtn" class="dark" type="button">Είσοδος</button></div></section>
    <section class="scl-login-card"><h2 class="scl-login-title">Φαρμακείο</h2><p class="scl-login-desc">Άνοιξε τον προσωπικό σύνδεσμο που σου έστειλαν τα κεντρικά.</p><details><summary>Είσοδος με κωδικό</summary><div class="scl-login-form"><label for="sclPharmacyTokenInput">Κωδικός φαρμακείου</label><input id="sclPharmacyTokenInput" placeholder="Κωδικός φαρμακείου"><button id="sclOpenPharmacyBtn" type="button">Είσοδος</button></div></details></section>
  </div>
</div>

'''
s = re.sub(r'<div id="sclLanding" class="scl-access-card">[\s\S]*?(?=<div id="sclHqShell")', lambda _:landing, s, count=1)
s = s.replace('      \n      <button id="scl212Refresh"', '\n      <button id="scl212Refresh"')
p.write_text(s)
print('Built connected HQ workspace v306.')
