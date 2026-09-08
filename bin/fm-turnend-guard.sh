#!/usr/bin/env bash
# Turn-end guard for any firstmate PRIMARY session: the main home OR a
# secondmate's own home. A secondmate runs its own primary firstmate session and
# is guarded exactly like the main primary; only child crew/scout worktrees are
# exempt (see the scoping block below and docs/turnend-guard.md).
#
# fm-guard.sh (bin/fm-guard.sh) is pull-based: it only warns when some other
# supervision script happens to run. A primary session that ends a turn without
# resuming its harness supervision protocol, and then never runs another
# fleet-touching command itself, can sit blind for hours.
# This script is push-based: verified harness turn-end hooks invoke it every time
# the primary is about to end a turn.
# Claude blocks directly with exit status 2 and stderr.
# Codex first yields to its own Stop-owned background wake
# (bin/fm-codex-stop-autoarm.sh), which is registered ahead of this guard on the
# same Stop event: a live supervisor bound to THIS conversation whose home has no
# unresolved arm-failure episode, or the fresh record of a wake that supervisor
# successfully published for it before exiting, already owns recovery, so the
# stop is allowed. Only when neither proof materializes within
# FM_CODEX_AUTOARM_SYNC_WAIT_MS does Codex fall back to its native structured
# Stop continuation, which keeps routine recovery typed and compact instead of
# rendering the full operator diagnostic banner.
# OpenCode and pi adapters use the same predicate and force one bounded
# follow-up because their turn-end events are passive. Grok delegates native
# blocking when its running Stop payload advertises that capability, with one
# bounded resume fallback for payloads from pre-native processes.
# See docs/turnend-guard.md for the per-harness mechanics, validation evidence,
# and fail-open tradeoffs.
#
# Ships with TRACKED harness hook files at the repo root, so this file is
# checked out into every worktree of this repo: the primary checkout, every
# secondmate home (treehouse-leased or git-cloned), and any crewmate/scout task
# worktree spawned to work on firstmate itself (the recursive "firstmate
# improving itself" case). A secondmate home runs its OWN primary firstmate
# session, so it must be guarded like the main primary; only child crew/scout
# worktrees are exempt. It must therefore scope itself at runtime to a real
# primary checkout - the main home or a genuinely marked secondmate home - and
# stay a silent, fast no-op inside child task worktrees.
#
# Loop-guard, every mode except --claude (--codex, Grok, and the cross-harness
# default): never block twice in the same turn.
# Codex uses stop_hook_active and Grok uses stopHookActive; typed camel-case
# takes precedence when both spellings are present. A true value means the
# current stop attempt already follows a block, so this guard always allows it.
# Passive harness adapters provide their own one-follow-up guard before calling
# this script.
# That bounds those harnesses to at most one forced continuation per turn -
# never a wedged, un-endable session - while still nagging again on a later turn
# if the problem persists.
#
# Loop-guard, --claude mode (Stop-owned auto-arm cooperation): Claude Code
# marks EVERY stop after ANY stop-hook-driven continuation stop_hook_active=true,
# including turns started by the asyncRewake auto-arm, so the one-shot allow
# would re-open the exact blind window this guard exists to close
# (docs/turnend-guard.md records the 2026-07-21 incident). In --claude mode this
# guard ignores stop_hook_active and instead cooperates with the Stop-owned
# auto-arm (bin/fm-claude-stop-autoarm.sh), which fires on the same Stop event:
#   1. a live identity-matched watcher with a fresh beacon allows immediately;
#   2. otherwise wait briefly (FM_CLAUDE_AUTOARM_SYNC_WAIT_MS, default 800ms)
#      for the auto-arm to claim this home (state/.claude-autoarm.lock owner
#      alive) or to record a fresh actionable exit-2 outcome
#      (state/.claude-autoarm-epoch) for this event epoch - either proof allows
#      without consuming a continuation, so one event epoch yields exactly one recovery turn;
#      the first fresh exhausted-failure epoch preserves the bounded progression,
#      while later fresh failed epochs consume it instead of resetting it;
#   3. only when neither materializes is the auto-arm genuinely absent: re-block
#      with the repair banner, bounded to FM_CLAUDE_TURNEND_BLOCK_BUDGET
#      (default 3) consecutive blocks per session - safely below Claude Code's
#      hard 8-consecutive-block override - then allow one loud attended
#      fail-open only for an already verified failure episode.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
WATCH="$SCRIPT_DIR/fm-watch.sh"
CLAUDE_MODE=0
CODEX_MODE=0
SYNC_WAIT_MS=${FM_CLAUDE_AUTOARM_SYNC_WAIT_MS:-800}
EPOCH_FRESH=${FM_CLAUDE_AUTOARM_EPOCH_FRESH:-15}
BLOCK_BUDGET=${FM_CLAUDE_TURNEND_BLOCK_BUDGET:-3}
CODEX_SYNC_WAIT_MS=${FM_CODEX_AUTOARM_SYNC_WAIT_MS:-1500}
CODEX_OUTCOME_FRESH=${FM_CODEX_AUTOARM_OUTCOME_FRESH:-15}
case "$SYNC_WAIT_MS" in ''|*[!0-9]*) SYNC_WAIT_MS=800 ;; esac
case "$EPOCH_FRESH" in ''|*[!0-9]*|0) EPOCH_FRESH=15 ;; esac
case "$BLOCK_BUDGET" in ''|*[!0-9]*|0) BLOCK_BUDGET=3 ;; esac
case "$CODEX_SYNC_WAIT_MS" in ''|*[!0-9]*) CODEX_SYNC_WAIT_MS=1500 ;; esac
case "$CODEX_OUTCOME_FRESH" in ''|*[!0-9]*|0) CODEX_OUTCOME_FRESH=15 ;; esac

