#!/usr/bin/env bash
# Own Firstmate's executable review-convergence state and focused-verification
# evidence for a no-mistakes run.
#
# A normal run uses this lifecycle:
#   start <state-dir> <task-id> <task-worktree> <implementation-start-epoch> <validation-start-epoch>
#   attach <state-dir> <run-id> <gate-worktree> <initial-status-file>
#   restore <state-dir> <run-id> <gate-worktree>
#   begin-remediation <gate-worktree>
#   record <gate-worktree> -- <focused verification command...>
#   close-review <gate-worktree> <closure-status-file>
#   mark-tests <gate-worktree> [epoch]
#   mark-complete <gate-worktree> [epoch]
#   observe-status <gate-worktree-or-state-dir> <status-file>
#   metrics <gate-worktree-or-state-dir>
#
# start records the submitted implementation and proportional test selection.
# attach copies that record into no-mistakes' ignored gate-worktree state, where
# it survives fixer/reviewer session changes without entering the shipped diff.
# Exactly one begin-remediation transition is legal. record first checks that
# remediation did not add a new production path or grow the selected test set
# beyond max(10, 2x the initial selection), then runs one focused command and
# binds its complete output to the command arguments and current worktree tree.
# An identical later record call reuses that receipt; a changed command or tree
# cannot. close-review accepts only explicit `info`/`no-op` `FOLLOW-UP:`
# findings as adjacent output and refuses another blocking cycle. Exact mechanics live here rather
# than in agent prose so pass nine is unreachable on the supported entry path.
set -eu

usage() {
  sed -n '2,/^set -eu$/s/^# \{0,1\}//p' "$0" >&2
}

die() {
  printf 'fm-review-convergence: %s\n' "$*" >&2
  exit 2
}

now_epoch() {
  date +%s
}

now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time() * 1000))'
  else
    echo "$(($(date +%s) * 1000))"
  fi
}

state_for_worktree() {
  printf '%s/.no-mistakes/review-convergence\n' "$1"
}

state_for_target() {
  if [ -s "$1/manifest" ]; then
    printf '%s\n' "$1"
  else
    state_for_worktree "$1"
  fi
}

manifest_field() {
  local state=$1 key=$2
  sed -n "s/^${key}=//p" "$state/manifest" | sed -n '1p'
}

set_manifest_field() {
  local state=$1 key=$2 value=$3 tmp
  tmp=$(mktemp "$state/.manifest.XXXXXX")
  awk -F= -v key="$key" '$1 != key { print }' "$state/manifest" > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$state/manifest"
}

sync_mirror() {
  local state=$1 mirror
  mirror=$(manifest_field "$state" mirror_dir)
  [ -n "$mirror" ] || return 0
  [ "$mirror" != "$state" ] || return 0
  mkdir -p "$mirror"
  cp -R "$state/." "$mirror/"
}

require_git_worktree() {
  local worktree=$1
  [ -d "$worktree" ] || die "worktree not found: $worktree"
  git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "not a git worktree: $worktree"
}

resolve_base() {
  local worktree=$1 candidate
  for candidate in origin/main main origin/master master; do
    if git -C "$worktree" rev-parse --verify "$candidate" >/dev/null 2>&1; then
      git -C "$worktree" merge-base "$candidate" HEAD
      return 0
    fi
  done
  if git -C "$worktree" rev-parse --verify HEAD^ >/dev/null 2>&1; then
    git -C "$worktree" rev-parse HEAD^
  else
    git -C "$worktree" rev-parse HEAD
  fi
}

changed_paths() {
  local worktree=$1 base=$2
  {
    git -C "$worktree" diff --name-only "$base...HEAD" 2>/dev/null || true
    git -C "$worktree" diff --name-only HEAD 2>/dev/null || true
    git -C "$worktree" ls-files --others --exclude-standard 2>/dev/null || true
  } | awk '$0 !~ /^\.no-mistakes\//' | LC_ALL=C sort -u
}

