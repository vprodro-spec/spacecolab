from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
p = root / 'index.html'
s = p.read_text()
for name in ['core', 'ui']:
    s = re.sub(r'\s*<script id="scl297-actions-' + name + r'">[\s\S]*?</script>', '', s)
blocks = ''.join('<script id="scl297-actions-' + name + '">\n' + (root / ('src/scl297-actions-' + name + '.js')).read_text() + '\n</script>\n' for name in ['core', 'ui'])
end = s.rfind('</body>')
s = s[:end] + blocks + s[end:]
s = re.sub(r'<title>.*?</title>', '<title>SpaceCoLab v297 · Pharmaplus</title>', s, count=1)
s = s.replace("content:'SpaceCoLab v296';", "content:'SpaceCoLab v297';")
p.write_text(s)
print('Built pharmacy actions v297.')
