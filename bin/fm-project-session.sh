#!/usr/bin/env bash
# fm-project-session.sh - hand one tmux-hosted Codex captain into an
# unsupervised project-local orchestrator.
#
# This resolves one registered canonical repository, discloses uncommitted
# canonical paths, refuses preserved session custody, leases and verifies one
# clean remote-default Treehouse worktree, writes one private literal prompt,
# and opens one stable tmux window. It selects that window only when the current
# tmux session has exactly one attached client. It creates no Firstmate task,
# metadata, watcher, status, check, wake, backlog, or retry state.
#
# Failures after lease allocation use the lease-holder guard, verify release
# through Treehouse's JSON status, and never force cleanup. After a successful
# window creation the project session owns its worktree and the printed manual
# cleanup command; this launcher does not supervise or recover it.
#
# Usage:
#   fm-project-session.sh <project-id-or-canonical-path> -- <captain-request>
#   fm-project-session.sh --help
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-project-lib.sh
. "$SCRIPT_DIR/fm-project-lib.sh"

usage() {
  printf 'usage: fm-project-session.sh <project-id-or-canonical-path> -- <captain-request>\n'
}

if [ "${1:-}" = --help ]; then
  usage
  exit 0
fi

[ "$#" -ge 3 ] || {
  usage >&2
  exit 2
}

PROJECT_ARG=$1
shift
[ "$1" = -- ] || {
  printf 'project session: expected -- before request\n' >&2
  exit 2
}
shift
CAPTAIN_REQUEST=$*
[ -n "$CAPTAIN_REQUEST" ] || {
  printf 'project session: request is empty\n' >&2
  exit 2
}

fm_project_resolve_arg "$PROJECT_ARG"

[ -n "${TMUX:-}" ] || {
  printf 'project session: Codex CLI launch requires tmux\n' >&2
  exit 1
}
command -v codex >/dev/null || {
  printf 'project session: codex is unavailable\n' >&2
  exit 1
}
command -v treehouse >/dev/null || {
  printf 'project session: treehouse is unavailable\n' >&2
  exit 1
}
command -v tmux >/dev/null || {
  printf 'project session: tmux is unavailable\n' >&2
  exit 1
}

SKILL_PATH="${CODEX_HOME:-$HOME/.codex}/skills/design-to-code/SKILL.md"
[ -f "$SKILL_PATH" ] && [ ! -L "$SKILL_PATH" ] && [ -r "$SKILL_PATH" ] || {
  printf 'project session: install the design-to-code skill through the standard Codex skill installer before launch\n' >&2
  exit 1
}

session=$(tmux display-message -p '#S') || {
  printf 'project session: current tmux session is unavailable\n' >&2
  exit 1
}
[ -n "$session" ] || {
  printf 'project session: current tmux session is empty\n' >&2
  exit 1
}
window_name="project:$FM_PROJECT_ID"
if tmux list-windows -t "$session" -F '#{window_name}' | grep -Fxq "$window_name"; then
  printf 'project session: window %s:%s already exists\n' "$session" "$window_name" >&2
  exit 1
fi

session_ref="refs/heads/project-session/$FM_PROJECT_ID"
if git -C "$FM_PROJECT_PATH" show-ref --verify --quiet "$session_ref"; then
  printf 'project session: %s already preserves a session; inspect with %s/fm-project-status.sh %s before disposition\n' \
    "$session_ref" "$SCRIPT_DIR" "$FM_PROJECT_ID" >&2
  exit 1
fi

canonical_status=$(git -C "$FM_PROJECT_PATH" -c core.quotePath=false status --porcelain --untracked-files=all) || {
  printf 'project session: canonical checkout status is unreadable\n' >&2
  exit 1
}
canonical_paths=
canonical_joined=
while IFS= read -r status_line; do
  [ -n "$status_line" ] || continue
  canonical_path=${status_line#???}
  canonical_paths="${canonical_paths}${canonical_paths:+
}$canonical_path"
  canonical_joined="${canonical_joined}${canonical_joined:+ and }$canonical_path"
done <<EOF
$canonical_status
EOF

if [ -n "$canonical_paths" ]; then
  printf 'PROJECT_SESSION_CANONICAL_DRIFT project=%s\n' "$FM_PROJECT_ID"
  while IFS= read -r canonical_path; do
    printf 'uncommitted canonical-checkout path absent from leased copy: %s\n' "$canonical_path"
  done <<EOF
$canonical_paths
EOF
  printf 'project session: the leased copy uses the remote default ref and does not contain these changes\n'
fi

lease_holder="project-session:$FM_PROJECT_ID"
worktree=$(cd "$FM_PROJECT_PATH" && treehouse get --lease --lease-holder "$lease_holder") || {
  printf 'project session: Treehouse lease allocation failed\n' >&2
  exit 1
}
prompt_file=
printf -v worktree_command '%q' "$worktree"

lease_release_verified() {
  export FM_PROJECT_SESSION_WORKTREE=$worktree
  export FM_PROJECT_SESSION_LEASE_HOLDER=$lease_holder
  if treehouse status --json 2>/dev/null | python3 -c '
import json, os, sys
target = os.environ["FM_PROJECT_SESSION_WORKTREE"]
holder = os.environ["FM_PROJECT_SESSION_LEASE_HOLDER"]
rows = json.load(sys.stdin)
raise SystemExit(1 if any(row.get("path") == target and row.get("status") == "leased" and row.get("lease_holder") == holder for row in rows) else 0)
' 2>/dev/null; then
    released=0
  else
    released=1
  fi
  unset FM_PROJECT_SESSION_WORKTREE FM_PROJECT_SESSION_LEASE_HOLDER
  return "$released"
}

