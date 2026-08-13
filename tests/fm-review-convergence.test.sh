#!/usr/bin/env bash
# Behavioral fixture for Firstmate's bounded no-mistakes review integration.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONVERGENCE="$ROOT/bin/fm-review-convergence.sh"
ADJACENT="$ROOT/tests/fixtures/review-convergence/closure-findings.toon"
TMP_ROOT=$(fm_test_tmproot fm-review-convergence-tests)

make_repo() {
  local initial_count=${2:-6} repo="$TMP_ROOT/$1/repo"
  mkdir -p "$repo/bin" "$repo/src" "$repo/tests"
  git -C "$repo" init -q
  git -C "$repo" config user.name 'Firstmate Tests'
  git -C "$repo" config user.email tests@example.invalid
  printf '# fixture\n' > "$repo/README.md"
  # shellcheck disable=SC2016  # fixture variables must expand when the generated runner executes.
  printf '#!/usr/bin/env bash\nset -eu\nif [ "${1:-}" = --list ]; then\n  i=1\n  while [ "$i" -le "${FM_FIXTURE_TEST_COUNT:-%s}" ]; do\n    printf "tests/fixture-%%03d.test.sh\\n" "$i"\n    i=$((i + 1))\n  done\n  exit 0\nfi\nexit 1\n' "$initial_count" > "$repo/bin/fm-test-run.sh"
  chmod +x "$repo/bin/fm-test-run.sh"
  printf 'base=true\n' > "$repo/src/core.sh"
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  git -C "$repo" branch -M main
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" checkout -qb fm/synthetic
  printf 'base=true\nfeature=true\n' > "$repo/src/core.sh"
  git -C "$repo" add src/core.sh
  git -C "$repo" commit -qm implementation
  printf '%s\n' "$repo"
}

start_and_attach() {
  local case_dir=$1 repo=$2
  mkdir -p "$case_dir/state"
  "$CONVERGENCE" start "$case_dir/state" synthetic "$repo" 1000 1100 \
    "$case_dir/pipeline-final-change.txt" >/dev/null
  "$CONVERGENCE" attach "$case_dir/state" RUN-SYNTHETIC "$repo" "$case_dir/initial-status.toon" >/dev/null
}

write_initial_status() {
  local path=$1
  cat > "$path" <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,awaiting_approval,2,1200
    test,pending,0,0
gate:
  step: review
  status: awaiting_approval
  findings[2]{id,severity,file,action,description}:
    root-a,error,src/core.sh,auto-fix,"First root finding."
    root-b,warning,src/core.sh,auto-fix,"Second root finding."
EOF
}