for arg in "$@"; do
  case "$arg" in
    --claude)
      [ "$CODEX_MODE" -eq 0 ] || { echo "usage: $(basename "$0") [--claude|--codex]" >&2; exit 2; }
      CLAUDE_MODE=1
      ;;
    --codex)
      [ "$CLAUDE_MODE" -eq 0 ] || { echo "usage: $(basename "$0") [--claude|--codex]" >&2; exit 2; }
      CODEX_MODE=1
      ;;
    *) echo "usage: $(basename "$0") [--claude|--codex]" >&2; exit 2 ;;
  esac
done

# A mode flag is set by that harness's OWN registered Stop hook, so it is
# authoritative about which harness this session runs, and it outranks
# bin/fm-harness.sh detection for the repair line: detection checks environment
# markers before process ancestry, so a foreign marker retained in a stored
# multiplexer environment can otherwise hand a markerless harness (codex) a
# different harness's repair instruction. Modes without a flag keep detecting.
HARNESS_PIN=
[ "$CLAUDE_MODE" -eq 1 ] && HARNESS_PIN=claude
[ "$CODEX_MODE" -eq 1 ] && HARNESS_PIN=codex

# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"

# Read the whole turn-end hook payload once; never block on unreadable/absent
# stdin.
PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0

# jq is the repo's established JSON dependency (bin/fm-x-poll.sh uses the same
# "missing jq -> silent no-op" degrade). Without it we cannot safely read the
# loop-guard field, so we must never block - fail open, not noisy.
command -v jq >/dev/null 2>&1 || exit 0

STOP_HOOK_ACTIVE=$(printf '%s' "$PAYLOAD" | jq -r '
  if type != "object" then error("payload")
  elif has("stopHookActive") then
    if ((.stopHookActive | type) == "boolean") then .stopHookActive else error("stopHookActive") end
  elif has("stop_hook_active") then
    if ((.stop_hook_active | type) == "boolean") then .stop_hook_active else error("stop_hook_active") end
  else false
  end
' 2>/dev/null) || exit 0
if [ "$CLAUDE_MODE" -eq 0 ] && [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# --- scope precisely to a PRIMARY checkout ----------------------------------
# A genuinely-marked secondmate home runs its OWN primary firstmate session, so
# force-INCLUDE it as a guarded primary whether treehouse leased it as a linked
# worktree (git-dir != git-common-dir) or it is a git-cloned plain checkout. This
# mirrors the cd-guard's intent that a secondmate's own session is a guarded
# primary. Only an UNMARKED checkout (or one with an invalid marker) falls
# through to the linked-worktree exemption: firstmate hands out crewmate/scout
# task worktrees as genuine linked `git worktree`s (bin/fm-spawn.sh aborts
# otherwise), whose git-dir lives under the parent repo's .git/worktrees/<name>
# and differs from the common (shared) git-dir, while a main, non-worktree
# checkout has the two equal. Child worktrees never carry the gitignored marker,
# so this exempts them while guarding every real secondmate home.
fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0

# --- the actual predicate ----------------------------------------------------
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh"

BUDGET_FILE="$STATE/.turnend-claude-blocks"
BUDGET_LOCK="$STATE/.turnend-claude-blocks.lock"
OWNER_LOCK="$STATE/.claude-autoarm.lock"
FAILURE_NOTICE="$STATE/.claude-autoarm-failure-notified"
FAILURE_ALARM="$STATE/.claude-autoarm-failure-alarmed"
SESSION_ID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')
# A Stop payload with no usable conversation id is its own condition, not a
# binding mismatch: SESSION_ID falls back to a sentinel, so every Codex identity
# comparison below fails for that one reason. The sibling hook already treats
# this payload shape as real and stays inert on it. Record the fact separately
# from the sentinel - a comparison against "unknown" cannot tell the difference,
# and the diagnostic must not accuse a correctly bound supervisor of targeting
# somewhere else.
CODEX_SESSION_ID_PRESENT=0
case "$(printf '%s' "$PAYLOAD" | jq -r '
  if type == "object" and (.session_id | type) == "string" then .session_id else empty end
' 2>/dev/null || true)" in
  ''|*[!0-9A-Za-z._-]*) : ;;
  *) CODEX_SESSION_ID_PRESENT=1 ;;
