"""Prepare only; preserve all existing hostpaths and the Portainer x-base."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

os.umask(0o077)
root = Path('/var/snap/docker/common/viperchat-hostpaths/sparse-echo-463-468-20261020')
private = root / 'private'
compose = Path('/var/snap/docker/common/var-lib-docker/volumes/portainer_data/_data/compose/24/docker-compose.yml')
manifest = json.loads((root / 'script/validation/sparse_echo_manifest_20261020.json').read_text())
names = ['chatwoot-uno-chatwoot-web-1', 'chatwoot-uno-chatwoot-worker-1', 'chatwoot-uno-chatwoot-worker-2']
assert (private / 'database.dump').stat().st_size > 1_000_000 and (private / 'database.catalog').stat().st_size > 0
inspection = json.loads(subprocess.check_output(['docker', 'inspect', *names]))
assert all(c['State']['Running'] for c in inspection) and len({c['Image'] for c in inspection}) == 1
assert compose.read_bytes() == (private / 'compose.before.yml').read_bytes()
(private / 'runtime.validated.before.json').write_text(json.dumps(inspection, indent=2))
lines = compose.read_text().splitlines(keepends=True)
start = next(i for i, line in enumerate(lines) if line.startswith('x-base: &base'))
for item in manifest:
    path = item['path']
    source = root / path
    assert hashlib.sha256(source.read_bytes()).hexdigest() == item['sha256'], path
    for container in names:
        current = subprocess.run(['docker', 'exec', container, 'cat', '/app/' + path], capture_output=True)
        if item['base_sha256'] is None:
            assert current.returncode != 0, path
        else:
            assert current.returncode == 0, path
            actual = hashlib.sha256(current.stdout.replace(b'\r\n', b'\n')).hexdigest()
            assert actual == item['base_sha256'], f'Active source differs from base: {container} {path} {actual}'
            saved = private / 'sources.before' / container / path
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(current.stdout)
    checked = subprocess.run(['docker', 'exec', '-i', names[0], 'ruby', '-c'], input=source.read_bytes(), capture_output=True)
    assert checked.returncode == 0, path
    end = next(i for i in range(start + 1, len(lines)) if re.match(r'^[a-zA-Z0-9_-]+:', lines[i]))
    existing = [i for i in range(start, end) if lines[i].strip().endswith(':/app/' + path + ':ro')]
    assert len(existing) <= 1
    mount = f'    - {source}:/app/{path}:ro\n'
    if existing:
        lines[existing[0]] = mount
    else:
        lines.insert(end, mount)
candidate = compose.with_name('docker-compose.sparse-echo-20261020.candidate.yml')
candidate.write_text(''.join(lines))
subprocess.run(['docker', 'compose', '-p', 'chatwoot-uno', '-f', str(candidate), 'config', '--quiet'], check=True)
(private / 'compose.candidate.yml').write_bytes(candidate.read_bytes())
print(json.dumps({'prepared': True, 'files': len(manifest), 'image': inspection[0]['Image']}))
