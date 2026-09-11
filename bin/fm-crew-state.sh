#!/usr/bin/env bash
# fm-crew-state.sh - deterministic read of a crew's CURRENT state.
#
# Why this exists: state/<id>.status is an append-only, best-effort EVENT LOG.
# Crews append selected transitions, including routine working and paused notes,
# and may append nothing when they resume, so `tail -1` of that log reports the
# last EVENT, not the current STATE. After firstmate resolves a needs-decision
# or blocked and the crew resumes (responds to the gate, the pipeline fixes, it
# re-validates), the log's last line stays stale. This helper never infers the
# current state from a tail of the log: it reads the authoritative source (a
# no-mistakes run-step attributed to this crew's branch and current code
# identity, else the semantic busy-state contract in bin/fm-busy-lib.sh) and
# reconciles the possibly-stale log against it.
#
# The determinism lives entirely here - only run-step / pane / log reads plus
# fixed mapping logic, no heuristics and no LLM. Output is one stable, parseable,
# token-tight line firstmate can read every heartbeat:
#
#   state: <working|parked|done|blocked|paused|failed|unknown> · source: <run-step|pane|status-log|none> · <detail>
#
# Logic, in order:
#   1. Resolve worktree + backend target + kind from state/<id>.meta.
#   2. Matching no-mistakes run for this crew's branch AND current code identity,
#      active or terminal (from `axi status`, or the coarse `no-mistakes runs`
#      fallback)? Branch name alone is not enough: a historical run on a reused
#      branch whose head was rewritten or diverged must not be attributed.
#      A run matches when its head equals the worktree HEAD, or the worktree HEAD
#      is an ancestor of the run head (pipeline fix commits advanced the run on
#      the same line of history). Local work that advanced past the run head, or
#      diverged from it, invalidates attribution.
#      The run-step is AUTHORITATIVE: running/fixing -> working, ci -> working,
#      awaiting_approval/fix_review -> parked (with gate findings), terminal
#      passed/checks-passed -> done, failed/cancelled -> failed. EXCEPT: on the
#      light delivery modes (direct-PR, local-only) the run carries the review
#      step alone, so a terminal run means the REVIEW finished, not the task - the
#      worker still has to open its PR or declare its branch ready. There the
#      crew's own status-log verb decides instead, through map_log_state, so a
#      light-path done/blocked/needs-decision/paused keeps its own meaning and
#      only an absent or unrecognized event falls back to working; the detail
#      never claims a PR (local-only never has one), and the source is stamped
#      status-log or none rather than run-step, because a terminal run is not
#      evidence the crew is still working. EXCEPT: while
#      the active step is ci, `axi status` alone cannot tell "still waiting on
#      checks" from "checks green, waiting on merge" (see nm_ci_checks_state) -
#      a ci-step log-tail check overrides working -> done once checks read
#      green, so a green PR is never silently read as still-validating.
#   3. Reconcile the status log: if its last line says needs-decision/blocked but
#      the run-step shows the run moved on, the log is deterministically stale and
#      is flagged superseded. A genuinely parked run plus a needs-decision log
#      agree, and are reported as parked.
#   4. No run for this crew (pre-validation, or kind=scout): fall back to the
#      crew's semantic busy state (fm_busy_classify). Only an exact busy verdict
#      reports working · pane. An exact idle verdict falls through to the status
#      log's last line, read only when its verb maps to a recognized run-state,
#      and so does an unverified-harness verdict, whose harness has no semantic
#      writer wired at all. Every other verdict - missing, malformed, stale, or
#      untrusted state for a harness that IS wired - reports unknown · pane and
#      never reaches the log. Decision-only events such as `resolved` never
#      become current state or detail.
#   5. Missing meta or torn-down worktree: report unknown · none. If no run is
#      attributed to this crew, a dead endpoint also reports unknown · none rather
#      than trusting a stale status log.
#
# `--progress-token <id>` prints a stable token for an attributable active
# run-step and its bounded active-step log tail, or nothing when no such owned
# progress source is active.
# `--with-run-identity <id>` prints the ordinary current-state line and then, when
# the run-step path attributed a run to this crew, one extra `run-identity: <run-id>`
# line naming that exact run. It answers "WHICH owned run is this state about", which
# a supervisor needs to tell one failed run from its rerun without having observed
# the working interval between them. The value is the producer's own run ID and
# nothing else: a ULID is already globally unique, so consumption stays stable when
# a head is projected short in one answer and full in another, or when the same run
# is read through a different surface.
# The full path takes the ID from the `axi status` output this reader already holds,
# with no extra producer call. The coarse fallback's `no-mistakes runs` rows carry
# no ID. For failed/cancelled runs that path resolves one through nm_exact_run_id
# (below), the producer's existing read-only lookup. Other coarse states omit the
# identity because no consumer needs it. An unavailable identity is also omitted;
# a consumer must treat that as "not known", never as a different run.
# Read-only and side-effect free. Always exits 0 on a successful read regardless
# of state; exit 2 only on a usage error.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-tmux-lib.sh
. "$SCRIPT_DIR/fm-tmux-lib.sh"
# shellcheck source=bin/fm-backend.sh
. "$SCRIPT_DIR/fm-backend.sh"
# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$SCRIPT_DIR/fm-busy-lib.sh"
# shellcheck source=bin/fm-nm-run-lib.sh
. "$SCRIPT_DIR/fm-nm-run-lib.sh"

PROGRESS_TOKEN_MODE=0
RUN_IDENTITY_MODE=0
case "${1:-}" in
  --progress-token)    PROGRESS_TOKEN_MODE=1; shift ;;
  --with-run-identity) RUN_IDENTITY_MODE=1; shift ;;
esac
ID=${1:-}
[ -n "$ID" ] && [ "$#" -eq 1 ] \
  || { echo "usage: fm-crew-state.sh [--progress-token|--with-run-identity] <id>" >&2; exit 2; }

