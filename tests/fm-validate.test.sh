#!/usr/bin/env bash
# Tests for bin/fm-validate.sh: the one place a task's pipeline skip set is
# derived from its delivery mode.
#
# The point of this script is that `--skip pr,ci` is structural. A validated-main
# task must inherit it on every run by anyone, without a worker remembering to type
# it, so these tests pin that the flags come from the recorded mode and that a
# caller cannot displace them.
#
# The load-bearing negative is that no mode ever skips review. Dropping the pull
# request is not dropping the automated review, and the review is what makes landing
# without a human reading the diff safe. direct-PR and local-only are the light
# paths: they keep review alone, which ADDS the reviewer to paths that previously ran
# no pipeline at all, so a regression that drops review from them returns those paths
# to having nothing read the change. The full-pipeline modes separately keep test,
# document, and lint.
#
# Matrix:
#   (a) validated-main derives --skip pr,ci
#   (b) no-mistakes runs the full pipeline with no --skip
#   (c) a caller's --skip is merged with the mode's, never replaces it
#   (d) the --skip=<v> form merges the same way
#   (e) no mode ever skips review
#   (f) a caller's own --skip review is stripped, for every mode
#   (g) direct-PR and local-only derive the review-only skip set
#   (h) the full-pipeline modes never skip test, document, or lint
#   (i) missing executed evidence refuses before starting a run
#   (j) missing task meta refuses before starting a run
#   (k) a mode with no recorded value falls back to the full pipeline
#   (l) running outside the task's recorded worktree refuses before starting a run
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VALIDATE="$ROOT/bin/fm-validate.sh"
TMP_ROOT=$(fm_test_tmproot fm-validate-tests)