esac
budget_reset() {
  [ "$CLAUDE_MODE" -eq 1 ] || return 0
  fm_lock_try_acquire "$BUDGET_LOCK" || return 0
  rm -f "$BUDGET_FILE" 2>/dev/null || true
  fm_lock_release "$BUDGET_LOCK"
}

# --- --codex cooperative path ------------------------------------------------
# The Stop-owned background wake (bin/fm-codex-stop-autoarm.sh) is registered
# ahead of this guard on the same Stop event and detaches its supervisor rather
# than blocking. Give it a brief bounded window to prove it owns recovery for
# THIS conversation before falling back to the repair block: without this, the
# very first turn end of every cycle would still force a foreground checkpoint,
# which is exactly what that mode removes.
#
# Read the record ONCE per decision. Each publication of the binding is atomic,
# but a sequence of separate reads is not: a replacement landing between two of
# them would let the session of one record and the pid of another combine into a
# proof that neither record supports. One open, one pass, one snapshot - the
# open fd keeps reading the version it started on even if the name is replaced.
codex_binding_snapshot() {
  local line
  CODEX_BIND_PID=
  CODEX_BIND_IDENTITY=
  CODEX_BIND_SESSION=
  CODEX_BIND_OUTCOME=
  CODEX_BIND_UPDATED=
  [ -f "$STATE/.codex-autoarm-session" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      pid=*) [ -n "$CODEX_BIND_PID" ] || CODEX_BIND_PID=${line#pid=} ;;
      identity=*) [ -n "$CODEX_BIND_IDENTITY" ] || CODEX_BIND_IDENTITY=${line#identity=} ;;
      session=*) [ -n "$CODEX_BIND_SESSION" ] || CODEX_BIND_SESSION=${line#session=} ;;
      outcome=*) [ -n "$CODEX_BIND_OUTCOME" ] || CODEX_BIND_OUTCOME=${line#outcome=} ;;
      updated_at=*) [ -n "$CODEX_BIND_UPDATED" ] || CODEX_BIND_UPDATED=${line#updated_at=} ;;
    esac
  done < "$STATE/.codex-autoarm-session" 2>/dev/null
  [ -n "$CODEX_BIND_SESSION" ]
}

# An unresolved arm-failure episode. The auto-arm opens it on a failed cycle, a
# failed wake publication, and a failed retirement, and closes it only on an
# actionable published wake or a verified healthy watcher. This guard closes it
# too, at the two boundaries no supervisor survives to reach: a home with no
# supervision need left, and a home whose watcher is verifiably healthy again.
codex_failure_episode_open() {
  [ -e "$STATE/.codex-autoarm-failure-episode" ]
}

codex_failure_episode_clear() {
  rm -f "$STATE/.codex-autoarm-failure-episode" \
        "$STATE/.codex-autoarm-failure-notified" 2>/dev/null || true
}

# A supervisor process that is still exactly the process the binding recorded.
# Identity, not just the pid, so a recycled pid never buys a blind stop.
#
# Liveness alone is optimistic: a supervisor records outcome=arming within
# milliseconds of detaching, seconds before its arm wrapper can report anything.
# That optimism is only safe while the home's last completed cycle actually
# produced a watcher. state/.codex-autoarm-failure-episode says it did not, and
# the auto-arm clears it only on an actionable wake or a verified healthy
# watcher - never merely because a new supervisor started. So while that episode
# stands, a freshly started supervisor proves nothing, and accepting it would
# let every turn end after the episode's one notice pass silently and blind.
# Refuse here instead and fall through to the typed continuation, which the
# stop_hook_active loop guard above already bounds to one forced continuation
# per turn.
codex_supervisor_process_live() {
  local current
  case "$CODEX_BIND_PID" in
    ''|*[!0-9]*) return 1 ;;
  esac
  fm_pid_alive "$CODEX_BIND_PID" || return 1
  [ -n "$CODEX_BIND_IDENTITY" ] || return 1
  current=$(fm_pid_identity "$CODEX_BIND_PID" 2>/dev/null || true)
  [ -n "$current" ] && [ "$current" = "$CODEX_BIND_IDENTITY" ]
}

