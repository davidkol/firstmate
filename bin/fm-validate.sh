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
# Usage: fm-validate.sh <task-id> --intent "<what the user set out to accomplish>" [extra axi run args...]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

usage() {
  echo 'usage: fm-validate.sh <task-id> --intent "<what the user set out to accomplish>" [extra axi run args...]' >&2
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ID=${1:-}
[ -n "$ID" ] || { usage; exit 1; }
shift

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
if [ -n "$WORKTREE" ]; then
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
ARGS=()
HAS_INTENT=0
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
    --intent|--intent=*)
      HAS_INTENT=1
      ARGS+=("$1")
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# axi run requires --intent to start a run; refuse here with the reason rather
# than letting the daemon reject a half-started run.
[ "$HAS_INTENT" -eq 1 ] || {
  echo "error: --intent is required to start a validation run (what the user set out to accomplish, not a description of the diff)" >&2
  usage
  exit 1
}

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
