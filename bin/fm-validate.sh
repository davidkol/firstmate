#!/usr/bin/env bash
# Start (or restart) a task's no-mistakes validation run with the pipeline flags
# its delivery mode requires.
#
# The skip set is a property of the delivery mode, not of a call site. A
# validated-main task never opens a pull request, so its run must skip the pr and
# ci steps every time - on the first run, on a re-run after a failure, and for
# whoever drives it next. no-mistakes has no repository-level way to make --skip
# sticky (docs/verification/validation-pipeline.md), so this script is where that
# binding lives instead of in an instruction a worker has to remember to type.
#
# The mode is read from the task's own state/<id>.meta, which fm-spawn.sh recorded
# at dispatch, so the run inherits the mode the task was actually dispatched under
# rather than a registry that may have changed since.
#
# This script NEVER skips review, for any mode. Dropping the pull request is not
# dropping the automated review: the review step is what makes landing on a default
# branch safe when nobody reads the diff. A caller's own --skip is merged with the
# mode's, never allowed to replace it, and `review` is dropped out of that caller
# half with a warning so the promise holds against whoever types the flag. On a
# light path review is the only step that runs, so honouring `--skip review` there
# would start a run with every step skipped that still reports a passing outcome.
#
# The full-pipeline modes - no-mistakes and validated-main - additionally never drop
# test, document, or lint; only the two host-facing steps are ever mode-skipped there.
#
# direct-PR and local-only are the light paths and invert that shape. Both ran no
# pipeline at all until the captain's decision of 2026-07-30, which kept the light
# path the fleet default but gave it "a fresh-context review on its own - one agent
# reading the change cold, without the other eight pipeline steps around it". So
# their derived set keeps review and skips the other eight. That ADDS a reviewer to
# paths that had none; it does not remove steps from a path that had them, and the
# review it adds is run by an agent process the no-mistakes daemon starts, never by
# the worker that wrote the change.
#
# push is skipped on both, for different reasons: a direct-PR worker publishes and
# opens its own pull request afterwards, and a local-only worker must never reach a
# remote at all. Skipping push is what lets local-only run this review without
# violating its own no-push rule - the review reads the branch and publishes nothing.
#
# The gate the run needs is local, but `no-mistakes init` refuses in a repository
# with no `origin` remote at all, so a remoteless local-only project cannot run this
# review; docs/verification/validation-pipeline.md records that refusal. An origin
# pointing at a local filesystem path is enough, which is what the registry's
# local-only projects have.
#
# Run it from inside the task worktree - it hands off to no-mistakes in the current
# directory and does not change it, and refuses when that directory is not the one
# the task's own meta records. Drive every resulting gate through this script's
# `respond` form. It passes non-review gates through, but owns the review round
# budget, durable remediation receipt, bounded closure, and transition to tests.
# Calling `no-mistakes axi respond` directly bypasses that executable boundary.
# The selected review intent comes from the validated delivery contract in the
# task brief. A legacy caller-supplied --intent is accepted but ignored so a
# paraphrase cannot weaken or replace the canonical outcome. At least one
# --evidence path must name a non-empty executed result or capture inside the
# task worktree; the wrapper publishes copies on no-mistakes' temporary evidence
# surface so every isolated review round can inspect and refresh them.
# Usage:
#   fm-validate.sh <task-id> --evidence <path> [--evidence <path>...] [extra axi run args...]
#   fm-validate.sh <task-id> respond --action approve|fix|skip [axi respond args...]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

usage() {
  echo 'usage: fm-validate.sh <task-id> --evidence <path> [--evidence <path>...] [extra axi run args...]' >&2
  echo '       fm-validate.sh <task-id> respond --action approve|fix|skip [axi respond args...]' >&2
}

CONVERGENCE="$SCRIPT_DIR/fm-review-convergence.sh"

