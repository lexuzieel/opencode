#!/bin/bash
# OpenCode standalone web server for the reverse proxy (nginx-proxy-manager).
# Usage: web.sh [host] [port]
# Settings come from .env (see .env.example); the password from login.txt.
# The background service on 127.0.0.1 is not touched. The password is read
# from the file, so it never appears in argv.
set -eu

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$CONF_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$CONF_DIR/.env"
    set +a
fi

HOST="${1:-${WEB_HOST:-127.0.0.1}}"
PORT="${2:-${WEB_PORT:-49375}}"
PASS_FILE="${WEB_ACCESS_FILE:-login.txt}"
case "$PASS_FILE" in
    /*) ;;
    *) PASS_FILE="$CONF_DIR/$PASS_FILE" ;;
esac

PW=$(grep -oP '^password: \K\S+' "$PASS_FILE" 2>/dev/null | head -1)
if [ -z "$PW" ]; then
    echo "error: no password found in $PASS_FILE" >&2
    exit 1
fi

# A bridge address appears after boot; wait for it (up to 2 minutes).
case "$HOST" in
    127.0.0.1|localhost) ;;
    *)
        for _ in $(seq 1 60); do
            ip -4 addr show 2>/dev/null | grep -q " $HOST/" && break
            sleep 2
        done
        ip -4 addr show 2>/dev/null | grep -q " $HOST/" || {
            echo "error: $HOST is not up after 120s, giving up" >&2
            exit 1
        }
        ;;
esac

exec env OPENCODE_PASSWORD="$PW" opencode serve --hostname "$HOST" --port "$PORT"
