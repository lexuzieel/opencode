#!/bin/bash
# OpenCode in a persistent tmux session for a project (see agent.sh).
# Project wrappers set TMUX_PROJECT_DIR; otherwise the project is this folder.
export TMUX_PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec ~/claude/agent.sh opencode "$@"
