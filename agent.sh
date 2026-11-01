#!/bin/bash
# Persistent tmux sessions for coding agents, one per project folder plus
# optional named ones, each resuming its own conversation. Call it as
#   agent.sh <claude|codex|opencode> [COMMAND] [NAME]
# and run `agent.sh opencode help` for the command list. The wrappers in the
# parent directory (opencode.sh) call it with TMUX_PROJECT_DIR set.
set -o pipefail

TOOL="$1"; shift
PROG="$TOOL.sh"
usage() {
    cat <<EOF
Usage: $PROG [COMMAND] [NAME] [--debug]

Runs $LABEL in a tmux session that survives disconnects. Without NAME it is
the main session of the current project folder; NAME opens a separate
session in the same folder (e.g. $PROG hub, $PROG review).

Commands:
  (none) [NAME]       start the session, or attach if it is already running
  list          -l    running sessions and this folder's conversations
  show [NAME]   -n    what start would do (conversation, command), no changes
  kill [NAME]         stop the tmux session; the conversation is kept
  help          -h    this help

Options:
  -d, --debug         print how the conversation is picked while starting

Inside a session: Ctrl+b d detaches and leaves it running.
Command words (help, list, show, kill) can't be used as session names.
EOF
}

CMD_NAME="start" DEBUG="" POS=()
for arg in "$@"; do
    case "$arg" in
        -h|--help|help) CMD_NAME="help" ;;
        -l|--list|list|ls) CMD_NAME="list" ;;
        -n|--dry-run|show) CMD_NAME="show" ;;
        kill|stop) CMD_NAME="kill" ;;
        -d|--debug) DEBUG=1 ;;
        -*) echo "$PROG: unknown option '$arg' (see $PROG help)" >&2; exit 2 ;;
        *) POS+=("$arg") ;;
    esac
