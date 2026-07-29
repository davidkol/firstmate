#!/usr/bin/env bash
# Tests for bin/fm-review-diff.sh: when a task has an open PR recorded in meta,
# the review diff must compare the authoritative base against a freshly fetched
# PR head, not a stale local branch or a stale recorded pr_head= left behind
# after no-mistakes fix rounds push to the PR.
#
# Matrix:
#   (a) pr= + reachable pr_head=, no remote pull ref -> offline fallback to recorded SHA
#   (b) pr= without pr_head= -> fetch refs/pull/<n>/head and diff that
#   (c) pr= absent -> unchanged worktree-branch diff
#   (d) pr= present but PR head unreachable -> fallback to local branch + warning
#   (e) pr= + STALE recorded pr_head= + newer remote pull head -> must use fetched head
#       (this is the class that bit reviewers holding merges over "missing" fixes)
#
# mode=validated-main opens no PR, so it never records pr=, but its pipeline still
# pushes and bin/fm-merge-main.sh lands origin/<branch>. The review must therefore
# compare the published head, not the routinely-behind local branch:
#   (f) mode=validated-main + published origin/fm/<id> -> diff the published head
#   (g) mode=validated-main + nothing published -> local branch, no warning
#   (h) mode=validated-main + unreachable remote -> local branch WITH a warning
#
# Each fallback above is otherwise indistinguishable from a normal run on stdout,
# so every case asserts the "compare: " line naming the side actually used, and
#   (i) mode=validated-main + local branch ahead of the published head -> the diff
#       names the published head and reports the local commits it omits
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

REVIEW_DIFF="$ROOT/bin/fm-review-diff.sh"
TMP_ROOT=$(fm_test_tmproot fm-review-diff-tests)

make_case() {
  local name=$1 case_dir
  case_dir="$TMP_ROOT/$name"
  mkdir -p "$case_dir/state"

  git init -q --bare "$case_dir/origin.git"
  git -C "$case_dir/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$case_dir/origin.git" "$case_dir/_seed" 2>/dev/null
  printf 'base\n' > "$case_dir/_seed/feature.txt"
  git -C "$case_dir/_seed" add feature.txt
  git -C "$case_dir/_seed" -c user.email=t@t -c user.name=t commit -qm "origin baseline"
  git -C "$case_dir/_seed" push -q origin main
  rm -rf "$case_dir/_seed"

  git clone -q "$case_dir/origin.git" "$case_dir/project"
  git -C "$case_dir/project" remote set-head origin main 2>/dev/null || true
  git -C "$case_dir/project" worktree add -q -b fm/task-x1 "$case_dir/wt" main

  touch "$case_dir/state/.last-watcher-beat"
  printf '%s\n' "$case_dir"
}

write_task_meta() {
  local case_dir=$1
  shift
  fm_write_meta "$case_dir/state/task-x1.meta" \
    "window=fm-task-x1" \
    "worktree=$case_dir/wt" \
    "project=$case_dir/project" \
    "$@"
}

stale_and_pr_commits() {
  local case_dir=$1
  printf 'stale-local\n' > "$case_dir/wt/feature.txt"
  git -C "$case_dir/wt" add feature.txt
  git -C "$case_dir/wt" commit -qm "stale local branch"

  git -C "$case_dir/wt" checkout -q -b pr-head-tmp
  printf 'pr-fixed\n' > "$case_dir/wt/feature.txt"
  git -C "$case_dir/wt" add feature.txt
  git -C "$case_dir/wt" commit -qm "pipeline fix on PR"
  PR_SHA=$(git -C "$case_dir/wt" rev-parse HEAD)

  git -C "$case_dir/wt" checkout -q fm/task-x1
}

run_review_diff() {
  local case_dir=$1
  shift
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$case_dir/state" \
    "$REVIEW_DIFF" "$@"
}

test_pr_meta_uses_pr_head_not_stale_local() {
  local case_dir out
  case_dir=$(make_case pr-head-sha)
  stale_and_pr_commits "$case_dir"
  # No remote pull ref: fetch fails, recorded pr_head is the offline fallback.
  write_task_meta "$case_dir" \
    "pr=https://github.com/example/repo/pull/9" \
    "pr_head=$PR_SHA"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+pr-fixed' "pr-head-sha: diff should show the PR head content"
  assert_not_contains "$out" 'stale-local' "pr-head-sha: diff must not use the stale local branch"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: PR head unavailable' \
    "pr-head-sha: should not warn when recorded pr_head is reachable offline"
  assert_contains "$out" "compare: PR head $PR_SHA" \
    "pr-head-sha: must name the resolved PR head as the compare side"
  pass "fm-review-diff falls back to recorded pr_head when pull head cannot be fetched"
}