codex_autoarm_supervisor_live() {
  codex_failure_episode_open && return 1
  codex_supervisor_process_live
}

# A supervisor whose whole cycle fits inside the wait window above publishes its
# wake and exits, so process liveness alone would report a wake that was just
# published as absent supervision and send this session to repair a hook
# registration that is working. Accept only the outcome the supervisor writes
# after its publication call returned success, and only while it is fresh enough
# to have been published recently: arming, wake-unpublished, superseded, failed,
# afk, clean, and every aged record still block. Freshness is a time window, not
# a cycle identity - it establishes that a wake was published recently, not that
# it belongs to this Stop's own cycle. That success is a publication and not a
# delivery receipt; the durable state/.wake-queue record is what keeps a wake no
# live conversation consumed recoverable. This mirrors the fresh rewake outcome
# the --claude path accepts from its own auto-arm epoch.
codex_autoarm_delivered_wake() {
  local age
  [ "$CODEX_BIND_OUTCOME" = wake ] || return 1
  case "$CODEX_BIND_UPDATED" in
    ''|*[!0-9]*) return 1 ;;
  esac
  age=$(( $(date +%s) - CODEX_BIND_UPDATED ))
  [ "$age" -ge 0 ] && [ "$age" -lt "$CODEX_OUTCOME_FRESH" ]
}

# A usable delivery route for THIS conversation, judged without reference to the
# failure episode. The cooperative allow below withholds trust from a merely
# started supervisor while an episode stands; this predicate answers the
# different question of whether the route itself is intact, which is what
# decides when an episode has actually ended.
codex_delivery_route_ok() {
  codex_binding_snapshot || return 1
  # The wake target must be this conversation; a supervisor bound to a closed
  # one would publish where nobody is reading.
  [ "$CODEX_BIND_SESSION" = "$SESSION_ID" ] || return 1
  codex_supervisor_process_live && return 0
  codex_autoarm_delivered_wake
}

codex_autoarm_owns_recovery() {
  codex_binding_snapshot || return 1
  [ "$CODEX_BIND_SESSION" = "$SESSION_ID" ] || return 1
  codex_autoarm_supervisor_live && return 0
  codex_autoarm_delivered_wake
}

# Supervision belongs to the session holding state/.lock. The Stop-owned wake
# applies exactly this gate before it arms, and a session it declines to arm for
# must not then be told to repair the owner's supervision: a read-only Codex
# session sits beside a healthy watcher it neither started nor may touch. So the
# Codex-specific delivery proof is asked ONLY of the owning session; a session
# with a live foreign owner keeps the shared harness behavior and never writes
# or clears this home's episode state.
#
# Only a LIVE foreign owner is someone else's home. A missing, malformed or dead
# recorded owner is not another session, so the owning-session rules still apply
# and a genuine diagnostic still reaches the conversation.
CODEX_FOREIGN_OWNER=0
if [ "$CODEX_MODE" -eq 1 ] && ! fm_session_lock_owned_by_self "$STATE"; then
  codex_lock_pid=$(cat "$STATE/.lock" 2>/dev/null || true)
  case "$codex_lock_pid" in
    ''|*[!0-9]*) : ;;
    *) fm_harness_pid_alive "$codex_lock_pid" && CODEX_FOREIGN_OWNER=1 ;;
  esac
fi
CODEX_OWNS_HOME=0
[ "$CODEX_MODE" -eq 1 ] && [ "$CODEX_FOREIGN_OWNER" -eq 0 ] && CODEX_OWNS_HOME=1

