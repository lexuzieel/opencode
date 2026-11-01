#!/bin/bash
# Protect or unprotect an nginx-proxy-manager host with the Authelia gate.
# Usage: guard.sh protect|unprotect HOST_ID
# Environment:
#   NPM_URL       API base, e.g. http://127.0.0.1:81 (required)
#   NPM_IDENTITY  agent account email (required)
#   NPM_SECRET    agent account password (required)
#   AUTH_DOMAIN   Authelia portal host, e.g. auth.example.com (required)
# A backup of the host is written next to this script before the first change.
set -eu

ACTION="${1:?usage: guard.sh protect|unprotect HOST_ID}"
HOST_ID="${2:?usage: guard.sh protect|unprotect HOST_ID}"
case "$HOST_ID" in
    ''|*[!0-9]*) echo "error: HOST_ID must be numeric" >&2; exit 2 ;;
esac

NPM_URL="${NPM_URL:?set NPM_URL, e.g. http://127.0.0.1:81}"
: "${NPM_IDENTITY:?set NPM_IDENTITY}"
: "${NPM_SECRET:?set NPM_SECRET}"
AUTH_DOMAIN="${AUTH_DOMAIN:?set AUTH_DOMAIN, e.g. auth.example.com}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MARK="Authelia auth gateway"

token() {
    curl -sS --noproxy '*' -m 10 -X POST "$NPM_URL/api/tokens" \
        -H 'Content-Type: application/json' \
        -d "{\"identity\":\"$NPM_IDENTITY\",\"secret\":\"$NPM_SECRET\"}" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])'
}

TOKEN="$(token)"
echo "authenticated against $NPM_URL" >&2

python3 - "$ACTION" "$HOST_ID" "$AUTH_DOMAIN" "$MARK" "$HERE" "$NPM_URL" "$TOKEN" <<'PY'
import json, pathlib, subprocess, sys

action, host_id, auth_domain, mark, here, npm_url, token = sys.argv[1:8]
hosts = json.loads(subprocess.run(
    ["curl", "-sS", "--noproxy", "*", "-m", "10",
     f"{npm_url}/api/nginx/proxy-hosts/{host_id}",
     "-H", f"Authorization: Bearer {token}"],
    capture_output=True, text=True, check=True).stdout)

backup = pathlib.Path(here) / f"guard-backup-{host_id}.json"
advanced = hosts.get("advanced_config") or ""

if action == "protect":
    if not backup.exists():
        backup.write_text(json.dumps(hosts, indent=1))
        backup.chmod(0o600)
    snippet = f"""# {mark} for {', '.join(hosts['domain_names'])}
# Backup of the original host: {backup}
auth_request /authelia;
error_page 401 =302 https://{auth_domain}/?rd=$scheme://$http_host$request_uri;

location = /authelia {{
    internal;
    proxy_pass http://authelia:9091/api/authz/auth-request;

    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $http_host;
    proxy_set_header X-Forwarded-Uri $request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header Host $http_host;
    proxy_set_header Cookie $http_cookie;
}}
"""
    advanced = snippet
elif action == "unprotect":
    advanced = ""
    if backup.exists():
        original = json.loads(backup.read_text())
        advanced = original.get("advanced_config", "")
else:
    print("error: action must be protect or unprotect", file=sys.stderr)
    sys.exit(2)

hosts["advanced_config"] = advanced
payload = {k: hosts[k] for k in (
    "domain_names", "forward_scheme", "forward_host", "forward_port",
    "access_list_id", "certificate_id", "ssl_forced", "caching_enabled",
    "block_exploits", "allow_websocket_upgrade", "advanced_config",
    "enabled", "locations") if k in hosts}

res = subprocess.run(
    ["curl", "-sS", "--noproxy", "*", "-m", "15", "-X", "PUT",
     f"{npm_url}/api/nginx/proxy-hosts/{host_id}",
     "-H", f"Authorization: Bearer {token}",
     "-H", "Content-Type: application/json",
     "-d", json.dumps(payload)],
    capture_output=True, text=True, check=True)
try:
    data = json.loads(res.stdout)
except json.JSONDecodeError:
    print("error: unexpected API answer:", res.stdout[:200], file=sys.stderr)
    sys.exit(1)
meta = data.get("meta") or {}
print(f"{action}: host {host_id} {data.get('domain_names')} online={meta.get('nginx_online')} err={meta.get('nginx_err')}")
PY
