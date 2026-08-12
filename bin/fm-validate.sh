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
# the task's own meta records. Drive the resulting gates with
# `no-mistakes axi respond` as usual; this script only starts the run.
# The selected review intent comes from the validated delivery contract in the
# task brief. A legacy caller-supplied --intent is accepted but ignored so a
# paraphrase cannot weaken or replace the canonical outcome. At least one
# --evidence path must name a non-empty executed result or capture inside the
# task worktree; the wrapper publishes copies on no-mistakes' temporary evidence
# surface so every isolated review round can inspect and refresh them.
# Usage: fm-validate.sh <task-id> --evidence <path> [--evidence <path>...] [extra axi run args...]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

usage() {
  echo 'usage: fm-validate.sh <task-id> --evidence <path> [--evidence <path>...] [extra axi run args...]' >&2
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
- When a pipeline rebase resolution or review fix changes the relevant final diff, that phase must save the output or capture from its already-required focused verification in $PIPELINE_EVIDENCE_DIR/pipeline-final-change.txt, replacing the prior pipeline-final-change capture before the next review. Do not run a second execution solely to create evidence.
- After such a change, the next reviewer must inspect that pipeline-owned final-change capture and must not accept the initial worker capture, a plan, or a fix summary as evidence for the changed area."

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

if [ -n "$SKIP" ]; then
  echo "fm-validate: task $ID is mode=$MODE; skipping pipeline steps: $SKIP" >&2
  exec no-mistakes axi run --skip "$SKIP" "${ARGS[@]}"
fi
echo "fm-validate: task $ID is mode=$MODE; running the full pipeline" >&2
exec no-mistakes axi run "${ARGS[@]}"