fm_supervision_status "$STATE" "$GRACE"
if [ "$FM_SUP_NEEDED" = false ]; then
  # Nothing left to supervise, so any Codex failure episode has outlived its
  # cause. No supervisor survives a failed cycle to reach this boundary, and the
  # auto-arm hook returns even earlier, so this is the one place that can retire
  # it before a later batch of work inherits a stale, misleading block.
  [ "$CODEX_OWNS_HOME" -eq 1 ] && codex_failure_episode_clear
  [ -e "$FAILURE_NOTICE" ] || budget_reset
  exit 0
fi
if fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME"; then
  if [ "$CODEX_OWNS_HOME" -eq 1 ]; then
    # A healthy watcher is NOT, on its own, a stop proof for Codex. The watcher
    # observes the home; the supervisor is what turns an observed event into a
    # message in a conversation. A watcher that is healthy while the only
    # supervisor is bound to a conversation that has been replaced leaves this
    # one with no route at all, which is exactly how a handoff goes missing.
    #
    # It is not, on its own, the end of a failure episode either. An episode
    # opened by a routing or publication failure is about the route to this
    # conversation, and the stuck supervisor's own watcher is usually still
    # beating; only a watcher that is healthy AND a route that is intact says
    # the episode is over. Away mode is the one exception to both: there the
    # daemon owns triage and delivery.
    if [ -e "$STATE/.afk" ]; then
      codex_failure_episode_clear
      exit 0
    fi
    codex_delivery_route_ok && codex_failure_episode_clear
  elif [ "$CODEX_MODE" -eq 1 ]; then
    exit 0
  else
    [ "$CLAUDE_MODE" -eq 1 ] || exit 0
    fm_failure_episode_reset "$STATE" && exit 0
    # Supervision is healthy, but the recorded failure episode could not be
    # cleared. Blocking is the safe branch: it keeps every episode marker intact
    # for the retry instead of allowing the stop with stale failure state that
    # would mis-account the next episode. Say so, because a silent exit 2
    # re-invokes the model with no message and no instruction.
    printf '●  Supervision is healthy, but the Claude failure episode could not be reset: %s is held by another Stop-event writer or its state directory is unwritable.\n●  This stop is blocked so the episode markers survive for the retry. Simply end the turn again.\n●  If every retry reports this, check that directory by hand: a live holder clears on its own, an unwritable or full state directory does not.\n' \
      "$BUDGET_LOCK" >&2
    exit 2
  fi
fi

# What the Codex guard actually refused, in one sentence, or empty when the
# generic repair line already says it. The repair line names the hook
# registration and the watcher; when neither of those is the failure, saying so
# alone would send the session to inspect two working things. This states the
# condition; bin/fm-supervision-instructions.sh still owns the instruction.
codex_refusal_detail() {
  if [ "$CODEX_SESSION_ID_PRESENT" -eq 0 ]; then
    printf '%s\n' 'This Stop payload carried no usable conversation id, so there is no conversation for a wake to be addressed to and no supervisor binding can match it.'
    return 0
  fi
  codex_binding_snapshot || {
    printf '%s\n' 'No Stop-owned supervisor is bound to this conversation, so nothing is holding a delivery route for it.'
    return 0
  }
  if [ "$CODEX_BIND_SESSION" != "$SESSION_ID" ]; then
    if codex_supervisor_process_live; then
      printf 'The running Stop-owned supervisor (pid %s) is bound to conversation "%s", so its wake would be published there and not to this one; this conversation has no delivery route until a Stop rebinds it.\n' \
        "$CODEX_BIND_PID" "$CODEX_BIND_SESSION"
    else
      printf 'The only supervisor record belongs to conversation "%s" and its process is gone, so this conversation has no delivery route.\n' \
        "$CODEX_BIND_SESSION"
    fi
    return 0
  fi
  if codex_failure_episode_open; then
    printf '%s\n' 'An unresolved arm-failure episode is open for this home, so a supervisor that has only just started is not yet evidence that a watcher came up.'
    return 0
  fi
  case "$CODEX_BIND_OUTCOME" in
    wake-unpublished)
      printf '%s\n' 'The last wake for this conversation could not be published; the event is still durable in state/.wake-queue and is drained by bin/fm-wake-drain.sh.'
      return 0
      ;;
  esac
  return 0
}

