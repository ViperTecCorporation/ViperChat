"""Scoped hostpath deployment. Back up before prepare; never restore the database automatically."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlparse

os.umask(0o077)
root = Path('/var/snap/docker/common/viperchat-hostpaths/meta-echo-event-460-20261020')
private = root / 'private'
private.mkdir(mode=0o700, exist_ok=True)
compose = Path('/var/snap/docker/common/var-lib-docker/volumes/portainer_data/_data/compose/24/docker-compose.yml')
candidate = compose.with_name('docker-compose.event-460.candidate.yml')
manifest = json.loads((root / 'script/validation/event_460_manifest_20261020.json').read_text())
names = ['chatwoot-uno-chatwoot-web-1', 'chatwoot-uno-chatwoot-worker-1', 'chatwoot-uno-chatwoot-worker-2']


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def inspected():
    rows = json.loads(subprocess.check_output(['docker', 'inspect', *names]))
    assert all(row['State']['Running'] for row in rows)
    assert len({row['Image'] for row in rows}) == 1
    return rows


def config(path):
    return json.loads(subprocess.check_output(['docker', 'compose', '-p', 'chatwoot-uno', '-f', str(path), 'config', '--format', 'json']))


def compose_up():
    before = json.loads((private / 'runtime.before.json').read_text())
    services = {}
    for row in before:
        service = row['Config']['Labels']['com.docker.compose.service']
        services[service] = services.get(service, 0) + 1
    args = ['docker', 'compose', '-p', 'chatwoot-uno', '-f', str(compose), 'up', '-d', '--no-deps', '--force-recreate']
    for service, count in services.items():
        args.extend(['--scale', f'{service}={count}'])
    run([*args, *services])


mode = sys.argv[1]
if mode in ('prepare', 'prepare-resume'):
    rows = inspected()
    if mode == 'prepare':
        assert not (private / 'compose.before.yml').exists(), 'Backup already exists; do not overwrite it'
        (private / 'compose.before.yml').write_bytes(compose.read_bytes())
        env = dict(entry.split('=', 1) for entry in rows[0]['Config']['Env'])
        database = env.get('POSTGRES_DATABASE') or urlparse(env.get('DATABASE_URL', '')).path.lstrip('/')
        assert database and re.fullmatch(r'[A-Za-z0-9_]+', database), 'Unknown database'
        pg = json.loads(subprocess.check_output(['docker', 'inspect', 'chatwoot-postgres']))[0]
        pg_env = dict(entry.split('=', 1) for entry in pg['Config']['Env'])
        with (private / 'database.dump').open('wb') as stream:
            run(['docker', 'exec', 'chatwoot-postgres', 'pg_dump', '-U', pg_env['POSTGRES_USER'], '-Fc', database], stdout=stream)
        with (private / 'database.catalog').open('wb') as stream, (private / 'database.dump').open('rb') as source:
            run(['docker', 'exec', '-i', 'chatwoot-postgres', 'pg_restore', '--list'], stdin=source, stdout=stream)
    else:
        assert compose.read_bytes() == (private / 'compose.before.yml').read_bytes()
        previous = json.loads((private / 'runtime.before.json').read_text())
        assert [(r['Id'], r['Image']) for r in rows] == [(r['Id'], r['Image']) for r in previous]
    assert (private / 'database.dump').stat().st_size > 1_000_000 and (private / 'database.catalog').stat().st_size > 0
    for row in rows:
        row['Config']['Env'] = ['<redacted>']
    (private / 'runtime.before.json').write_text(json.dumps(rows, indent=2))
    lines = compose.read_text().splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.startswith('x-base: &base'))
    for entry in manifest:
        source = root / entry['path']
        assert hashlib.sha256(source.read_bytes()).hexdigest() == entry['sha256'], entry['path']
        for name in names:
            active = subprocess.run(['docker', 'exec', name, 'cat', '/app/' + entry['path']], capture_output=True)
            if entry['base_sha256'] is None:
                assert active.returncode != 0, 'New service already present'
            else:
                assert active.returncode == 0
                assert hashlib.sha256(active.stdout.replace(b'\r\n', b'\n')).hexdigest() == entry['base_sha256'], entry['path']
                backup = private / 'sources.before' / name / entry['path']
                backup.parent.mkdir(parents=True, exist_ok=True)
                backup.write_bytes(active.stdout)
        run(['docker', 'exec', '-i', names[0], 'ruby', '-c'], input=source.read_bytes())
        end = next(i for i in range(start + 1, len(lines)) if re.match(r'^[a-zA-Z0-9_-]+:', lines[i]))
        existing = [i for i in range(start, end) if lines[i].strip().endswith(':/app/' + entry['path'] + ':ro')]
        assert len(existing) <= 1
        mount = f'    - {source}:/app/{entry["path"]}:ro\n'
        if existing:
            lines[existing[0]] = mount
        else:
            lines.insert(end, mount)
    candidate.write_text(''.join(lines))
    before, after = config(compose), config(candidate)
    destinations = {'/app/' + entry['path'] for entry in manifest}
    for service in after['services'].values():
        service['volumes'] = [mount for mount in service.get('volumes', []) if mount.get('target') not in destinations]
    for service in before['services'].values():
        service['volumes'] = [mount for mount in service.get('volumes', []) if mount.get('target') not in destinations]
    for resolved in (before, after):
        resolved['x-base']['volumes'] = [mount for mount in resolved['x-base']['volumes']
                                         if not any(mount.endswith(':' + target + ':ro') for target in destinations)]
    assert before == after, 'Unrelated resolved Compose settings changed'
    (private / 'compose.candidate.yml').write_bytes(candidate.read_bytes())
    print(json.dumps({'prepared': True, 'backup_bytes': (private / 'database.dump').stat().st_size, 'image': rows[0]['Image']}))
elif mode == 'deploy':
    assert compose.read_bytes() == (private / 'compose.before.yml').read_bytes(), 'Active Compose changed'
    assert candidate.read_bytes() == (private / 'compose.candidate.yml').read_bytes()
    current = inspected()
    before = json.loads((private / 'runtime.before.json').read_text())
    assert [(r['Id'], r['Image']) for r in current] == [(r['Id'], r['Image']) for r in before], 'Runtime changed'
    drain = ('ps=Sidekiq::ProcessSet.new; raise "Expected two workers" unless ps.size==2; '
             'ps.each(&:quiet!); puts "QUIET_REQUESTED #{Time.current.utc.iso8601}"; '
             'deadline=Time.now+45; loop do; p=Sidekiq::ProcessSet.new; '
             'break if p.size==2 && p.all?{|x| x["busy"].to_i==0 && x["quiet"].to_s=="true"}; '
             'raise "Drain timeout" if Time.now>deadline; sleep 0.5; end; puts "DRAINED #{Time.current.utc.iso8601}"')
    try:
        run(['docker', 'exec', '-e', 'LOG_LEVEL=error', names[0], 'bundle', 'exec', 'rails', 'runner', drain])
        compose.write_bytes(candidate.read_bytes())
        compose_up()
    except Exception:
        compose.write_bytes((private / 'compose.before.yml').read_bytes())
        compose_up()
        raise
    print('DEPLOYED: workers recreated; no data maintenance yet')
elif mode == 'verify':
    rows = inspected()
    expected_image = json.loads((private / 'runtime.before.json').read_text())[0]['Image']
    for row in rows:
        assert row['Image'] == expected_image
        for entry in manifest:
            data = subprocess.check_output(['docker', 'exec', row['Name'].lstrip('/'), 'cat', '/app/' + entry['path']])
            assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['path']
            mounts = [m for m in row['Mounts'] if m['Destination'] == '/app/' + entry['path']]
            assert len(mounts) == 1 and not mounts[0]['RW'] and mounts[0]['Source'] == str(root / entry['path'])
    print(json.dumps({'verified': True, 'files': len(manifest), 'containers': len(rows), 'image': expected_image,
                      'mount_counts': [len(row['Mounts']) for row in rows]}))
else:
    raise ValueError('Unknown mode')