diff_stats() {
  local worktree=$1 base=$2 mode=${3:-committed}
  if [ "$mode" = working ]; then
    git -C "$worktree" diff --numstat "$base" 2>/dev/null
  else
    git -C "$worktree" diff --numstat "$base...HEAD" 2>/dev/null
  fi | awk '
    BEGIN { files=0; insertions=0; deletions=0 }
    {
      files++
      if ($1 ~ /^[0-9]+$/) insertions += $1
      if ($2 ~ /^[0-9]+$/) deletions += $2
    }
    END { printf "%d %d %d\n", files, insertions, deletions }
  '
}

select_tests() {
  local worktree=$1 base=$2 output=$3
  if [ ! -x "$worktree/bin/fm-test-run.sh" ]; then
    : > "$output"
    return 1
  fi
  if ! (cd "$worktree" && bin/fm-test-run.sh --list --changed --base "$base") \
    > "$output.tmp" 2> "$output.err"; then
    mv "$output.tmp" "$output"
    return 1
  fi
  LC_ALL=C sort -u "$output.tmp" > "$output"
  rm -f "$output.tmp" "$output.err"
  return 0
}

count_status_findings() {
  awk '
    /^[[:space:]]*findings\[[0-9]+\].*\{.*\}:/ { in_findings=1; next }
    in_findings && /^    [^ ]/ { count++ ; next }
    in_findings { in_findings=0 }
    END { print count + 0 }
  ' "$1"
}

append_status_findings() {
  local status_file=$1 phase=$2 output=$3
  awk -v phase="$phase" '
    /^[[:space:]]*findings\[[0-9]+\].*\{.*\}:/ { in_findings=1; next }
    in_findings && /^    [^ ]/ {
      line=$0
      sub(/^    /, "", line)
      print phase "\t" line
      next
    }
    in_findings { in_findings=0 }
  ' "$status_file" >> "$output"
}

status_gate_step() {
  awk '
    /^gate:/ { in_gate=1; next }
    in_gate && /^  step:/ {
      sub(/^  step:[[:space:]]*/, "")
      print
      exit
    }
    in_gate && /^[^ ]/ { in_gate=0 }
  ' "$1"
}

defect_ids() {
  local state=$1 phase=$2
  awk -F '\t' -v phase="$phase" '
    $1 == phase {
      split($2, fields, ",")
      if (ids != "") ids = ids ","
      ids = ids fields[1]
    }
    END {
      if (ids == "") print "none"
      else print ids
    }
  ' "$state/defects.tsv"
}

worktree_tree() {
  local worktree=$1 state=$2 temp_index tree
  temp_index=$(mktemp "$state/.index.XXXXXX")
  rm -f "$temp_index"
  GIT_INDEX_FILE="$temp_index" git -C "$worktree" read-tree HEAD
  GIT_INDEX_FILE="$temp_index" git -C "$worktree" add -A -- . ':(exclude).no-mistakes'
  tree=$(GIT_INDEX_FILE="$temp_index" git -C "$worktree" write-tree)
  rm -f "$temp_index"
  printf '%s\n' "$tree"
}

command_display() {
  printf '%q ' "$@"
  printf '\n'
}

command_digest() {
  local worktree=$1
  shift
  command_display "$@" | git -C "$worktree" hash-object --stdin
}