# One sandbox: a state dir with a task meta, the worktree that meta records, and a
# no-mistakes mock on PATH that records the exact argv it was invoked with. Echoes
# the case dir.
make_case() {
  local name=$1 mode=$2 case_dir fakebin
  case_dir="$TMP_ROOT/$name"
  fakebin="$case_dir/fakebin"
  mkdir -p "$case_dir/state" "$case_dir/wt" "$case_dir/data/task-v1" "$case_dir/pipeline-tmp" "$fakebin"
  fm_write_ship_brief "$case_dir/data/task-v1/brief.md" T0 \
    "tests/fm-validate.test.sh#$name => validation starts with the recorded delivery topology"
  printf '%s\n' 'command: focused-final-change-check' 'exit: 0' 'result: observable behavior passed' \
    > "$case_dir/wt/final-change-evidence.txt"
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

# The script hands off to no-mistakes in the current directory, so every call runs
# from somewhere explicit. run_validate uses the worktree the task meta records,
# which is where a worker is supposed to be.
run_validate_from() {
  local case_dir=$1 from=$2; shift 2
  (
    cd "$from" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    FM_TEST_NM_LOG="$case_dir/nm.log" \
    TMPDIR="$case_dir/pipeline-tmp" \
    PATH="$case_dir/fakebin:$PATH" \
      "$VALIDATE" "$@"
  )
}

run_validate() {
  local case_dir=$1; shift
  run_validate_from "$case_dir" "$case_dir/wt" "$@" \
    --evidence "$case_dir/wt/final-change-evidence.txt"
}

invoked() {
  cat "$1/nm.log" 2>/dev/null || true
}

invoked_skip() {
  sed -n '1s/.*--skip \([^ ]*\).*/\1/p' "$1/nm.log" 2>/dev/null || true
}

pipeline_evidence_dir() {
  sed -n 's/^Pipeline evidence directory: //p' "$1/nm.log" 2>/dev/null | sed -n '1p'
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

# The property the whole delivery contract rests on. If any mode ever skipped
# review, that path would have nothing standing between an unread change and the
# captain's default branch. This is the one assertion that must hold for every mode,
# including the light one.
test_no_mode_skips_review() {
  local case_dir out mode
  for mode in validated-main no-mistakes direct-PR local-only; do
    case_dir=$(make_case "review-kept-$mode" "$mode")
    run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
      || fail "review-kept-$mode: fm-validate should succeed"
    out=$(invoked_skip "$case_dir")
    assert_not_contains "$out" "review" \
      "review-kept-$mode: mode $mode must never skip the review step"
  done
  pass "fm-validate never skips the review step for any delivery mode"
}

# The same property, against the caller rather than the mode. The merge loop used
# to be purely additive, so `--skip review` passed straight through to the run.
# On a light path review is the only step that runs, so honouring it starts a run
# with all nine steps skipped that still reports a passing outcome - a safeguard
# that returns success without running anything, after which the worker opens the
# PR believing it ran. The reachable path is a worker or firstmate retrying a run
# that keeps failing at the review step, which is the exact flag an agent reaches
# for. Both halves of the final skip set are exercised: the light mode, where
# review is everything, and a full-pipeline mode, where it is one step of several.
test_caller_cannot_skip_review() {
  local case_dir out mode
  for mode in direct-PR validated-main; do
    case_dir=$(make_case "caller-skip-review-$mode" "$mode")
    run_validate "$case_dir" task-v1 --intent "add a thing" --skip review \
      >/dev/null 2> "$case_dir/stderr" \
      || fail "caller-skip-review-$mode: fm-validate should still start the run"
    [ -s "$case_dir/nm.log" ] \
      || fail "caller-skip-review-$mode: the run should still have been started"
    assert_not_contains "$(invoked_skip "$case_dir")" "review" \
      "caller-skip-review-$mode: a caller's --skip review must never reach the final skip set"
    assert_grep "dropped 'review'" "$case_dir/stderr" \
      "caller-skip-review-$mode: dropping the caller's review skip must be reported on stderr"
  done

  case_dir=$(make_case caller-skip-review-equals direct-PR)
  run_validate "$case_dir" task-v1 --intent "add a thing" --skip=review >/dev/null 2>&1 \
    || fail "caller-skip-review-equals: fm-validate should still start the run"
  assert_not_contains "$(invoked_skip "$case_dir")" "review" \
    "caller-skip-review-equals: the --skip=<value> form must not smuggle review through"

  case_dir=$(make_case caller-skip-review-mixed validated-main)
  run_validate "$case_dir" task-v1 --intent "add a thing" --skip review,lint >/dev/null 2>&1 \
    || fail "caller-skip-review-mixed: fm-validate should still start the run"
  out=$(invoked_skip "$case_dir")
  assert_contains "$out" 'pr,ci,lint' \
    "caller-skip-review-mixed: the caller's other requested steps must still merge"
  assert_not_contains "$out" "review" \
    "caller-skip-review-mixed: review must be dropped out of a mixed caller skip set"
  pass "fm-validate strips a caller's --skip review instead of honouring it"
}

# The light paths. Before 2026-07-30 both ran no pipeline at all, so nothing read
# the change before the PR opened or the branch was declared ready. They now run
# review and nothing else: the eight omissions are derived here, so no worker types
# them and a re-run inherits them. A regression that drops review from this set
# silently restores the no-review light path.
#
# push is in the set for both, and for local-only that is load-bearing rather than
# incidental: local-only forbids reaching any remote, so the review may read the
# branch but must never publish it.
test_light_paths_derive_the_review_only_skip_set() {
  local case_dir out step mode
  for mode in direct-PR local-only; do
    case_dir=$(make_case "review-only-$mode" "$mode")
    run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
      || fail "review-only-$mode: fm-validate should succeed"
    out=$(invoked_skip "$case_dir")
    assert_contains "$out" 'intent,rebase,test,document,lint,push,pr,ci' \
      "review-only-$mode: $mode must derive the review-only skip set"
    for step in intent rebase test document lint push pr ci; do
      assert_contains "$out" "$step" \
        "review-only-$mode: $mode must skip the $step step"
    done
    assert_not_contains "$out" "review," \
      "review-only-$mode: review must never appear in the skip set"
  done
  pass "fm-validate derives a review-only run for the light paths"
}

test_t3_review_depth_does_not_change_direct_pr_topology() {
  local case_dir out brief
  case_dir=$(make_case t3-direct-pr direct-PR)
  brief="$case_dir/data/task-v1/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T3' \
    '- outcome: design/system-map.md#assembly => the ordinary player path composes the full system' \
    '- player: normal launch -> use the system -> observe the composed result' \
    '- parts: input=trace; runtime=counter; output=observable change' \
    > "$brief"

  run_validate "$case_dir" task-v1 >/dev/null 2>&1 \
    || fail "t3-direct-pr: fm-validate should keep the direct-PR path usable"
  out=$(invoked "$case_dir")
  assert_contains "$out" '--skip intent,rebase,test,document,lint,push,pr,ci' \
    "t3-direct-pr: T3 evidence depth secretly changed the direct-PR topology"
  assert_contains "$out" 'one full project regression on the final change' \
    "t3-direct-pr: the selected reviewer did not receive the T3 regression duty"
  assert_contains "$out" 'parts: input=trace; runtime=counter; output=observable change' \
    "t3-direct-pr: the selected reviewer did not receive the applicable parts evidence"
  assert_contains "$out" 'whether the task was under-tiered' \
    "t3-direct-pr: the selected reviewer did not receive the tier-check duty"
  assert_contains "$out" 'Executed final-change evidence' \
    "t3-direct-pr: the selected reviewer did not receive the executed evidence"
  assert_contains "$out" 'final-change-evidence.txt' \
    "t3-direct-pr: the selected reviewer cannot inspect the saved result"
  assert_contains "$out" 'do not invent a new product target' \
    "t3-direct-pr: the selected reviewer can still manufacture a new target"
  pass "fm-validate keeps T3 evidence depth independent from direct-PR topology"
}

# Keeping review everywhere must not be read as licence to drop the rest from the
# modes that carry the full pipeline. validated-main lands straight on the default
# branch, so its local test, document, and lint steps stay load-bearing.
test_full_pipeline_modes_keep_test_document_and_lint() {
  local case_dir out mode step
  for mode in validated-main no-mistakes; do
    case_dir=$(make_case "full-surface-$mode" "$mode")
    run_validate "$case_dir" task-v1 --intent "add a thing" >/dev/null 2>&1 \
      || fail "full-surface-$mode: fm-validate should succeed"
    out=$(invoked_skip "$case_dir")
    for step in test document lint; do
      assert_not_contains "$out" "$step" \
        "full-surface-$mode: mode $mode must never skip the $step step"
    done
  done
  pass "fm-validate keeps test, document, and lint for the full-pipeline modes"
}

test_canonical_intent_comes_from_brief() {
  local case_dir out
  case_dir=$(make_case canonical-intent validated-main)
  run_validate "$case_dir" task-v1 >/dev/null 2>&1 \
    || fail "canonical-intent: fm-validate should start without a caller paraphrase"
  out=$(invoked "$case_dir")
  assert_contains "$out" 'Firstmate Designer -> Runtime -> Player selected review.' \
    "canonical-intent: the selected-review role contract did not reach no-mistakes"
  assert_contains "$out" 'tests/fm-validate.test.sh#canonical-intent => validation starts with the recorded delivery topology' \
    "canonical-intent: the canonical outcome did not reach no-mistakes"

  case_dir=$(make_case caller-intent-ignored validated-main)
  run_validate "$case_dir" task-v1 --intent "weakened caller paraphrase" \
    > /dev/null 2> "$case_dir/stderr" \
    || fail "caller-intent-ignored: fm-validate should start with canonical intent"
  out=$(invoked "$case_dir")
  assert_not_contains "$out" 'weakened caller paraphrase' \
    "caller-intent-ignored: a caller paraphrase displaced the canonical outcome"
  assert_grep 'ignored caller --intent' "$case_dir/stderr" \
    "caller-intent-ignored: the ignored paraphrase was not disclosed"
  pass "fm-validate derives canonical selected-review intent from the task brief"
}

test_executed_evidence_is_required_and_forwarded() {
  local case_dir out pipeline_dir published rc
  case_dir=$(make_case required-evidence direct-PR)
  set +e
  run_validate_from "$case_dir" "$case_dir/wt" task-v1 \
    > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  expect_code 1 "$rc" "validation must refuse without an executed evidence capture"
  assert_grep 'at least one --evidence path is required' "$case_dir/stderr" \
    "the refusal did not name the missing final-change evidence"
  [ ! -s "$case_dir/nm.log" ] || fail "the review started without inspectable executed evidence"

  run_validate "$case_dir" task-v1 >/dev/null 2>&1 \
    || fail "validation should start when a non-empty evidence capture is supplied"
  out=$(invoked "$case_dir")
  assert_contains "$out" 'shared no-mistakes evidence surface' \
    "the executed evidence was not forwarded to the selected reviewer"
  assert_contains "$out" 'final-change-evidence.txt' \
    "the selected reviewer did not receive the inspectable capture path"
  pipeline_dir=$(pipeline_evidence_dir "$case_dir")
  [ -n "$pipeline_dir" ] || fail "the invocation did not name its pipeline evidence directory"
  case "$pipeline_dir" in
    "$case_dir/pipeline-tmp/no-mistakes-evidence/"*) ;;
    *) fail "evidence was not published on the no-mistakes temp surface: $pipeline_dir" ;;
  esac
  published="$pipeline_dir/input-1-final-change-evidence.txt"
  cmp "$case_dir/wt/final-change-evidence.txt" "$published" >/dev/null \
    || fail "the published pipeline evidence does not preserve the executed worker capture"
  rm -f "$case_dir/wt/final-change-evidence.txt"
  [ -s "$published" ] \
    || fail "the published capture disappeared with the worker-local copy"
  assert_contains "$out" 'Reuse these captures when no pipeline rebase resolution or review fix changes the relevant final diff.' \
    "an unchanged diff cannot reuse its existing accessible capture"
  assert_contains "$out" 'exact fm-review-convergence record command' \
    "a pipeline change was not bound to its one focused verification"
  assert_contains "$out" "gate worktree's ignored pipeline state" \
    "the next review did not receive the durable pipeline-owned evidence location"
  assert_contains "$out" 'Do not run that command separately.' \
    "the evidence lifecycle can duplicate an execution that already proves the fix"
  assert_contains "$out" 'one bounded closure review' \
    "the review intent did not narrow the post-remediation closure"
  assert_contains "$out" 'never begin review pass three' \
    "the review intent did not expose the executable remediation budget"
  assert_not_contains "$out" '--evidence' \
    "the wrapper leaked its evidence option to no-mistakes instead of consuming it"
  pass "fm-validate publishes reusable evidence and binds changed diffs to pipeline verification"
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

# The skip set is a property of ONE task's repository. Started from anywhere else -
# a wrong directory, a stale or mistyped id - it would hand that task's mode to
# whatever pipeline lives in the current directory, which is the worker-discipline
# failure this script exists to remove.
test_wrong_worktree_refuses() {
  local case_dir rc elsewhere
  case_dir=$(make_case wrong-worktree validated-main)
  elsewhere="$case_dir/somewhere-else"
  mkdir -p "$elsewhere"

  set +e
  run_validate_from "$case_dir" "$elsewhere" task-v1 --intent "add a thing" \
    > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "wrong-worktree: fm-validate should refuse outside the task's worktree"
  assert_grep "worktree is $case_dir/wt" "$case_dir/stderr" \
    "wrong-worktree: the refusal should name the worktree the task records"
  [ ! -s "$case_dir/nm.log" ] \
    || fail "wrong-worktree: another repository's pipeline was started with this task's skip set"
  pass "fm-validate refuses to apply a task's mode-derived skip set outside that task's worktree"
}

# A subdirectory is still inside the task's repository, so no-mistakes resolves the
# same repo there; refusing it would only make the guard annoying.
test_subdirectory_of_worktree_is_accepted() {
  local case_dir
  case_dir=$(make_case worktree-subdir validated-main)
  mkdir -p "$case_dir/wt/src"
  run_validate_from "$case_dir" "$case_dir/wt/src" task-v1 --intent "add a thing" \
    --evidence "$case_dir/wt/final-change-evidence.txt" >/dev/null 2>&1 \
    || fail "worktree-subdir: fm-validate should accept a subdirectory of the task's worktree"
  assert_contains "$(invoked "$case_dir")" 'axi run --skip pr,ci' \
    "worktree-subdir: the run should start normally from inside the worktree"
  pass "fm-validate accepts a subdirectory of the task's worktree"
}

test_validated_main_derives_skip
test_no_mistakes_runs_full_pipeline
test_caller_skip_is_merged_not_substituted
test_caller_skip_equals_form_is_merged
test_no_mode_skips_review
test_caller_cannot_skip_review
test_light_paths_derive_the_review_only_skip_set
test_full_pipeline_modes_keep_test_document_and_lint
test_canonical_intent_comes_from_brief
test_executed_evidence_is_required_and_forwarded
test_missing_meta_refuses
test_absent_mode_falls_back_to_full_pipeline
test_wrong_worktree_refuses
test_subdirectory_of_worktree_is_accepted
test_t3_review_depth_does_not_change_direct_pr_topology
