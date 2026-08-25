#!/usr/bin/env bash
# fm-project-status.sh - print one registered project's committed status snapshot.
#
# The deterministic project-session branch is authoritative while it exists;
# otherwise this reads the remote default ref. It never reads canonical HEAD or
# working-tree bytes. Missing refs and commits, missing status, and non-regular
# status blobs fail with typed PROJECT_STATUS diagnostics.
#
# Usage:
#   fm-project-status.sh <project-id-or-canonical-path>
#   fm-project-status.sh --help
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-project-lib.sh
. "$SCRIPT_DIR/fm-project-lib.sh"

usage() {
  printf 'usage: fm-project-status.sh <project-id-or-canonical-path>\n'
}

if [ "${1:-}" = --help ]; then
  usage
  exit 0
fi

PROJECT_ARG=${1:?usage: fm-project-status.sh <project-id-or-canonical-path>}
fm_project_resolve_arg "$PROJECT_ARG"

session_ref="refs/heads/project-session/$FM_PROJECT_ID"
if git -C "$FM_PROJECT_PATH" show-ref --verify --quiet "$session_ref"; then
  status_ref=$session_ref
else
  remote_short=$(git -C "$FM_PROJECT_PATH" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || {
    printf 'PROJECT_STATUS_UNREADABLE id=%s reason=remote-default-unavailable\n' "$FM_PROJECT_ID" >&2
    exit 1
  }
  status_ref="refs/remotes/$remote_short"
fi

head_sha=$(git -C "$FM_PROJECT_PATH" rev-parse "$status_ref^{commit}" 2>/dev/null) || {
  printf 'PROJECT_STATUS_UNREADABLE id=%s ref=%s reason=commit-unavailable\n' "$FM_PROJECT_ID" "$status_ref" >&2
  exit 1
}
mode=$(git -C "$FM_PROJECT_PATH" ls-tree "$head_sha" -- docs/project-status.md | awk 'NR == 1 { print $1 }')

if [ -z "$mode" ]; then
  printf 'PROJECT_STATUS_MISSING id=%s ref=%s commit=%s path=docs/project-status.md\n' \
    "$FM_PROJECT_ID" "$status_ref" "$head_sha" >&2
  exit 1
fi

if [ "$mode" != 100644 ]; then
  printf 'PROJECT_STATUS_INVALID id=%s ref=%s commit=%s path=docs/project-status.md mode=%s\n' \
    "$FM_PROJECT_ID" "$status_ref" "$head_sha" "$mode" >&2
  exit 1
fi

printf 'PROJECT_STATUS id=%s ref=%s commit=%s\n' "$FM_PROJECT_ID" "$status_ref" "$head_sha"
git -C "$FM_PROJECT_PATH" show "$head_sha:docs/project-status.md"