test_receipt_survives_handoff_and_reuses_only_exact_proof() {
  local case_dir="$TMP_ROOT/receipt" repo counter focused pipeline_capture out rc
  repo=$(make_repo receipt 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null
  counter="$case_dir/verification-runs"
  focused="$case_dir/focused-verification.sh"
  cat > "$focused" <<'SH'
#!/usr/bin/env bash
printf 'run\n' >> "$VERIFY_COUNTER"
printf 'focused verification passed\n'
SH
  chmod +x "$focused"

  VERIFY_COUNTER="$counter" "$CONVERGENCE" record "$repo" -- "$focused" \
    > "$case_dir/first-record.out"
  [ "$(wc -l < "$counter" | tr -d ' ')" -eq 1 ] \
    || fail "focused verification did not execute exactly once"
  pipeline_capture="$case_dir/pipeline-final-change.txt"
  assert_grep 'command: ' "$pipeline_capture" \
    "pipeline evidence omitted the executed command"
  assert_grep 'exit: 0' "$pipeline_capture" \
    "pipeline evidence omitted the successful exit"
  assert_grep 'focused verification passed' "$pipeline_capture" \
    "pipeline evidence omitted the executed output"
  rm -f "$pipeline_capture"

  # A new shell stands in for a cold reviewer/session handoff. The identical
  # command must reuse the receipt without executing it again.
  out=$(VERIFY_COUNTER="$counter" bash -c \
    '"$1" record "$2" -- "$3"' _ "$CONVERGENCE" "$repo" "$focused")
  assert_contains "$out" 'FM_REVIEW_EVIDENCE reused=true' \
    "the cold handoff reran unchanged focused verification instead of reusing it"
  [ "$(wc -l < "$counter" | tr -d ' ')" -eq 1 ] \
    || fail "an unchanged handoff executed focused verification twice"
  [ -s "$pipeline_capture" ] \
    || fail "the cold handoff did not republish pipeline evidence from the bound receipt"

  "$CONVERGENCE" verify "$repo" -- "$focused" \
    >/dev/null || fail "the unchanged code and command did not verify"

  set +e
  "$CONVERGENCE" verify "$repo" -- bash -c 'printf "different\n"' \
    > "$case_dir/different.out" 2> "$case_dir/different.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a different command reused the focused-verification receipt"
  assert_grep 'command binding changed' "$case_dir/different.err" \
    "the different-command refusal did not name the broken binding"

  printf 'base=true\nfeature=true\nchanged-after-proof=true\n' > "$repo/src/core.sh"
  set +e
  "$CONVERGENCE" verify "$repo" -- "$focused" \
    > "$case_dir/tree-binding.out" 2> "$case_dir/tree-binding.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "changed code reused an earlier focused-verification receipt"
  assert_grep 'code binding changed' "$case_dir/tree-binding.err" \
    "the changed-code refusal did not name the tree binding"
  printf 'base=true\nfeature=true\n' > "$repo/src/core.sh"

  sed 's/^run_id=.*/run_id=RUN-OTHER/' \
    "$repo/.no-mistakes/review-convergence/manifest" \
    > "$case_dir/changed-run-manifest"
  mv "$case_dir/changed-run-manifest" "$repo/.no-mistakes/review-convergence/manifest"
  set +e
  "$CONVERGENCE" verify "$repo" -- "$focused" \
    > "$case_dir/run-binding.out" 2> "$case_dir/run-binding.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a prior run's receipt was accepted by a different run"
  assert_grep 'run binding changed' "$case_dir/run-binding.err" \
    "the cross-run receipt refusal did not name the run binding"
  pass "review convergence preserves and safely reuses focused evidence across a handoff"
}

test_second_remediation_is_an_executable_refusal() {
  local case_dir="$TMP_ROOT/budget" repo attempt rc
  repo=$(make_repo budget 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null

  for attempt in 2 3 4 5 6 7 8 9; do
    set +e
    "$CONVERGENCE" begin-remediation "$repo" \
      > "$case_dir/pass-$attempt.out" 2> "$case_dir/pass-$attempt.err"
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "review remediation pass $attempt was allowed"
    assert_grep 'one batched remediation already started' "$case_dir/pass-$attempt.err" \
      "pass $attempt refusal did not name the convergence budget"
  done
  pass "review convergence makes a ninth remediation pass unreachable"
}

test_scope_expansion_refuses_before_focused_verification() {
  local case_dir="$TMP_ROOT/scope" repo rc counter
  repo=$(make_repo scope 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null
  counter="$case_dir/verification-runs"
  printf '#!/usr/bin/env bash\n' > "$repo/bin/new-lifecycle.sh"

  set +e
  # shellcheck disable=SC2016  # VERIFY_COUNTER belongs to the child command.
  VERIFY_COUNTER="$counter" "$CONVERGENCE" record "$repo" -- \
    bash -c 'printf "run\n" >> "$VERIFY_COUNTER"' \
    > "$case_dir/out" 2> "$case_dir/err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a remediation that pulled in a new production path was accepted"
  assert_grep 'scope expansion refused' "$case_dir/err" \
    "the scope-expansion refusal was not observable"
  [ ! -e "$counter" ] || fail "focused verification ran after scope expansion was refused"
  assert_grep 'bin/new-lifecycle.sh' "$repo/.no-mistakes/review-convergence/followups/scope-expansion.txt" \
    "the refused production path was not preserved as follow-up evidence"
  pass "review convergence fails closed when remediation pulls in a new subsystem"
}

test_test_amplification_is_measured_and_bounded() {
  local case_dir="$TMP_ROOT/amplification" repo rc counter
  repo=$(make_repo amplification 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null
  counter="$case_dir/verification-runs"
  printf 'base=true\nfeature=true\nremediated=true\n' > "$repo/src/core.sh"

  set +e
  # shellcheck disable=SC2016  # VERIFY_COUNTER belongs to the child command.
  FM_FIXTURE_TEST_COUNT=118 VERIFY_COUNTER="$counter" \
    "$CONVERGENCE" record "$repo" -- bash -c 'printf "run\n" >> "$VERIFY_COUNTER"' \
    > "$case_dir/out" 2> "$case_dir/err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a six-to-118 proportional-test amplification was accepted"
  assert_grep 'test amplification refused' "$case_dir/err" \
    "the 118-test refusal did not identify amplification"
  assert_grep 'initial_tests=6' "$repo/.no-mistakes/review-convergence/followups/test-amplification.txt" \
    "the amplification evidence lost the initial test count"
  assert_grep 'final_tests=118' "$repo/.no-mistakes/review-convergence/followups/test-amplification.txt" \
    "the amplification evidence lost the final test count"
  [ ! -e "$counter" ] || fail "focused verification ran after test amplification was refused"
  pass "review convergence measures and refuses a 118-test amplification spiral"
}

test_closure_routes_adjacent_findings_and_emits_turnaround_metrics() {
  local case_dir="$TMP_ROOT/closure" repo metrics
  repo=$(make_repo closure 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null
  "$CONVERGENCE" record "$repo" -- bash -c 'printf "focused verification passed\n"' >/dev/null
  "$CONVERGENCE" close-review "$repo" "$ADJACENT" >/dev/null
  "$CONVERGENCE" mark-tests "$repo" 1300 >/dev/null
  metrics=$($CONVERGENCE metrics "$repo")

  [ "$(wc -l < "$repo/.no-mistakes/review-convergence/followups/closure.tsv" | tr -d ' ')" -eq 5 ] \
    || fail "the five adjacent incident findings were not routed to follow-up output"
  assert_contains "$metrics" 'initial_review_rounds=1' "metrics lost the initial review"
  assert_contains "$metrics" 'remediation_rounds=1' "metrics lost the batched remediation"
  assert_contains "$metrics" 'closure_review_rounds=1' "metrics lost the bounded closure review"
  assert_contains "$metrics" 'time_to_first_test_ms=200000' "metrics lost time to first executable test"
  assert_contains "$metrics" 'initial_tests=6' "metrics lost the initial proportional test count"
  assert_contains "$metrics" 'final_tests=6' "metrics lost the final proportional test count"
  assert_contains "$metrics" 'repeated_tests=6' "metrics lost repeated-test measurement"
  assert_contains "$metrics" 'new_tests=0' "metrics lost new-test measurement"
  pass "closure review routes adjacent work and emits convergence measurements"
}

test_catastrophic_closure_fails_closed_without_another_remediation() {
  local case_dir="$TMP_ROOT/catastrophic" repo rc
  repo=$(make_repo catastrophic 6)
  write_initial_status "$case_dir/initial-status.toon"
  start_and_attach "$case_dir" "$repo"
  "$CONVERGENCE" begin-remediation "$repo" >/dev/null
  "$CONVERGENCE" record "$repo" -- bash -c 'printf "focused verification passed\n"' >/dev/null
  cat > "$case_dir/catastrophic.toon" <<'EOF'
gate:
  step: review
  status: fix_review
  findings[1]{id,severity,file,action,description}:
    security-regression,error,src/core.sh,auto-fix,"The remediation introduced an immediately reachable security failure."
EOF

  set +e
  "$CONVERGENCE" close-review "$repo" "$case_dir/catastrophic.toon" \
    > "$case_dir/out" 2> "$case_dir/err"
  rc=$?
  set -e
  [ "$rc" -eq 44 ] || fail "a catastrophic closure did not fail closed with exit 44"
  assert_grep 'split or fail closed' "$case_dir/err" \
    "the catastrophic closure refusal did not give the bounded next action"
  assert_grep 'stage=closure-blocked' "$repo/.no-mistakes/review-convergence/manifest" \
    "the catastrophic closure did not persist its blocked state"
  set +e
  "$CONVERGENCE" begin-remediation "$repo" \
    > "$case_dir/reopen.out" 2> "$case_dir/reopen.err"
  rc=$?
  set -e
  [ "$rc" -eq 45 ] || fail "a catastrophic closure reopened another remediation"
  pass "catastrophic closure fails closed instead of recursively fixing"
}

test_ordinary_validation_entry_converges_before_tests() {
  local case_dir="$TMP_ROOT/ordinary" task gate fakebin evidence outer_state metrics
  local review_response_count accepted_response_count pipeline_final_change rc before_responses after_responses
  case_dir="$TMP_ROOT/ordinary"
  task=$(make_repo ordinary-task 6)
  gate="$case_dir/nm-home/worktrees/repo/RUN-SYNTHETIC"
  fakebin="$case_dir/fakebin"
  evidence="$task/final-change-evidence.txt"
  outer_state="$case_dir/state/synthetic.review-convergence"
  mkdir -p "$(dirname "$gate")" "$fakebin" "$case_dir/state" "$case_dir/data/synthetic"
  git clone -q "$task" "$gate"
  git -C "$gate" checkout -q fm/synthetic
  git -C "$gate" config user.name 'No Mistakes Fixture'
  git -C "$gate" config user.email gate@example.invalid
  printf 'command: focused fixture\nexit: 0\nresult: passed\n' > "$evidence"
  fm_write_ship_brief "$case_dir/data/synthetic/brief.md" T3 \
    'README.md#fixture => one initial review and one bounded closure precede executable tests'
  printf '%s\n' \
    '- player: invoke fm-validate -> close one review batch -> observe executable tests' \
    '- parts: review budget=round counter; evidence=bound receipt; amplification=selection preflight' \
    >> "$case_dir/data/synthetic/brief.md"
  fm_write_meta "$case_dir/state/synthetic.meta" \
    'window=fm-synthetic' \
    "worktree=$task" \
    "project=$task" \
    'kind=ship' \
    'mode=validated-main'
  printf 'initial\n' > "$case_dir/phase"
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FM_FIXTURE_AXI_LOG"
phase=$(cat "$FM_FIXTURE_PHASE")
initial_gate() {
  cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,awaiting_approval,2,1200
    test,pending,0,0
gate:
  step: review
  status: awaiting_approval
  findings[2]{id,severity,file,action,description}:
    root-a,error,src/core.sh,auto-fix,"First root finding."
    root-b,warning,src/core.sh,auto-fix,"Second root finding."
EOF
}
case "${1:-} ${2:-}" in
  'axi run') initial_gate ;;
  'axi status')
    case "$phase" in
      initial) initial_gate ;;
      wrong)
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/another-task
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,awaiting_approval,2,1200
    test,pending,0,0
gate:
  step: review
  status: awaiting_approval
EOF
        ;;
      closure)
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,fix_review,5,2400
    test,pending,0,0
EOF
        cat "$FM_FIXTURE_ADJACENT"
        ;;
      test-gate)
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,completed,5,2400
    test,awaiting_approval,1,600
