#!/usr/bin/env bash
# Tests for bin/fm-validate.sh: the one place a task's pipeline skip set is
# derived from its delivery mode.
#
# The point of this script is that `--skip pr,ci` is structural. A validated-main
# task must inherit it on every run by anyone, without a worker remembering to type
# it, so these tests pin that the flags come from the recorded mode and that a
# caller cannot displace them.
#
# The load-bearing negative is that no mode ever skips review, test, document, or
# lint. Dropping the pull request is not dropping the automated review, and the
# review is what makes landing without a human reading the diff safe.
#
# Matrix:
#   (a) validated-main derives --skip pr,ci
#   (b) no-mistakes runs the full pipeline with no --skip
#   (c) a caller's --skip is merged with the mode's, never replaces it
#   (d) the --skip=<v> form merges the same way
#   (e) no mode ever skips review, test, document, or lint
#   (f) a missing --intent refuses before starting a run
#   (g) missing task meta refuses before starting a run
#   (h) a mode with no recorded value falls back to the full pipeline
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VALIDATE="$ROOT/bin/fm-validate.sh"
TMP_ROOT=$(fm_test_tmproot fm-validate-tests)

# One sandbox: a state dir with a task meta and a no-mistakes mock on PATH that
# records the exact argv it was invoked with. Echoes the case dir.
make_case() {
  local name=$1 mode=$2 case_dir fakebin
  case_dir="$TMP_ROOT/$name"
  fakebin="$case_dir/fakebin"
  mkdir -p "$case_dir/state" "$fakebin"
  if [ "$mode" != "__none__" ]; then
    fm_write_meta "$case_dir/state/task-v1.meta" \
      "window=fm-task-v1" \
      "worktree=$case_dir/wt" \
      "project=$case_dir/project" \
      "kind=ship" \
      "mode=$mode"
  else
    fm_write_meta "$case_dir/state/task-v1.meta" \
      "window=fm-task-v1" \
      "worktree=$case_dir/wt" \
      "project=$case_dir/project" \
      "kind=ship"
  fi
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FM_TEST_NM_LOG"
exit 0
SH
  chmod +x "$fakebin/no-mistakes"
  printf '%s\n' "$case_dir"
}

run_validate() {
  local case_dir=$1; shift
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$case_dir/state" \
  FM_TEST_NM_LOG="$case_dir/nm.log" \
  PATH="$case_dir/fakebin:$PATH" \
    "$VALIDATE" "$@"
}

invoked() {
  cat "$1/nm.log" 2>/dev/null || true
}

test_validated_main_derives_skip() {
  local case_dir
  case_dir=$(make_case validated-main-skip validated-main)
  run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
    || fail "validated-main-skip: fm-validate should succeed"
  assert_contains "$(invoked "$case_dir")" 'axi run --skip pr,ci' \
    "validated-main-skip: the pr and ci skips must come from the mode, not the caller"
  pass "fm-validate derives --skip pr,ci from a validated-main task's recorded mode"
}

test_no_mistakes_runs_full_pipeline() {
  local case_dir
  case_dir=$(make_case nomistakes-full no-mistakes)
  run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
    || fail "nomistakes-full: fm-validate should succeed"
  assert_not_contains "$(invoked "$case_dir")" '--skip' \
    "nomistakes-full: a no-mistakes task must run every step including pr and ci"
  pass "fm-validate runs the full pipeline for a no-mistakes task"
}

test_caller_skip_is_merged_not_substituted() {
  local case_dir out
  case_dir=$(make_case caller-skip-merged validated-main)
  run_validate "$case_dir" task-v1 --intent "add a thing" --skip lint >/dev/null 2>&1 \
    || fail "caller-skip-merged: fm-validate should succeed"
  out=$(invoked "$case_dir")
  assert_contains "$out" '--skip pr,ci,lint' \
    "caller-skip-merged: a caller's --skip must merge with the mode's, never replace it"
  pass "fm-validate merges a caller's --skip with the mode's instead of letting it win"
}

test_caller_skip_equals_form_is_merged() {
  local case_dir
  case_dir=$(make_case caller-skip-equals validated-main)
  run_validate "$case_dir" task-v1 --intent "add a thing" --skip=lint >/dev/null 2>&1 \
    || fail "caller-skip-equals: fm-validate should succeed"
  assert_contains "$(invoked "$case_dir")" '--skip pr,ci,lint' \
    "caller-skip-equals: the --skip=<v> form must merge the same way as --skip <v>"
  pass "fm-validate merges the --skip=<value> form the same way"
}

# The property the whole delivery mode rests on. If a mode ever skipped review,
# landing straight on a default branch would have nothing standing between an
# unread change and main.
test_no_mode_skips_the_local_review_surface() {
  local case_dir out mode step
  for mode in validated-main no-mistakes direct-PR local-only; do
    case_dir=$(make_case "review-kept-$mode" "$mode")
    run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
      || fail "review-kept-$mode: fm-validate should succeed"
    out=$(invoked "$case_dir")
    for step in review test document lint; do
      assert_not_contains "$out" "$step" \
        "review-kept-$mode: mode $mode must never skip the $step step"
    done
  done
  pass "fm-validate never skips review, test, document, or lint for any delivery mode"
}

test_missing_intent_refuses() {
  local case_dir rc
  case_dir=$(make_case missing-intent validated-main)
  set +e
  run_validate "$case_dir" task-v1 > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  expect_code 1 "$rc" "missing-intent: fm-validate should refuse without --intent"
  assert_grep '--intent is required' "$case_dir/stderr" \
    "missing-intent: the refusal should name the missing intent"
  [ ! -s "$case_dir/nm.log" ] || fail "missing-intent: no run should have been started"
  pass "fm-validate refuses a run with no --intent before starting one"
}

test_missing_meta_refuses() {
  local case_dir rc
  case_dir=$(make_case missing-meta validated-main)
  rm -f "$case_dir/state/task-v1.meta"
  set +e
  run_validate "$case_dir" task-v1 > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  expect_code 1 "$rc" "missing-meta: fm-validate should refuse with no task meta"
  assert_grep 'no meta for task task-v1' "$case_dir/stderr" \
    "missing-meta: the refusal should name the missing record"
  [ ! -s "$case_dir/nm.log" ] || fail "missing-meta: no run should have been started"
  pass "fm-validate refuses before starting a run when the task record is missing"
}

test_absent_mode_falls_back_to_full_pipeline() {
  local case_dir
  case_dir=$(make_case absent-mode __none__)
  run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
    || fail "absent-mode: fm-validate should succeed"
  assert_not_contains "$(invoked "$case_dir")" '--skip' \
    "absent-mode: an unrecorded mode must fall back to the full pipeline, never to skipping steps"
  pass "fm-validate falls back to the full pipeline when the task records no mode"
}

test_validated_main_derives_skip
test_no_mistakes_runs_full_pipeline
test_caller_skip_is_merged_not_substituted
test_caller_skip_equals_form_is_merged
test_no_mode_skips_the_local_review_surface
test_missing_intent_refuses
test_missing_meta_refuses
test_absent_mode_falls_back_to_full_pipeline
