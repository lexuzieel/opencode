#!/bin/bash
# OpenCode TUI in a persistent tmux session, one per project folder.
# Usage: opencode.sh [ARGS...]    (ARGS go to opencode)
# Ctrl+b d detaches and leaves the session running; the next call reattaches.
# Uses the agent wrapper shipped in bin/ (or OPENCODE_AGENT_SH, or the one in
# ~/claude); without any of them it falls back to a minimal tmux session.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${TMUX_PROJECT_DIR:-$PWD}"
WRAPPER="${OPENCODE_AGENT_SH:-}"
if [ -z "$WRAPPER" ]; then
    for candidate in "$HERE/bin/agent.sh" "$HOME/claude/agent.sh"; do
        [ -x "$candidate" ] && { WRAPPER="$candidate"; break; }
    done
fi

if [ -n "$WRAPPER" ] && [ -x "$WRAPPER" ]; then
    export TMUX_PROJECT_DIR="$PROJECT_DIR"
    exec "$WRAPPER" opencode "$@"
fi

SOCKET="opencode"
NAME="opencode-$(basename "$PROJECT_DIR" | tr '[:upper:]_' '[:lower:]-' | tr -c 'a-z0-9.-' '-')"
tmx() { tmux -L "$SOCKET" "$@"; }

if tmx has-session -t "$NAME" 2>/dev/null; then
    if [ -n "${TMUX:-}" ]; then
        exec tmx switch-client -t "$NAME"
    fi
    exec tmx attach -t "$NAME"
fi

if [ -n "${TMUX:-}" ]; then
    exec tmx new-session -d -s "$NAME" -c "$PROJECT_DIR" "opencode --continue $*" \; switch-client -t "$NAME"
fi
exec tmx new-session -s "$NAME" -c "$PROJECT_DIR" "opencode --continue $*"