test_stale_recorded_pr_head_loses_to_fetched_pull_head() {
  local case_dir out stale_sha
  case_dir=$(make_case stale-recorded)
  stale_and_pr_commits "$case_dir"
  stale_sha=$(git -C "$case_dir/wt" rev-parse fm/task-x1)
  # Remote PR head is newer (pipeline fix); meta still points at the older local tip.
  git -C "$case_dir/wt" push -q origin "pr-head-tmp:refs/pull/9/head"
  write_task_meta "$case_dir" \
    "pr=https://github.com/example/repo/pull/9" \
    "pr_head=$stale_sha"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+pr-fixed' \
    "stale-recorded: diff must show the fetched PR head, not the recorded stale SHA"
  assert_not_contains "$out" 'stale-local' \
    "stale-recorded: diff must not use the stale local/recorded content"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: PR head unavailable' \
    "stale-recorded: fetch of refs/pull/<n>/head should succeed"
  assert_contains "$out" "compare: PR head $PR_SHA" \
    "stale-recorded: compare line must name the fetched PR head, not the recorded SHA"
  # Pre-fix behavior preferred reachable recorded pr_head= and would show stale-local.
  [ "$stale_sha" != "$PR_SHA" ] || fail "stale-recorded: fixture did not diverge recorded vs PR head"
  pass "fm-review-diff prefers freshly fetched PR head over a stale recorded pr_head="
}

test_pr_meta_fetches_pull_head_without_recorded_sha() {
  local case_dir out
  case_dir=$(make_case pr-fetch)
  stale_and_pr_commits "$case_dir"
  git -C "$case_dir/wt" push -q origin "pr-head-tmp:refs/pull/9/head"
  write_task_meta "$case_dir" "pr=https://github.com/example/repo/pull/9"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+pr-fixed' "pr-fetch: diff should use fetched PR head"
  assert_not_contains "$out" 'stale-local' "pr-fetch: diff must not use the stale local branch"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: PR head unavailable' \
    "pr-fetch: should not warn when fetch succeeds"
  assert_contains "$out" "compare: PR head $PR_SHA" \
    "pr-fetch: must name the fetched PR head as the compare side"
  pass "fm-review-diff fetches refs/pull/<n>/head when pr_head= is absent"
}

test_no_pr_meta_uses_local_branch() {
  local case_dir out
  case_dir=$(make_case no-pr-meta)
  stale_and_pr_commits "$case_dir"
  write_task_meta "$case_dir"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+stale-local' "no-pr-meta: diff should still use the local branch"
  assert_not_contains "$out" '+pr-fixed' "no-pr-meta: diff must not jump to the unpushed PR commit"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: PR head unavailable' \
    "no-pr-meta: no warning without pr= in meta"
  assert_contains "$out" 'compare: local branch fm/task-x1' \
    "no-pr-meta: must name the local branch as the compare side"
  pass "fm-review-diff without pr= keeps the worktree-branch diff"
}

test_unreachable_pr_head_falls_back_with_warning() {
  local case_dir out err
  case_dir=$(make_case fetch-fallback)
  stale_and_pr_commits "$case_dir"
  git -C "$case_dir/wt" remote remove origin
  write_task_meta "$case_dir" \
    "pr=https://github.com/example/repo/pull/9" \
    "pr_head=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  set +e
  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")
  set -e
  err=$(cat "$case_dir/stderr")

  assert_contains "$err" 'warning: PR head unavailable; diff may lag the open PR' \
    "fetch-fallback: must warn when PR head cannot be resolved"
  assert_contains "$out" '+stale-local' "fetch-fallback: should fall back to the local branch diff"
  assert_not_contains "$out" '+pr-fixed' "fetch-fallback: must not invent a PR head diff offline"
  assert_contains "$out" 'compare: local branch fm/task-x1 (PR head unavailable)' \
    "fetch-fallback: compare line must disclose the fallback to the local branch"
  pass "fm-review-diff falls back to local branch with a warning when PR head is unreachable"
}