block_stop() {
  local afk x_mode read_only reason rule continuation detail
  local -a instr_args
  afk=0
  [ -e "$STATE/.afk" ] && afk=1
  x_mode=0
  [ -f "$CONFIG/x-mode.env" ] && x_mode=1
  # A session that does not own the home must be told repair belongs to the
  # lock holder, not handed the owner's repair instruction.
  read_only=0
  [ "${CODEX_FOREIGN_OWNER:-0}" -eq 1 ] && read_only=1
  instr_args=(--afk "$afk" --x-mode "$x_mode" --read-only "$read_only" --repair-line)
  [ -n "$HARNESS_PIN" ] && instr_args=(--harness "$HARNESS_PIN" "${instr_args[@]}")
  reason=$("$SCRIPT_DIR/fm-supervision-instructions.sh" "${instr_args[@]}" 2>/dev/null \
    || printf '%s\n' 'tasks in flight, no live watcher - repair missing watcher supervision according to the session-start operating block before ending the turn')
  if [ "$CODEX_MODE" -eq 1 ]; then
    # bin/fm-supervision-instructions.sh owns what this session must actually
    # do, and every branch of its line is already a complete imperative, so the
    # line itself is still sent unaltered. What it does NOT carry is which
    # condition failed, and the Codex refusals are not all about the hook
    # registration it names. Lead with the observed condition, then the
    # instruction, so the session repairs the thing that is actually broken.
    detail=
    [ "$afk" -eq 1 ] || [ "$read_only" -eq 1 ] || detail=$(codex_refusal_detail)
    if [ -n "$detail" ]; then
      continuation=$(printf '%s %s' "$detail" "$reason")
    else
      continuation=$reason
    fi
    continuation=$(printf '%s' "$continuation" \
      | "$SCRIPT_DIR/fm-operational-input.sh" encode turn-end-guard 2>/dev/null || true)
    # Fail closed like every other edge here: only a successfully emitted typed
    # block may allow this stop, otherwise fall through to the exit-2 banner.
    if [ -n "$continuation" ] && jq -cn --arg reason "$continuation" '{decision:"block",reason:$reason}'; then
      exit 0
    fi
  fi
  rule='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  {
    printf '●%s\n' "$rule"
    printf '●  TURN WOULD END BLIND - SUPERVISION IS OFF\n'
    if [ "$FM_SUP_IN_FLIGHT" -gt 0 ]; then
      printf '●  %s task(s) in flight, but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_IN_FLIGHT" "$FM_SUP_BEACON_DESC"
    else
      printf '●  X-mode relay polling needs supervision, but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_BEACON_DESC"
    fi
    if [ "$read_only" -eq 1 ]; then
      printf '●  Another live session holds this home lock, so its supervision is not yours to repair.\n'
    elif [ "$CODEX_MODE" -eq 1 ] && codex_binding_snapshot && codex_supervisor_process_live; then
      # A supervisor IS running; it just did not prove recovery for this stop.
      # Saying otherwise would send the operator to look for a process that is
      # in front of them.
      printf '●  A Stop-owned supervisor (pid %s) is running for conversation "%s" with recorded outcome "%s", but it is not usable recovery for THIS stop.\n' \
        "$CODEX_BIND_PID" "$CODEX_BIND_SESSION" "${CODEX_BIND_OUTCOME:-unrecorded}"
      if [ "$CODEX_SESSION_ID_PRESENT" -eq 0 ]; then
        printf '●  This Stop payload carried no usable conversation id, so no binding can match it.\n'
      elif [ "$CODEX_BIND_SESSION" != "$SESSION_ID" ]; then
        printf '●  Its wake would be published to that conversation, not to this one (%s).\n' "$SESSION_ID"
      elif codex_failure_episode_open; then
        printf '●  An unresolved arm-failure episode is open, so a supervisor that has only just started is not evidence a watcher came up.\n'
      fi
    elif [ "$CLAUDE_MODE" -eq 1 ] || [ "$CODEX_MODE" -eq 1 ]; then
      printf '●  The Stop-owned auto-arm did not claim this home either, so recovery is NOT already under way.\n'
    fi
    printf '●  %s\n' "$reason"
    printf '●%s\n' "$rule"
  } >&2
  exit 2
}

if [ "$CODEX_OWNS_HOME" -eq 1 ]; then
  codex_waited=0
  while :; do
    codex_autoarm_owns_recovery && exit 0
    [ "$codex_waited" -ge "$CODEX_SYNC_WAIT_MS" ] && break
    sleep 0.1
    codex_waited=$((codex_waited + 100))
  done