gate:
  step: test
  status: awaiting_approval
  findings[1]{id,severity,file,action,description}:
    test-a,warning,tests/fixture-001.test.sh,auto-fix,"Focused test caught a defect."
EOF
        ;;
      tests)
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: completed
  steps[9]{step,status,findings,duration_ms}:
    review,completed,5,2400
    test,completed,1,600
outcome: passed
EOF
        ;;
    esac
    ;;
  'axi respond')
    case "$phase" in
      initial)
        if [ ! -e "$FM_FIXTURE_RETRY_MARKER" ]; then
          : > "$FM_FIXTURE_RETRY_MARKER"
          exit 71
        fi
        printf 'remediation\n' >> "$FM_FIXTURE_ACCEPTED_RESPONSES"
        printf 'base=true\nfeature=true\nremediated=true\n' > "$FM_FIXTURE_GATE/src/core.sh"
        "$FM_FIXTURE_CONVERGENCE" record "$FM_FIXTURE_GATE" -- \
          bash -c 'printf "focused remediation passed\\n"'
        git -C "$FM_FIXTURE_GATE" add src/core.sh
        git -C "$FM_FIXTURE_GATE" commit -qm remediation
        printf 'closure\n' > "$FM_FIXTURE_PHASE"
        cat "$FM_FIXTURE_ADJACENT"
        ;;
      closure)
        printf 'closure\n' >> "$FM_FIXTURE_ACCEPTED_RESPONSES"
        printf 'test-gate\n' > "$FM_FIXTURE_PHASE"
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,completed,5,2400
    test,awaiting_approval,1,600
