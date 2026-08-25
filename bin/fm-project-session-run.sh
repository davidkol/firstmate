#!/usr/bin/env bash
# fm-project-session-run.sh - consume one private prompt and replace this shell
# with an interactive Codex project orchestrator. The prompt is removed before
# Codex starts; after exec, the runner owns no session, status, or return path.
#
# Usage:
#   fm-project-session-run.sh <prompt-file>
set -eu

PROMPT_FILE=${1:?usage: fm-project-session-run.sh <prompt-file>}
[ -f "$PROMPT_FILE" ] && [ ! -L "$PROMPT_FILE" ] || {
  printf 'project session runner: prompt is missing or not an ordinary file\n' >&2
  exit 1
}

prompt=$(cat "$PROMPT_FILE")
rm -f "$PROMPT_FILE"
exec codex --dangerously-bypass-approvals-and-sandbox "$prompt"
