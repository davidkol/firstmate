#!/usr/bin/env bash
# tests/fm-wake-drain-open-decisions.test.sh - behavior tests for the OPEN
# DECISIONS section bin/fm-wake-drain.sh prints for selected changed or complete
# durable decision views, including the empty-queue fast path. The section is pure wiring around
# fm-classify-lib.sh's status_open_decisions fold (the ONE authoritative
# open/resolved statement); these tests exercise the real drain script over
# crafted status logs and assert on its printed output, not on the fold's own
# source text.
set -u

# shellcheck source=tests/wake-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/wake-helpers.sh"

DRAIN="$ROOT/bin/fm-wake-drain.sh"

TMP_ROOT=$(fm_test_tmproot fm-wake-drain-open-decisions-tests)

test_buried_decision_still_surfaces() {
  local dir state out
  dir=$(make_case buried)
  state="$dir/state"
  out="$dir/drain.out"
  # The needs-decision line sits under later routine and unrelated-key lines,
  # exactly the burial scenario the fix targets: last-line-only reads would
  # show "resolved [key=other]" and hide the still-open api-shape decision.
  printf 'needs-decision [key=api-shape]: pick REST or RPC\n' > "$state/task1.status"
  printf 'working: continuing other work\n' >> "$state/task1.status"
  printf 'resolved [key=other]: unrelated decision closed\n' >> "$state/task1.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on a buried decision"

  grep -F 'OPEN DECISIONS' "$out" >/dev/null || fail "buried decision produced no OPEN DECISIONS section"
  grep -F 'task1' "$out" | grep -F '[key=api-shape]' | grep -F 'pick REST or RPC' >/dev/null \
    || fail "buried needs-decision was not surfaced with its task, key, and note"
  grep -F "close one by answering it: bin/fm-send.sh <task> --resolve-key <key>" "$out" >/dev/null \
    || fail "open section is missing the answerer-closes hint"
  pass "a needs-decision buried under later routine/other-key lines still reports as open"
}

test_explicit_resolution_closes_it() {
  local dir state out
  dir=$(make_case resolved)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'needs-decision [key=api-shape]: pick REST or RPC\n' > "$state/task2.status"
  printf 'resolved [key=api-shape]: went with REST\n' >> "$state/task2.status"
  printf 'done: shipped\n' >> "$state/task2.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed after an explicit resolution"

  if grep -F 'OPEN DECISIONS' "$out" >/dev/null; then
    fail "an explicitly resolved decision still printed as open: $(cat "$out")"
  fi
  pass "an explicit resolved [key=X] closes the keyed decision"
}

test_later_unrelated_terminal_line_does_not_close_it() {
  local dir state out
  dir=$(make_case unrelated-terminal)
  state="$dir/state"
  out="$dir/drain.out"
  # A later done: with no matching [key=...] token opens/closes only the
  # "default" key; it must never clear the still-open api-shape decision.
  printf 'needs-decision [key=api-shape]: pick REST or RPC\n' > "$state/task3.status"
  printf 'done: unrelated later milestone\n' >> "$state/task3.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed after an unrelated terminal line"

  grep -F 'task3' "$out" | grep -F '[key=api-shape]' | grep -F 'pick REST or RPC' >/dev/null \
    || fail "a later unrelated terminal line incorrectly cleared the open decision"
  pass "a later unrelated terminal line never clears an open decision"
}

test_no_open_decisions_prints_nothing() {
  local dir state out
  dir=$(make_case none-open)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'working: on it\n' > "$state/task4.status"
  printf 'done: shipped clean\n' > "$state/task5.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed with no open decisions"

  if grep -F 'OPEN DECISIONS' "$out" >/dev/null; then
    fail "the empty case printed an OPEN DECISIONS section: $(cat "$out")"
  fi
  [ ! -s "$out" ] || fail "the empty case with no queued wakes was not silent: $(cat "$out")"
  pass "no open decisions across the fleet prints nothing"
}

