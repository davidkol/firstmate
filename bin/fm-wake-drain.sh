#!/usr/bin/env bash
# Atomically drain durable watcher wake records, optionally annotate validated
# signal status keys after raw consumption commits, then assert liveness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
# shellcheck source=bin/fm-line-cap-lib.sh
. "$SCRIPT_DIR/fm-line-cap-lib.sh"

DRAIN_TMP=
DRAIN_LOCK_HELD=false
RAW_ROWS=
OPEN_DECISIONS_MODE=changed

usage() {
  cat <<'EOF'
Usage: fm-wake-drain.sh [--open-decisions changed|all]

Drain durable wakes and print decisions whose durable open record changed.
Use --open-decisions all for session recovery, when every open decision must be shown.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --open-decisions)
      [ "$#" -gt 1 ] || { echo "error: --open-decisions requires changed or all" >&2; exit 2; }
      OPEN_DECISIONS_MODE=$2
      shift 2
      ;;
    --open-decisions=*)
      OPEN_DECISIONS_MODE=${1#--open-decisions=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done
case "$OPEN_DECISIONS_MODE" in
  changed|all) ;;
  *) echo "error: --open-decisions requires changed or all" >&2; exit 2 ;;
esac

# Defense in depth for the supervision chain: this script runs at the top of
# every wake-handling and recovery turn, so assert supervision health here too. A
# lapsed supervision chain then surfaces on a plain drain-and-handle turn, not
# only when a guarded supervision script (fm-peek/fm-send/...) happens to run.
# Reuse fm-guard.sh's model-aware alarm and FM_GUARD_GRACE instead of duplicating
# its supervision verdict. Under Claude's between-turns auto-arm model, a normal
# fire leaves a recent beacon well inside grace and stays silent mid-turn. Under
# persistent-watcher models, the guard also requires the live identity-matched
# watcher. Call after the queue is emptied so guard never re-prints its own
# queued-wakes notice for the records this run just drained, and never let a
# guard hiccup change the drain's exit status.
assert_watcher_liveness() {
  "$SCRIPT_DIR/fm-guard.sh" || true
}

