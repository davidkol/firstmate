#!/usr/bin/env bash
# Shared guards for updating canonical project checkouts without disturbing local files.

fm_git_has_tracked_changes() {
  [ -n "$(GIT_OPTIONAL_LOCKS=0 git -C "$1" status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]
}

fm_git_update_preflight() {
  git -C "$1" read-tree -n -m -u HEAD "$2"
}