receipt_valid() {
  local worktree=$1 state=$2 expected_digest=${3:-} receipt tree output_hash actual_output_hash
  local receipt_run manifest_run
  receipt="$state/remediation.receipt"
  [ -s "$receipt" ] || { printf 'fm-review-convergence: focused remediation evidence is missing\n' >&2; return 1; }
  receipt_run=$(sed -n 's/^run_id=//p' "$receipt")
  manifest_run=$(manifest_field "$state" run_id)
  [ -n "$receipt_run" ] && [ "$receipt_run" = "$manifest_run" ] \
    || { printf 'fm-review-convergence: focused remediation run binding changed\n' >&2; return 1; }
  [ "$(sed -n 's/^exit=//p' "$receipt")" = 0 ] \
    || { printf 'fm-review-convergence: focused remediation verification did not pass\n' >&2; return 1; }
  if [ -n "$expected_digest" ] \
     && [ "$(sed -n 's/^command_digest=//p' "$receipt")" != "$expected_digest" ]; then
    printf 'fm-review-convergence: focused remediation command binding changed\n' >&2
    return 1
  fi
  tree=$(worktree_tree "$worktree" "$state")
  [ "$(sed -n 's/^worktree_tree=//p' "$receipt")" = "$tree" ] \
    || { printf 'fm-review-convergence: focused remediation code binding changed\n' >&2; return 1; }
  output="$state/remediation.output"
  [ -s "$output" ] || { printf 'fm-review-convergence: focused remediation output is missing\n' >&2; return 1; }
  output_hash=$(sed -n 's/^output_hash=//p' "$receipt")
  actual_output_hash=$(git -C "$worktree" hash-object "$output")
  [ "$output_hash" = "$actual_output_hash" ] \
    || { printf 'fm-review-convergence: focused remediation output binding changed\n' >&2; return 1; }
}