META="$STATE/$ID.meta"
LOG="$STATE/$ID.status"
NM_TIMEOUT=${FM_CREW_STATE_NM_TIMEOUT:-10}
case "$NM_TIMEOUT" in ''|*[!0-9]*) NM_TIMEOUT=10 ;; esac
# How many of the most recent `no-mistakes runs` rows the cross-branch fallback
# (nm_runs_status_for_branch, below) scans. Generous enough to still find a
# branch's own run on a busy multi-crew fleet without listing the entire
# history every call.
FM_CREW_STATE_RUNS_LIMIT=${FM_CREW_STATE_RUNS_LIMIT:-200}
case "$FM_CREW_STATE_RUNS_LIMIT" in ''|*[!0-9]*) FM_CREW_STATE_RUNS_LIMIT=200 ;; esac
SEP=' · '

# Emit the one canonical line and exit 0. Detail is optional.
emit() {  # <state> <source> [detail]
  local line="state: $1${SEP}source: $2"
  if [ "$PROGRESS_TOKEN_MODE" -eq 1 ]; then
    if [ "$1" = working ] && [ "$2" = run-step ] && [ "${RUN_SOURCE:-}" = full ]; then
      emit_run_progress_token
    fi
    exit 0
  fi
  [ -n "${3:-}" ] && line="$line${SEP}$3"
  printf '%s\n' "$line"
  if [ "$RUN_IDENTITY_MODE" -eq 1 ] && [ "$2" = run-step ]; then
    emit_run_identity
  fi
  exit 0
}

# --- meta resolution --------------------------------------------------------

[ -f "$META" ] || emit unknown none "no metadata for $ID"

meta_value() {  # <key>
  grep "^$1=" "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

WT=$(meta_value worktree)
KIND=$(meta_value kind)
HARNESS=$(meta_value harness)
MODE=$(meta_value mode)
[ -n "$KIND" ] || KIND=ship
# An unrecorded mode is the full pipeline, matching bin/fm-validate.sh's fallback.
[ -n "$MODE" ] || MODE=no-mistakes

# A torn-down (or never-created) worktree has no current state to read.
if [ -z "$WT" ] || [ ! -d "$WT" ]; then
  emit unknown none "worktree gone (torn down?)"
fi

# --- status log ------------------------------------------------------------

# Last non-empty status line, and its leading verb (the word before the colon).
log_last_line() {
  [ -f "$LOG" ] || return 1
  grep -v '^[[:space:]]*$' "$LOG" 2>/dev/null | tail -1
}
# Map a status-log verb onto a canonical state for the fallback path. `paused` is
# the deliberate-external-wait verb (fm-classify-lib.sh's FM_CLASSIFY_PAUSED_VERB):
# a crew with no active run and an idle pane that declared a known external wait
# reports `paused` distinctly, so a supervisor reading this sees a declared pause
# and its reason rather than a wedge-suspect idle.
map_log_state() {  # <line>
  if status_is_paused "$1"; then
    echo paused
    return
  fi
  case "$(status_line_verb "$1")" in
    working)        echo working ;;
    needs-decision) echo parked ;;
    blocked)        echo blocked ;;
    done)           echo "done" ;;
    failed)         echo failed ;;
    *)              echo unknown ;;
  esac
}

LOG_LINE=$(log_last_line || true)
LOG_VERB=$(status_line_verb "$LOG_LINE")

# pane_readable is consulted ONLY in the no-run fallback below. The run-step path
# stays authoritative regardless of pane liveness - judge by the run-step, not the
# shell - so a finished crew whose endpoint has closed still reports its run-step
# state (e.g. done) instead of being masked as unknown. Backend-aware
# (fm_backend_of_meta defaults absent backend= to tmux, the P1 contract): a
# herdr task is read through fm_backend_capture instead of a bare tmux probe.
TASK_BACKEND=$(fm_backend_of_meta "$META")
BACKEND_TARGET=$(fm_backend_target_of_meta "$META")
EXPECTED_LABEL="fm-$ID"
pane_readable() {  # <target>
  case "$TASK_BACKEND" in
    tmux) tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1 ;;
    *) fm_backend_capture "$TASK_BACKEND" "$1" 1 "$EXPECTED_LABEL" >/dev/null 2>&1 ;;
  esac
}
# crew_busy_verdict: the crew's semantic busy state from the one contract
# owner (bin/fm-busy-lib.sh), as "<busy|idle|unknown> <source>". A converted
# adapter answers from its own lifecycle record; Grok answers from its
# isolated rendered-tail fallback; a herdr crew's native `busy` is accepted
# when no record exists, but its native `idle` is NOT, because agent.get
# reports generation state (idle while a crew blocks on its own long-running
# foreground tool call) rather than turn state.
crew_busy_verdict() {  # <target>
  local tail40=''
  case "$HARNESS" in
    grok*) tail40=$(fm_backend_capture "$TASK_BACKEND" "$1" 40 "$EXPECTED_LABEL" 2>/dev/null) || tail40='' ;;
  esac
  fm_busy_classify "$TASK_BACKEND" "$1" "$HARNESS" "$ID" "$STATE" "$tail40"
}

# --- no-mistakes run lookup (authoritative when a run matches this branch) --

trim() {
  local s=${1:-}
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
strip_quotes() {
  local s
  s=$(trim "${1:-}")
  case "$s" in
    \"*\") s=${s#\"}; s=${s%\"} ;;
  esac
  trim "$s"
}

# Bounded no-mistakes call in the worktree; stdout only, never fails the script.
HAVE_TIMEOUT=none
if command -v timeout >/dev/null 2>&1; then HAVE_TIMEOUT=timeout
elif command -v gtimeout >/dev/null 2>&1; then HAVE_TIMEOUT=gtimeout
elif command -v perl >/dev/null 2>&1; then HAVE_TIMEOUT=perl
fi
nm_run() {  # <args...>
  case "$HAVE_TIMEOUT" in
    timeout)  ( cd "$WT" && timeout "$NM_TIMEOUT" no-mistakes "$@" ) 2>/dev/null || true ;;
    gtimeout) ( cd "$WT" && gtimeout "$NM_TIMEOUT" no-mistakes "$@" ) 2>/dev/null || true ;;
    perl)     ( cd "$WT" && perl -e 'my $t = shift; my $pid = fork; die "fork failed" unless defined $pid; if (!$pid) { setpgrp(0, 0); exec @ARGV } local $SIG{ALRM} = sub { kill "TERM", -$pid; select undef, undef, undef, 0.2; kill "KILL", -$pid; exit 124 }; alarm $t; waitpid $pid, 0; exit($? >> 8)' "$NM_TIMEOUT" no-mistakes "$@" ) 2>/dev/null || true ;;
    *)        true ;;
  esac
}