# Print the consolidated OPEN DECISIONS section from the fleet-wide durable
# needs-decision/blocked fold rather than from latest-line annotations.
# Routine drains print only newly opened, reopened, or materially changed
# records, while --open-decisions all prints every still-open record for session
# recovery. The cursor-backed wrapper still carries buried decisions until
# explicit resolution and bounds each scan to bytes appended since the prior
# drain. Bounded and silent when the selected mode has nothing to report.
print_open_decisions_section() {
  local open task key verb note line global_bytes=4000
  local output='' used=0 shown=0 omitted=0 bytes misplaced=0

  open=$(scan_open_decisions_incremental "$STATE" "$OPEN_DECISIONS_MODE") || return 0
  [ -n "$open" ] || return 0

  while IFS=$(printf '\t') read -r task key verb note; do
    [ -n "$task" ] || continue
    # The key is ALWAYS rendered, including the implicit "default" key an
    # unkeyed `needs-decision:`/`blocked:` line opens: it is the exact literal
    # the --resolve-key hint below demands, so it has to be readable right here
    # rather than inferred. Suppressing it left the dominant unkeyed case with
    # no way to close the decision from this listing.
    line="$task [key=$key] $verb: $note"
    # Per-line cut is owned by fm-line-cap-lib.sh so this section and the
    # closing line fm-send.sh appends share one marker and one limit; this
    # function still owns the global budget and its "N more omitted" line.
    fm_cap_line_var "$line"
    line=$FM_LINE_CAP_LINE
    bytes=$(( ${#line} + 1 ))
    if [ $((used + bytes)) -gt "$global_bytes" ]; then
      omitted=$((omitted + 1))
      continue
    fi
    output="$output$line
"
    used=$((used + bytes))
    shown=$((shown + 1))
    # A second "[key=...]" in the rendered entry came from the NOTE, which is on
    # the wrong side of the colon and so keyed nothing (contract:
    # bin/fm-classify-lib.sh's key grammar). The record itself is intact and is
    # listed with the key that really closes it; the count below only stops that
    # note slug from reading as that key, which otherwise sends the answerer to
    # a --resolve-key the ledger refuses. Counted on the CAPPED line and only
    # for entries actually shown, so the warning describes what is on screen.
    case "${line#*]}" in *'[key='*) misplaced=$((misplaced + 1)) ;; esac
  done <<EOF
$open
EOF

  [ "$shown" -gt 0 ] || [ "$omitted" -gt 0 ] || return 0
  printf 'OPEN DECISIONS (still open, folded from the durable status logs - not just the latest line):\n'
  printf '%s' "$output"
  if [ "$omitted" -gt 0 ]; then
    printf 'OPEN DECISIONS: %d more omitted (byte cap)\n' "$omitted"
  fi
  # Answerer-closes hint, printed at exactly the moment an answer gets written:
  # the send that answers a listed decision also closes it, so closure never
  # depends on the busy worker writing a matching resolved line (contract:
  # bin/fm-send.sh header).
  printf "OPEN DECISIONS: close one by answering it: bin/fm-send.sh <task> --resolve-key <key> '<answer>' - <key> is the exact literal in that entry's [key=...], 'default' included.\n"
  if [ "$misplaced" -gt 0 ]; then
    printf 'OPEN DECISIONS: %d entry(ies) above carry a [key=...] inside the note text, after the colon, where it keys nothing - close those with the [key=...] printed before the state word, not the slug in the note.\n' "$misplaced"
  fi
}

# shellcheck disable=SC2317,SC2329 # Invoked by trap handlers below.
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$DRAIN_LOCK_HELD" = true ] && [ -n "$DRAIN_TMP" ] && [ -e "$DRAIN_TMP" ]; then
    fm_wake_restore_queue "$DRAIN_TMP" || true
  fi
  if [ "$DRAIN_LOCK_HELD" = true ]; then
    fm_lock_release "$FM_WAKE_QUEUE_LOCK"
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fm_lock_acquire_wait "$FM_WAKE_QUEUE_LOCK"
DRAIN_LOCK_HELD=true

if [ ! -s "$FM_WAKE_QUEUE" ]; then
  : > "$FM_WAKE_QUEUE"
  fm_lock_release "$FM_WAKE_QUEUE_LOCK"
  DRAIN_LOCK_HELD=false
  (print_open_decisions_section) || true
  assert_watcher_liveness
  exit 0
fi

DRAIN_TMP="$STATE/.wake-queue.drain.$(fm_current_pid)"
rm -f "$DRAIN_TMP"
mv "$FM_WAKE_QUEUE" "$DRAIN_TMP" || exit 1
: > "$FM_WAKE_QUEUE" || exit 1

RAW_ROWS=$(fm_wake_print_deduped "$DRAIN_TMP") || exit "$?"
case "${FM_WAKE_DRAIN_TEST_DELAY_BEFORE_COMMIT:-0}" in
  0) ;;
  ''|*[!0-9]*) ;;
  *) sleep "$FM_WAKE_DRAIN_TEST_DELAY_BEFORE_COMMIT" ;;
esac
if [ -n "$RAW_ROWS" ]; then
  # Print-before-delete is the deliberate at-least-once no-loss boundary: a
  # crash in this micro-gap may replay a wake, and annotations stay outside it.
  printf '%s\n' "$RAW_ROWS" || exit "$?"
fi
rm -f "$DRAIN_TMP" || exit "$?"
DRAIN_TMP=
fm_lock_release "$FM_WAKE_QUEUE_LOCK"
DRAIN_LOCK_HELD=false

# Raw output and queue deletion are authoritative. Everything below is
# best-effort and cannot restore, duplicate, hide, or fail the consumed rows.
(fm_wake_print_annotations "$RAW_ROWS") || true
(print_open_decisions_section) || true
assert_watcher_liveness
exit 0
