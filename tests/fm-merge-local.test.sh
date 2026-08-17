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

# Build one sandbox and echo the case dir. Args: name [legacy]
# "legacy" reproduces a task recorded before the canonical-repository change:
# the project is the home's managed clone projects/fixture, the registry entry
# has no path:, and the task meta has no project_id=.
make_case() {
  local dir="$TMP_ROOT/$1" layout=${2:-canonical} project
  mkdir -p "$dir/home/data" "$dir/home/state" "$dir/home/projects"
  project="$dir/project"
  [ "$layout" != legacy ] || project="$dir/home/projects/fixture"
  fm_git_init_commit "$project"
  git -C "$project" branch -m main
  git -C "$project" checkout -q -b "$BRANCH"
  printf 'task work\n' > "$project/task.txt"
  git -C "$project" add task.txt
  git -C "$project" commit -qm 'task: implement'
  git -C "$project" checkout -q main
  git -C "$project" worktree add --quiet "$dir/wt" "$BRANCH"
  if [ "$layout" = legacy ]; then
    printf -- '- fixture [local-only] - local fixture\n' > "$dir/home/data/projects.md"
    fm_write_meta "$dir/home/state/$TASK.meta" \
      "worktree=$dir/wt" "project=$project" "kind=ship" "mode=local-only"
  else
    printf -- '- fixture [local-only] - local fixture\n  path: %s\n' "$project" > "$dir/home/data/projects.md"
    fm_write_meta "$dir/home/state/$TASK.meta" \
      "worktree=$dir/wt" "project_id=fixture" "project=$project" "kind=ship" "mode=local-only"
  fi
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

test_lands_legacy_task_while_entry_is_pathless() {
  local dir rc target project
  dir=$(make_case legacy-pathless legacy)
  project="$dir/home/projects/fixture"
  target=$(git -C "$dir/wt" rev-parse HEAD)

  set +e
  run_merge "$dir" > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "legacy pathless landing"
  [ "$(git -C "$project" rev-parse HEAD)" = "$target" ] || fail "legacy pathless landing did not move main"
  pass "fm-merge-local lands a task recorded without project_id while its entry is still pathless"
}

test_refuses_legacy_task_once_entry_is_migrated() {
  local dir rc before project
  dir=$(make_case legacy-migrated legacy)
  project="$dir/home/projects/fixture"
  git clone --quiet "$project" "$dir/canonical"
  printf -- '- fixture [local-only] - local fixture\n  path: %s\n' "$dir/canonical" > "$dir/home/data/projects.md"
  before=$(git -C "$project" rev-parse HEAD)

  set +e
  run_merge "$dir" > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "legacy migrated refusal"
  assert_grep 'PROJECT_IDENTITY_MISSING' "$dir/stderr" "legacy migrated refusal did not name the missing identity"
  [ "$(git -C "$project" rev-parse HEAD)" = "$before" ] || fail "legacy migrated refusal moved the retained clone's main"
  pass "fm-merge-local refuses a task recorded without project_id once its project has a canonical path"
}

test_preserves_nonconflicting_untracked_file
test_refuses_untracked_collision_without_mutation
test_lands_legacy_task_while_entry_is_pathless
test_refuses_legacy_task_once_entry_is_migrated
