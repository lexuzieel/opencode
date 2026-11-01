#!/bin/bash
# OpenCode standalone web server for the reverse proxy (nginx-proxy-manager).
#
# Commands:
#   web.sh                  run in the foreground (Ctrl-C to stop)
#   web.sh start            start in the tmux session "opencode-web"
#   web.sh stop             stop that session
#   web.sh restart          stop, start, wait for the port, print a login link
#   web.sh status           is it up, and does its password match the file
#   web.sh passwd [--restart] [--yes]
#                           write a new password to the password file
#
# `passwd` replaces a credential and ends every open browser session, so it
# asks for confirmation; --yes answers it, for scripts and cron.
#
# Settings come from .env (see .env.example); the password from password.txt.
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

SESSION="${WEB_SESSION:-opencode-web}"
SOCKET="${WEB_TMUX_SOCKET:-opencode}"
ASSUME_YES=false

PASS_FILE="${WEB_ACCESS_FILE:-password.txt}"
case "$PASS_FILE" in
    /*) ;;
    *) PASS_FILE="$CONF_DIR/$PASS_FILE" ;;
esac

usage() {
    cat <<'EOF'
Usage: web.sh [command]

  (no command)              run in the foreground, Ctrl-C to stop
  start                     start in the tmux session "opencode-web"
  stop                      stop that session
  restart                   stop, start, wait for the port, print a login link
  status                    is it up, and does its password match the file
  passwd [--restart] [--yes]
                            write a new password to the password file

`passwd` ends every open browser session; it asks before doing that.
--yes answers the question, for scripts and cron.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

confirm() {
    local answer
    [ "$ASSUME_YES" = true ] && return 0
    if [ ! -t 0 ]; then
        die "not a terminal, refusing to continue (rerun with --yes)"
    fi
    printf '%s [y/N] ' "$1"
    read -r answer || answer=""
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
    esac
    echo "aborted"
    exit 1
}

read_pw() {
    grep -oP '^password: \K\S+' "$PASS_FILE" 2>/dev/null | head -1
}

session_exists() {
    tmux -L "$SOCKET" has-session -t "$SESSION" 2>/dev/null
}

# HTTP code of /api/info using the password from the file. Always succeeds so
# callers under `set -e` get a value: 200 (matches), 401 (different password),
# 000 (nothing listening).
api_code() {
    local host="${WEB_HOST:-127.0.0.1}"
    local port="${WEB_PORT:-49375}"
    local pw
    pw="$(read_pw)"
    curl -s --noproxy '*' -m 5 -o /dev/null -w '%{http_code}' \
        -u "opencode:$pw" "http://$host:$port/api/info" 2>/dev/null || true
    return 0
}

# Wait until the server answers at all (200 or 401), up to 60 seconds.
wait_ready() {
    local i code
    for i in $(seq 1 60); do
        code="$(api_code)"
        case "$code" in
            200|401) return 0 ;;
        esac
        sleep 1
    done
    return 1
}

cmd_serve() {
    local host="${1:-${WEB_HOST:-127.0.0.1}}"
    local port="${2:-${WEB_PORT:-49375}}"
    local pw i
    pw="$(read_pw)"
    [ -n "$pw" ] || die "no password found in $PASS_FILE"

    # A bridge address appears after boot; wait for it (up to 2 minutes).
    case "$host" in
        127.0.0.1|localhost) ;;
        *)
            for i in $(seq 1 60); do
                ip -4 addr show 2>/dev/null | grep -q " $host/" && break
                sleep 2
            done
            ip -4 addr show 2>/dev/null | grep -q " $host/" || \
                die "$host is not up after 120s, giving up"
            ;;
    esac

    exec env OPENCODE_PASSWORD="$pw" opencode serve --hostname "$host" --port "$port"
}

cmd_start() {
    if session_exists; then
        echo "already running in tmux session $SESSION (use: web.sh restart)"
        return 0
    fi
    [ -n "$(read_pw)" ] || die "no password found in $PASS_FILE"
    tmux -L "$SOCKET" new-session -d -s "$SESSION" -c "$CONF_DIR" \
        "bash $(printf '%q' "$CONF_DIR/web.sh") serve"
    if wait_ready; then
        echo "started in tmux session $SESSION on ${WEB_HOST:-127.0.0.1}:${WEB_PORT:-49375}"
    else
        echo "started, but no answer within 60s (check: tmux -L $SOCKET attach -t $SESSION)" >&2
        return 1
    fi
}

cmd_stop() {
    if session_exists; then
        tmux -L "$SOCKET" kill-session -t "$SESSION"
        echo "stopped tmux session $SESSION"
    else
        echo "not running (no tmux session $SESSION)"
    fi
}

pair_link() {
    [ -n "${PUBLIC_URL:-}" ] || return 0
    PAIR_NO_QR=1 "$CONF_DIR/pair.sh" 2>/dev/null || \
        echo "warning: could not mint a login link (see: ./pair.sh)" >&2
}

cmd_restart() {
    local before arg
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) ASSUME_YES=true ;;
            *) die "unknown argument to restart: $arg" ;;
        esac
    done
    before="$(api_code)"
    cmd_stop
    cmd_start
    if [ "$before" = "401" ]; then
        echo "note: the file password was never applied to the old process," >&2
        echo "      so sessions signed with it are gone; pair again with ./pair.sh" >&2
    fi
    pair_link
}

cmd_status() {
    local code
    code="$(api_code)"
    if session_exists; then
        echo "tmux session $SESSION: present"
    else
        echo "tmux session $SESSION: absent"
    fi
    case "$code" in
        200) echo "api: 200, the password in $PASS_FILE matches the running server" ;;
        401) echo "api: 401, the running server holds a different password (run: web.sh restart)"
             return 1 ;;
        000) echo "api: nothing listening on ${WEB_HOST:-127.0.0.1}:${WEB_PORT:-49375}"
             return 1 ;;
        *) echo "api: unexpected HTTP $code"
           return 1 ;;
    esac
}

cmd_passwd() {
    local restart=false arg pw tmp
    for arg in "$@"; do
        case "$arg" in
            --restart) restart=true ;;
            --yes|-y) ASSUME_YES=true ;;
            *) die "unknown argument to passwd: $arg" ;;
        esac
    done
    command -v openssl >/dev/null 2>&1 || die "openssl not found"

    echo "about to replace the password in $PASS_FILE."
    echo "every open browser session ends, because cookies are signed with it."
    confirm "replace the password?"

    pw="$(openssl rand -hex 16)"
    tmp="$(mktemp "$PASS_FILE.XXXXXX")"
    ( umask 077; printf '# OpenCode web UI (login: opencode)\npassword: %s\n' "$pw" > "$tmp" )
    chmod 600 "$tmp"
    mv "$tmp" "$PASS_FILE"

    echo "new password written to $PASS_FILE"
    echo
    echo "$pw"
    echo
    if [ "$restart" = true ]; then
        cmd_restart --yes
    else
        echo "not applied yet: run 'web.sh restart' to use it."
        echo "the restart ends every current browser session, so pair again afterwards."
    fi
}

case "${1:-}" in
    ""|serve)
        shift || true
        cmd_serve "$@"
        ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) shift; cmd_restart "$@" ;;
    status) cmd_status ;;
    passwd) shift; cmd_passwd "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $1 (see: web.sh --help)" ;;
esac
