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
  printf '%s\n' '# Scout evidence' 'Rejected: the alternate scout mechanism was not viable.' > "$home/data/scout-a/report.md"
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
  local dir brief review_out validate_out inventory_line preserve_line base_line branch_line
  dir=$(make_scout success)
  brief="$dir/home/data/scout-a/brief.md"
  printf '%s\n' '- project [local-only] - promotion fixture (added 2026-08-12)' > "$dir/home/data/projects.md"

  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should shape a valid ship task from the explicit authoritative outcome"

  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = ship ] \
    || fail "promotion did not change kind after shaping the ship brief"
  [ "$(sed -n 's/^mode=//p' "$dir/home/state/scout-a.meta")" = local-only ] \
    || fail "promotion metadata did not converge on the promotion-time registry mode"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief" \
    || fail "the promoted brief does not carry a valid canonical delivery contract"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the promoted brief lost its valid captain provenance"
  assert_grep 'Implement the accepted bounded scout finding.' "$brief" \
    "promotion lost the accepted scout task"
  assert_grep 'This project ships **local-only**' "$brief" \
    "the promoted prompt did not use the same promotion-time delivery mode as metadata"
  assert_no_grep 'This project ships **direct-PR**' "$brief" \
    "the promoted prompt retained the scout's stale delivery mode"
  assert_grep 'You drive the review by responding to its gate' "$brief" \
    "promotion did not install the delivery-mode-specific ship worker prompt"

  inventory_line=$(grep -nF '1. Inventory the scout state before changing refs:' "$brief" | cut -d: -f1)
  preserve_line=$(grep -nF '2. Preserve the complete scout state recoverably before cleaning it:' "$brief" | cut -d: -f1)
  base_line=$(grep -nF '3. Return to the proven clean default-branch base:' "$brief" | cut -d: -f1)
  branch_line=$(grep -nF '5. Only after that proof, create the ship branch:' "$brief" | cut -d: -f1)
  [ -n "$inventory_line" ] && [ -n "$preserve_line" ] && [ -n "$base_line" ] && [ -n "$branch_line" ] \
    || fail "the promoted prompt omitted its promotion-specific setup stages"
  [ "$inventory_line" -lt "$preserve_line" ] && [ "$preserve_line" -lt "$base_line" ] && [ "$base_line" -lt "$branch_line" ] \
    || fail "the promoted prompt creates the ship branch before preserving scout work and proving a clean base"

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

test_promotion_requires_explicit_authority_instead_of_scout_prose() {
  local dir brief original rc
  dir=$(make_scout report-only)
  brief="$dir/home/data/scout-a/brief.md"
  original="$dir/original-brief.md"
  cp "$brief" "$original"
  printf '%s\n' '# Scout evidence' 'Rejected: X is enabled through the bounded path.' > "$dir/home/data/scout-a/report.md"

  set +e
  run_promote "$dir" \
    --task-tier T1 \
    > "$dir/promote.out" 2> "$dir/promote.err"
  rc=$?
  set -e

  expect_code 1 "$rc" "rejected scout prose must not become promotion authority without an explicit outcome"
  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = scout ] \
    || fail "promotion changed kind without explicit authoritative input"
  cmp "$original" "$brief" >/dev/null \
    || fail "promotion rewrote the scout brief without explicit authoritative input"
  assert_grep 'explicit authoritative --outcome' "$dir/promote.err" \
    "the refusal did not identify the missing authority handoff"
  pass "fm-promote.sh: scout prose alone cannot authorize promotion"
}

test_promotion_refuses_a_generic_decision_pointer() {
  local dir brief original rc
  dir=$(make_scout generic-pointer)
  brief="$dir/home/data/scout-a/brief.md"
  original="$dir/original-brief.md"
  cp "$brief" "$original"
  printf '%s\n' '# Scout evidence' 'Ship X through the bounded path.' > "$dir/home/data/scout-a/report.md"

  set +e
  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err"
  rc=$?
  set -e

  expect_code 1 "$rc" "promotion must reject a generic decision pointer even when scout prose repeats its result"
  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = scout ] \
    || fail "promotion changed kind for an ambiguous decision pointer"
  cmp "$original" "$brief" >/dev/null \
    || fail "promotion rewrote the scout brief for an ambiguous decision pointer"
  assert_grep 'must use captain decision <complete-id>' "$dir/promote.err" \
    "the refusal did not identify the canonical captain receipt syntax"
  pass "fm-promote.sh: generic decision pointers fail closed"
}

test_promotion_builds_a_validated_ship_prompt_before_changing_kind
test_promotion_requires_explicit_authority_instead_of_scout_prose
test_promotion_refuses_a_generic_decision_pointer
