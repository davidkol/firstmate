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
    $0 == "{TASK}" { print "Diagnose only; do not implement the suspected bounded-path change."; next }
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
    'mode=direct-PR' \
    'yolo=on'
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

prompt_command() {
  local brief=$1 prefix=$2
  awk -v prefix="$prefix" '
    index($0, prefix) == 1 {
      count = split($0, pieces, "`")
      if (count >= 3) print pieces[2]
      exit
    }
  ' "$brief"
}

test_promotion_builds_a_validated_ship_prompt_before_changing_kind() {
  local dir brief review_out validate_out inventory_line preserve_line base_line branch_line task_text context_text
  dir=$(make_scout success)
  brief="$dir/home/data/scout-a/brief.md"
  printf '%s\n' '- project [local-only] - promotion fixture (added 2026-08-12)' > "$dir/home/data/projects.md"

  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should shape a valid ship task from the explicit authoritative outcome: $(cat "$dir/promote.err")"

  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = ship ] \
    || fail "promotion did not change kind after shaping the ship brief"
  [ "$(sed -n 's/^mode=//p' "$dir/home/state/scout-a.meta")" = local-only ] \
    || fail "promotion metadata did not converge on the promotion-time registry mode"
  [ "$(sed -n 's/^yolo=//p' "$dir/home/state/scout-a.meta")" = off ] \
    || fail "promotion metadata retained the scout's revoked yolo authority"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief" \
    || fail "the promoted brief does not carry a valid canonical delivery contract"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the promoted brief lost its valid captain provenance"
  task_text=$(awk '$0 == "# Task" { active = 1; next } active && $0 == "# Delivery contract" { exit } active { print }' "$brief")
  assert_contains "$task_text" 'Ship X through the bounded path.' \
    "the promoted ship task was not generated from the explicit accepted target"
  assert_not_contains "$task_text" 'Diagnose only' \
    "the promoted ship task retained the scout's contradictory diagnose-only instruction"
  context_text=$(awk '$0 == "# Promotion evidence and scout context" { active = 1 } active && $0 == "# What the captain decided" { exit } active { print }' "$brief")
  assert_contains "$context_text" 'Diagnose only; do not implement the suspected bounded-path change.' \
    "promotion did not retain the original scout task as provisional context"
  assert_contains "$context_text" 'Rejected: the alternate scout mechanism was not viable.' \
    "promotion did not retain the scout report as provisional evidence"
  assert_grep 'This project ships **local-only**' "$brief" \
    "the promoted prompt did not use the same promotion-time delivery mode as metadata"
  assert_grep 'promotion delivery state is **mode=local-only, yolo=off**' "$brief" \
    "the promoted prompt did not record the same current yolo posture as metadata"
  assert_no_grep 'promotion delivery state is **mode=local-only, yolo=on**' "$brief" \
    "the promoted prompt retained revoked yolo authority"
  assert_no_grep 'This project ships **direct-PR**' "$brief" \
    "the promoted prompt retained the scout's stale delivery mode"
  assert_grep "bin/fm-validate.sh scout-a respond" "$brief" \
    "promotion did not install the executable review-convergence worker prompt"
  # shellcheck disable=SC2016  # Backticks are literal generated-brief prose.
  assert_grep 'Do not call `no-mistakes axi respond` directly' "$brief" \
    "promotion still allows the old unbounded raw response path"

  inventory_line=$(grep -nF '1. Inventory the scout state before changing refs:' "$brief" | cut -d: -f1)
  preserve_line=$(grep -nF '2. Preserve the complete scout state recoverably before cleaning it:' "$brief" | cut -d: -f1)
  base_line=$(grep -nF '3. Return to the proven clean default-branch base:' "$brief" | cut -d: -f1)
  branch_line=$(grep -nF '5. Only after that proof, create or reuse the ship branch:' "$brief" | cut -d: -f1)
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