fi

if [ "$CLAUDE_MODE" -eq 0 ]; then
  block_stop
fi

# --- --claude cooperative path -----------------------------------------------
# The Stop-owned auto-arm fires on the same Stop event. Give it a brief bounded
# window to prove it owns recovery for this event epoch before consuming one of
# Claude's bounded continuations.
budget_account_current_epoch() {
  local current_epoch outcome old_session old_count old_epoch tmp initialized
  fm_lock_try_acquire "$BUDGET_LOCK" || return 1
  current_epoch=$(sed -n 's/^epoch=\([0-9][0-9]*\) .*/\1/p' "$STATE/.claude-autoarm-epoch" 2>/dev/null || true)
  outcome=$(sed -n 's/^.*outcome=\([a-z][a-z-]*\) .*$/\1/p' "$STATE/.claude-autoarm-epoch" 2>/dev/null || true)
  initialized=0
  COUNT=0
  if [ -f "$BUDGET_FILE" ]; then
    old_session=$(sed -n '1s/^session=//p' "$BUDGET_FILE" 2>/dev/null || true)
    old_count=$(sed -n '2s/^count=//p' "$BUDGET_FILE" 2>/dev/null || true)
    old_epoch=$(sed -n '3s/^epoch=//p' "$BUDGET_FILE" 2>/dev/null || true)
    case "$old_count" in
      ''|*[!0-9]*) old_count=0 ;;
    esac
    if [ "$old_session" = "$SESSION_ID" ]; then
      COUNT=$old_count
      if [ -n "$current_epoch" ] && [ "$old_epoch" = "$current_epoch" ]; then
        :
      else
        COUNT=$((COUNT + 1))
      fi
    fi
  fi
  if [ ! -f "$BUDGET_FILE" ] || [ "${old_session:-}" != "$SESSION_ID" ]; then
    case "$outcome" in
      failed|failed-suppressed)
        if [ -e "$FAILURE_NOTICE" ]; then
          initialized=1
          COUNT=0
        else
          COUNT=1
        fi
        ;;
      *) COUNT=1 ;;
    esac
  fi
  tmp="$BUDGET_FILE.tmp.$$"
  if ! printf 'session=%s\ncount=%s\nepoch=%s\n' "$SESSION_ID" "$COUNT" "$current_epoch" > "$tmp" 2>/dev/null \
    || ! mv -f "$tmp" "$BUDGET_FILE" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    fm_lock_release "$BUDGET_LOCK"
    return 1
  fi
  rm -f "$tmp" 2>/dev/null || true
  BUDGET_INITIALIZED_FAILURE=$initialized
  fm_lock_release "$BUDGET_LOCK"
  return 0
}

autoarm_owns_recovery() {
  local pid role outcome age
  fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME" && return 0
  pid=$(cat "$OWNER_LOCK/pid" 2>/dev/null || true)
  role=$(fm_lock_role "$OWNER_LOCK" 2>/dev/null || true)
  if fm_pid_alive "$pid" && [ "$role" = autoarm ]; then
    [ ! -e "$FAILURE_NOTICE" ] || budget_account_current_epoch || true
    return 0
  fi
  outcome=$(sed -n 's/^.*outcome=\([a-z][a-z-]*\) .*$/\1/p' "$STATE/.claude-autoarm-epoch" 2>/dev/null || true)
  case "$outcome" in
    rewake)
      age=$(fm_path_age "$STATE/.claude-autoarm-epoch")
      if [ "$age" -lt "$EPOCH_FRESH" ]; then
        [ ! -e "$FAILURE_NOTICE" ] || budget_account_current_epoch || true
        return 0
      fi
      ;;
    failed)
      age=$(fm_path_age "$STATE/.claude-autoarm-epoch")
      if [ "$age" -lt "$EPOCH_FRESH" ] && [ -e "$FAILURE_NOTICE" ] \
        && budget_account_current_epoch; then
        [ "$BUDGET_INITIALIZED_FAILURE" -eq 1 ] && return 0
      fi
      ;;
    failed-suppressed)
      age=$(fm_path_age "$STATE/.claude-autoarm-epoch")
      if [ "$age" -lt "$EPOCH_FRESH" ] && [ -e "$FAILURE_NOTICE" ] \
        && budget_account_current_epoch; then
        :
      fi
      ;;
  esac
  return 1
}

