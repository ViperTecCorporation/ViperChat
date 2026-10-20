"""Read an authorized production key and send it to the local isolated runner over stdin.

stdin: JSON with host, user, password, known_hosts. Never prints or writes the key.
Requires existing paramiko and docker.exe; does not install dependencies or mutate VPS.
"""
import json
import shlex
import subprocess
import sys

import paramiko

options = json.load(sys.stdin)
ssh = paramiko.SSHClient()
ssh.load_host_keys(options["known_hosts"])
ssh.set_missing_host_key_policy(paramiko.RejectPolicy())
try:
    ssh.connect(options["host"], username=options["user"], password=options["password"],
                timeout=10, look_for_keys=False, allow_agent=False)
    _, stdout, _ = ssh.exec_command("docker ps --format '{{.ID}} {{.Names}}'", timeout=10)
    containers = [line.split(maxsplit=1) for line in stdout.read().decode().splitlines()]
    web = [row for row in containers if len(row) == 2 and
           ("chatwoot" in row[1].lower() or "viperchat" in row[1].lower()) and
           ("app" in row[1].lower() or "rails" in row[1].lower() or "web" in row[1].lower()) and
           "sidekiq" not in row[1].lower() and "redis" not in row[1].lower()]
    if len(web) != 1:
        raise RuntimeError("Production application container is ambiguous; no key was read")
    ruby = "print({api_key: InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value}.to_json)"
    command = "docker exec " + shlex.quote(web[0][0]) + " bundle exec rails runner " + shlex.quote(ruby)
    _, stdout, _ = ssh.exec_command(command, timeout=45)
    payload = stdout.read().decode()
    if stdout.channel.recv_exit_status() != 0:
        raise RuntimeError("Read-only production config lookup failed")
    lines = [line for line in payload.splitlines() if line.strip().startswith('{"api_key":')]
    if len(lines) != 1 or not json.loads(lines[0]).get("api_key"):
        raise RuntimeError("No usable key returned; no provider request was made")
    credentials = json.loads(lines[0])
    credentials["skip_chat"] = bool(options.get("skip_chat", False))
    credentials = json.dumps(credentials)
finally:
    ssh.close()

result = subprocess.run([
    "docker.exe", "exec", "-i", "-e", "RAILS_ENV=test", "-e", "POSTGRES_DATABASE=viperchat_meta_embed_validation",
    "-e", "CONFIRM_OPENROUTER_SMOKE=1", "viperchat-replica-web-1", "sh", "-lc",
    'export DATABASE_URL="${DATABASE_URL%/*}/viperchat_meta_embed_validation"; '
    'exec bundle exec rails runner /app/script/validation/openrouter_live_smoke.rb'
], input=credentials, text=True, capture_output=True, timeout=150)
credentials = None
if result.returncode:
    # Never echo provider bodies, exceptions, subprocess stdin, or credentials.
    print("Local paid smoke failed; credentials were not printed or persisted.")
    for line in result.stdout.splitlines():
        if line.startswith('{"stage":'):
            print(line)
    sys.exit(1)
for line in result.stdout.splitlines():
    if line.startswith('{"stage":') or line.startswith('{"chat_models":'):
        print(line)