# Scalar value of a TOON key in the captured run output ($RUN_OUT).
RUN_OUT=""
nm_field() {  # <key>
  printf '%s\n' "$RUN_OUT" | sed -n "s/^[[:space:]]*$1:[[:space:]]*\(.*\)/\1/p" | head -1
}
# Finding count from a findings[N]{...} table header; empty when none.
nm_findings_count() {
  printf '%s\n' "$RUN_OUT" | grep -oE 'findings\[[0-9]+\]' | head -1 | grep -oE '[0-9]+'
}
nm_gate_step_row() {
  local row step rest status findings
  row=$(printf '%s\n' "$RUN_OUT" | grep -E '^[[:space:]]*[^,]+,[[:space:]]*"?(awaiting_approval|fix_review)"?[[:space:]]*,' | head -1)
  [ -n "$row" ] || return 0
  row=$(trim "$row")
  step=$(trim "${row%%,*}")
  rest=${row#*,}
  status=$(strip_quotes "$(trim "${rest%%,*}")")
  rest=${rest#*,}
  findings=$(trim "${rest%%,*}")
  printf '%s|%s|%s' "$step" "$status" "$findings"
}
nm_has_gate() {
  printf '%s\n' "$RUN_OUT" | grep -Eq '^[[:space:]]*gate:[[:space:]]*'
}
nm_gate_line_name() {
  local gate step
  gate=$(strip_quotes "$(nm_field gate)")
  [ -n "$gate" ] && { printf '%s' "$gate"; return; }
  step=$(printf '%s\n' "$RUN_OUT" | sed -n '/^[[:space:]]*gate:[[:space:]]*$/,/^[^[:space:]][^:]*:/s/^[[:space:]]*step:[[:space:]]*\(.*\)/\1/p' | head -1)
  step=$(strip_quotes "$step")
  [ -n "$step" ] && printf '%s' "$step"
}
nm_gate_name() {
  local gate row
  gate=$(nm_gate_line_name)
  [ -n "$gate" ] && { printf '%s' "$gate"; return; }
  row=$(nm_gate_step_row)
  [ -n "$row" ] && printf '%s' "${row%%|*}"
}
nm_gate_findings_count() {
  local f row rest
  f=$(nm_findings_count)
  [ -n "$f" ] && { printf '%s' "$f"; return; }
  row=$(nm_gate_step_row)
  [ -n "$row" ] || return 0
  rest=${row#*|}
  rest=${rest#*|}
  rest=${rest%%|*}
  case "$rest" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$rest"
}
# The light delivery modes run the review step alone (bin/fm-validate.sh), so
# their run finishing is not their task finishing: a direct-PR worker still has to
# push and open its PR, and a local-only worker still has to declare its branch
# ready. Neither run reaches a pr step at all, so its terminal detail must never
# claim a PR - local-only never has one.
mode_is_light_path() {
  case "$MODE" in
    direct-PR|local-only) return 0 ;;
  esac
  return 1
}

log_reports_ci_ready() {
  [ "$LOG_VERB" = "done" ] || return 1
  case "$(status_line_note "$LOG_LINE")" in
    *PR*"checks green"*|*"checks green"*PR*) return 0 ;;
    *) return 1 ;;
  esac
}

nm_ci_step_status() {
  local row rest
  row=$(printf '%s\n' "$RUN_OUT" | grep -E '^[[:space:]]*ci,[[:space:]]*"?(running|fixing)"?[[:space:]]*,' | head -1)
  [ -n "$row" ] || return 0
  row=$(trim "$row")
  rest=${row#*,}
  strip_quotes "$(trim "${rest%%,*}")"
}

nm_effective_ci_step_status() {
  local step_status
  if [ "${RUN_STATUS:-}" = fixing ]; then
    printf 'fixing'
    return 0
  fi
  step_status=$(nm_ci_step_status)
  if [ -n "$step_status" ]; then
    printf '%s' "$step_status"
    return 0
  fi
  if [ "${RUN_STATUS:-}" = ci ]; then
    printf 'running'
  fi
}

# Root cause of the PR #252 incident (2026-07): for a repo where merge is left
# to the captain, no-mistakes' ci step (and therefore top-level status/outcome)
# stays "running" for the ENTIRE CI-monitor phase, including long after GitHub
# reports every check green - it only reaches outcome=passed once the PR is
# actually merged (or failed/cancelled if closed). `axi status`'s steps[] table
# never distinguishes "still waiting on checks" from "checks green, waiting on
# merge": both read as plain `ci,running,...`. The only place that transition is
# recorded is the ci step's own log text, e.g. "all CI checks passed - still
# monitoring until merged or closed" or "no CI checks reported - still
# monitoring until merged or closed" (verified against 360+ real run logs under
# ~/.no-mistakes/logs/*/ci.log on the installed v1.32.2 binary, including the
# actual PR #252 run). Reads the ci step's log tail via `axi logs` and scans it
# for the MOST RECENT recognized marker (the log is append-only/chronological,
# so the last match is current): green with nothing red after it means CI is
# green right now, still only waiting on merge/close.
nm_ci_checks_state() {
  local run_id log_tail marker
  run_id=$(strip_quotes "$(nm_field id)")
  [ -n "$run_id" ] || { printf 'unknown'; return; }
  log_tail=$(nm_run axi logs --step ci --run "$run_id") || true
  [ -n "$log_tail" ] || { printf 'unknown'; return; }
  marker=$(printf '%s\n' "$log_tail" \
    | grep -E 'CI checks passed|no CI checks reported - still monitoring|no CI checks reported yet|checks failed|issues detected|CI checks running|base branch advanced.*re-arming CI monitor timeout' \
    | tail -1)
  case "$marker" in
    *"checks passed"*|*"no CI checks reported - still monitoring"*) printf 'green' ;;
    *"no CI checks reported yet"*|*"checks failed"*|*"issues detected"*|*"CI checks running"*|*"base branch advanced"*"re-arming CI monitor timeout"*) printf 'not-ready' ;;
    *) printf 'unknown' ;;
  esac
}
# Coarse fallback for cross-branch attribution. `no-mistakes axi status` (bare)
# reports the active-or-most-recent run for the CURRENT branch when one
# exists, else falls back to some other branch's run purely as informational
# display (verified empirically: querying a worktree with its own active run
# reliably returns that run, even under concurrent load from several other
# validating crews on the same underlying repo). A crew whose branch genuinely
# has no run yet therefore sees another branch's answer here.
#
# This fallback used to shell out to `no-mistakes axi` (bare, no subcommand)
# expecting a `runs[N]{id,branch,status,...}:` TOON table and re-query the
# matched id via `axi status --run <id>`. Verified against the real installed
# CLI (v1.32.2): the `axi` surface exposes only abort/logs/respond/run/status -
# there is no runs-listing subcommand under `axi` at all, so that table never
# appears and the lookup was silently dead code; whenever the bare `axi
# status` answer was not this crew's own branch, attribution always failed and
# the caller fell straight through to the pane/log fallback below. (The
# PRIMARY cause of the 2026-07 herdr false-surface incidents turned out to be
# a separate bug in bin/fm-watch.sh's stale_is_terminal precedence - see that
# file's history - but this cross-branch path was independently confirmed
# dead code and is worth having actually work.)
#
# The real run-listing command is the top-level `no-mistakes runs` (verified:
# `no-mistakes --help` lists it separately from `axi`). It is plain, human-
# oriented text - no run id, no JSON/TOON, newest-first, columns
# "<status> <branch> <short-sha> <date> [<pr-url>]" separated by runs of
# spaces (verified: no quoting, so splitting on the first two whitespace runs
# is exact) - but branch + coarse status is exactly what this predicate needs:
# is a run for THIS branch active right now. Echoes the first (most recent)
# matching row's status word (running/completed/cancelled/failed), or empty
# when the branch has no run within FM_CREW_STATE_RUNS_LIMIT rows.
# Prints "<status>\t<short-sha>" for the matched row: the sha is what lets the exact
# identity lookup below resolve this row's full head, and it is already validated
# against the worktree by the same code-identity rule the full path uses.
nm_runs_status_for_branch() {  # <branch>
  local branch=$1 out row st rest br sha
  out=$(nm_run runs --limit "$FM_CREW_STATE_RUNS_LIMIT")
  [ -n "$out" ] || return 0
  while IFS= read -r row; do
    row=$(trim "$row")
    [ -n "$row" ] || continue
    st=${row%% *}
    rest=${row#* }
    rest=$(trim "$rest")
    br=${rest%% *}
    rest=${rest#* }
    rest=$(trim "$rest")
    sha=${rest%% *}
    if [ "$br" = "$branch" ]; then
      # Same code-identity rule as axi status: skip a same-branch row whose
      # short-sha does not match this worktree (rewritten or advanced tip).
      if ! nm_coarse_head_matches_worktree "$sha"; then
        continue
      fi
      printf '%s\t%s' "$st" "$sha"
      return 0
    fi
  done <<< "$out"
  return 0
}

# CREW_BRANCH is empty at detached HEAD (a just-spawned crew, or a scout's
# scratch worktree); with no branch there is no run to attribute to this crew.
CREW_BRANCH=$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)

# 0 if the active axi-status run's head field matches this worktree's code
# identity. Branch match is a precondition (caller). The matching rule itself
# is owned by bin/fm-nm-run-lib.sh's fm_nm_head_matches_worktree, shared with
# bin/fm-teardown.sh's pre-teardown run abort so both bind a run to a worktree
# by exactly the same contract; this wrapper only supplies the head field from
# the captured $RUN_OUT.
nm_run_head_matches_worktree() {
  local run_head
  run_head=$(strip_quotes "$(nm_field head)")
  fm_nm_head_matches_worktree "$WT" "$run_head"
}

# Minimum abbreviation git itself will produce, and the floor this reader accepts
# when the producer projects one commit two ways in a single answer.
NM_MIN_ABBREV=7

# 0 when two head fields FROM THE SAME producer answer name the same commit.
# `axi status` renders the top-level head abbreviated (internal/cli/axi_render.go
# shortSHA) while branch_sync.pipeline.current_head is full, so a literal string
# comparison of the two can never hold. Neither side is resolvable with git here:
# an unpublished pipeline commit lives in the gate's object store, not the worker's,
# and this reader must never fetch it. Agreement is therefore decided on the
# producer's own representations: both must be hex object names, the shorter must
# reach NM_MIN_ABBREV, and the shorter must be a prefix of the longer. A differing
# prefix, a non-hex value, an empty side, or an abbreviation below the floor is a
# mismatch - this normalises representation only, and relaxes no binding.
nm_same_producer_head() {  # <head-a> <head-b>
  local a=$1 b=$2 short long
  case "$a" in ''|*[!0-9a-f]*) return 1 ;; esac
  case "$b" in ''|*[!0-9a-f]*) return 1 ;; esac
  if [ "${#a}" -le "${#b}" ]; then short=$a; long=$b; else short=$b; long=$a; fi
  [ "${#short}" -ge "$NM_MIN_ABBREV" ] || return 1
  [ "${long#"$short"}" != "$long" ]
}

