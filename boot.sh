#!/bin/bash
# Boot entry point for the OpenCode web UI (called by cron @reboot).
# Starts the standalone web server in the tmux session "opencode-web".
# Idempotent: does nothing when the session already exists.
set -eu
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.opencode/bin

# Docker and the bridge network come up after boot; give them time.
sleep 20

if tmux -L opencode has-session -t opencode-web 2>/dev/null; then
    exit 0
fi

exec "$HOME/opencode/web.sh" start
