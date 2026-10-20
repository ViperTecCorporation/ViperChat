"""Prepare, do not deploy. Sources/configuration backups are restricted to root."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

os.umask(0o077)
root = Path('/var/snap/docker/common/viperchat-hostpaths/contact-phone-change-20261020')
private = root / 'private'
compose = Path('/var/snap/docker/common/var-lib-docker/volumes/portainer_data/_data/compose/24/docker-compose.yml')
names = ['chatwoot-uno-chatwoot-web-1', 'chatwoot-uno-chatwoot-worker-1', 'chatwoot-uno-chatwoot-worker-2']
assert (private / 'database.dump').stat().st_size > 1_000_000
assert (private / 'database.catalog').stat().st_size > 0
manifest = json.loads((root / 'script/validation/contact_phone_change_manifest_20261020.json').read_text())
inspection = json.loads(subprocess.check_output(['docker', 'inspect', *names]))
assert all(c['State']['Running'] for c in inspection)
assert len({c['Image'] for c in inspection}) == 1
# This preparation was explicitly audited with no prior application binds.
assert all(not c['Mounts'] for c in inspection), 'Reaudit existing binds before changing Compose'
(private / 'runtime.before.json').write_text(json.dumps(inspection, indent=2))
before = private / 'compose.before.yml'
if not before.exists():
    before.write_bytes(compose.read_bytes())
assert before.read_bytes() == compose.read_bytes(), 'Compose changed since backup'
for item in manifest:
    path = item['path']
    source = root / path
    assert hashlib.sha256(source.read_bytes()).hexdigest() == item['sha256'], path
    current = subprocess.run(['docker', 'exec', names[0], 'cat', '/app/' + path], capture_output=True)
    if item['base_sha256'] is None:
        assert current.returncode != 0, 'New service already exists; inspect it'
    else:
        assert current.returncode == 0, path
        saved = private / 'sources.before' / path
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_bytes(current.stdout)
        actual = hashlib.sha256(current.stdout.replace(b'\r\n', b'\n')).hexdigest()
        assert actual == item['base_sha256'], f'Active source differs from patch base: {path} {actual}'
    checked = subprocess.run(['docker', 'exec', '-i', names[0], 'ruby', '-c'], input=source.read_bytes(), capture_output=True)
    assert checked.returncode == 0, path

text = before.read_text()
assert 'x-base: &base' in text
lines = text.splitlines(keepends=True)
start = next(i for i, line in enumerate(lines) if line.startswith('x-base: &base'))
end = next(i for i in range(start + 1, len(lines)) if re.match(r'^[a-zA-Z0-9_-]+:', lines[i]))
assert not any(re.match(r'^  volumes:', line) for line in lines[start:end]), 'Reaudit existing base volumes'
mounts = ['  volumes:\n'] + [f"    - {root / item['path']}:/app/{item['path']}:ro\n" for item in manifest]
candidate = compose.with_name('docker-compose.contact-phone-change-20261020.candidate.yml')
candidate.write_text(''.join(lines[:end] + mounts + ['\n'] + lines[end:]))
subprocess.run(['docker', 'compose', '-p', 'chatwoot-uno', '-f', str(candidate), 'config', '--quiet'], check=True)
(private / 'compose.candidate.yml').write_bytes(candidate.read_bytes())
print(json.dumps({'prepared': True, 'files': len(manifest), 'image': inspection[0]['Image'], 'candidate': str(candidate)}))
