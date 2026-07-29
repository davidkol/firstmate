#!/usr/bin/env bash
# Tests for bin/fm-merge-main.sh: the path firstmate uses to land a validated-main
# ship task on the project's default branch and push it to the host, with no pull
# request at any point.
#
# The load-bearing property is that the merge source is the PUBLISHED head
# (origin/fm/<id>) whenever it exists, because the no-mistakes pipeline commits its
# own fix rounds and pushes them - the local task branch is routinely behind, and
# merging the stale local head would land code the reviewer never saw.
#
# Matrix:
#   (a) lands the published head on the default branch, pushes it, retires the branch
#   (b) refuses a task whose mode is not validated-main
#   (c) refuses when the local branch carries commits the published head lacks
#   (d) refuses a branch that has diverged from the default branch
#   (e) refuses when the host's default branch has moved ahead of the branch
#   (f) lands the local branch when the pipeline published nothing
#   (g) refuses a dirty project checkout
#   (h) refuses a project with no origin remote
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

MERGE_MAIN="$ROOT/bin/fm-merge-main.sh"
TMP_ROOT=$(fm_test_tmproot fm-merge-main-tests)
TASK=task-m1
BRANCH="fm/$TASK"

# Build one sandbox: a bare remote, a project clone on main, a task branch with one
# commit, and a task meta. Echoes the case dir. Args: name [mode]
make_case() {
  local name=$1 mode=${2:-validated-main} case_dir
  case_dir="$TMP_ROOT/$name"
  mkdir -p "$case_dir/state"

  git init -q -b main "$case_dir/seed"
  printf 'seed\n' > "$case_dir/seed/README.md"
  git -C "$case_dir/seed" add README.md
  git -C "$case_dir/seed" commit -qm initial
  git clone --quiet --bare "$case_dir/seed" "$case_dir/remote.git"
  git clone --quiet "$case_dir/remote.git" "$case_dir/project"

  git -C "$case_dir/project" checkout -q -b "$BRANCH"
  printf 'task work\n' > "$case_dir/project/task.txt"
  git -C "$case_dir/project" add task.txt
  git -C "$case_dir/project" commit -qm 'task: implement'
  git -C "$case_dir/project" checkout -q main

  fm_write_meta "$case_dir/state/$TASK.meta" \
    "window=fm-$TASK" \
    "worktree=$case_dir/wt" \
    "project=$case_dir/project" \
    "kind=ship" \
    "mode=$mode"
  printf '%s\n' "$case_dir"
}

# Simulate the pipeline's push step publishing the task branch.
publish_branch() {
  git -C "$1/project" push --quiet origin "$BRANCH"
}

# Add one commit to the task branch without publishing it.
commit_on_branch() {
  local case_dir=$1 text=$2
  git -C "$case_dir/project" checkout -q "$BRANCH"
  printf '%s\n' "$text" > "$case_dir/project/extra.txt"
  git -C "$case_dir/project" add extra.txt
  git -C "$case_dir/project" commit -qm "task: $text"
  git -C "$case_dir/project" checkout -q main
}

# Advance the host's default branch from a separate clone, so the project's
# origin/main is behind after a fetch.
advance_remote_main() {
  local case_dir=$1
  git clone --quiet "$case_dir/remote.git" "$case_dir/other"
  printf 'other work\n' > "$case_dir/other/other.txt"
  git -C "$case_dir/other" add other.txt
  git -C "$case_dir/other" commit -qm 'other: land first'
  git -C "$case_dir/other" push --quiet origin main
}

run_merge_main() {
  local case_dir=$1; shift
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$case_dir/state" \
    "$MERGE_MAIN" "$@"
}

remote_main_sha() {
  git -C "$1/remote.git" rev-parse main
}

test_lands_published_head_and_pushes() {
  local case_dir rc branch_sha
  case_dir=$(make_case lands-published)
  publish_branch "$case_dir"
  branch_sha=$(git -C "$case_dir/project" rev-parse "$BRANCH")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "lands-published: fm-merge-main should succeed"
  assert_grep "validated head origin/$BRANCH" "$case_dir/stdout" \
    "lands-published: should report landing the published head, not the local branch"
  [ "$(git -C "$case_dir/project" rev-parse main)" = "$branch_sha" ] \
    || fail "lands-published: local main was not fast-forwarded to the task branch"
  [ "$(remote_main_sha "$case_dir")" = "$branch_sha" ] \
    || fail "lands-published: the host's main was not updated - the change never reached the host"
  git -C "$case_dir/remote.git" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
    && fail "lands-published: the published task branch should be retired after landing"
  assert_grep "retired published branch origin/$BRANCH" "$case_dir/stdout" \
    "lands-published: retiring the published branch should be reported"
  pass "fm-merge-main lands the published head on main, pushes it, and retires the branch"
}