# Current no-mistakes explicitly reports a daemon-owned branch split during a
# live fix round. Accept that divergence only when every ownership field binds
# the active run to this exact branch and worktree tip.
# Terminal statuses are accepted alongside active ones because the producer keeps
# reporting pipeline_owned custody (safety blocked_pipeline_owned_recoverable) for a
# failed or cancelled run whose commits are still unpublished. Dropping those was
# how a genuinely failed owned run reached the status-log fallback and was reported
# as ordinary progress instead of a failure.
nm_pipeline_owned_matches_worktree() {
  local block local_block pipeline_block state run_status run_id pipeline_run
  local local_branch local_head submitted_head current_head run_head worktree_head
  block=$(printf '%s\n' "$RUN_OUT" | sed -n '/^branch_sync:/,$p')
  [ -n "$block" ] || return 1
  state=$(strip_quotes "$(printf '%s\n' "$block" | sed -n 's/^  state:[[:space:]]*//p' | head -1)")
  [ "$state" = pipeline_owned ] || return 1
  run_status=$(strip_quotes "$(nm_field status)")
  case "$run_status" in running|fixing|ci|failed|cancelled) ;; *) return 1 ;; esac
  run_id=$(strip_quotes "$(nm_field id)")
  run_head=$(strip_quotes "$(nm_field head)")
  [ -n "$run_id" ] && [ -n "$run_head" ] || return 1

  local_block=$(printf '%s\n' "$block" | sed -n '/^  local:/,/^  pipeline:/p')
  pipeline_block=$(printf '%s\n' "$block" | sed -n '/^  pipeline:/,$p')
  local_branch=$(strip_quotes "$(printf '%s\n' "$local_block" | sed -n 's/^    branch:[[:space:]]*//p' | head -1)")
  local_head=$(strip_quotes "$(printf '%s\n' "$local_block" | sed -n 's/^    head:[[:space:]]*//p' | head -1)")
  pipeline_run=$(strip_quotes "$(printf '%s\n' "$pipeline_block" | sed -n 's/^    run:[[:space:]]*//p' | head -1)")
  submitted_head=$(strip_quotes "$(printf '%s\n' "$pipeline_block" | sed -n 's/^    submitted_head:[[:space:]]*//p' | head -1)")
  current_head=$(strip_quotes "$(printf '%s\n' "$pipeline_block" | sed -n 's/^    current_head:[[:space:]]*//p' | head -1)")
  worktree_head=$(git -C "$WT" rev-parse HEAD 2>/dev/null || true)
  [ -n "$worktree_head" ] \
    && [ "$local_branch" = "$CREW_BRANCH" ] \
    && [ "$local_head" = "$worktree_head" ] \
    && [ "$submitted_head" = "$worktree_head" ] \
    && [ "$pipeline_run" = "$run_id" ] \
    && nm_same_producer_head "$current_head" "$run_head"
}

