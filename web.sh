#!/bin/bash
# OpenCode standalone web server for the reverse proxy (nginx-proxy-manager).
# Usage: web.sh [host] [port]
#   host  interface to listen on (default: 172.23.0.1, the docker bridge IP,
#         reachable from the proxy container but not from the internet)
#   port  port to listen on (default: 49375)
# The background service on 127.0.0.1 is not touched. The password comes
# from web-access.txt, so it never appears in argv.
set -eu

HOST="${1:-${WEB_HOST:-172.23.0.1}}"
PORT="${2:-${WEB_PORT:-49375}}"
PASS_FILE="${WEB_ACCESS_FILE:-$HOME/opencode/login.txt}"

PW=$(grep -oP 'password: \K\S+' "$PASS_FILE" 2>/dev/null | head -1)
if [ -z "$PW" ]; then
    echo "error: no password found in $PASS_FILE" >&2
    exit 1
fi

# Docker brings the bridge IP up after boot; wait for it (up to 2 minutes).
for _ in $(seq 1 60); do
    ip -4 addr show 2>/dev/null | grep -q " $HOST/" && break
    sleep 2
done
ip -4 addr show 2>/dev/null | grep -q " $HOST/" || {
    echo "error: $HOST is not up after 120s, giving up" >&2
    exit 1
}

exec env OPENCODE_PASSWORD="$PW" opencode serve --hostname "$HOST" --port "$PORT"
