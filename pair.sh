#!/bin/bash
# Print a one-time login link for the OpenCode web UI, plus a terminal QR code.
# Usage: pair.sh [public-url]
# Settings come from .env (see .env.example); the password from login.txt.
# The link lives 5 minutes; logging in through it keeps a 30-day cookie.
# Mints the code on the standalone web server; the background service on
# 127.0.0.1 is not touched.
set -eu

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$CONF_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$CONF_DIR/.env"
    set +a
fi

PUBLIC_URL="${1:-${PUBLIC_URL:-https://code.aleksei.dev}}"
HOST="${WEB_HOST:-172.23.0.1}"
PORT="${WEB_PORT:-49375}"
PASS_FILE="${WEB_ACCESS_FILE:-login.txt}"
case "$PASS_FILE" in
    /*) ;;
    *) PASS_FILE="$CONF_DIR/$PASS_FILE" ;;
esac

PW=$(grep -oP 'password: \K\S+' "$PASS_FILE" 2>/dev/null | head -1)
if [ -z "$PW" ]; then
    echo "error: no password found in $PASS_FILE" >&2
    exit 1
fi

CODE=$(curl -s --noproxy '*' -m 8 -u "opencode:$PW" -X POST "http://$HOST:$PORT/api/pair" \
    -H 'Content-Type: application/json' -d '{}' \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('code',''))")
if [ -z "$CODE" ]; then
    echo "error: could not mint a pair code (is the server on $HOST:$PORT running?)" >&2
    exit 1
fi

echo "$PUBLIC_URL/auth/connect/$CODE"
echo
python3 - "$PUBLIC_URL/auth/connect/$CODE" <<'PY'
import sys
try:
    import qrcode
except ImportError:
    sys.exit(0)  # link is already printed; QR is a bonus
qr = qrcode.QRCode(border=1)
qr.add_data(sys.argv[1])
qr.make()
try:
    qr.print_ascii(invert=True)
except BrokenPipeError:
    pass
PY