nm_active_step() {
  local row step
  row=$(printf '%s\n' "$RUN_OUT" \
    | grep -E '^[[:space:]]*[^,]+,[[:space:]]*"?(running|fixing|awaiting_approval|fix_review)"?[[:space:]]*,' \
    | head -1)
  [ -n "$row" ] || return 0
  row=$(trim "$row")
  step=$(trim "${row%%,*}")
  strip_quotes "$step"
}

# The local no-mistakes daemon endpoint, resolved by the producer's OWN documented
# rule (NM_HOME, else ~/.no-mistakes; internal/paths/paths.go). FM_NM_IPC_SOCKET is
# the test seam, and FM_NM_IPC_TIMEOUT bounds the whole exchange.
FM_NM_IPC_SOCKET="${FM_NM_IPC_SOCKET:-${NM_HOME:-$HOME/.no-mistakes}/socket}"
FM_NM_IPC_TIMEOUT=${FM_NM_IPC_TIMEOUT:-5}
case "$FM_NM_IPC_TIMEOUT" in ''|*[!0-9]*) FM_NM_IPC_TIMEOUT=5 ;; esac

# Resolve the exact producer run ID for a run this reader attributed through the
# coarse listing, which prints no ID of its own.
#
# This is a BOUNDED, FIXED-PURPOSE read of the producer's existing API, not a new
# capability and not a database reader: exactly two read-only JSON-RPC methods that
# the installed daemon already serves and its own CLI already uses - `get_run` to
# learn the repository identity from a run the answer we hold already names, and
# `get_runs_for_head` to ask for this crew's exact branch and full head. Repository
# identity therefore comes from the producer, never from a guessed path or hash.
#
# Every returned record is re-validated against the exact repo, branch and full head
# that were asked for, and against the status this reader attributed, so a wrong,
# reordered, partial or unrelated answer yields nothing rather than a wrong ID. One
# connection, one socket deadline, a 1 MiB frame bound, and no retry. A missing
# socket, missing python3, refused connection, timeout, malformed frame or absent
# method all print nothing, which callers must read as "not known".
nm_exact_run_id() {  # <known-run-id> <branch> <full-head> <status>
  [ -S "$FM_NM_IPC_SOCKET" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$FM_NM_IPC_SOCKET" "$FM_NM_IPC_TIMEOUT" "$1" "$2" "$3" "$4" <<'NM_IPC_PY' 2>/dev/null || true
import json, socket, sys, time

sock_path, timeout, known_run, branch, head, status = sys.argv[1:7]
FRAME_MAX = 1024 * 1024


def remaining_timeout(conn, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("identity lookup deadline expired")
    conn.settimeout(remaining)


def call(conn, pending, deadline, method, params, rid):
    remaining_timeout(conn, deadline)
    conn.sendall((json.dumps({"jsonrpc": "2.0", "method": method,
                             "params": params, "id": rid}) + "\n").encode())
    while True:
        newline = pending.find(b"\n")
        if newline >= 0:
            line = bytes(pending[:newline + 1])
            del pending[:newline + 1]
            break
        if len(pending) >= FRAME_MAX:
            return None
        remaining_timeout(conn, deadline)
        chunk = conn.recv(min(65536, FRAME_MAX - len(pending)))
        if not chunk:
            return None
        pending.extend(chunk)
    if not line or len(line) >= FRAME_MAX:
        return None
    try:
        msg = json.loads(line.decode("utf-8", "replace"))
    except ValueError:
        return None
    if not isinstance(msg, dict) or msg.get("id") != rid or msg.get("error") is not None:
        return None
    result = msg.get("result")
    return result if isinstance(result, dict) else None


try:
    deadline = time.monotonic() + float(timeout)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        pending = bytearray()
        remaining_timeout(conn, deadline)
        conn.connect(sock_path)

        result = call(conn, pending, deadline, "get_run", {"run_id": known_run}, 1)
        run = (result or {}).get("run")
        if not isinstance(run, dict) or run.get("id") != known_run:
            raise SystemExit(0)
        repo = run.get("repo_id")
        if not isinstance(repo, str) or not repo:
            raise SystemExit(0)

        result = call(conn, pending, deadline, "get_runs_for_head",
                      {"repo_id": repo, "branch": branch, "head_sha": head}, 2)
        runs = (result or {}).get("runs")
        if not isinstance(runs, list):
            raise SystemExit(0)
        for record in runs:
            if not isinstance(record, dict):
                continue
            if record.get("repo_id") != repo or record.get("branch") != branch \
                    or record.get("head_sha") != head:
                continue
            if status and record.get("status") != status:
                continue
            run_id = record.get("id")
            if isinstance(run_id, str) and run_id:
                if time.monotonic() < deadline:
                    sys.stdout.write(run_id + "\n")
                break
except SystemExit:
    raise
except Exception:
    pass
NM_IPC_PY
}

# The exact producer identity of the run this reader attributed. The full path reads
# it from the `axi status` answer already in hand; the coarse path asks the producer
# for it. Either way the value is the run ID alone, so it does not change when the
# same run is projected with a short head in one answer and a full head in another.
#
# BOUNDARY, deliberate: the coarse path resolves an ID only for a FAILED or CANCELLED
# run. That is the one identity any consumer needs - the watcher keys its
# failure receipt on it - and every other coarse state would pay a socket round trip
# for a value nothing reads. The cheap full-path ID is still reported for every
# state, so a caller that only wants "which run is this" keeps it there.
emit_run_identity() {
  local run_id known head_full
  if [ "${RUN_SOURCE:-}" = coarse ]; then
    case "$COARSE_STATUS" in failed|cancelled) ;; *) return 0 ;; esac
    [ -n "$COARSE_HEAD_SHORT" ] || return 0
    head_full=$(git -C "$WT" rev-parse --verify "${COARSE_HEAD_SHORT}^{commit}" 2>/dev/null) || return 0
    [ -n "$head_full" ] || return 0
    known=$(strip_quotes "$(nm_field id)")
    [ -n "$known" ] || return 0
    run_id=$(nm_exact_run_id "$known" "$CREW_BRANCH" "$head_full" "$COARSE_STATUS")
  else
    run_id=$(strip_quotes "$(nm_field id)")
  fi
  [ -n "$run_id" ] || return 0
  printf 'run-identity: %s\n' "$run_id"
}

