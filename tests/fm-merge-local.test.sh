#!/usr/bin/env bash
# Focused behavior tests for canonical local-only landing.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

MERGE_LOCAL="$ROOT/bin/fm-merge-local.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-merge-local.XXXXXX")
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
TASK=local-task
BRANCH="fm/$TASK"

make_case() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/home/data" "$dir/home/state" "$dir/home/projects"
  fm_git_init_commit "$dir/project"
  git -C "$dir/project" branch -m main
  git -C "$dir/project" checkout -q -b "$BRANCH"
  printf 'task work\n' > "$dir/project/task.txt"
  git -C "$dir/project" add task.txt
  git -C "$dir/project" commit -qm 'task: implement'
  git -C "$dir/project" checkout -q main
  git -C "$dir/project" worktree add --quiet "$dir/wt" "$BRANCH"
  printf -- '- fixture [local-only] - local fixture\n  path: %s\n' "$dir/project" > "$dir/home/data/projects.md"
  fm_write_meta "$dir/home/state/$TASK.meta" \
    "worktree=$dir/wt" "project_id=fixture" "project=$dir/project" "kind=ship" "mode=local-only"
  printf '%s\n' "$dir"
}

run_merge() {
  local dir=$1
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$dir/home" FM_STATE_OVERRIDE="$dir/home/state" \
    "$MERGE_LOCAL" "$TASK"
}

test_preserves_nonconflicting_untracked_file() {
  local dir rc target
  dir=$(make_case safe)
  target=$(git -C "$dir/wt" rev-parse HEAD)
  printf 'captain notes\n' > "$dir/project/notes.md"

  set +e
  run_merge "$dir" > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "local untracked-safe landing"
  [ "$(git -C "$dir/project" rev-parse HEAD)" = "$target" ] || fail "local untracked-safe landing did not move main"
  [ "$(cat "$dir/project/notes.md")" = "captain notes" ] || fail "local untracked-safe landing changed notes.md"
  pass "fm-merge-local preserves a nonconflicting untracked file"
}

test_refuses_untracked_collision_without_mutation() {
  local dir rc before index_before
  dir=$(make_case collision)
  printf 'task tracked version\n' > "$dir/wt/collision.txt"
  git -C "$dir/wt" add collision.txt
  git -C "$dir/wt" commit -qm 'task: add collision target'
  printf 'captain local version\n' > "$dir/project/collision.txt"
  before=$(git -C "$dir/project" rev-parse HEAD)
  index_before=$(git -C "$dir/project" write-tree)

  set +e
  run_merge "$dir" > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "local untracked collision"
  assert_grep 'untracked' "$dir/stderr" "local collision refusal did not identify untracked state"
  [ "$(git -C "$dir/project" rev-parse HEAD)" = "$before" ] || fail "local collision moved HEAD"
  [ "$(git -C "$dir/project" write-tree)" = "$index_before" ] || fail "local collision changed index"
  [ "$(cat "$dir/project/collision.txt")" = "captain local version" ] || fail "local collision changed local file"
  pass "fm-merge-local refuses an untracked collision without mutation"
}

test_preserves_nonconflicting_untracked_file
test_refuses_untracked_collision_without_mutation