toon_run_id() {
  awk '
    /^run:/ { in_run=1; next }
    in_run && /^  id:/ {
      sub(/^  id:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
    in_run && /^[^ ]/ { in_run=0 }
  ' "$1"
}

toon_run_branch() {
  awk '
    /^run:/ { in_run=1; next }
    in_run && /^  branch:/ {
      sub(/^  branch:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
    in_run && /^[^ ]/ { in_run=0 }
  ' "$1"
}

toon_run_status() {
  awk '
    /^run:/ { in_run=1; next }
    in_run && /^  status:/ {
      sub(/^  status:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
    in_run && /^[^ ]/ { in_run=0 }
  ' "$1"
}

toon_gate_step() {
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

toon_gate_status() {
  awk '
    /^gate:/ { in_gate=1; next }
    in_gate && /^  status:/ {
      sub(/^  status:[[:space:]]*/, "")
      print
      exit
    }
    in_gate && /^[^ ]/ { in_gate=0 }
  ' "$1"
}

toon_actionable_ids() {
  awk '
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
      if (action == "auto-fix" || action == "ask-user") print fields[1]
      next
    }
    in_findings { in_findings=0 }
  ' "$1" | LC_ALL=C sort -u
}

find_gate_worktree() {
  local run_id=$1 nm_root candidate count=0 found=
  nm_root=${NM_HOME:-${HOME}/.no-mistakes}
  [ -d "$nm_root/worktrees" ] || return 1
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    found=$candidate
    count=$((count + 1))
  done < <(find "$nm_root/worktrees" -mindepth 2 -maxdepth 2 -type d -name "$run_id" -print 2>/dev/null)
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$found"
}

meta_mtime_epoch() {
  local file=$1
  stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || date +%s
}

manifest_value() {
  local target=$1 key=$2 manifest
  if [ -s "$target/manifest" ]; then
    manifest="$target/manifest"
  else
    manifest="$target/.no-mistakes/review-convergence/manifest"
  fi
  sed -n "s/^${key}=//p" "$manifest" | sed -n '1p'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ID=${1:-}
[ -n "$ID" ] || { usage; exit 1; }
shift

BRIEF="$DATA/$ID/brief.md"
[ -f "$BRIEF" ] || { echo "error: no brief for task $ID at $BRIEF" >&2; exit 1; }

META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }
MODE=$(grep '^mode=' "$META" | cut -d= -f2- || true)
[ -n "$MODE" ] || MODE=no-mistakes

# The skip set derived below belongs to THIS task's repository, and no-mistakes
# picks its repository up from the current directory. Started from anywhere else -
# a wrong directory, a mistyped or stale task id - it would hand one task's mode to
# another project's pipeline. The meta already records where the task lives, so the
# binding is checked here rather than left to a worker remembering to cd first.
WORKTREE=$(grep '^worktree=' "$META" | cut -d= -f2- || true)
[ -n "$WORKTREE" ] || { echo "error: task $ID has no recorded worktree, so final-change evidence cannot be bound to it" >&2; exit 1; }
HERE=$(pwd -P)
THERE=$(cd "$WORKTREE" 2>/dev/null && pwd -P) || THERE=$WORKTREE
case "$HERE" in
  "$THERE"|"$THERE"/*) ;;
  *)
    echo "error: task $ID's worktree is $WORKTREE, but this is $HERE" >&2
    echo "Run fm-validate.sh from inside the task worktree; a mode-derived skip set must never be applied to another repository's pipeline." >&2
    exit 1
    ;;
esac

respond_gate() {
  local status_file response_file after_file run_id run_branch task_branch gate_step gate_status gate_worktree stage action=
  local after_gate_step after_run_status
  local findings='' caller_instructions='' resolve_keys='' resolve_key
  local expected_ids selected_ids convergence_instructions combined_instructions
  local response_rc close_rc=0 outer_state has_add_finding=0
  local -a response_args=() forwarded_args=()

  [ "$#" -gt 0 ] || { usage; exit 1; }
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)
        echo "error: --yes bypasses Firstmate's authority and review-convergence gates" >&2
        exit 1
        ;;
      --action)
        [ "$#" -ge 2 ] || { echo "error: --action needs a value" >&2; exit 1; }
        action=$2
        response_args+=("$1" "$2")
        shift 2
        ;;
      --action=*)
        action=${1#--action=}
        response_args+=("$1")
        shift
        ;;
      --findings)
        [ "$#" -ge 2 ] || { echo "error: --findings needs a value" >&2; exit 1; }
        findings=$2
        response_args+=("$1" "$2")
        shift 2
        ;;
      --findings=*)
        findings=${1#--findings=}
        response_args+=("$1")
        shift
        ;;
      --instructions)
        [ "$#" -ge 2 ] || { echo "error: --instructions needs a value" >&2; exit 1; }
        caller_instructions=$2
        shift 2
        ;;
      --instructions=*)
        caller_instructions=${1#--instructions=}
        shift
        ;;
      --resolve-key)
        [ "$#" -ge 2 ] || { echo "error: --resolve-key needs a value" >&2; exit 1; }
        resolve_key=$2
        case "$resolve_key" in
          ''|*[!A-Za-z0-9._-]*)
            echo "error: --resolve-key '$resolve_key' is not a valid decision key" >&2
            exit 1
            ;;
        esac
        case " $resolve_keys " in
          *" $resolve_key "*) echo "error: duplicate --resolve-key '$resolve_key'" >&2; exit 1 ;;
        esac
        resolve_keys="${resolve_keys}${resolve_keys:+ }$resolve_key"
        shift 2
        ;;
      --resolve-key=*)
        resolve_key=${1#--resolve-key=}
        case "$resolve_key" in
          ''|*[!A-Za-z0-9._-]*)
            echo "error: --resolve-key '$resolve_key' is not a valid decision key" >&2
            exit 1
            ;;
        esac
        case " $resolve_keys " in
          *" $resolve_key "*) echo "error: duplicate --resolve-key '$resolve_key'" >&2; exit 1 ;;
        esac
        resolve_keys="${resolve_keys}${resolve_keys:+ }$resolve_key"
        shift
        ;;
      --add-finding)
        [ "$#" -ge 2 ] || { echo "error: --add-finding needs a value" >&2; exit 1; }
        has_add_finding=1
        response_args+=("$1" "$2")
        shift 2
        ;;
      --add-finding=*)
        has_add_finding=1
        response_args+=("$1")
        shift
        ;;
      *)
        response_args+=("$1")
        shift
        ;;
    esac
  done
  [ -n "$action" ] || { echo "error: respond needs --action" >&2; exit 1; }

  close_resolved_keys() {
    local key
    for key in $resolve_keys; do
      if ! printf 'resolved [key=%s]: validation decision applied at %s gate\n' \
        "$key" "$gate_step" >> "$STATE/$ID.status"; then
        echo "error: validation response succeeded, but decision key '$key' could not be closed in $STATE/$ID.status" >&2
        return 1
      fi
    done
  }

  outer_state="$STATE/$ID.review-convergence"
  mkdir -p "$outer_state"
  status_file="$outer_state/axi-status-before.toon"
  if ! no-mistakes axi status > "$status_file"; then
    echo "error: cannot read no-mistakes status for task $ID" >&2
    exit 1
  fi
  run_id=$(toon_run_id "$status_file")
  [ -n "$run_id" ] || { echo "error: no active no-mistakes run id for task $ID" >&2; exit 1; }
  run_branch=$(toon_run_branch "$status_file")
  task_branch=$(git -C "$THERE" branch --show-current)
  [ -n "$run_branch" ] && [ -n "$task_branch" ] && [ "$run_branch" = "$task_branch" ] || {
    echo "error: active no-mistakes run $run_id is for branch ${run_branch:-unknown}, not task $ID's branch ${task_branch:-detached}" >&2
    exit 1
  }
  gate_step=$(toon_gate_step "$status_file")
  gate_status=$(toon_gate_status "$status_file")
  [ -n "$gate_step" ] || { echo "error: no parked no-mistakes gate for task $ID" >&2; exit 1; }

  # Review is the only phase with a Firstmate convergence overlay. Every later
  # pipeline gate keeps no-mistakes' native response semantics, but still comes
  # back through this wrapper so test findings and terminal metrics stay durable.
  if [ "$gate_step" != review ]; then
    if [ -s "$outer_state/manifest" ]; then
      "$CONVERGENCE" observe-status "$outer_state" "$status_file" >/dev/null
      stage=$(manifest_value "$outer_state" stage)
      case "$MODE:$stage" in
        no-mistakes:initial-review|no-mistakes:closure-reviewed|\
        validated-main:initial-review|validated-main:closure-reviewed)
          "$CONVERGENCE" mark-tests "$outer_state" "$(date +%s)" >/dev/null
          ;;
      esac
    fi
    forwarded_args=("${response_args[@]}")
    if [ -n "$caller_instructions" ]; then
      forwarded_args+=(--instructions "$caller_instructions")
    fi
    response_file="$outer_state/axi-respond.toon"
    set +e
    no-mistakes axi respond "${forwarded_args[@]}" | tee "$response_file"
    response_rc=${PIPESTATUS[0]}
    set -e
    [ "$response_rc" -eq 0 ] || return "$response_rc"
    close_resolved_keys || return 1
    after_file="$outer_state/axi-status-after.toon"
    no-mistakes axi status > "$after_file" || return 1
    if [ -s "$outer_state/manifest" ]; then
      "$CONVERGENCE" observe-status "$outer_state" "$after_file" >/dev/null
      after_run_status=$(toon_run_status "$after_file")
      stage=$(manifest_value "$outer_state" stage)
      if [ "$after_run_status" = completed ] && [ "$stage" != complete ]; then
        "$CONVERGENCE" mark-complete "$outer_state" "$(date +%s)" >/dev/null
      fi
      "$CONVERGENCE" metrics "$outer_state" | tee "$outer_state/metrics.txt"
    fi
    return 0
  fi
  [ "$has_add_finding" -eq 0 ] || {
    echo "error: review convergence does not allow a new finding to expand the initial remediation batch" >&2
    exit 1
  }
  [ "$gate_status" = awaiting_approval ] || [ "$gate_status" = fix_review ] \
    || { echo "error: unsupported review gate status: $gate_status" >&2; exit 1; }
  gate_worktree=$(find_gate_worktree "$run_id") || {
    echo "error: cannot resolve the unique no-mistakes gate worktree for run $run_id" >&2
    exit 1
  }
  if [ ! -s "$gate_worktree/.no-mistakes/review-convergence/manifest" ] \
     && [ -s "$outer_state/manifest" ] \
     && [ "$(manifest_value "$outer_state" task_id)" = "$ID" ] \
     && [ "$(manifest_value "$outer_state" stage)" = started ]; then
    "$CONVERGENCE" attach "$outer_state" "$run_id" "$gate_worktree" "$status_file" >/dev/null
  fi
  if [ ! -s "$gate_worktree/.no-mistakes/review-convergence/manifest" ] \
     && [ -s "$outer_state/manifest" ] \
     && [ "$(manifest_value "$outer_state" task_id)" = "$ID" ]; then
    "$CONVERGENCE" restore "$outer_state" "$run_id" "$gate_worktree" >/dev/null
  fi
  [ -s "$gate_worktree/.no-mistakes/review-convergence/manifest" ] || {
    echo "error: run $run_id has no durable Firstmate review-convergence state; do not respond directly" >&2
    exit 1
  }
  stage=$(manifest_value "$gate_worktree" stage)

  case "$action" in
    fix)
      [ "$stage" = initial-review ] || {
        echo "error: one batched remediation already ran; a second review-fix pass is forbidden" >&2
        exit 45
      }
      expected_ids=$(toon_actionable_ids "$status_file")
      selected_ids=$(printf '%s\n' "$findings" | tr ',' '\n' | sed '/^$/d' | LC_ALL=C sort -u)
      [ -n "$expected_ids" ] || {
        echo "error: the initial review has no actionable findings to remediate" >&2
        exit 1
      }
      [ "$selected_ids" = "$expected_ids" ] || {
        echo "error: the one remediation must batch every actionable initial-review finding" >&2
        echo "expected finding ids: $(printf '%s' "$expected_ids" | tr '\n' ',' | sed 's/,$//')" >&2
        exit 1
      }
      "$CONVERGENCE" begin-remediation "$gate_worktree" >/dev/null
      convergence_instructions="Firstmate review convergence: this is the only remediation pass. Apply the selected findings as one root-cause batch. Run exactly one focused verification after all edits by wrapping that command as: $CONVERGENCE record $gate_worktree -- <focused-command-and-args>. Do not run that focused command outside the wrapper. If the wrapper refuses scope expansion or proportional-test amplification, stop and preserve its follow-up output instead of broadening the change."
      combined_instructions=${caller_instructions:+$caller_instructions$'\n'}$convergence_instructions
      forwarded_args=("${response_args[@]}" --instructions "$combined_instructions")
      ;;
    approve)
      case "$stage" in
        remediation)
          "$CONVERGENCE" close-review "$gate_worktree" "$status_file"
          stage=closure-reviewed
          ;;
        initial-review|closure-reviewed) ;;
        closure-blocked)
          echo "error: the bounded closure found a catastrophic blocker; split or fail closed" >&2
          exit 44
          ;;
        *)
          echo "error: review approval is not legal from convergence stage $stage" >&2
          exit 1
          ;;
      esac
      if [ -n "$caller_instructions" ]; then
        forwarded_args=("${response_args[@]}" --instructions "$caller_instructions")
      else
        forwarded_args=("${response_args[@]}")
      fi
      ;;
    skip)
      echo "error: Firstmate review may not be skipped" >&2
      exit 1
      ;;
    *)
      echo "error: unsupported response action: $action" >&2
      exit 1
      ;;
  esac

  response_file="$outer_state/axi-respond.toon"
  set +e
  no-mistakes axi respond "${forwarded_args[@]}" | tee "$response_file"
  response_rc=${PIPESTATUS[0]}
  set -e
  [ "$response_rc" -eq 0 ] || return "$response_rc"
  close_resolved_keys || return 1

  # A fix response is the closure review itself. Close it immediately while the
  # exact reviewed worktree is still present, including when a clean closure lets
  # a review-only run finish and the daemon would otherwise retire that worktree.
  if [ "$action" = fix ]; then
    set +e
    "$CONVERGENCE" close-review "$gate_worktree" "$response_file"
    close_rc=$?
    set -e
    [ "$close_rc" -eq 0 ] || return "$close_rc"
  fi

  after_file="$outer_state/axi-status-after.toon"
  no-mistakes axi status > "$after_file" || return 1
  "$CONVERGENCE" observe-status "$outer_state" "$after_file" >/dev/null
  after_gate_step=$(toon_gate_step "$after_file")
  after_run_status=$(toon_run_status "$after_file")
  stage=$(manifest_value "$outer_state" stage)
  if [ "$after_gate_step" != review ]; then
    case "$MODE" in
      direct-PR|local-only)
        [ "$after_run_status" = completed ] || {
          echo "error: review-only run left review without reaching a terminal outcome" >&2
          return 1
        }
        [ "$stage" = complete ] \
          || "$CONVERGENCE" mark-complete "$outer_state" "$(date +%s)" >/dev/null
        ;;
      *)
        case "$stage" in
          initial-review|closure-reviewed)
            "$CONVERGENCE" mark-tests "$outer_state" "$(date +%s)" >/dev/null
            ;;
        esac
        ;;
    esac
  fi
  stage=$(manifest_value "$outer_state" stage)
  case "$stage" in
    tests|complete)
      "$CONVERGENCE" metrics "$outer_state" | tee "$outer_state/metrics.txt"
      ;;
  esac
}

if [ "${1:-}" = respond ]; then
  shift
  respond_gate "$@"
  exit $?
fi

# Steps this delivery mode must always omit. review never appears here for any
# mode; it is the one step every mode keeps.
case "$MODE" in
  validated-main)       MODE_SKIP="pr,ci" ;;
  direct-PR|local-only) MODE_SKIP="intent,rebase,test,document,lint,push,pr,ci" ;;
  *)                    MODE_SKIP="" ;;
esac

# Pull any caller-supplied --skip out of the passthrough args so a second --skip
# cannot override the mode's. The two sets are merged below.
CALLER_SKIP=""
CALLER_INTENT=""
EVIDENCE_PATHS=()
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip)
      [ $# -ge 2 ] || { echo "error: --skip needs a value" >&2; exit 1; }
      CALLER_SKIP="${CALLER_SKIP:+$CALLER_SKIP,}$2"
      shift 2
      ;;
    --skip=*)
      CALLER_SKIP="${CALLER_SKIP:+$CALLER_SKIP,}${1#--skip=}"
      shift
      ;;
    --intent)
      [ $# -ge 2 ] || { echo "error: --intent needs a value" >&2; exit 1; }
      CALLER_INTENT=$2
      shift 2
      ;;
    --intent=*)
      CALLER_INTENT=${1#--intent=}
      shift
      ;;
    --evidence)
      [ $# -ge 2 ] || { echo "error: --evidence needs a path" >&2; exit 1; }
      EVIDENCE_PATHS+=("$2")
      shift 2
      ;;
    --evidence=*)
      EVIDENCE_PATHS+=("${1#--evidence=}")
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

[ "${#EVIDENCE_PATHS[@]}" -gt 0 ] || {
  echo "error: at least one --evidence path is required; save the executed final-change result or capture inside $THERE" >&2
  exit 1
}

EVIDENCE_REAL_PATHS=()
for evidence_path in "${EVIDENCE_PATHS[@]}"; do
  [ -n "$evidence_path" ] || { echo "error: --evidence path cannot be empty" >&2; exit 1; }
  [ -f "$evidence_path" ] && [ ! -L "$evidence_path" ] && [ -s "$evidence_path" ] || {
    echo "error: evidence must be a non-empty regular file, not a symlink: $evidence_path" >&2
    exit 1
  }
  evidence_dir=$(cd "$(dirname "$evidence_path")" 2>/dev/null && pwd -P) || {
    echo "error: evidence directory cannot be resolved: $evidence_path" >&2
    exit 1
  }
  evidence_real="$evidence_dir/$(basename "$evidence_path")"
  case "$evidence_real" in
    "$THERE"/*) ;;
    *)
      echo "error: evidence must stay inside the task worktree $THERE: $evidence_path" >&2
      exit 1
      ;;
  esac
  EVIDENCE_REAL_PATHS+=("$evidence_real")
done

REVIEW_INTENT=$("$SCRIPT_DIR/fm-doctrine-contract.sh" review-intent "$BRIEF") || {
  echo "error: task $ID has no valid canonical delivery contract; validation did not start" >&2
  exit 1
}

PIPELINE_EVIDENCE_ROOT="${TMPDIR:-/tmp}/no-mistakes-evidence"
mkdir -p "$PIPELINE_EVIDENCE_ROOT" || {
  echo "error: cannot create no-mistakes evidence root: $PIPELINE_EVIDENCE_ROOT" >&2
  exit 1
}
evidence_slug=$(printf '%s' "$ID" | tr -c 'A-Za-z0-9._-' '-')
PIPELINE_EVIDENCE_DIR=$(mktemp -d "$PIPELINE_EVIDENCE_ROOT/fm-validate-$evidence_slug.XXXXXX") || {
  echo "error: cannot create pipeline evidence directory under $PIPELINE_EVIDENCE_ROOT" >&2
  exit 1
}

EVIDENCE_INTENT=""
evidence_index=0
for evidence_real in "${EVIDENCE_REAL_PATHS[@]}"; do
  evidence_index=$((evidence_index + 1))
  evidence_name=$(basename "$evidence_real")
  evidence_name=$(printf '%s' "$evidence_name" | tr -c 'A-Za-z0-9._-' '-')
  published_evidence="$PIPELINE_EVIDENCE_DIR/input-$evidence_index-$evidence_name"
  cp "$evidence_real" "$published_evidence" || {
    echo "error: cannot publish evidence to $published_evidence" >&2
    exit 1
  }
  [ -s "$published_evidence" ] || {
    echo "error: published evidence is empty: $published_evidence" >&2
    exit 1
  }
  EVIDENCE_INTENT="${EVIDENCE_INTENT}${EVIDENCE_INTENT:+
}$published_evidence"
done

REVIEW_INTENT="$REVIEW_INTENT
Executed final-change evidence is on the shared no-mistakes evidence surface.
Pipeline evidence directory: $PIPELINE_EVIDENCE_DIR
Initial worker captures (inspect each directly):
$EVIDENCE_INTENT
Evidence lifecycle for every topology:
- Reuse these captures when no pipeline rebase resolution or review fix changes the relevant final diff.
- When a review remediation changes the relevant diff, the response wrapper supplies an exact fm-review-convergence record command. That executable runs the one focused verification, persists its complete output in the gate worktree's ignored pipeline state, and binds it to the unchanged worktree tree and exact command. Do not run that command separately.
- The first review is the one full independent audit. A post-remediation review is one bounded closure review over the initial findings, the remediation delta, and only catastrophic regressions: accepted-intent contradiction, work loss or destruction, security failure, or an immediately reachable regression introduced at the changed boundary.
- On that closure review, report adjacent hardening and pre-existing weaknesses only as severity info, action no-op findings prefixed FOLLOW-UP. Do not restart the full-branch audit or request another remediation for them.
- The executable response boundary permits one remediation only. If closure finds a catastrophic blocker, report it and fail closed so the work can be split; never begin review pass three."

if [ -n "$CALLER_INTENT" ]; then
  echo "fm-validate: ignored caller --intent; using the canonical outcome and selected-review contract from $BRIEF." >&2
fi
ARGS+=(--intent "$REVIEW_INTENT")

# Merge and de-duplicate, preserving the mode's steps first. This loop is the one
# place the final skip set is assembled, so it is where the never-skip-review
# invariant is enforced: no mode-derived set contains review, so any review here
# came from the caller and is dropped.
SKIP=""
REVIEW_REQUESTED=0
for step in ${MODE_SKIP//,/ } ${CALLER_SKIP//,/ }; do
  if [ "$step" = review ]; then
    REVIEW_REQUESTED=1
    continue
  fi
  case ",$SKIP," in
    *",$step,"*) continue ;;
  esac
  SKIP="${SKIP:+$SKIP,}$step"
done

if [ "$REVIEW_REQUESTED" -eq 1 ]; then
  echo "fm-validate: dropped 'review' from the requested --skip; no mode may skip the review step." >&2
  echo "Review is the only step a light path runs, so skipping it would start a run with nothing left to execute that still reports a passing outcome. Re-run the review instead, or escalate to firstmate if it keeps failing." >&2
fi

start_pipeline() {
  local outer_state start_epoch implementation_epoch output_file run_id gate_worktree rc
  local tracking=0
  local -a run_args=()
  if [ -n "$SKIP" ]; then
    echo "fm-validate: task $ID is mode=$MODE; skipping pipeline steps: $SKIP" >&2
    run_args+=(--skip "$SKIP")
  else
    echo "fm-validate: task $ID is mode=$MODE; running the full pipeline" >&2
  fi
  run_args+=("${ARGS[@]}")

  # Older unit fixtures are deliberately not git repositories. Real task
  # worktrees always are; only they receive durable convergence state.
  if [ -x "$CONVERGENCE" ] && git -C "$THERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tracking=1
    outer_state="$STATE/$ID.review-convergence"
    start_epoch=$(date +%s)
    implementation_epoch=$(meta_mtime_epoch "$META")
    "$CONVERGENCE" start "$outer_state" "$ID" "$THERE" "$implementation_epoch" "$start_epoch" >/dev/null
    output_file="$outer_state/axi-start.toon"
    set +e
    no-mistakes axi run "${run_args[@]}" | tee "$output_file"
    rc=${PIPESTATUS[0]}
    set -e
    [ "$rc" -eq 0 ] || return "$rc"
    if [ "$(toon_gate_step "$output_file")" = review ]; then
      run_id=$(toon_run_id "$output_file")
      [ -n "$run_id" ] || {
        echo "error: initial review gate did not expose its run id" >&2
        return 1
      }
      gate_worktree=$(find_gate_worktree "$run_id") || {
        echo "error: cannot resolve the unique no-mistakes gate worktree for run $run_id" >&2
        return 1
      }
      "$CONVERGENCE" attach "$outer_state" "$run_id" "$gate_worktree" "$output_file" >/dev/null
    fi
    return 0
  fi

  [ "$tracking" -eq 0 ] || return 1
  exec no-mistakes axi run "${run_args[@]}"
}

start_pipeline