test_validated_main_uses_published_head() {
  local case_dir out
  case_dir=$(make_case validated-main-published)
  stale_and_pr_commits "$case_dir"
  # The pipeline's push step published its fix round; the local branch is behind.
  git -C "$case_dir/wt" push -q origin "pr-head-tmp:refs/heads/fm/task-x1"
  write_task_meta "$case_dir" "mode=validated-main"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+pr-fixed' \
    "validated-main-published: diff must show the published head fm-merge-main.sh would land"
  assert_not_contains "$out" 'stale-local' \
    "validated-main-published: diff must not use the behind local branch"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: published head origin/' \
    "validated-main-published: no warning when the published head resolves"
  assert_contains "$out" "compare: published head origin/fm/task-x1 $PR_SHA" \
    "validated-main-published: must name the published head as the compare side"
  assert_not_contains "$out" 'the published head does not contain' \
    "validated-main-published: local branch is behind, so there is nothing omitted to report"
  pass "fm-review-diff on validated-main compares the published origin branch head"
}

test_validated_main_unpublished_uses_local_branch() {
  local case_dir out
  case_dir=$(make_case validated-main-unpublished)
  stale_and_pr_commits "$case_dir"
  # Nothing pushed: the pipeline's push step has not run, so local is the only head.
  write_task_meta "$case_dir" "mode=validated-main"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" '+stale-local' \
    "validated-main-unpublished: diff should use the local branch"
  assert_not_contains "$(cat "$case_dir/stderr")" 'warning: published head origin/' \
    "validated-main-unpublished: an unpublished branch is normal, not a warning"
  assert_contains "$out" 'compare: local branch fm/task-x1 (nothing published)' \
    "validated-main-unpublished: stderr stays silent, so the compare line must say nothing is published"
  pass "fm-review-diff on validated-main uses the local branch when nothing is published"
}

test_validated_main_unreachable_remote_warns() {
  local case_dir out err
  case_dir=$(make_case validated-main-unreachable)
  stale_and_pr_commits "$case_dir"
  # Worktrees share .git/config, so this takes origin away from the project too -
  # a validated-main task that cannot reach its remote at all.
  git -C "$case_dir/wt" remote remove origin
  write_task_meta "$case_dir" "mode=validated-main"

  set +e
  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")
  set -e
  err=$(cat "$case_dir/stderr")

  assert_contains "$err" "warning: published head origin/fm/task-x1 unavailable" \
    "validated-main-unreachable: must warn when the published head cannot be resolved"
  assert_contains "$out" '+stale-local' \
    "validated-main-unreachable: should fall back to the local branch diff"
  assert_contains "$out" 'compare: local branch fm/task-x1 (published head unavailable)' \
    "validated-main-unreachable: compare line must disclose the fallback to the local branch"
  pass "fm-review-diff on validated-main warns when the published head is unreachable"
}

test_validated_main_reports_local_commits_missing_from_published_head() {
  local case_dir out
  case_dir=$(make_case validated-main-local-ahead)
  stale_and_pr_commits "$case_dir"
  git -C "$case_dir/wt" push -q origin "pr-head-tmp:refs/heads/fm/task-x1"
  # Committed after the pipeline published: the head that lands does not carry it,
  # and bin/fm-merge-main.sh refuses exactly this state, so review must say so.
  printf 'local-only\n' > "$case_dir/wt/extra.txt"
  git -C "$case_dir/wt" add extra.txt
  git -C "$case_dir/wt" commit -qm "edited after validation"
  write_task_meta "$case_dir" "mode=validated-main"

  out=$(run_review_diff "$case_dir" task-x1 2> "$case_dir/stderr")

  assert_contains "$out" "compare: published head origin/fm/task-x1 $PR_SHA" \
    "validated-main-local-ahead: compare side is still the published head"
  assert_contains "$out" 'has 1 commit(s) the published head does not contain' \
    "validated-main-local-ahead: must report the local commits the diff omits"
  assert_not_contains "$out" 'extra.txt' \
    "validated-main-local-ahead: the local-only commit is genuinely absent from the diff"
  pass "fm-review-diff on validated-main reports local commits the published head omits"
}

test_pr_meta_uses_pr_head_not_stale_local
test_pr_meta_fetches_pull_head_without_recorded_sha
test_stale_recorded_pr_head_loses_to_fetched_pull_head
test_no_pr_meta_uses_local_branch
test_unreachable_pr_head_falls_back_with_warning
test_validated_main_uses_published_head
test_validated_main_unpublished_uses_local_branch
test_validated_main_unreachable_remote_warns
test_validated_main_reports_local_commits_missing_from_published_head