emit_run_progress_token() {
  local run_id run_head run_status active_step log_tail material
  run_id=$(strip_quotes "$(nm_field id)")
  run_head=$(strip_quotes "$(nm_field head)")
  run_status=$(strip_quotes "$(nm_field status)")
  active_step=$(nm_active_step)
  [ -n "$active_step" ] || active_step=$run_status
  [ -n "$run_id" ] && [ -n "$active_step" ] || return 0
  log_tail=$(nm_run axi logs --step "$active_step" --run "$run_id" | tail -80)
  material=$(printf 'run=%s\nhead=%s\nstatus=%s\nstep=%s\n%s' \
    "$run_id" "$run_head" "$run_status" "$active_step" "$log_tail")
  printf '%s' "$material" | LC_ALL=C cksum | awk '{ printf "%s:%s\n", $1, $2 }'
}

# Coarse runs-list rows are "<status> <branch> <short-sha> ...". 0 if the short
# sha for this branch row matches the worktree head under the same shared rule,
# taking the sha as an argument rather than reading it from $RUN_OUT.
nm_coarse_head_matches_worktree() {  # <short-sha>
  fm_nm_head_matches_worktree "$WT" "$1"
}

HAVE_RUN=0
# RUN_SOURCE distinguishes the two ways HAVE_RUN=1 can happen: "full" means
# $RUN_OUT is real `axi status` TOON with step/gate detail; "coarse" means only
# a bare status word came back from the runs-list fallback above, so the
# run-step block below skips the TOON field parsing entirely for this crew.
RUN_SOURCE=full
COARSE_STATUS=""
COARSE_HEAD_SHORT=""
# Scouts and secondmates never drive a no-mistakes validation of their own
# worktree, so skip the lookup for them and read state from pane/log directly.
if [ "$KIND" = ship ] && [ -n "$CREW_BRANCH" ] && command -v no-mistakes >/dev/null 2>&1; then
  RUN_OUT=$(nm_run axi status)
  if [ -n "$RUN_OUT" ]; then
    run_branch=$(strip_quotes "$(nm_field branch)")
    if [ -n "$run_branch" ] && [ "$run_branch" = "$CREW_BRANCH" ] \
      && { nm_run_head_matches_worktree || nm_pipeline_owned_matches_worktree; }; then
      HAVE_RUN=1
    else
      # The active-or-most-recent run is for another branch, or same branch with
      # a rewritten/diverged head (the CLI is alive and answered; only the
      # attribution missed) - try the coarse fallback.
      # Deliberately nested inside `[ -n "$RUN_OUT" ]`: an empty/timed-out
      # primary call means the CLI itself did not respond, so retrying it
      # immediately with a second bounded call would just double the wait
      # for no better answer.
      COARSE_ROW=$(nm_runs_status_for_branch "$CREW_BRANCH")
      COARSE_STATUS=${COARSE_ROW%%	*}
      COARSE_HEAD_SHORT=${COARSE_ROW#*	}
      [ "$COARSE_HEAD_SHORT" != "$COARSE_ROW" ] || COARSE_HEAD_SHORT=""
      if [ -n "$COARSE_STATUS" ]; then
        HAVE_RUN=1
        RUN_SOURCE=coarse
      fi
    fi
  fi
fi

# --- run-step authoritative path -------------------------------------------

if [ "$HAVE_RUN" = 1 ]; then
  RUN_STATE=working
  RUN_DETAIL=""
  # Provenance of the line this block emits. The run step is the source for every
  # state it decides itself; the light-path guard below re-stamps it, because there
  # the state comes from the crew's own status event or from no evidence at all.
  RUN_EMIT_SOURCE="run-step"
  CI_STEP_STATUS=""
  CI_LOG_STATE=""
  RUN_STATUS=""
  if [ "$RUN_SOURCE" = coarse ]; then
    # No step/gate detail is available from the plain runs list - only ever
    # true/working, done, or failed. A crew genuinely parked at a gate still
    # gets full detail once `axi status` reports its own branch again (e.g.
    # once its own step is the most-recently-touched one), and its own
    # needs-decision/blocked status-log append (a captain-relevant VERB) is
    # surfaced by the watcher's unconsumed-coordination scan
    # (status_unseen_coordination) regardless of this coarse-vs-full
    # distinction, so a real gate is never silently missed.
    case "$COARSE_STATUS" in
      running)   RUN_STATE=working; RUN_DETAIL="validating (background run)" ;;
      completed) RUN_STATE="done";  RUN_DETAIL="run completed" ;;
      failed)    RUN_STATE=failed;  RUN_DETAIL="run failed" ;;
      cancelled) RUN_STATE=failed;  RUN_DETAIL="run cancelled" ;;
      *)         RUN_STATE=unknown; RUN_DETAIL="runs list status: $COARSE_STATUS" ;;
    esac
  else
    status=$(strip_quotes "$(nm_field status)")
    RUN_STATUS=$status
    outcome=$(strip_quotes "$(nm_field outcome)")
    has_gate=0
    nm_has_gate && has_gate=1

    if [ -n "$outcome" ]; then
      case "$outcome" in
        passed)        RUN_STATE="done"; RUN_DETAIL="run passed: PR merged/closed" ;;
        checks-passed) RUN_STATE="done"; RUN_DETAIL="checks green: PR ready for review" ;;
        failed)        RUN_STATE=failed; RUN_DETAIL="run failed" ;;
        cancelled)     RUN_STATE=failed; RUN_DETAIL="run cancelled" ;;
        *)             RUN_STATE=unknown; RUN_DETAIL="outcome: $outcome" ;;
      esac
    elif fm_nm_status_is_parked "$RUN_OUT"; then
      if [ "$has_gate" = 1 ]; then
        gate=$(nm_gate_line_name)
      else
        gate=$(nm_gate_name)
      fi
      [ -n "$gate" ] || gate=$status
      [ -n "$gate" ] || gate=gate
      RUN_STATE=parked
      RUN_DETAIL="parked at $gate"
      fcount=$(nm_gate_findings_count)
      [ -n "$fcount" ] && RUN_DETAIL="$RUN_DETAIL: $fcount finding(s)"
      if printf '%s\n' "$RUN_OUT" | grep -q 'ask-user'; then
        RUN_DETAIL="$RUN_DETAIL (ask-user: authority decision)"
      fi
    else
      case "$status" in
        ci)             RUN_STATE=working; RUN_DETAIL="ci running" ;;
        running|fixing) RUN_STATE=working; RUN_DETAIL="validating ($status)" ;;
        completed)      RUN_STATE="done"; RUN_DETAIL="run completed" ;;
        failed)         RUN_STATE=failed;  RUN_DETAIL="run failed" ;;
        cancelled)      RUN_STATE=failed;  RUN_DETAIL="run cancelled" ;;
        "")             RUN_STATE=working; RUN_DETAIL="run active" ;;
        *)              RUN_STATE=working; RUN_DETAIL="run active ($status)" ;;
      esac
      if [ "$RUN_STATE" = working ]; then
        CI_STEP_STATUS=$(nm_effective_ci_step_status)
        case "$CI_STEP_STATUS" in
          running)
            CI_LOG_STATE=$(nm_ci_checks_state)
            if [ "$CI_LOG_STATE" = green ]; then
              RUN_STATE="done"
              RUN_DETAIL="checks green: PR ready for review (still monitoring for merge/close)"
            fi
            ;;
          fixing)
            CI_LOG_STATE=not-ready
            ;;
        esac
      fi
    fi
  fi

  # One guard over the final RUN_STATE, covering every terminal -> done transition
  # above: the coarse completed row, outcome passed or checks-passed, and a status
  # of completed with no outcome field. A light delivery mode runs the review step
  # alone (bin/fm-validate.sh), so all three mean the REVIEW finished, not the task:
  # a direct-PR worker still has to open its PR and a local-only worker still has to
  # declare its branch ready, and neither run reaches a pr step at all, so the detail
  # must never claim a PR. What marks the task is the crew's own status event, and
  # map_log_state is this file's single owner of that verb -> state mapping, so a
  # light-path crew that appended blocked, needs-decision, failed or a paused verb
  # keeps that meaning; working is the default only for an absent or unrecognized
  # event. Placed before the ci-ready check below, which is a no-op here: it needs
  # RUN_STATE=working with a done log verb, and a done verb maps to done.
  #
  # The source is re-stamped with the state, because `run-step` is not a label here:
  # crew_absorb_class (bin/fm-classify-lib.sh) reads working plus run-step|pane as
  # positive evidence a crew is mid-work and ABSORBS a no-verb or stale wake on it.
  # A terminal run is neither an actively running step nor a busy pane, and it never
  # transitions again, so claiming run-step for the no-event default would suppress
  # every later wake for that crew permanently. status-log is the truth when a crew
  # verb decided the state; none is the truth when nothing did.
  if mode_is_light_path && [ "$RUN_STATE" = "done" ]; then
    RUN_STATE=$(map_log_state "$LOG_LINE")
    if [ "$RUN_STATE" = unknown ]; then
      RUN_STATE=working
      RUN_DETAIL="review passed: worker has not reported ready yet"
      RUN_EMIT_SOURCE="none"
    else
      RUN_DETAIL="review passed: $(status_line_note "$LOG_LINE")"
      RUN_EMIT_SOURCE="status-log"
    fi
  fi

  if [ "$RUN_STATE" = working ] && log_reports_ci_ready; then
    if [ "$RUN_SOURCE" = coarse ]; then
      emit "done" status-log "$(status_line_note "$LOG_LINE")${SEP}run still monitoring PR"
    fi
    [ -n "$CI_STEP_STATUS" ] || CI_STEP_STATUS=$(nm_effective_ci_step_status)
    if [ "$RUN_STATUS" = fixing ]; then
      CI_LOG_STATE=not-ready
    elif [ "$CI_STEP_STATUS" = running ] && [ -z "$CI_LOG_STATE" ]; then
      CI_LOG_STATE=$(nm_ci_checks_state)
    elif [ "$CI_STEP_STATUS" = fixing ]; then
      CI_LOG_STATE=not-ready
    fi
    if [ "$CI_LOG_STATE" != not-ready ]; then
      emit "done" status-log "$(status_line_note "$LOG_LINE")${SEP}run still monitoring PR"
    fi
  fi

  # Reconcile the status log. A needs-decision/blocked log line that the run-step
  # has moved past (anything but a genuinely parked run) is deterministically
  # stale: the gate resolved and the run resumed or finished. A state this reader
  # took FROM that same log line agrees with it and has nothing to supersede, which
  # is how a light path's own blocked event survives the guard above; no run-step
  # mapping yields blocked, so nothing else reaches that arm.
  case "$LOG_VERB" in
    needs-decision|blocked)
      if [ "$RUN_STATE" != parked ] && [ "$RUN_STATE" != "$(map_log_state "$LOG_LINE")" ]; then
        if [ "$RUN_STATE" = working ]; then
          RUN_DETAIL="$RUN_DETAIL${SEP}status-log superseded by active run"
        else
          RUN_DETAIL="$RUN_DETAIL${SEP}status-log superseded (run $RUN_STATE)"
        fi
      fi
      ;;
  esac

  emit "$RUN_STATE" "$RUN_EMIT_SOURCE" "$RUN_DETAIL"