test_promoted_setup_recovers_across_separate_shells() {
  local dir brief worktree command snapshot
  dir=$(make_scout separate-shells)
  brief="$dir/home/data/scout-a/brief.md"
  worktree="$dir/worktree"
  git -C "$worktree" init -q -b main
  git -C "$worktree" config user.name 'Promotion Test'
  git -C "$worktree" config user.email 'promotion@example.invalid'
  printf '%s\n' base > "$worktree/intended.txt"
  git -C "$worktree" add intended.txt
  git -C "$worktree" commit -q -m base
  git -C "$worktree" switch -q -c scout-scratch
  printf '%s\n' 'preserved scout work' > "$worktree/intended.txt"
  printf '%s\n' 'debug residue' > "$worktree/debug.txt"
  printf '%s\n' '.fm-grok-turnend' >> "$worktree/.git/info/exclude"
  printf '%s\n' 'token=fm.123456789012' > "$worktree/.fm-grok-turnend"

  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should generate the separate-shell recovery contract"

  command=$(prompt_command "$brief" '2. Preserve the complete scout state recoverably before cleaning it:')
  [ -n "$command" ] || fail "the promoted prompt did not emit an executable preservation command"
  (cd "$worktree" && bash -c "$command") \
    || fail "the preservation command failed in its own worker shell"
  snapshot=$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot) \
    || fail "the preservation command did not create its task-scoped Git ref"

  command=$(prompt_command "$brief" '3. Return to the proven clean default-branch base:')
  (cd "$worktree" && bash -c "$command") \
    || fail "the clean-base command could not recover in a separate worker shell"
  command=$(prompt_command "$brief" '2. Preserve the complete scout state recoverably before cleaning it:')
  (cd "$worktree" && bash -c "$command") \
    || fail "retrying preservation after an interruption failed"
  [ "$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)" = "$snapshot" ] \
    || fail "retrying preservation replaced the original scout snapshot with the clean base"
  command=$(prompt_command "$brief" '4. Prove and record the base before carrying work:')
  (cd "$worktree" && bash -c "$command") \
    || fail "the base-proof command depended on variables from an earlier worker shell"
  command=$(prompt_command "$brief" '5. Only after that proof, create or reuse the ship branch:')
  (cd "$worktree" && bash -c "$command") \
    || fail "the branch command failed after the separate-shell base proof"
  command=$(prompt_command "$brief" '3. Return to the proven clean default-branch base:')
  (cd "$worktree" && bash -c "$command") \
    || fail "retrying setup after branch creation could not recover the recorded promotion base"
  command=$(prompt_command "$brief" '4. Prove and record the base before carrying work:')
  (cd "$worktree" && bash -c "$command") \
    || fail "retrying setup after branch creation lost the proven promotion base"
  command=$(prompt_command "$brief" '5. Only after that proof, create or reuse the ship branch:')
  (cd "$worktree" && bash -c "$command") \
    || fail "retrying setup after branch creation did not reuse the valid task branch"
  [ "$(git -C "$worktree" branch --show-current)" = fm/scout-a ] \
    || fail "retrying setup did not return to the existing task branch"
  command=$(prompt_command "$brief" '6. Import only the intended implementation and regression-test paths transactionally:')
  command=${command//'<paths>'/intended.txt}
  (cd "$worktree" && bash -c "$command") \
    || fail "the import transaction could not recover and commit the selected scout work"
  [ "$(cat "$worktree/intended.txt")" = 'preserved scout work' ] \
    || fail "the import transaction did not recover the selected scout work"
  [ ! -e "$worktree/debug.txt" ] \
    || fail "the import transaction carried unselected debug residue"
  [ "$(cat "$worktree/.fm-grok-turnend")" = 'token=fm.123456789012' ] \
    || fail "promotion deleted or changed Firstmate's ignored worktree control artifact"
  git -C "$worktree" diff --quiet "$snapshot" HEAD -- intended.txt \
    || fail "the committed ship history does not preserve the selected snapshot path"
  [ "$(git -C "$worktree" log -1 --format=%s)" = 'import promoted scout work' ] \
    || fail "the selected scout work was not committed as a reachable import"
  if git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/scout-snapshot; then
    fail "the proven selective import retained its private snapshot ref"
  fi
  if git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/import; then
    fail "the proven selective import retained its transaction ref"
  fi
  if git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/base; then
    fail "the proven selective import retained its promotion-base ref"
  fi
  pass "fm-promote.sh: promoted setup retries and commits selective recovery safely"
}

