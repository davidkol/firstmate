#!/usr/bin/env bash
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROMOTE="$ROOT/bin/fm-promote.sh"
TMP_ROOT=$(fm_test_tmproot fm-promote)

make_scout() {
  local name=$1 dir home brief
  dir="$TMP_ROOT/$name"
  home="$dir/home"
  mkdir -p "$home/data" "$home/state" "$dir/project" "$dir/worktree" "$dir/fakebin" "$dir/pipeline-tmp"
  printf '%s\n' '- project [direct-PR] - promotion fixture (added 2026-08-12)' > "$home/data/projects.md"
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" FM_STATE_OVERRIDE="$home/state" \
    "$ROOT/bin/fm-brief.sh" scout-a project --scout >/dev/null \
    || fail "$name: could not generate the canonical scout brief"
  brief="$home/data/scout-a/brief.md"
  awk '
    $0 == "{TASK}" { print "Implement the accepted bounded scout finding."; next }
    $0 == "{CAPTAIN_RULINGS}" { print "- Captain decision 1: \"Enable X through the bounded path.\""; next }
    $0 == "{FIRSTMATE_INFERENCE}" { print "- The scout isolated the bounded implementation path."; next }
    { print }
  ' "$brief" > "$brief.filled" && mv "$brief.filled" "$brief"
  printf '%s\n' '# Accepted scout findings' 'X is enabled through the bounded path.' > "$home/data/scout-a/report.md"
  fm_write_meta "$home/state/scout-a.meta" \
    'window=fm-scout-a' \
    "worktree=$dir/worktree" \
    "project=$dir/project" \
    'kind=scout' \
    'mode=direct-PR'
  printf '%s\n' 'command: focused accepted-finding check' 'exit: 0' > "$dir/worktree/evidence.txt"
  cat > "$dir/fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FM_TEST_NM_LOG"
SH
  chmod +x "$dir/fakebin/no-mistakes"
  printf '%s\n' "$dir"
}

run_promote() {
  local dir=$1; shift
  FM_GATE_REFUSE_BYPASS=1 FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$dir/home" \
    FM_DATA_OVERRIDE="$dir/home/data" FM_STATE_OVERRIDE="$dir/home/state" \
    "$PROMOTE" scout-a "$@"
}

test_promotion_builds_a_validated_ship_prompt_before_changing_kind() {
  local dir brief review_out validate_out
  dir=$(make_scout success)
  brief="$dir/home/data/scout-a/brief.md"

  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => X is enabled through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should shape a valid ship task from the accepted scout finding"

  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = ship ] \
    || fail "promotion did not change kind after shaping the ship brief"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief" \
    || fail "the promoted brief does not carry a valid canonical delivery contract"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the promoted brief lost its valid captain provenance"
  assert_grep 'Implement the accepted bounded scout finding.' "$brief" \
    "promotion lost the accepted scout task"
  assert_grep 'You drive the review by responding to its gate' "$brief" \
    "promotion did not install the delivery-mode-specific ship worker prompt"

  review_out=$("$ROOT/bin/fm-doctrine-contract.sh" review-intent "$brief") \
    || fail "the promoted brief cannot render its selected reviewer contract"
  assert_contains "$review_out" '- Captain decision 1: "Enable X through the bounded path."' \
    "the promoted reviewer contract cannot inspect the matched captain receipt"

  validate_out=$(
    cd "$dir/worktree" || exit 1
    FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$dir/home" FM_DATA_OVERRIDE="$dir/home/data" \
      FM_STATE_OVERRIDE="$dir/home/state" FM_TEST_NM_LOG="$dir/no-mistakes.log" \
      TMPDIR="$dir/pipeline-tmp" PATH="$dir/fakebin:$PATH" \
      "$ROOT/bin/fm-validate.sh" scout-a --evidence "$dir/worktree/evidence.txt" 2>&1
  ) || fail "the promoted scout should enter its supported review-only validation path: $validate_out"
  assert_grep 'matched captain authority receipt:' "$dir/no-mistakes.log" \
    "validation did not forward the promoted task's matched authority receipt"
  pass "fm-promote.sh: promotion constructs a validated role-specific ship prompt"
}

test_promotion_refuses_an_ungrounded_outcome_before_mutating_the_scout() {
  local dir brief original rc
  dir=$(make_scout ungrounded)
  brief="$dir/home/data/scout-a/brief.md"
  original="$dir/original-brief.md"
  cp "$brief" "$original"

  set +e
  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => A product choice absent from the scout report.' \
    > "$dir/promote.out" 2> "$dir/promote.err"
  rc=$?
  set -e

  expect_code 1 "$rc" "promotion must stop on an outcome absent from accepted scout findings"
  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = scout ] \
    || fail "promotion changed kind before resolving the design fork"
  cmp "$original" "$brief" >/dev/null \
    || fail "promotion rewrote the scout brief before resolving the design fork"
  assert_grep 'not an exact accepted finding' "$dir/promote.err" \
    "the refusal did not identify the ungrounded outcome"
  pass "fm-promote.sh: an ungrounded outcome leaves the scout unchanged"
}

test_promotion_builds_a_validated_ship_prompt_before_changing_kind
test_promotion_refuses_an_ungrounded_outcome_before_mutating_the_scout
