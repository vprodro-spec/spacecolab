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
s = s[:end] + blocks + s[end:]
# Always emit dependent UI modules in one canonical order, including on rebuilt downloads.
ordered = []
for script_id in ['scl290-installation', 'scl292-ui', 'scl293-ui', 'scl300-pharmaplus-core', 'scl295-pharmacy', 'scl297-actions-core', 'scl297-actions-ui', 'scl299-blocks-ui', 'scl300-pharmaplus-ui']:
    pattern = r'\s*<script id="' + script_id + r'">[\s\S]*?</script>'
    matches = re.findall(pattern, s)
    assert len(matches) == 1, f'Expected one {script_id}, found {len(matches)}'
    ordered.append(matches[0].strip())
    s = re.sub(pattern, '', s)
closing = re.search(r'</body>\s*</html>\s*$', s)
assert closing, 'Missing final document closing tags'
s = s[:closing.start()].rstrip() + '\n' + '\n'.join(ordered) + '\n</body>\n</html>\n'
s = re.sub(r'<title>.*?</title>', '<title>SpaceCoLab v301 · Pharmaplus</title>', s, count=1)
s = re.sub(r"content:'SpaceCoLab v(?:29[6789]|30[01])';", "content:'SpaceCoLab v301';", s)
# Disable only obsolete local enrichment; the canonical renderer and filters stay.
s = s.replace('function installChangesPatch(){var prev=', 'function installChangesPatch(){if(window.SCL299)return;var prev=')
s = s.replace('__change:change,', '__change:window.SCL299?window.SCL299.reason(change):change,')
p.write_text(s)
print('Built pharmacy actions and annual Pharmaplus v301.')
