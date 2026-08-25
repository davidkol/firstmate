#!/usr/bin/env bash
# Behavior tests for committed project-status reads from published project refs.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_git_identity

STATUS="$ROOT/bin/fm-project-status.sh"
TMP_ROOT=$(fm_test_tmproot fm-project-status)

new_home() {
  local home="$TMP_ROOT/$1-home"
  mkdir -p "$home/data" "$home/state" "$home/projects"
  printf '%s\n' "$home"
}

new_remote_fixture() {
  local seed="$TMP_ROOT/$1-seed" remote="$TMP_ROOT/$1.git" repo="$TMP_ROOT/$1-repo"
  git init -q -b main "$seed"
  mkdir -p "$seed/docs"
  printf '%s\n' '# Project status' '- latest verified outcome: initial value' > "$seed/docs/project-status.md"
  git -C "$seed" add docs/project-status.md
  git -C "$seed" commit -qm initial
  git clone -q --bare "$seed" "$remote"
  git clone -q "$remote" "$repo"
  git -C "$repo" remote set-head origin -a >/dev/null
  printf '%s\n' "$repo"
}

register_fixture() {
  fm_register_project "$1/data" Fixture "$2" validated-main
}

run_status() {
  FM_HOME=$1 FM_ROOT_OVERRIDE="$ROOT" "$STATUS" Fixture
}

test_session_branch_wins_and_working_tree_is_ignored() {
  local home repo writer remote_head session_head output
  home=$(new_home preferred)
  repo=$(new_remote_fixture preferred)
  register_fixture "$home" "$repo"

  writer="$TMP_ROOT/preferred-writer"
  git clone -q "$(git -C "$repo" remote get-url origin)" "$writer"
  printf '%s\n' '# Project status' '- latest verified outcome: remote value' > "$writer/docs/project-status.md"
  git -C "$writer" add docs/project-status.md
  git -C "$writer" commit -qm remote-status
  git -C "$writer" push -q origin main
  git -C "$repo" fetch -q origin
  remote_head=$(git -C "$repo" rev-parse refs/remotes/origin/main)
  [ "$(git -C "$repo" rev-parse main)" != "$remote_head" ] || fail 'fixture local main is not behind origin/main'

  git -C "$repo" switch -q -c project-session/Fixture refs/remotes/origin/main
  printf '%s\n' '# Project status' '- latest verified outcome: session value' > "$repo/docs/project-status.md"
  git -C "$repo" add docs/project-status.md
  git -C "$repo" commit -qm session-status
  session_head=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" switch -q main
  printf '%s\n' '# Project status' '- latest verified outcome: working-tree-only value' > "$repo/docs/project-status.md"

  output=$(run_status "$home") || fail 'status reader failed on the session branch'
  assert_contains "$output" "PROJECT_STATUS id=Fixture ref=refs/heads/project-session/Fixture commit=$session_head" \
    'status reader did not report the deterministic session ref and commit'
  assert_contains "$output" 'latest verified outcome: session value' \
    'status reader did not print the session snapshot'
  assert_not_contains "$output" 'working-tree-only value' \
    'status reader trusted modified working-tree bytes'
  pass 'project status prefers the deterministic session ref and ignores working-tree drift'
}

test_remote_default_fallback_ignores_behind_local_main() {
  local home repo writer remote_head output
  home=$(new_home fallback)
  repo=$(new_remote_fixture fallback)
  register_fixture "$home" "$repo"

  writer="$TMP_ROOT/fallback-writer"
  git clone -q "$(git -C "$repo" remote get-url origin)" "$writer"
  printf '%s\n' '# Project status' '- latest verified outcome: remote default value' > "$writer/docs/project-status.md"
  git -C "$writer" add docs/project-status.md
  git -C "$writer" commit -qm remote-status
  git -C "$writer" push -q origin main
  git -C "$repo" fetch -q origin
  remote_head=$(git -C "$repo" rev-parse refs/remotes/origin/main)
  [ "$(git -C "$repo" rev-parse main)" != "$remote_head" ] || fail 'fixture local main is not behind origin/main'

  output=$(run_status "$home") || fail 'status reader failed on the remote-default fallback'
  assert_contains "$output" "PROJECT_STATUS id=Fixture ref=refs/remotes/origin/main commit=$remote_head" \
    'status reader did not report the remote-default ref and commit'
  assert_contains "$output" 'latest verified outcome: remote default value' \
    'status reader fell back to the behind local main'
  pass 'project status falls back to the remote default ref instead of local main'
}

test_unreadable_remote_default_is_typed() {
  local home repo output rc
  home=$(new_home unreadable)
  repo="$TMP_ROOT/unreadable-repo"
  fm_git_init_commit "$repo"
  register_fixture "$home" "$repo"

  set +e
  output=$(run_status "$home" 2>&1)
  rc=$?
  set -e

  expect_code 1 "$rc" 'repository without a published default ref'
  assert_contains "$output" 'PROJECT_STATUS_UNREADABLE id=Fixture reason=remote-default-unavailable' \
    'unreadable repository did not return the typed diagnostic'
  pass 'project status types an unavailable published default ref'
}

test_missing_status_is_typed() {
  local home repo head output rc
  home=$(new_home missing)
  repo=$(new_remote_fixture missing)
  register_fixture "$home" "$repo"
  git -C "$repo" rm -q docs/project-status.md
  git -C "$repo" commit -qm remove-status
  git -C "$repo" branch -f project-session/Fixture HEAD
  head=$(git -C "$repo" rev-parse HEAD)

  set +e
  output=$(run_status "$home" 2>&1)
  rc=$?
  set -e

  expect_code 1 "$rc" 'missing committed project status'
  assert_contains "$output" "PROJECT_STATUS_MISSING id=Fixture ref=refs/heads/project-session/Fixture commit=$head path=docs/project-status.md" \
    'missing committed status did not return the typed diagnostic'
  pass 'project status rejects a missing committed snapshot'
}

test_symlink_status_is_rejected_without_following_target() {
  local home repo head output rc
  home=$(new_home symlink)
  repo=$(new_remote_fixture symlink)
  register_fixture "$home" "$repo"
  printf '%s\n' 'working-tree target must stay unread' > "$repo/secret-status"
  rm "$repo/docs/project-status.md"
  ln -s ../secret-status "$repo/docs/project-status.md"
  git -C "$repo" add docs/project-status.md
  git -C "$repo" commit -qm symlink-status
  git -C "$repo" branch -f project-session/Fixture HEAD
  head=$(git -C "$repo" rev-parse HEAD)

  set +e
  output=$(run_status "$home" 2>&1)
  rc=$?
  set -e

  expect_code 1 "$rc" 'symlink project status'
  assert_contains "$output" "PROJECT_STATUS_INVALID id=Fixture ref=refs/heads/project-session/Fixture commit=$head path=docs/project-status.md mode=120000" \
    'symlink status did not return the invalid-mode diagnostic'
  assert_not_contains "$output" 'working-tree target must stay unread' \
    'status reader followed or printed the symlink target'
  pass 'project status rejects a symlink blob without following it'
}

test_session_branch_wins_and_working_tree_is_ignored
test_remote_default_fallback_ignores_behind_local_main
test_unreadable_remote_default_is_typed
test_missing_status_is_typed
test_symlink_status_is_rejected_without_following_target

printf 'all fm-project-status tests passed\n'