test_promoted_setup_refuses_an_unrelated_existing_branch() {
  local dir brief worktree command snapshot tree unrelated rc
  dir=$(make_scout unrelated-branch)
  brief="$dir/home/data/scout-a/brief.md"
  worktree="$dir/worktree"
  git -C "$worktree" init -q -b main
  git -C "$worktree" config user.name 'Promotion Test'
  git -C "$worktree" config user.email 'promotion@example.invalid'
  printf '%s\n' base > "$worktree/intended.txt"
  git -C "$worktree" add intended.txt
  git -C "$worktree" commit -q -m base
  git -C "$worktree" switch -q -c scout-scratch
  printf '%s\n' 'preserved scout work' > "$worktree/intended.txt"

  run_promote "$dir" --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should generate the ancestry-checked branch setup"

  command=$(prompt_command "$brief" '2. Preserve the complete scout state recoverably before cleaning it:')
  (cd "$worktree" && bash -c "$command") || fail "the preservation command failed"
  snapshot=$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)
  command=$(prompt_command "$brief" '3. Return to the proven clean default-branch base:')
  (cd "$worktree" && bash -c "$command") || fail "the base command failed"
  command=$(prompt_command "$brief" '4. Prove and record the base before carrying work:')
  (cd "$worktree" && bash -c "$command") || fail "the base proof failed"

  tree=$(git -C "$worktree" mktree </dev/null)
  unrelated=$(printf '%s\n' unrelated | git -C "$worktree" commit-tree "$tree")
  git -C "$worktree" branch fm/scout-a "$unrelated"
  command=$(prompt_command "$brief" '5. Only after that proof, create or reuse the ship branch:')
  set +e
  (cd "$worktree" && bash -c "$command")
  rc=$?
  set -e

  expect_code 1 "$rc" "an existing task branch unrelated to the recorded base must fail closed"
  [ "$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)" = "$snapshot" ] \
    || fail "refusing the unrelated branch lost the immutable scout snapshot"
  pass "fm-promote.sh: promoted setup rejects unrelated existing task branches"
}

test_promoted_import_refuses_residue_on_a_valid_task_branch() {
  local dir brief worktree command snapshot rc
  dir=$(make_scout branch-residue)
  brief="$dir/home/data/scout-a/brief.md"
  worktree="$dir/worktree"
  git -C "$worktree" init -q -b main
  git -C "$worktree" config user.name 'Promotion Test'
  git -C "$worktree" config user.email 'promotion@example.invalid'
  printf '%s\n' base > "$worktree/intended.txt"
  git -C "$worktree" add intended.txt
  git -C "$worktree" commit -q -m base
  git -C "$worktree" switch -q -c scout-scratch
  printf '%s\n' 'preserved scout work' > "$worktree/intended.txt"

  run_promote "$dir" --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should generate the complete branch-scope proof"

  for prefix in \
    '2. Preserve the complete scout state recoverably before cleaning it:' \
    '3. Return to the proven clean default-branch base:' \
    '4. Prove and record the base before carrying work:' \
    '5. Only after that proof, create or reuse the ship branch:'; do
    command=$(prompt_command "$brief" "$prefix")
    (cd "$worktree" && bash -c "$command") \
      || fail "the promoted setup command failed before the residue reproduction: $prefix"
  done
  snapshot=$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)
  printf '%s\n' 'committed debug residue' > "$worktree/debug.txt"
  git -C "$worktree" add debug.txt
  git -C "$worktree" commit -q -m 'unrelated debug residue'

  command=$(prompt_command "$brief" '6. Import only the intended implementation and regression-test paths transactionally:')
  command=${command//'<paths>'/intended.txt}
  set +e
  (cd "$worktree" && bash -c "$command")
  rc=$?
  set -e

  expect_code 1 "$rc" "an ancestry-valid task branch with unrelated committed residue must fail closed"
  [ "$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)" = "$snapshot" ] \
    || fail "refusing committed residue lost the immutable scout snapshot"
  git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/base \
    || fail "refusing committed residue deleted the recorded promotion base"
  git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/import \
    || fail "refusing committed residue deleted the selected import proof"
  git -C "$worktree" merge-base --is-ancestor refs/fm-promote/scout-a/import HEAD \
    || fail "the selected import commit is not reachable from the refused branch"
  [ "$(cat "$worktree/debug.txt")" = 'committed debug residue' ] \
    || fail "refusing committed residue discarded the unrelated work"
  pass "fm-promote.sh: promoted import preserves recovery refs around branch residue"
}