fi

# --- fallback: no run attributed to this crew ------------------------------
# The run-step path above already handled any crew with a run, regardless of pane
# liveness, so a finished-but-pane-closed crew never reaches here. Down here there
# is no run to consult, so a dead/unreadable target means the crew is gone: report
# unknown rather than trusting a possibly-stale status log as the current state.
#
# NAMED GAP, accepted deliberately rather than closed. A light-path crew whose run
# is terminal takes its state from its own status event above, and a terminal run
# never transitions again, so a crew that appended NOTHING and then died or wedged
# between its review passing and its own event reads `working` indefinitely and
# never reaches this fallback's liveness check. Routing that state through
# map_log_state narrowed the window to exactly that case: any append at all -
# done, blocked, needs-decision, failed, paused - resolves it. Consulting the pane
# from the run-step path was declined because it would make a terminal run's
# verdict depend on shell liveness, which is the inference this reader exists to
# remove, and the same blind spot is pre-existing and accepted for an active run.
# What the window does NOT do is suppress supervision: that state is emitted with
# source `none`, so crew_absorb_class sees no positive evidence and a no-verb or
# stale wake for such a crew is surfaced rather than absorbed.
[ -n "$BACKEND_TARGET" ] || emit unknown none "no backend target recorded"
pane_readable "$BACKEND_TARGET" || emit unknown none "backend target gone: $BACKEND_TARGET"