terminal_fail_open() {
  local pid role old_session old_count
  [ "$COUNT" -gt "$BLOCK_BUDGET" ] || return 1
  failure_episode_verified || return 1
  [ ! -e "$FAILURE_ALARM" ] || return 1
  if ! fm_lock_try_acquire "$OWNER_LOCK"; then
    pid=$(cat "$OWNER_LOCK/pid" 2>/dev/null || true)
    role=$(fm_lock_role "$OWNER_LOCK" 2>/dev/null || true)
    if fm_pid_alive "$pid" && [ "$role" = autoarm ]; then
      return 2
    fi
    return 1
  fi
  if ! fm_lock_set_role "$OWNER_LOCK" terminal-check; then
    fm_lock_release "$OWNER_LOCK"
    return 1
  fi
  if ! fm_lock_try_acquire "$BUDGET_LOCK"; then
    fm_lock_release "$OWNER_LOCK"
    return 1
  fi
  old_session=$(sed -n '1s/^session=//p' "$BUDGET_FILE" 2>/dev/null || true)
  old_count=$(sed -n '2s/^count=//p' "$BUDGET_FILE" 2>/dev/null || true)
  case "$old_count" in
    ''|*[!0-9]*) old_count=0 ;;
  esac
  role=$(fm_lock_role "$OWNER_LOCK" 2>/dev/null || true)
  if [ "$role" != terminal-check ] || [ "$old_session" != "$SESSION_ID" ] \
    || [ "$old_count" -le "$BLOCK_BUDGET" ] || ! failure_episode_verified \
    || [ -e "$FAILURE_ALARM" ]; then
    fm_lock_release "$BUDGET_LOCK"
    fm_lock_release "$OWNER_LOCK"
    return 1
  fi
  if fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME"; then
    if ! fm_failure_episode_reset "$STATE" held; then
      fm_lock_release "$BUDGET_LOCK"
      fm_lock_release "$OWNER_LOCK"
      return 1
    fi
    fm_lock_release "$BUDGET_LOCK"
    fm_lock_release "$OWNER_LOCK"
    return 2
  fi
  if ! (set -C; : > "$FAILURE_ALARM") 2>/dev/null; then
    fm_lock_release "$BUDGET_LOCK"
    fm_lock_release "$OWNER_LOCK"
    return 1
  fi
  fm_lock_release "$BUDGET_LOCK"
  fm_lock_release "$OWNER_LOCK"
  return 0
}

failure_episode_verified() {
  local outcome
  [ ! -e "$STATE/.afk" ] || return 1
  [ -e "$FAILURE_NOTICE" ] || return 1
  outcome=$(sed -n 's/^.*outcome=\([a-z][a-z-]*\) .*$/\1/p' "$STATE/.claude-autoarm-epoch" 2>/dev/null || true)
  case "$outcome" in
    failed|failed-suppressed) return 0 ;;
    *) return 1 ;;
  esac
}

i=0
while [ "$i" -lt $((SYNC_WAIT_MS / 100)) ]; do
  if autoarm_owns_recovery; then
    if fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME"; then
      fm_failure_episode_reset "$STATE" || exit 2
    fi
    exit 0
  fi
  sleep 0.1
  i=$((i + 1))
done
if autoarm_owns_recovery; then
  if fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME"; then
    fm_failure_episode_reset "$STATE" || exit 2
  fi
  exit 0
fi

# The auto-arm genuinely failed to establish: consume the bounded re-block
# budget before considering the verified one-time attended fail-open.
budget_account_current_epoch || block_stop
terminal_fail_open
terminal_status=$?
if [ "$terminal_status" -eq 0 ]; then
  if [ "$FM_SUP_IN_FLIGHT" -gt 0 ]; then
    NEED_DESC="$FM_SUP_IN_FLIGHT task(s) in flight"
  else
    NEED_DESC="X-mode relay polling active"
  fi
  printf '{"systemMessage":"FIRSTMATE SUPERVISION IS GENUINELY DOWN: %s, the Stop-owned auto-arm exhausted its bounded retries and one failure notice, no watcher or automatic continuation exists, and the block budget is exhausted. Keep this session attended and diagnose the automatic Stop-hook and watcher startup before relying on unattended supervision."}\n' "$NEED_DESC"
  exit 0
fi
[ "$terminal_status" -eq 2 ] && exit 0
block_stop