gate:
  step: test
  status: awaiting_approval
  findings[1]{id,severity,file,action,description}:
    test-a,warning,tests/fixture-001.test.sh,auto-fix,"Focused test caught a defect."
EOF
        ;;
      test-gate)
        printf 'tests\n' > "$FM_FIXTURE_PHASE"
        cat <<'EOF'
run:
  id: RUN-SYNTHETIC
  branch: fm/synthetic
  status: completed
  steps[9]{step,status,findings,duration_ms}:
    review,completed,5,2400
    test,completed,1,600
outcome: passed
EOF
        ;;
    esac
    ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"

  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic --evidence "$evidence"
  ) > "$case_dir/start.out" 2> "$case_dir/start.err" \
    || fail "ordinary fm-validate start did not reach the initial review gate"

  [ -s "$gate/.no-mistakes/review-convergence/manifest" ] \
    || fail "ordinary fm-validate did not attach durable convergence state to the gate worktree"
  pipeline_final_change=$(sed -n 's/^pipeline_final_change=//p' "$outer_state/manifest")
  [ -n "$pipeline_final_change" ] \
    || fail "ordinary validation did not persist its pipeline final-change evidence path"
  assert_contains "$(cat "$case_dir/axi.log")" "$pipeline_final_change" \
    "the closure reviewer was not directed to the pipeline final-change capture"

  before_responses=$(grep -c '^axi respond' "$case_dir/axi.log" || true)
  set +e
  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --action approve
  ) > "$case_dir/initial-approve.out" 2> "$case_dir/initial-approve.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "actionable initial findings were approved without remediation"
  assert_grep 'actionable initial-review findings remain' "$case_dir/initial-approve.err" \
    "the initial approval refusal did not identify the remaining remediation"
  after_responses=$(grep -c '^axi respond' "$case_dir/axi.log" || true)
  [ "$after_responses" -eq "$before_responses" ] \
    || fail "the refused initial approval reached no-mistakes"
  mv "$gate/.no-mistakes/review-convergence" "$case_dir/simulated-lost-gate-state"

  printf 'wrong\n' > "$case_dir/phase"
  set +e
  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --action fix --findings root-a,root-b
  ) > "$case_dir/wrong-branch.out" 2> "$case_dir/wrong-branch.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a response for another task branch was accepted"
  assert_grep 'not task synthetic' "$case_dir/wrong-branch.err" \
    "the cross-task response refusal did not identify the branch binding"
  printf 'initial\n' > "$case_dir/phase"

  set +e
  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    FM_FIXTURE_RETRY_MARKER="$case_dir/respond-failed-once" \
    FM_FIXTURE_ACCEPTED_RESPONSES="$case_dir/accepted-review-responses" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --action fix --findings root-a,root-b
  ) > "$case_dir/failed-dispatch.out" 2> "$case_dir/failed-dispatch.err"
  rc=$?
  set -e
  [ "$rc" -eq 71 ] || fail "the synthetic pre-dispatch failure did not propagate"
  assert_grep 'stage=remediation' "$outer_state/manifest" \
    "the failed response did not preserve its pending remediation transition"
  [ ! -e "$case_dir/accepted-review-responses" ] \
    || fail "the failed response dispatched remediation work"
  mv "$gate/.no-mistakes/review-convergence" "$case_dir/simulated-failed-dispatch-state"

  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    FM_FIXTURE_RETRY_MARKER="$case_dir/respond-failed-once" \
    FM_FIXTURE_ACCEPTED_RESPONSES="$case_dir/accepted-review-responses" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --action fix --findings root-a,root-b
  ) > "$case_dir/fix.out" 2> "$case_dir/fix.err" \
    || fail "ordinary fm-validate did not complete the batched remediation and bounded closure"

  [ -s "$gate/.no-mistakes/review-convergence/remediation.receipt" ] \
    || fail "ordinary validation did not restore cold-session state from the durable mirror"
  [ -s "$pipeline_final_change" ] \
    || fail "ordinary validation did not publish pipeline final-change evidence before closure"
  assert_grep 'exit: 0' "$pipeline_final_change" \
    "pipeline final-change evidence did not record the successful focused verification"
  assert_grep 'focused remediation passed' "$pipeline_final_change" \
    "pipeline final-change evidence did not preserve the focused verification output"

  [ "$(wc -l < "$gate/.no-mistakes/review-convergence/followups/closure.tsv" | tr -d ' ')" -eq 5 ] \
    || fail "ordinary validation did not route the five closure findings to follow-up evidence"

  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    FM_FIXTURE_RETRY_MARKER="$case_dir/respond-failed-once" \
    FM_FIXTURE_ACCEPTED_RESPONSES="$case_dir/accepted-review-responses" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --action approve
  ) > "$case_dir/approve.out" 2> "$case_dir/approve.err" \
    || fail "ordinary fm-validate did not transition from closure to executable tests"

  printf 'needs-decision [key=test-choice]: apply the test finding\n' \
    >> "$case_dir/state/synthetic.status"
  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_AXI_LOG="$case_dir/axi.log" \
    FM_FIXTURE_ADJACENT="$ADJACENT" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" synthetic respond --step test --action fix \
        --findings test-a --add-finding '{"id":"test-extra"}' --resolve-key test-choice
  ) > "$case_dir/test.out" 2> "$case_dir/test.err" \
    || fail "ordinary fm-validate did not drive the executable-test gate to completion"

  metrics=$(cat "$outer_state/metrics.txt")
  assert_contains "$metrics" 'initial_review_rounds=1' "ordinary path metrics lost the initial review"
  assert_contains "$metrics" 'remediation_rounds=1' "ordinary path metrics lost remediation"
  assert_contains "$metrics" 'closure_review_rounds=1' "ordinary path metrics lost closure"
  assert_contains "$metrics" 'initial_tests=6' "ordinary path metrics lost initial test selection"
  assert_contains "$metrics" 'final_tests=6' "ordinary path metrics lost final test selection"
  assert_contains "$metrics" 'review_defects=2' "ordinary path metrics lost review-found defects"
  assert_contains "$metrics" 'review_defect_ids=root-a,root-b' \
    "ordinary path metrics did not identify review-found defects"
  assert_contains "$metrics" 'test_defects=1' "ordinary path metrics lost test-found defects"
  assert_contains "$metrics" 'test_defect_ids=test-a' \
    "ordinary path metrics did not identify test-found defects"
  assert_grep 'resolved [key=test-choice]: validation decision applied at test gate' \
    "$case_dir/state/synthetic.status" \
    "the successful wrapper response did not close its decision key"
  review_response_count=$(grep '^axi respond' "$case_dir/axi.log" | grep -vc -- '--step test' || true)
  [ "$review_response_count" -eq 3 ] \
    || fail "ordinary path did not preserve one failed dispatch, one remediation, and one closure response"
  accepted_response_count=$(wc -l < "$case_dir/accepted-review-responses" | tr -d ' ')
  [ "$accepted_response_count" -eq 2 ] \
    || fail "ordinary path accepted $accepted_response_count review responses instead of one remediation and one closure"
  assert_grep '--add-finding {"id":"test-extra"}' "$case_dir/axi.log" \
    "the response boundary changed a non-review gate's native add-finding semantics"
  assert_grep 'outcome: passed' "$case_dir/test.out" \
    "ordinary path did not expose the successful test outcome"
  pass "ordinary fm-validate converges initial review -> remediation -> closure -> tests"
}