rollback_lease() {
  [ -z "$prompt_file" ] || rm -f "$prompt_file"
  treehouse return --if-lease-holder "$lease_holder" "$worktree" </dev/null || true
  if ! lease_release_verified; then
    printf 'project session: lease release could not be verified; recover with treehouse return --if-lease-holder %s %s\n' \
      "$lease_holder" "$worktree_command" >&2
    return 1
  fi
  return 0
}

abort_after_lease() {
  printf 'project session: %s\n' "$1" >&2
  rollback_lease || true
  exit 1
}

case "$worktree" in
  /*) ;;
  *) abort_after_lease 'Treehouse returned a non-absolute worktree path' ;;
esac
[ -d "$worktree" ] && [ ! -L "$worktree" ] || abort_after_lease 'Treehouse returned a non-directory worktree path'
worktree_root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) \
  || abort_after_lease 'leased path is not a readable Git worktree'
worktree_physical=$(cd "$worktree" && pwd -P) \
  || abort_after_lease 'leased worktree physical path is unreadable'
root_physical=$(cd "$worktree_root" && pwd -P) \
  || abort_after_lease 'leased Git root physical path is unreadable'
[ "$worktree_physical" = "$root_physical" ] \
  || abort_after_lease 'leased path is not the Git worktree root'
[ -z "$(git -C "$worktree" status --porcelain --untracked-files=all)" ] \
  || abort_after_lease 'leased worktree is not clean'

remote_short=$(git -C "$worktree" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
  || abort_after_lease 'leased worktree remote default is unavailable'
remote_ref="refs/remotes/$remote_short"
remote_head=$(git -C "$worktree" rev-parse "$remote_ref^{commit}" 2>/dev/null) \
  || abort_after_lease 'leased remote-default commit is unavailable'
worktree_head=$(git -C "$worktree" rev-parse 'HEAD^{commit}' 2>/dev/null) \
  || abort_after_lease 'leased HEAD commit is unavailable'
[ "$worktree_head" = "$remote_head" ] \
  || abort_after_lease 'leased HEAD does not match its remote default'

if [ -n "$canonical_joined" ]; then
  drift_prompt="Uncommitted canonical-checkout paths absent from this lease: $canonical_joined.
Those newer bytes are not in this remote-default worktree; ask rather than assume if committed intent appears stale."
else
  drift_prompt='Uncommitted canonical-checkout paths absent from this lease: none observed.'
fi

prompt="You are the project-local orchestrator for $FM_PROJECT_ID.
Project worktree: $worktree.
Session commit: $worktree_head.
Remote default ref: $remote_ref.
$drift_prompt

Captain request:
$CAPTAIN_REQUEST

Before trusting any document, run git status, git log --oneline -15, git rev-parse HEAD, and compare HEAD with the remote default branch.
Create and remain on project-session/$FM_PROJECT_ID before writing or committing anything; dispatch workers from this session HEAD, never local main.
Read AGENTS.md and the authoritative project sources it routes you to.
Invoke \$design-to-code before shaping or executing the captain's request.
Firstmate has handed the captain into this project session and is not supervising, steering, retrying, reviewing, or holding worker custody.
The captain is now interacting directly with you.
Do not read or write Firstmate private task data.
Update docs/project-status.md only at meaningful handoffs and commit every update on project-session/$FM_PROJECT_ID.
Stop for genuine product, programming-architecture, destructive, irreversible, or security-sensitive choices.
Finish with a concise terminal account and an exact docs/project-status.md update."

prompt_file=$(mktemp "${TMPDIR:-/tmp}/fm-project-session.XXXXXX") \
  || abort_after_lease 'could not create the private prompt file'
chmod 600 "$prompt_file" || abort_after_lease 'could not protect the private prompt file'
printf '%s' "$prompt" > "$prompt_file" || abort_after_lease 'could not write the private prompt file'

printf -v runner_command '%q %q' "$SCRIPT_DIR/fm-project-session-run.sh" "$prompt_file"
if ! window_id=$(tmux new-window -d -P -F '#{window_id}' -t "$session:" -n "$window_name" -c "$worktree" "$runner_command"); then
  abort_after_lease 'tmux could not create the project window'
fi

tmux set-option -w -t "$window_id" automatic-rename off || \
  printf 'project session: warning: tmux automatic rename could not be disabled for %s\n' "$window_id" >&2
tmux set-option -w -t "$window_id" allow-rename off || \
  printf 'project session: warning: tmux client rename could not be disabled for %s\n' "$window_id" >&2

window_target="$session:$window_name"
printf 'PROJECT_SESSION project=%s window=%s window_id=%s worktree=%s\n' \
  "$FM_PROJECT_ID" "$window_target" "$window_id" "$worktree"
printf 'PROJECT_SESSION_CLEANUP treehouse return --if-lease-holder %s %s\n' \
  "$lease_holder" "$worktree_command"

client_count=$(tmux list-clients -t "$session" -F '#{client_name}' 2>/dev/null \
  | awk 'NF { count++ } END { print count + 0 }')
if [ "$client_count" -eq 1 ]; then
  tmux select-window -t "$window_target"
else
  printf 'PROJECT_SESSION_HANDOFF select window %s manually\n' "$window_target"
fi