done
[[ "$CMD_NAME" == "show" ]] && DEBUG=1
(( ${#POS[@]} > 1 )) && { echo "$PROG: expected one session name, got: ${POS[*]}" >&2; exit 2; }
NAME="${POS[0]}"
debug() { [[ -n "$DEBUG" ]] && echo "[$PROG] $*" >&2; return 0; }
slug() { tr '[:upper:]_' '[:lower:]-' <<< "$1"; }

PROJECT_DIR="${TMUX_PROJECT_DIR:-$PWD}"
[[ -d "$PROJECT_DIR" ]] || { echo "agent.sh: project directory not found: $PROJECT_DIR" >&2; exit 2; }
DOTENV="$PROJECT_DIR/.env"

# --- Claude Code: conversations are found by title (claude --name). A saved
# session id goes stale on /clear, so the newest transcript with the title wins.
claude_setup() {
    LABEL="Claude Code" COLOR="#A85050"
    TITLE=$(grep -sE '^CLAUDE_SESSION_NAME=' "$DOTENV" | cut -d= -f2-)
    TITLE="${TITLE:+$TITLE${NAME:+-}}$NAME"
    TITLE="${TITLE:-$(basename "$PROJECT_DIR")}"
}
claude_find() {
    local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<< "$PROJECT_DIR")"
    debug "transcripts: $dir"
    local f title
    for f in $(ls -t "$dir"/*.jsonl 2>/dev/null); do
        title=$(grep -h '^{"type":"custom-title"' "$f" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
        [[ -n "$title" ]] && debug "  $(date -r "$f" '+%F %T') $(basename "$f" .jsonl) '$title'"
        [[ "$title" == "$TITLE" ]] && { basename "$f" .jsonl; return; }
    done
    # Conversations started before titles were used are only known by the id
    # the old launcher saved; resuming one with --name titles it for next time.
    local legacy
    legacy=$(head -1 "$PROJECT_DIR/.claude-session-id${NAME:+-$NAME}" 2>/dev/null)
    if [[ "$legacy" =~ ^[0-9a-f-]{36}$ && -f "$dir/$legacy.jsonl" ]]; then
        debug "no title match, using the legacy id file"
        echo "$legacy"
    fi
}
claude_conversations() {
    local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<< "$PROJECT_DIR")"
    local f title n=0
    local -A seen
    for f in $(ls -t "$dir"/*.jsonl 2>/dev/null); do
        title=$(grep -h '^{"type":"custom-title"' "$f" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
        [[ -z "$title" || -n "${seen[$title]}" ]] && continue
        seen[$title]=1
        printf '  %-20s %s  %s\n' "$title" "$(date -r "$f" '+%F %H:%M')" "$(basename "$f" .jsonl)"
        (( ++n >= 10 )) && break
    done
}
claude_cmd() { echo "claude ${1:+--resume '$1' }--name '$TITLE'"; }

# --- Codex: `codex resume --last` also picks up exec runs, subagents and
# plugin tasks. A NAME matches a thread renamed with /rename; the default
# session is the newest interactive (codex-tui, cli) thread started here.
codex_setup() {
    LABEL="Codex" COLOR="#5080A8" TITLE="$NAME"
}
codex_find() {
    local home="${CODEX_HOME:-$HOME/.codex}"
    if [[ -n "$TITLE" ]]; then
        debug "looking for a thread named '$TITLE' in $home/session_index.jsonl"
        jq -r --arg t "$TITLE" 'select(.thread_name == $t) | .id' "$home/session_index.jsonl" 2>/dev/null | tail -1
        return
    fi
    debug "using Codex's most recent session for this project"
}
codex_conversations() {
    local home="${CODEX_HOME:-$HOME/.codex}" f id name n=0
    for f in $(ls -t "$home"/sessions/*/*/*/*.jsonl 2>/dev/null); do
        id=$(head -1 "$f" | jq -r --arg cwd "$PROJECT_DIR" \
            '.payload | select(.cwd == $cwd and .originator == "codex-tui" and .source == "cli") | .id' 2>/dev/null)
        [[ -z "$id" ]] && continue
        name=$(jq -r --arg id "$id" 'select(.id == $id) | .thread_name' "$home/session_index.jsonl" 2>/dev/null | tail -1)
        printf '  %-20s %s  %s\n' "${name:-(unnamed)}" "$(date -r "$f" '+%F %H:%M')" "$id"
        (( ++n >= 10 )) && break
    done
}
codex_cmd() {
    if [[ -n "$1" ]]; then echo "codex resume '$1'"; return; fi
    if [[ -z "$TITLE" ]]; then echo "codex resume --last"; return; fi
    [[ -n "$TITLE" ]] && echo "New Codex thread: run /rename $TITLE in it so this session can find it again." >&2
    echo "codex"
}

# --- OpenCode: session list is per project directory; a NAME matches a session
# renamed in the TUI (Ctrl+R). Without NAME the newest session keeps going.
opencode_setup() {
    LABEL="OpenCode" COLOR="#50A050"
    TITLE=$(grep -sE '^OPENCODE_SESSION_NAME=' "$DOTENV" | cut -d= -f2-)
    TITLE="${TITLE:+$TITLE${NAME:+-}}$NAME"
    TITLE="${TITLE:-$NAME}"
}
opencode_find() {
    if [[ -z "$TITLE" ]]; then return; fi
    debug "looking for a session titled '$TITLE'"
    (cd "$PROJECT_DIR" && opencode session list 2>/dev/null) \
        | awk -F '\t' -v t="$TITLE" '$2 == t {print $1; exit}'
}
opencode_conversations() {
    local id title date
    while IFS=$'\t' read -r id title date; do
        printf '  %-20s %s  %s\n' "$title" "$date" "$id"
    done < <(cd "$PROJECT_DIR" && opencode session list 2>/dev/null | head -10)
}
opencode_cmd() {
    if [[ -n "$1" ]]; then echo "opencode --session '$1'"; return; fi
    if [[ -z "$TITLE" ]]; then echo "opencode --continue"; return; fi
    [[ -n "$TITLE" ]] && echo "New OpenCode session: name it with Ctrl+R ('$TITLE') in it so this session can find it again." >&2
    echo "opencode"
}

case "$TOOL" in
    claude|codex|opencode) "${TOOL}_setup" ;;
    *) echo "usage: agent.sh <claude|codex|opencode> [ARGS...]" >&2; exit 2 ;;
esac

command -v tmux >/dev/null || { echo "agent.sh: tmux is not installed" >&2; exit 2; }
if [[ "$TOOL" != "opencode" ]]; then
    command -v jq >/dev/null || { echo "agent.sh: jq is required for $TOOL sessions" >&2; exit 2; }
fi

SESSION="$TOOL-$(slug "$(basename "$PROJECT_DIR")")${NAME:+-$(slug "$NAME")}"
TMUX_CONF="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux.conf"
tmx() { tmux -L "$TOOL" -f "$TMUX_CONF" "$@"; }

case "$CMD_NAME" in
    help)
        usage; exit 0 ;;
    list)
        echo "Running $LABEL sessions:"
        tmx ls -F '#{session_name}|#{session_path}|#{?session_attached,attached,detached}' 2>/dev/null \
            | while IFS='|' read -r s path state; do
                printf '  %-32s %-9s %s\n' "$s" "$state" "${path/#$HOME/\~}"
            done | grep . || echo "  (none)"
        echo
        echo "Conversations in ${PROJECT_DIR/#$HOME/\~} (newest first):"
        "${TOOL}_conversations" | grep . || echo "  (none)"
        exit 0 ;;
    kill)
        tmx kill-session -t "$SESSION" 2>/dev/null && echo "Session '$SESSION' stopped." || echo "No session '$SESSION' running."
        exit 0 ;;
esac

debug "project: $PROJECT_DIR"
debug "tmux session: $SESSION (socket $TOOL)"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
if tmx has-session -t "$SESSION" 2>/dev/null; then
    debug "tmux session is running, attaching to it as is"
    [[ "$CMD_NAME" == "show" ]] && exit 0
else
    debug "conversation title: '${TITLE:-none}'"
    ID=$("${TOOL}_find")
    if [[ -n "$ID" ]]; then debug "resuming $ID"; elif [[ ( "$TOOL" == codex || "$TOOL" == opencode ) && -z "$TITLE" ]]; then debug "will continue the most recent conversation"; else debug "nothing found, starting a new conversation"; fi
    CMD=$("${TOOL}_cmd" "$ID")
    debug "command: $CMD"
    [[ "$CMD_NAME" == "show" ]] && exit 0

    tmx new-session -d -s "$SESSION" -c "$PROJECT_DIR" -x 220 -y 50
    # The proxy goes into this session's environment only,
    # never into argv (CWE-214: argv is visible to every local user via ps).
    # The pane is respawned so its shell starts with that environment.
    # The proxy always comes from the project's .env, else from the one next to
    # this script, so it stays out of argv.
    PROXY=""
    for f in "$PROJECT_DIR/.env" "$(dirname "$TMUX_CONF")/.env"; do
        PROXY=$(grep -sE '^HTTPS_PROXY=' "$f" 2>/dev/null | cut -d= -f2-)
        [[ -n "$PROXY" ]] && break
    done
    if [[ -n "$PROXY" ]]; then
        for var in HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ALL_PROXY all_proxy; do
            tmx set-environment -t "$SESSION" "$var" "$PROXY"
        done
        tmx set-environment -t "$SESSION" NO_PROXY localhost,127.0.0.1
        tmx set-environment -t "$SESSION" no_proxy localhost,127.0.0.1
        tmx respawn-pane -k -t "$SESSION"
    fi
    tmx send-keys -t "$SESSION" "$CMD" Enter
fi

# A server started before tmux.conf existed did not read it.
tmx source-file "$TMUX_CONF"
tmx source-file - <<EOF
set -g mouse on
set -g status-style "bg=default,fg=$COLOR"
set -g status-right ""
set -g window-status-format ""
set -g window-status-current-format ""
set -g status-left "  $LABEL @ #{s|$HOME|~|:pane_current_path} "
set -g status-left-length 80
EOF
exec tmux -2 -L "$TOOL" -f "$TMUX_CONF" attach -t "$SESSION"