preflight() {
  local worktree=$1 state=$2 base initial_count final_count limit repeated new_count
  local added_path scope_file amplification_file final_files final_insertions final_deletions
  base=$(manifest_field "$state" base)
  mkdir -p "$state/followups"
  changed_paths "$worktree" "$base" > "$state/final-paths"
  scope_file="$state/followups/scope-expansion.txt"
  : > "$scope_file"
  while IFS= read -r added_path; do
    [ -n "$added_path" ] || continue
    case "$added_path" in
      tests/*) ;;
      *) printf '%s\n' "$added_path" >> "$scope_file" ;;
    esac
  done < <(comm -13 "$state/initial-paths" "$state/final-paths")
  if [ -s "$scope_file" ]; then
    printf 'fm-review-convergence: scope expansion refused; split or fail closed before another review:\n' >&2
    sed 's/^/  /' "$scope_file" >&2
    set_manifest_field "$state" scope_expansion_refused 1
    sync_mirror "$state"
    return 42
  fi

  initial_count=$(manifest_field "$state" initial_tests)
  amplification_file="$state/followups/test-amplification.txt"
  if select_tests "$worktree" "$base" "$state/final-tests"; then
    final_count=$(wc -l < "$state/final-tests" | tr -d ' ')
    set_manifest_field "$state" final_tests "$final_count"
    if [ "$initial_count" -ge 0 ] 2>/dev/null; then
      repeated=$(comm -12 "$state/initial-tests" "$state/final-tests" | wc -l | tr -d ' ')
      new_count=$(comm -13 "$state/initial-tests" "$state/final-tests" | wc -l | tr -d ' ')
      set_manifest_field "$state" repeated_tests "$repeated"
      set_manifest_field "$state" new_tests "$new_count"
      limit=$(manifest_field "$state" test_growth_limit)
      if [ "$final_count" -gt "$limit" ]; then
        {
          printf 'initial_tests=%s\n' "$initial_count"
          printf 'final_tests=%s\n' "$final_count"
          printf 'growth_limit=%s\n' "$limit"
          printf 'repeated_tests=%s\n' "$repeated"
          printf 'new_tests=%s\n' "$new_count"
        } > "$amplification_file"
        printf 'fm-review-convergence: test amplification refused: initial=%s final=%s limit=%s\n' \
          "$initial_count" "$final_count" "$limit" >&2
        set_manifest_field "$state" test_amplification_refused 1
        sync_mirror "$state"
        return 43
      fi
    fi
  else
    set_manifest_field "$state" final_tests -1
  fi
  read -r final_files final_insertions final_deletions <<EOF
$(diff_stats "$worktree" "$base" working)
EOF
  set_manifest_field "$state" final_files "$final_files"
  set_manifest_field "$state" final_insertions "$final_insertions"
  set_manifest_field "$state" final_deletions "$final_deletions"
  sync_mirror "$state"
}

cmd_start() {
  [ "$#" -eq 5 ] || die "start needs <state-dir> <task-id> <worktree> <implementation-start-epoch> <validation-start-epoch>"
  local state=$1 task=$2 worktree=$3 implementation_start=$4 validation_start=$5
  local base head initial_tree files insertions deletions initial_count limit
  require_git_worktree "$worktree"
  mkdir -p "$state"
  rm -f -- "$state/manifest" "$state/initial-paths" "$state/final-paths" \
    "$state/initial-tests" "$state/final-tests" "$state/initial-review.toon" \
    "$state/closure-review.toon" "$state/remediation.receipt" \
    "$state/remediation.output" "$state/defects.tsv"
  rm -rf -- "$state/followups"
  base=$(resolve_base "$worktree")
  head=$(git -C "$worktree" rev-parse HEAD)
  initial_tree=$(worktree_tree "$worktree" "$state")
  changed_paths "$worktree" "$base" > "$state/initial-paths"
  read -r files insertions deletions <<EOF
$(diff_stats "$worktree" "$base" committed)
EOF
  if select_tests "$worktree" "$base" "$state/initial-tests"; then
    initial_count=$(wc -l < "$state/initial-tests" | tr -d ' ')
    limit=$((initial_count * 2))
    [ "$limit" -ge 10 ] || limit=10
  else
    : > "$state/initial-tests"
    initial_count=-1
    limit=-1
  fi
  cat > "$state/manifest" <<EOF
format=1
task_id=$task
stage=started
task_worktree=$worktree
base=$base
initial_head=$head
initial_tree=$initial_tree
implementation_started_epoch=$implementation_start
validation_started_epoch=$validation_start
implementation_files=$files
implementation_insertions=$insertions
implementation_deletions=$deletions
final_files=$files
final_insertions=$insertions
final_deletions=$deletions
initial_review_rounds=0
initial_findings=0
remediation_rounds=0
closure_review_rounds=0
closure_followups=0
test_findings=0
initial_tests=$initial_count
final_tests=$initial_count
repeated_tests=$initial_count
new_tests=0
test_growth_limit=$limit
focused_verification_runs=0
scope_expansion_refused=0
test_amplification_refused=0
first_test_epoch=-1
completion_epoch=-1
mirror_dir=$state
EOF
  printf 'FM_REVIEW_CONVERGENCE stage=started task=%s initial_tests=%s growth_limit=%s\n' \
    "$task" "$initial_count" "$limit"
}

cmd_attach() {
  [ "$#" -eq 4 ] || die "attach needs <state-dir> <run-id> <gate-worktree> <initial-status-file>"
  local source=$1 run_id=$2 worktree=$3 status_file=$4 state findings
  local base head initial_tree files insertions deletions initial_count limit
  require_git_worktree "$worktree"
  [ -s "$source/manifest" ] || die "start state is missing: $source"
  [ -s "$status_file" ] || die "initial review status is missing: $status_file"
  state=$(state_for_worktree "$worktree")
  mkdir -p "$state"
  cp -R "$source/." "$state/"
  base=$(resolve_base "$worktree")
  head=$(git -C "$worktree" rev-parse HEAD)
  initial_tree=$(worktree_tree "$worktree" "$state")
  changed_paths "$worktree" "$base" > "$state/initial-paths"
  read -r files insertions deletions <<EOF
$(diff_stats "$worktree" "$base" committed)
EOF
  if select_tests "$worktree" "$base" "$state/initial-tests"; then
    initial_count=$(wc -l < "$state/initial-tests" | tr -d ' ')
    limit=$((initial_count * 2))
    [ "$limit" -ge 10 ] || limit=10
  else
    : > "$state/initial-tests"
    initial_count=-1
    limit=-1
  fi
  set_manifest_field "$state" mirror_dir "$source"
  set_manifest_field "$state" run_id "$run_id"
  set_manifest_field "$state" gate_worktree "$worktree"
  set_manifest_field "$state" base "$base"
  set_manifest_field "$state" initial_head "$head"
  set_manifest_field "$state" initial_tree "$initial_tree"
  set_manifest_field "$state" implementation_files "$files"
  set_manifest_field "$state" implementation_insertions "$insertions"
  set_manifest_field "$state" implementation_deletions "$deletions"
  set_manifest_field "$state" final_files "$files"
  set_manifest_field "$state" final_insertions "$insertions"
  set_manifest_field "$state" final_deletions "$deletions"
  set_manifest_field "$state" initial_tests "$initial_count"
  set_manifest_field "$state" final_tests "$initial_count"
  set_manifest_field "$state" repeated_tests "$initial_count"
  set_manifest_field "$state" new_tests 0
  set_manifest_field "$state" test_growth_limit "$limit"
  set_manifest_field "$state" stage initial-review
  set_manifest_field "$state" initial_review_rounds 1
  set_manifest_field "$state" initial_review_epoch "$(now_epoch)"
  findings=$(count_status_findings "$status_file")
  set_manifest_field "$state" initial_findings "$findings"
  cp "$status_file" "$state/initial-review.toon"
  : > "$state/defects.tsv"
  append_status_findings "$status_file" review "$state/defects.tsv"
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE stage=initial-review run=%s findings=%s\n' "$run_id" "$findings"
}

cmd_restore() {
  [ "$#" -eq 3 ] || die "restore needs <state-dir> <run-id> <gate-worktree>"
  local source=$1 run_id=$2 worktree=$3 state stage tree
  require_git_worktree "$worktree"
  [ -s "$source/manifest" ] || die "durable mirror is missing: $source"
  [ "$(manifest_field "$source" run_id)" = "$run_id" ] \
    || die "durable mirror belongs to a different run"
  stage=$(manifest_field "$source" stage)
  [ "$stage" != started ] || die "a run that never attached must use attach, not restore"
  state=$(state_for_worktree "$worktree")
  mkdir -p "$state"
  cp -R "$source/." "$state/"
  set_manifest_field "$state" mirror_dir "$source"
  set_manifest_field "$state" gate_worktree "$worktree"
  case "$stage" in
    initial-review)
      tree=$(worktree_tree "$worktree" "$state")
      [ "$tree" = "$(manifest_field "$state" initial_tree)" ] \
        || die "initial-review worktree changed while convergence state was unavailable"
      ;;
    remediation|closure-reviewed|closure-blocked)
      receipt_valid "$worktree" "$state" ""
      ;;
    *) die "cannot restore convergence stage $stage into a gate worktree" ;;
  esac
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE restored=true stage=%s run=%s\n' "$stage" "$run_id"
}

cmd_begin_remediation() {
  [ "$#" -eq 1 ] || die "begin-remediation needs <gate-worktree>"
  local worktree=$1 state stage rounds
  state=$(state_for_worktree "$worktree")
  [ -s "$state/manifest" ] || die "review convergence state is missing"
  stage=$(manifest_field "$state" stage)
  rounds=$(manifest_field "$state" remediation_rounds)
  if [ "$rounds" -ge 1 ] 2>/dev/null || [ "$stage" != initial-review ]; then
    printf 'fm-review-convergence: one batched remediation already started; another full review/fix pass is forbidden\n' >&2
    exit 45
  fi
  set_manifest_field "$state" remediation_rounds 1
  set_manifest_field "$state" remediation_started_epoch "$(now_epoch)"
  set_manifest_field "$state" stage remediation
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE stage=remediation round=1\n'
}

cmd_record() {
  [ "$#" -ge 3 ] || die "record needs <gate-worktree> -- <command...>"
  local worktree=$1 state digest existing_digest before after output receipt tmp_receipt
  local started finished duration rc display runs
  shift
  [ "${1:-}" = -- ] || die "record needs -- before the focused verification command"
  shift
  [ "$#" -gt 0 ] || die "record needs a focused verification command"
  state=$(state_for_worktree "$worktree")
  [ "$(manifest_field "$state" stage)" = remediation ] \
    || die "focused remediation evidence can be recorded only during the one remediation"
  digest=$(command_digest "$worktree" "$@")
  if [ -s "$state/remediation.receipt" ]; then
    existing_digest=$(sed -n 's/^command_digest=//p' "$state/remediation.receipt")
    if [ "$existing_digest" = "$digest" ] && receipt_valid "$worktree" "$state" "$digest"; then
      printf 'FM_REVIEW_EVIDENCE reused=true command_digest=%s\n' "$digest"
      cat "$state/remediation.output"
      return 0
    fi
  fi
  preflight "$worktree" "$state"
  before=$(worktree_tree "$worktree" "$state")
  display=$(command_display "$@")
  output="$state/remediation.output"
  started=$(now_ms)
  set +e
  "$@" 2>&1 | tee "$output"
  rc=${PIPESTATUS[0]}
  set -e
  finished=$(now_ms)
  duration=$((finished - started))
  after=$(worktree_tree "$worktree" "$state")
  [ "$before" = "$after" ] || {
    printf 'fm-review-convergence: focused verification changed the bound worktree; evidence refused\n' >&2
    return 46
  }
  receipt="$state/remediation.receipt"
  tmp_receipt=$(mktemp "$state/.receipt.XXXXXX")
  cat > "$tmp_receipt" <<EOF
format=1
run_id=$(manifest_field "$state" run_id)
worktree=$worktree
worktree_tree=$after
command_digest=$digest
command=$display
output_hash=$(git -C "$worktree" hash-object "$output")
exit=$rc
started_ms=$started
finished_ms=$finished
duration_ms=$duration
EOF
  mv "$tmp_receipt" "$receipt"
  runs=$(manifest_field "$state" focused_verification_runs)
  set_manifest_field "$state" focused_verification_runs "$((runs + 1))"
  sync_mirror "$state"
  printf 'FM_REVIEW_EVIDENCE reused=false command_digest=%s exit=%s\n' "$digest" "$rc"
  return "$rc"
}

cmd_verify() {
  [ "$#" -ge 1 ] || die "verify needs <gate-worktree> [-- <command...>]"
  local worktree=$1 state digest=
  shift
  state=$(state_for_worktree "$worktree")
  if [ "$#" -gt 0 ]; then
    [ "$1" = -- ] || die "verify needs -- before the expected command"
    shift
    [ "$#" -gt 0 ] || die "verify needs a command after --"
    digest=$(command_digest "$worktree" "$@")
  fi
  receipt_valid "$worktree" "$state" "$digest"
  printf 'FM_REVIEW_EVIDENCE verified=true\n'
}

cmd_close_review() {
  [ "$#" -eq 2 ] || die "close-review needs <gate-worktree> <closure-status-file>"
  local worktree=$1 status_file=$2 state followups blocking=0 count
  state=$(state_for_worktree "$worktree")
  [ "$(manifest_field "$state" stage)" = remediation ] \
    || die "closure review is legal only after the one remediation"
  [ -s "$status_file" ] || die "closure status is missing: $status_file"
  receipt_valid "$worktree" "$state" ""
  preflight "$worktree" "$state"
  mkdir -p "$state/followups"
  followups="$state/followups/closure.tsv"
  : > "$followups"
  awk -v out="$followups" '
    /^[[:space:]]*findings\[[0-9]+\].*\{.*\}:/ { in_findings=1; next }
    in_findings && /^    [^ ]/ {
      line=$0
      sub(/^    /, "", line)
      n=split(line, fields, ",")
      action=""
      for (i=1; i<=n && i<=7; i++) {
        if (fields[i] == "no-op" || fields[i] == "auto-fix" || fields[i] == "ask-user") {
          action=fields[i]
          break
        }
      }
      if (action == "no-op" && fields[2] == "info" && fields[5] ~ /^"FOLLOW-UP:/) {
        print line >> out
      } else if (action != "") {
        blocking++
      }
      next
    }
    in_findings { in_findings=0 }
    END { if (blocking > 0) exit 44 }
  ' "$status_file" || blocking=1
  count=$(wc -l < "$followups" | tr -d ' ')
  set_manifest_field "$state" closure_review_rounds 1
  set_manifest_field "$state" closure_review_epoch "$(now_epoch)"
  set_manifest_field "$state" closure_followups "$count"
  cp "$status_file" "$state/closure-review.toon"
  if [ "$blocking" -ne 0 ]; then
    set_manifest_field "$state" stage closure-blocked
    sync_mirror "$state"
    printf 'fm-review-convergence: closure found a catastrophic blocker; split or fail closed, do not start another remediation\n' >&2
    exit 44
  fi
  set_manifest_field "$state" stage closure-reviewed
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE stage=closure-reviewed followups=%s\n' "$count"
}

cmd_mark_tests() {
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "mark-tests needs <gate-worktree> [epoch]"
  local worktree=$1 epoch=${2:-$(now_epoch)} state stage
  state=$(state_for_target "$worktree")
  stage=$(manifest_field "$state" stage)
  case "$stage" in
    initial-review|closure-reviewed) ;;
    *) die "tests cannot start from convergence stage $stage" ;;
  esac
  set_manifest_field "$state" first_test_epoch "$epoch"
  set_manifest_field "$state" stage tests
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE stage=tests first_test_epoch=%s\n' "$epoch"
}

cmd_mark_complete() {
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "mark-complete needs <gate-worktree> [epoch]"
  local worktree=$1 epoch=${2:-$(now_epoch)} state stage
  state=$(state_for_target "$worktree")
  stage=$(manifest_field "$state" stage)
  case "$stage" in
    initial-review|closure-reviewed|tests) ;;
    *) die "validation cannot complete from convergence stage $stage" ;;
  esac
  set_manifest_field "$state" completion_epoch "$epoch"
  set_manifest_field "$state" stage complete
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE stage=complete completion_epoch=%s\n' "$epoch"
}

cmd_observe_status() {
  [ "$#" -eq 2 ] || die "observe-status needs <gate-worktree-or-state-dir> <status-file>"
  local target=$1 status_file=$2 state test_findings gate_step new_defects kept_defects
  state=$(state_for_target "$target")
  [ -s "$state/manifest" ] || die "review convergence state is missing"
  [ -s "$status_file" ] || die "pipeline status is missing: $status_file"
  test_findings=$(awk '
    /^[[:space:]]+test,/ {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      split(line, fields, ",")
      print fields[3] + 0
      exit
    }
  ' "$status_file")
  [ -n "$test_findings" ] || test_findings=0
  set_manifest_field "$state" test_findings "$test_findings"
  gate_step=$(status_gate_step "$status_file")
  if [ "$gate_step" = test ]; then
    new_defects=$(mktemp "$state/.test-defects.XXXXXX")
    kept_defects=$(mktemp "$state/.kept-defects.XXXXXX")
    : > "$new_defects"
    append_status_findings "$status_file" test "$new_defects"
    if [ -s "$new_defects" ]; then
      awk -F '\t' '$1 != "test" { print }' "$state/defects.tsv" > "$kept_defects"
      cat "$new_defects" >> "$kept_defects"
      mv "$kept_defects" "$state/defects.tsv"
    else
      rm -f "$kept_defects"
    fi
    rm -f "$new_defects"
  fi
  sync_mirror "$state"
  printf 'FM_REVIEW_CONVERGENCE test_findings=%s\n' "$test_findings"
}

cmd_metrics() {
  [ "$#" -eq 1 ] || die "metrics needs <gate-worktree-or-state-dir>"
  local target=$1 state validation_start implementation_start first_test review_end
  local review_time time_to_first_test
  local final_files final_insertions final_deletions initial_files initial_insertions initial_deletions
  state=$(state_for_target "$target")
  [ -s "$state/manifest" ] || die "review convergence state is missing"
  final_files=$(manifest_field "$state" final_files)
  final_insertions=$(manifest_field "$state" final_insertions)
  final_deletions=$(manifest_field "$state" final_deletions)
  initial_files=$(manifest_field "$state" implementation_files)
  initial_insertions=$(manifest_field "$state" implementation_insertions)
  initial_deletions=$(manifest_field "$state" implementation_deletions)
  validation_start=$(manifest_field "$state" validation_started_epoch)
  implementation_start=$(manifest_field "$state" implementation_started_epoch)
  first_test=$(manifest_field "$state" first_test_epoch)
  if [ "$first_test" -ge 0 ] 2>/dev/null; then
    review_end=$first_test
    time_to_first_test=$(((first_test - validation_start) * 1000))
  else
    review_end=$(manifest_field "$state" completion_epoch)
    [ "$review_end" -ge 0 ] 2>/dev/null \
      || die "metrics are unavailable until tests start or review-only validation completes"
    time_to_first_test=-1
  fi
  review_time=$(((review_end - validation_start) * 1000))
  cat <<EOF
FM_REVIEW_METRICS task_id=$(manifest_field "$state" task_id) run_id=$(manifest_field "$state" run_id)
implementation_time_ms=$(((validation_start - implementation_start) * 1000))
implementation_files=$initial_files
implementation_insertions=$initial_insertions
implementation_deletions=$initial_deletions
initial_review_rounds=$(manifest_field "$state" initial_review_rounds)
initial_review_findings=$(manifest_field "$state" initial_findings)
remediation_rounds=$(manifest_field "$state" remediation_rounds)
closure_review_rounds=$(manifest_field "$state" closure_review_rounds)
review_time_ms=$review_time
remediation_file_growth=$((final_files - initial_files))
remediation_insertion_growth=$((final_insertions - initial_insertions))
remediation_deletion_growth=$((final_deletions - initial_deletions))
time_to_first_test_ms=$time_to_first_test
initial_tests=$(manifest_field "$state" initial_tests)
final_tests=$(manifest_field "$state" final_tests)
repeated_tests=$(manifest_field "$state" repeated_tests)
new_tests=$(manifest_field "$state" new_tests)
focused_verification_runs=$(manifest_field "$state" focused_verification_runs)
closure_followups=$(manifest_field "$state" closure_followups)
review_defects=$(manifest_field "$state" initial_findings)
review_defect_ids=$(defect_ids "$state" review)
test_defects=$(manifest_field "$state" test_findings)
test_defect_ids=$(defect_ids "$state" test)
scope_expansion_refused=$(manifest_field "$state" scope_expansion_refused)
test_amplification_refused=$(manifest_field "$state" test_amplification_refused)
EOF
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  attach) shift; cmd_attach "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  begin-remediation) shift; cmd_begin_remediation "$@" ;;
  record) shift; cmd_record "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  close-review) shift; cmd_close_review "$@" ;;
  mark-tests) shift; cmd_mark_tests "$@" ;;
  mark-complete) shift; cmd_mark_complete "$@" ;;
  observe-status) shift; cmd_observe_status "$@" ;;
  metrics) shift; cmd_metrics "$@" ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
