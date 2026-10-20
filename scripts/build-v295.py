from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
s=re.sub(r'\s*<script id="scl295-pharmacy">[\s\S]*?</script>','',s)
s=re.sub(r'<title>.*?</title>','<title>SpaceCoLab v295 · Pharmaplus</title>',s,count=1)
s=s.replace("content:'v247 · pharmaplus rows in main changes table · HQ reference layout';","content:'SpaceCoLab v295';")
s=s.replace("content:'v178 · GitHub Pages ready';","content:none;")
block='<script id="scl295-pharmacy">\n'+(root/'src/scl295-pharmacy.js').read_text()+'\n</script>\n'
end=s.rfind('</body>');s=s[:end]+block+s[end:];p.write_text(s)
print('Built pharmacy experience v295.')