test_open_decision_surfaces_even_with_an_unrelated_queued_wake() {
  local dir state out
  dir=$(make_case fleet-wide)
  state="$dir/state"
  out="$dir/drain.out"
  # task6 has a buried, still-open decision but generates NO new queue record
  # this turn; task7 is what actually wakes the drain. The fleet-wide scan
  # must still catch task6's decision alongside task7's own raw row.
  printf 'needs-decision [key=migration]: pick the rollout plan\n' > "$state/task6.status"
  printf 'working: continuing\n' >> "$state/task6.status"
  printf 'blocked: waiting on credentials\n' > "$state/task7.status"
  append_wake "$state" signal task7.status "blocked: waiting on credentials" \
    || fail "queueing the unrelated wake failed"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed with a mixed fleet"

  grep "$(printf '\tsignal\ttask7.status\t')" "$out" >/dev/null || fail "task7's own raw row is missing"
  grep -F 'task6' "$out" | grep -F '[key=migration]' >/dev/null \
    || fail "task6's buried decision was not surfaced even though only task7 queued a wake"
  pass "the open-decision section is fleet-wide, not scoped to this drain's own queued records"
}

test_buried_decision_surfaces_on_the_empty_queue_fast_path() {
  local dir state out
  dir=$(make_case empty-queue-fast-path)
  state="$dir/state"
  out="$dir/drain.out"
  # No wake is queued at all (the empty-queue exit), but the decision is still
  # open on disk - session-start relies on exactly this path.
  printf 'needs-decision [key=api-shape]: pick REST or RPC\n' > "$state/task8.status"
  printf 'working: continuing\n' >> "$state/task8.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "empty-queue drain failed"

  grep -F 'task8' "$out" | grep -F '[key=api-shape]' >/dev/null \
    || fail "the empty-queue fast path did not surface a still-open decision"
  pass "a buried open decision surfaces even when the wake queue itself is empty"
}

test_unkeyed_decision_renders_its_literal_default_key() {
  local dir state out
  dir=$(make_case unkeyed-default-key)
  state="$dir/state"
  out="$dir/drain.out"
  # The dominant case: the worker briefs instruct a bare `needs-decision: ...`
  # with no [key=...] token, which opens the implicit "default" key. The
  # listing must print that literal, because it is exactly what an operator
  # has to pass to --resolve-key to close the record.
  printf 'needs-decision: pick A or B\n' > "$state/task9.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on an unkeyed decision"

  grep -F 'task9 [key=default] needs-decision: pick A or B' "$out" >/dev/null \
    || fail "an unkeyed decision did not render its literal default key: $(cat "$out")"
  grep -F -- "--resolve-key <key>" "$out" >/dev/null \
    || fail "the unkeyed decision listing lost the answerer-closes hint"
  pass "an unkeyed decision prints [key=default], the exact literal --resolve-key needs"
}

test_status_symlink_is_not_followed() {
  local dir state out
  dir=$(make_case status-symlink)
  state="$dir/state"
  out="$dir/drain.out"
  mkdir -p "$dir/outside"
  printf 'needs-decision [key=local]: keep this visible\n' > "$state/local.status"
  printf 'needs-decision [key=foreign]: do not expose this\n' > "$dir/outside/foreign.status"
  ln -s ../outside/foreign.status "$state/linked.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed with a symlinked status file"

  grep -F 'local [key=local] needs-decision: keep this visible' "$out" >/dev/null \
    || fail "the valid local decision did not surface alongside a rejected status symlink"
  if grep -F 'do not expose this' "$out" >/dev/null; then
    fail "the fleet scan followed a status symlink outside the state directory"
  fi
  pass "the fleet-wide decision scan does not follow status symlinks"
}

# The per-item cut comes from bin/fm-line-cap-lib.sh, shared with the
# session-start digest's status tails so one truncation marker means the same
# thing wherever an agent meets it. This pins the drain's own end of that
# contract: the lede survives, the marker appears, and the item still fits the
# shared per-line cap.
test_over_long_decision_note_is_capped_with_a_marker() {
  local dir state out line longest
  dir=$(make_case long-note)
  state="$dir/state"
  out="$dir/drain.out"
  {
    printf 'needs-decision [key=api-shape]: pick REST or RPC'
    awk 'BEGIN { while (i++ < 200) printf " and-then-some" }'
    printf '\n'
  } > "$state/task-long.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on an over-long decision note"

  line=$(grep -F 'task-long' "$out")
  case "$line" in
    'task-long [key=api-shape] needs-decision: pick REST or RPC'*' [truncated]') : ;;
    *) fail "an over-long decision note was not capped with its lede intact: $line" ;;
  esac
  longest=${#line}
  [ "$longest" -le 220 ] || fail "a capped decision item ran $longest characters past the shared per-line cap"

  printf 'needs-decision [key=short]: brief enough to keep whole\n' > "$state/task-short.status"
  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on a short decision note"
  grep -F 'task-short [key=short] needs-decision: brief enough to keep whole' "$out" >/dev/null \
    || fail "a decision note already under the cap was altered"
  if grep -F 'brief enough to keep whole [truncated]' "$out" >/dev/null; then
    fail "a decision note already under the cap was marked truncated"
  fi

  pass "an over-long open decision is cut to the shared per-line cap with its truncation marker"
}

