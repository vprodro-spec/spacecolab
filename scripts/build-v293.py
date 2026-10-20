from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
for name in ['core','ui']:
 s=re.sub(rf'<script id="scl293-{name}">[\s\S]*?</script>','',s)
# Display-only labels; storage keys and finance calculations remain unchanged.
if '<!-- v293 library integration -->' not in s:
 s=s.replace('<head>','<head>\n<!-- v293 library integration -->',1)
 for expression in ['row.label','s.label']:
  s=s.replace('esc('+expression+')','esc(window.scl293Title?window.scl293Title('+expression+'):'+expression+')')
 s=s.replace('<div class="theme">${esc(r.__theme)}</div></td>', '<div class="theme">${esc(window.scl293Title?window.scl293Title(r.__theme):r.__theme)}</div>${window.scl293FileHtml?window.scl293FileHtml(r):\'\'}</td>')
 # Custom month labels only, never the underlying data attributes / values.
 s=s.replace('esc(displayLabel(t,mech))','esc(window.scl293Title?window.scl293Title(displayLabel(t,mech)):displayLabel(t,mech))')
core='<script id="scl293-core">\n'+(root/'src/scl293-core.js').read_text()+'\n</script>\n'
ui='<script id="scl293-ui">\n'+(root/'src/scl293-ui.js').read_text()+'\n</script>\n'
s=s.replace('<head>','<head>\n'+core,1)
end=s.rfind('</body>');s=s[:end]+ui+s[end:];p.write_text(s)
print('Built shared library v293.')