# Secondmates idle on their own watcher (idle pane = healthy), so the busy
# state is not meaningful for them; read their state from the status log only.
# Only an exact busy verdict reports working here. An exact idle verdict permits
# the status-log fallback below, and so does an unverified-harness verdict
# (codex, standalone kimi): those harnesses have no semantic writer wired at all,
# so nothing was ever going to report, and their own status events stay the only
# state they can offer. Missing, malformed, stale, or untrusted state for a
# harness that IS wired remains unknown.
if [ "$KIND" != secondmate ]; then
  BUSY_VERDICT=$(crew_busy_verdict "$BACKEND_TARGET")
  case "$BUSY_VERDICT" in
    'busy '*) emit working pane "harness busy (${BUSY_VERDICT#* })" ;;
    'idle '*) ;;
    'unknown '*-unverified) ;;
    *) emit unknown pane "harness state unavailable ($BUSY_VERDICT)" ;;
  esac
fi

# Fall back to the status log's last line, but ONLY when its verb maps to a real
# run-state. A decision-closing event - resolved: (fm-classify-lib.sh's
# FM_CLASSIFY_RESOLVE_VERB), and any future decision-only sibling - is NOT a state:
# it exists solely to CLOSE a keyed decision in the durable fold, so a trailing
# resolved: must never become the current state or leak its resolution prose as the
# detail. Skipping it lets a just-resolved idle crew (typically a secondmate, which
# has no busy check above) fall through to the idle default instead of rendering
# `unknown` with the resolution note as `doing`. map_log_state is the single owner of
# the verb->state mapping (including the configurable paused verb), so reusing its
# `unknown` verdict as the "not a state" test needs no second verb list here.
if [ -n "$LOG_VERB" ]; then
  LOG_STATE=$(map_log_state "$LOG_LINE")
  if [ "$LOG_STATE" != unknown ]; then
    emit "$LOG_STATE" status-log "$(status_line_note "$LOG_LINE")"
  fi
fi

emit unknown none "no current-state source available"
