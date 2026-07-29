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
# This script NEVER skips review, test, document, or lint, for any mode. Dropping
# the pull request is not dropping the automated review: the review step is what
# makes landing on a default branch safe when nobody reads the diff. A caller's own
# --skip is merged with the mode's, never allowed to replace it.
#
# Run it from inside the task worktree - it hands off to no-mistakes in the current
# directory and does not change it. Drive the resulting gates with
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

# Steps this delivery mode must always omit. Only host-facing steps ever appear
# here; the local review surface is never skipped by mode.
case "$MODE" in
  validated-main) MODE_SKIP="pr,ci" ;;
  *)              MODE_SKIP="" ;;
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

# Merge and de-duplicate, preserving the mode's steps first.
SKIP=""
for step in ${MODE_SKIP//,/ } ${CALLER_SKIP//,/ }; do
  case ",$SKIP," in
    *",$step,"*) continue ;;
  esac
  SKIP="${SKIP:+$SKIP,}$step"
done

if [ -n "$SKIP" ]; then
  echo "fm-validate: task $ID is mode=$MODE; skipping pipeline steps: $SKIP" >&2
  exec no-mistakes axi run --skip "$SKIP" "${ARGS[@]}"
fi
echo "fm-validate: task $ID is mode=$MODE; running the full pipeline" >&2
exec no-mistakes axi run "${ARGS[@]}"