test_review_only_path_closes_cleanly_without_inventing_a_test_start() {
  local case_dir="$TMP_ROOT/review-only" task gate fakebin evidence outer_state metrics
  task=$(make_repo review-only-task 6)
  gate="$case_dir/nm-home/worktrees/repo/RUN-LIGHT"
  fakebin="$case_dir/fakebin"
  evidence="$task/final-change-evidence.txt"
  outer_state="$case_dir/state/light.review-convergence"
  mkdir -p "$(dirname "$gate")" "$fakebin" "$case_dir/state" "$case_dir/data/light"
  git clone -q "$task" "$gate"
  git -C "$gate" checkout -q fm/synthetic
  git -C "$gate" config user.name 'No Mistakes Fixture'
  git -C "$gate" config user.email gate@example.invalid
  printf 'command: focused fixture\nexit: 0\nresult: passed\n' > "$evidence"
  fm_write_ship_brief "$case_dir/data/light/brief.md" T2 \
    'README.md#fixture => review-only validation converges and completes without a test phase'
  printf '%s\n' '- player: invoke fm-validate and observe a bounded review-only outcome' \
    >> "$case_dir/data/light/brief.md"
  fm_write_meta "$case_dir/state/light.meta" \
    'window=fm-light' \
    "worktree=$task" \
    "project=$task" \
    'kind=ship' \
    'mode=direct-PR'
  printf 'initial\n' > "$case_dir/phase"
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
phase=$(cat "$FM_FIXTURE_PHASE")
initial_gate() {
  cat <<'EOF'
run:
  id: RUN-LIGHT
  branch: fm/synthetic
  status: running
  steps[9]{step,status,findings,duration_ms}:
    review,awaiting_approval,1,100
    test,skipped,0,0
gate:
  step: review
  status: awaiting_approval
  findings[1]{id,severity,file,action,description}:
    root-a,error,src/core.sh,auto-fix,"Root finding."
EOF
}
terminal() {
  cat <<'EOF'
run:
  id: RUN-LIGHT
  branch: fm/synthetic
  status: completed
  steps[9]{step,status,findings,duration_ms}:
    review,completed,0,200
    test,skipped,0,0
outcome: passed
EOF
}
case "${1:-} ${2:-}" in
  'axi run') initial_gate ;;
  'axi status')
    if [ "$phase" = initial ]; then initial_gate; else terminal; fi
    ;;
  'axi respond')
    printf 'base=true\nfeature=true\nremediated=true\n' > "$FM_FIXTURE_GATE/src/core.sh"
    "$FM_FIXTURE_CONVERGENCE" record "$FM_FIXTURE_GATE" -- \
      bash -c 'printf "focused remediation passed\\n"'
    git -C "$FM_FIXTURE_GATE" add src/core.sh
    git -C "$FM_FIXTURE_GATE" commit -qm remediation
    printf 'complete\n' > "$FM_FIXTURE_PHASE"
    terminal
    ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"

  (
    cd "$task" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" light --evidence "$evidence"
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    NM_HOME="$case_dir/nm-home" \
    FM_FIXTURE_GATE="$gate" \
    FM_FIXTURE_PHASE="$case_dir/phase" \
    FM_FIXTURE_CONVERGENCE="$CONVERGENCE" \
    PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" light respond --action fix --findings root-a
  ) > "$case_dir/out" 2> "$case_dir/err" \
    || fail "review-only fm-validate did not close its clean remediation review"

  metrics=$(cat "$outer_state/metrics.txt")
  assert_contains "$metrics" 'closure_review_rounds=1' "review-only metrics lost closure"
  assert_contains "$metrics" 'time_to_first_test_ms=-1' \
    "review-only validation invented an executable test start"
  assert_grep 'stage=complete' "$outer_state/manifest" \
    "review-only convergence did not record terminal completion"
  pass "review-only delivery modes converge without inventing a test phase"
}

test_receipt_survives_handoff_and_reuses_only_exact_proof
test_second_remediation_is_an_executable_refusal
test_scope_expansion_refuses_before_focused_verification
test_test_amplification_is_measured_and_bounded
test_closure_routes_adjacent_findings_and_emits_turnaround_metrics
test_catastrophic_closure_fails_closed_without_another_remediation
test_ordinary_validation_entry_converges_before_tests
test_review_only_path_closes_cleanly_without_inventing_a_test_start