# A "[key=...]" token written AFTER the colon keys nothing: the record folds to
# "default" and the slug survives as note text. That fold is deliberate and stays,
# but it used to be silent, and the listing then showed a slug that looks exactly
# like a key next to a key the operator could not see was different - so the
# obvious --resolve-key was the note slug, which the ledger refuses outright,
# mid-supervision, with a worker parked. The record must still be listed in full;
# only the ambiguity gets a warning.
test_misplaced_key_token_is_flagged_not_dropped() {
  local dir state out
  dir=$(make_case misplaced-key)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'needs-decision: [key=review-gate] approve the gate or not\n' > "$state/task-mis.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on a misplaced key token"

  grep -F 'task-mis [key=default] needs-decision: [key=review-gate] approve the gate or not' "$out" >/dev/null \
    || fail "a misplaced key token cost the record its listing or its real key: $(cat "$out")"
  grep -F 'carry a [key=...] inside the note text' "$out" >/dev/null \
    || fail "a misplaced key token was folded silently, with no warning: $(cat "$out")"

  # The warning is precise: a correctly keyed decision must not draw it.
  printf 'needs-decision [key=review-gate]: approve the gate or not\n' > "$state/task-ok.status"
  rm -f "$state/task-mis.status" "$state/.task-mis.open-decisions-cursor"
  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on a correctly keyed decision"
  grep -F 'task-ok [key=review-gate] needs-decision:' "$out" >/dev/null \
    || fail "a correctly keyed decision stopped listing"
  if grep -F 'inside the note text' "$out" >/dev/null; then
    fail "a correctly keyed decision drew the misplaced-token warning: $(cat "$out")"
  fi
  pass "a key token written after the colon is listed with its real key and flagged, never dropped"
}

# The token in the RIGHT position with an unreadable slug. The line used to fold
# to nothing at all, so a parked worker's escalation never reached this listing -
# a silent supervision failure, which is worse than a mis-keyed record. Opening
# verbs now fall back to "default"; closing verbs stay inert, so a typo can never
# silently close a decision nobody answered.
test_unreadable_key_slug_still_opens_but_never_closes() {
  local dir state out
  dir=$(make_case unreadable-key)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'needs-decision [key=bad slug!]: the escalation still has to be seen\n' > "$state/task-bad.status"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on an unreadable key slug"
  grep -F 'task-bad [key=default] needs-decision: the escalation still has to be seen' "$out" >/dev/null \
    || fail "an unreadable key slug silently dropped the whole escalation: $(cat "$out")"

  # A resolving line whose slug is equally unreadable must NOT close it.
  printf 'resolved [key=bad slug!]: typo in the closing key too\n' >> "$state/task-bad.status"
  FM_STATE_OVERRIDE="$state" "$DRAIN" --open-decisions all > "$out" \
    || fail "full decision drain failed after an unreadable resolving key"
  grep -F 'task-bad [key=default] needs-decision:' "$out" >/dev/null \
    || fail "an unreadable resolving key silently closed a decision nobody answered: $(cat "$out")"

  # The readable closing key the record actually carries still closes it.
  printf 'resolved: answered against the fallback key\n' >> "$state/task-bad.status"
  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed after the readable resolution"
  if grep -F 'task-bad' "$out" >/dev/null; then
    fail "the decision stayed open after a resolution against its real key: $(cat "$out")"
  fi
  pass "an unreadable key slug still opens the decision under default and never closes one"
}

test_buried_decision_still_surfaces
test_misplaced_key_token_is_flagged_not_dropped
test_unreadable_key_slug_still_opens_but_never_closes
test_over_long_decision_note_is_capped_with_a_marker
test_explicit_resolution_closes_it
test_later_unrelated_terminal_line_does_not_close_it
test_no_open_decisions_prints_nothing
test_open_decision_surfaces_even_with_an_unrelated_queued_wake
test_buried_decision_surfaces_on_the_empty_queue_fast_path
test_unkeyed_decision_renders_its_literal_default_key
test_status_symlink_is_not_followed