test_promoted_setup_refuses_non_firstmate_ignored_state() {
  local dir brief worktree command snapshot rc out
  dir=$(make_scout ignored-state)
  brief="$dir/home/data/scout-a/brief.md"
  worktree="$dir/worktree"
  git -C "$worktree" init -q -b main
  git -C "$worktree" config user.name 'Promotion Test'
  git -C "$worktree" config user.email 'promotion@example.invalid'
  printf '%s\n' '.env' > "$worktree/.gitignore"
  printf '%s\n' base > "$worktree/intended.txt"
  git -C "$worktree" add .gitignore intended.txt
  git -C "$worktree" commit -q -m base
  git -C "$worktree" switch -q -c scout-scratch
  printf '%s\n' 'preserved scout work' > "$worktree/intended.txt"
  printf '%s\n' 'SCOUT_ONLY=1' > "$worktree/.env"

  run_promote "$dir" --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/promote.out" 2> "$dir/promote.err" \
    || fail "promotion should generate the ignored-state base proof"

  command=$(prompt_command "$brief" '2. Preserve the complete scout state recoverably before cleaning it:')
  (cd "$worktree" && bash -c "$command") || fail "the preservation command failed"
  snapshot=$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)
  command=$(prompt_command "$brief" '3. Return to the proven clean default-branch base:')
  (cd "$worktree" && bash -c "$command") || fail "the base command failed"
  command=$(prompt_command "$brief" '4. Prove and record the base before carrying work:')
  set +e
  out=$(cd "$worktree" && bash -c "$command" 2>&1)
  rc=$?
  set -e

  expect_code 1 "$rc" "a promoted scout with non-Firstmate ignored state must fail closed"
  assert_contains "$out" 'start a fresh ship instead' \
    "the ignored-state refusal did not direct the caller to the safe delivery path"
  [ "$(git -C "$worktree" rev-parse refs/fm-promote/scout-a/scout-snapshot)" = "$snapshot" ] \
    || fail "refusing ignored state lost the immutable scout snapshot"
  [ "$(cat "$worktree/.env")" = 'SCOUT_ONLY=1' ] \
    || fail "refusing ignored state deleted or changed the scout-owned file"
  if git -C "$worktree" show-ref --verify --quiet refs/fm-promote/scout-a/base; then
    fail "the ignored-state refusal recorded an unproven promotion base"
  fi
  pass "fm-promote.sh: promoted setup refuses non-Firstmate ignored state"
}

test_promotion_resumes_after_brief_publication() {
  local dir brief journal original_ship_hash resumed_ship_hash fakebin real_mv rc
  dir=$(make_scout partial-publication)
  brief="$dir/home/data/scout-a/brief.md"
  journal="$dir/home/data/scout-a/.promotion"
  fakebin="$dir/fail-mv-bin"
  mkdir -p "$fakebin"
  real_mv=$(command -v mv)
  cat > "$fakebin/mv" <<'SH'
#!/usr/bin/env bash
set -u
last=${!#}
if [ "$last" = "${FM_TEST_META_DEST:-}" ] && [ ! -e "${FM_TEST_FAIL_ONCE:-}" ]; then
  : > "${FM_TEST_FAIL_ONCE:?}"
  exit 1
fi
exec "${FM_TEST_REAL_MV:?}" "$@"
SH
  chmod +x "$fakebin/mv"

  set +e
  PATH="$fakebin:$PATH" FM_TEST_REAL_MV="$real_mv" FM_TEST_META_DEST="$dir/home/state/scout-a.meta" \
    FM_TEST_FAIL_ONCE="$dir/meta-move-failed" run_promote "$dir" \
      --task-tier T1 \
      --outcome 'captain decision 1 => Ship X through the bounded path.' \
      > "$dir/promote.out" 2> "$dir/promote.err"
  rc=$?
  set -e

  expect_code 1 "$rc" "promotion must surface an interrupted metadata publication"
  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = scout ] \
    || fail "the interrupted publication unexpectedly changed scout metadata"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief" \
    || fail "the interrupted publication did not leave the validated ship brief in place"
  [ -d "$journal" ] || fail "the interrupted publication did not preserve its promotion journal"
  cmp "$brief" "$journal/brief.md" >/dev/null \
    || fail "the published ship brief does not match the saved promotion candidate"
  original_ship_hash=$(git hash-object "$brief")

  run_promote "$dir" \
    --task-tier T1 \
    --outcome 'captain decision 1 => Ship X through the bounded path.' \
    > "$dir/retry.out" 2> "$dir/retry.err" \
    || fail "promotion retry did not resume the saved publication: $(cat "$dir/retry.err")"

  resumed_ship_hash=$(git hash-object "$brief")
  [ "$resumed_ship_hash" = "$original_ship_hash" ] \
    || fail "promotion retry reparsed or rewrote the published ship brief"
  [ "$(sed -n 's/^kind=//p' "$dir/home/state/scout-a.meta")" = ship ] \
    || fail "promotion retry did not finish metadata publication"
  [ ! -e "$journal" ] && [ ! -e "$dir/home/data/scout-a/.promotion.done" ] \
    || fail "promotion retry retained a completed publication journal"
  pass "fm-promote.sh: promotion resumes after brief publication"
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
test_promoted_setup_recovers_across_separate_shells
test_promoted_setup_refuses_an_unrelated_existing_branch
test_promoted_import_refuses_residue_on_a_valid_task_branch
test_promoted_setup_refuses_non_firstmate_ignored_state
test_promotion_resumes_after_brief_publication
test_promotion_requires_explicit_authority_instead_of_scout_prose
test_promotion_refuses_a_generic_decision_pointer
