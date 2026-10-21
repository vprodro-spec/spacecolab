from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
s=re.sub(r'<script id="scl290-installation">[\s\S]*?</script>',lambda m:'<script id="scl290-installation">\n'+(root/'src/scl294-installation.js').read_text()+'\n</script>',s)
s=s.replace('v293 ·','v294 ·')
s=s.replace('<title>SpaceCoLab Stable Rollback</title>','<title>SpaceCoLab · Pharmaplus</title>')
# Route old overview/open-link handlers through the maintained canonical helper too.
s=re.sub(r"location\.href\.split\('\?'\)\[0\]\.split\('#'\)\[0\]\s*\+\s*'\?pharmacy='\s*\+\s*encodeURIComponent\(token\)", 'sclBuildPharmacyLink(token)', s)
p.write_text(s)
print('Built HQ registry and screens v294.')