test_refuses_wrong_mode() {
  local case_dir rc before
  case_dir=$(make_case wrong-mode no-mistakes)
  publish_branch "$case_dir"
  before=$(remote_main_sha "$case_dir")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "wrong-mode: fm-merge-main should refuse a non-validated-main task"
  assert_grep 'not validated-main' "$case_dir/stderr" \
    "wrong-mode: the refusal should name the mode mismatch"
  [ "$(remote_main_sha "$case_dir")" = "$before" ] \
    || fail "wrong-mode: the host's main must not move on a refusal"
  pass "fm-merge-main refuses a task whose mode is not validated-main"
}

test_refuses_unvalidated_local_commits() {
  local case_dir rc before
  case_dir=$(make_case local-ahead)
  publish_branch "$case_dir"
  commit_on_branch "$case_dir" 'edited after validation'
  before=$(remote_main_sha "$case_dir")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "local-ahead: fm-merge-main should refuse unvalidated local commits"
  assert_grep "commits the validated head origin/$BRANCH does not contain" "$case_dir/stderr" \
    "local-ahead: the refusal should name the unvalidated commits"
  [ "$(remote_main_sha "$case_dir")" = "$before" ] \
    || fail "local-ahead: unvalidated work must never reach the host"
  pass "fm-merge-main refuses when the local branch carries commits the validated head lacks"
}

test_refuses_diverged_branch() {
  local case_dir rc before
  case_dir=$(make_case diverged)
  # Move local main forward on its own, so the branch is no longer a fast-forward.
  printf 'divergent\n' > "$case_dir/project/divergent.txt"
  git -C "$case_dir/project" add divergent.txt
  git -C "$case_dir/project" commit -qm 'main: diverge'
  publish_branch "$case_dir"
  before=$(remote_main_sha "$case_dir")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "diverged: fm-merge-main should refuse a non-fast-forward"
  assert_grep 'has diverged' "$case_dir/stderr" \
    "diverged: the refusal should name the divergence"
  [ "$(remote_main_sha "$case_dir")" = "$before" ] \
    || fail "diverged: the host's main must not move on a refusal"
  pass "fm-merge-main refuses a task branch that has diverged from the default branch"
}

test_refuses_when_host_main_moved() {
  local case_dir rc before
  case_dir=$(make_case host-moved)
  publish_branch "$case_dir"
  advance_remote_main "$case_dir"
  before=$(remote_main_sha "$case_dir")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "host-moved: fm-merge-main should refuse when the host's main moved ahead"
  assert_grep "does not contain origin/main" "$case_dir/stderr" \
    "host-moved: the refusal should name the moved host default branch"
  [ "$(remote_main_sha "$case_dir")" = "$before" ] \
    || fail "host-moved: the host's main must not be rewound or force-moved"
  pass "fm-merge-main refuses when the host's default branch has moved ahead of the branch"
}

test_lands_local_branch_when_nothing_published() {
  local case_dir rc branch_sha
  case_dir=$(make_case nothing-published)
  branch_sha=$(git -C "$case_dir/project" rev-parse "$BRANCH")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "nothing-published: fm-merge-main should land the local branch"
  assert_grep "local $BRANCH" "$case_dir/stdout" \
    "nothing-published: should report landing the local branch"
  [ "$(remote_main_sha "$case_dir")" = "$branch_sha" ] \
    || fail "nothing-published: the host's main was not updated"
  pass "fm-merge-main lands the local branch when the pipeline published nothing"
}

test_refuses_dirty_project() {
  local case_dir rc before
  case_dir=$(make_case dirty-project)
  publish_branch "$case_dir"
  printf 'uncommitted\n' > "$case_dir/project/dirty.txt"
  git -C "$case_dir/project" add dirty.txt
  before=$(remote_main_sha "$case_dir")

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "dirty-project: fm-merge-main should refuse a dirty checkout"
  assert_grep 'dirty working tree' "$case_dir/stderr" \
    "dirty-project: the refusal should name the dirty working tree"
  [ "$(remote_main_sha "$case_dir")" = "$before" ] \
    || fail "dirty-project: the host's main must not move on a refusal"
  pass "fm-merge-main refuses a dirty project checkout"
}

test_refuses_project_without_origin() {
  local case_dir rc
  case_dir=$(make_case no-origin)
  git -C "$case_dir/project" remote remove origin

  set +e
  run_merge_main "$case_dir" "$TASK" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "no-origin: fm-merge-main should refuse a project with no origin"
  assert_grep 'no origin remote' "$case_dir/stderr" \
    "no-origin: the refusal should name the missing remote and point at local-only"
  pass "fm-merge-main refuses a validated-main project that has no origin remote"
}

test_lands_published_head_and_pushes
test_refuses_wrong_mode
test_refuses_unvalidated_local_commits
test_refuses_diverged_branch
test_refuses_when_host_main_moved
test_lands_local_branch_when_nothing_published
test_refuses_dirty_project
test_refuses_project_without_origin
