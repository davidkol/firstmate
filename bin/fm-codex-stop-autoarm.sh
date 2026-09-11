#!/usr/bin/env bash
# Codex Stop-owned background wake.
#
# Registered in tracked .codex/hooks.json as a Stop command hook, BEFORE the
# turn-end guard. It gives a Codex primary the same useful behavior Claude gets
# from its asyncRewake Stop hook: the session ends its turn, stays interactive
# for the captain, and is woken again only when a real supervision event lands -
# with no recurring foreground checkpoint and no model tokens while it waits.
#
# Codex has no async hook mode, so the hook itself must return immediately.
# It therefore splits into two roles:
#
#   hook mode (default, stdin = the Stop payload)
#     Applies the gates below, then launches THIS script again in supervise mode
#     through bin/fm-codex-detach.sh and exits 0 at once. It never blocks the
#     stop and never writes to stdout, so it cannot disturb the typed Stop
#     decision the turn-end guard owns on the same event.
#     One path is not instant, and says so rather than pretending: retiring a
#     supervisor bound to a REPLACED conversation waits for that process to die,
#     bounded by FM_CODEX_AUTOARM_RETIRE_WAIT (default 5s). That happens only on
#     the first turn end after a conversation restart, and the alternative -
#     arming a second supervisor beside a live one - is the misdelivery this
#     binding exists to prevent.
#
#   --supervise <session-id> <owner-pid> <owner-identity> (detached, internal)
#     Holds the home-scoped owner lock, foregrounds bin/fm-watch-arm.sh exactly
#     as the Claude auto-arm does, and translates an actionable close into
#     `codex queue --thread <session-id>`, which delivers one marked operational
#     input into that idle conversation and resumes it.
#     The owner arguments carry the primary that authorized this cycle. The
#     hook's ownership check is made at fork time and expires: this process can
#     start seconds later, after a different primary has taken the home. It
#     therefore re-establishes that authority before arming AND again before
#     publishing, and stands down as `superseded` rather than waking a
#     conversation the home no longer belongs to.
#
# Gates, all shared with bin/fm-claude-stop-autoarm.sh's model:
#   - Scope: only a genuine primary checkout (plain checkout or validly marked
#     secondmate home) with AGENTS.md, bin/, and the effective state dir - the
#     exact fm-turnend-guard.sh scope. Child crew/scout worktrees stay inert.
#   - Wake target: only a Stop payload carrying this conversation's session_id.
#     Without it there is nothing to wake, so the hook stays inert and lets the
#     turn-end guard be the loud path.
#   - Identity: only when THIS session's harness ancestor holds state/.lock.
#     A live foreign owner, missing lock, malformed lock, or unresolved ancestry
#     remains inert; only a dead recorded owner is reclaimed through
#     bin/fm-lock.sh, so a competing session never arms or wakes.
#   - AFK: while state/.afk exists the away daemon owns the watcher and triage;
#     the hook exits 0 and the supervisor NEVER queues a wake (checked again at
#     delivery time so a mid-cycle AFK transition is honored).
#   - Need: arms only while work is in flight (state/*.meta) or X mode has a
#     relay poll to run (state/x-watch.check.sh); an idle home exits 0.
#   - Delivery: a `codex` executable must exist before arming. That is a cheap
#     pre-check, NOT proof that this build supports `queue --thread`; only the
#     publication itself establishes that. A build without the subcommand fails
#     the publication, which records wake-unpublished and opens the failure
#     episode, so the home fails loud instead of looking armed. The exact client
#     the capability was observed on is recorded in
#     docs/verification/supervision.md.
#
# Session binding is what makes restart safe. A Stop event proves the session
# that emitted it is alive right now, so the NEWEST Stop always owns the wake
# target. A supervisor still bound to a closed conversation would publish its
# wake into a thread nobody is reading, so the hook retires that supervisor by
# its recorded pid identity and arms a fresh one for the current session.
#
# state/.codex-autoarm-session is that binding, written only by the supervisor
# and deliberately left behind when it exits, because it records an outcome
# rather than claiming liveness (state/.codex-autoarm.lock does that):
#   pid=<supervisor pid>
#   identity=<fm_pid_identity of that pid>
#   session=<codex conversation id this supervisor will wake>
#   outcome=<arming|wake|wake-unpublished|superseded|failed|clean|afk>
#   updated_at=<epoch seconds>
# The turn-end guard (bin/fm-turnend-guard.sh --codex) reads it to allow a stop
# whose recovery a live supervisor bound to THIS session already owns, instead
# of forcing the foreground checkpoint this mode exists to remove. A cycle that
# closes inside the guard's wait window leaves no live process, so the guard
# also accepts a still-fresh outcome=wake record for this session; that is why
# outcome and updated_at are part of this record's contract.
# outcome=wake is written only after the publication call returned success, and
# it claims exactly that much: the wake was PUBLISHED, never that the
# conversation consumed it. A publication that fails records wake-unpublished
# instead, which the guard refuses like every other non-wake outcome, so an
# attempted wake can never stand in for a published one.
#
# outcome=superseded means this supervisor stood down because the primary that
# authorized it no longer owns the home, or because a newer supervisor rebound
# the home while it was working. It publishes nothing in that state.
#
# A failure episode keeps two separate records so neither can silently do the
# other's job:
#   state/.codex-autoarm-failure-episode    an unresolved failure episode exists
#     because the last completed cycle could not bring a watcher up. This one
#     and only this one decides whether the turn-end guard may still accept a
#     merely live supervisor as recovery. It is written on every failed cycle.
#   state/.codex-autoarm-failure-notified   one operator notice was already
#     PUBLISHED for this episode. It decides nothing but whether to publish
#     another, and it is written only after the publication call succeeds, so a
#     notice that never reached the conversation cannot suppress the next one.
# Both are cleared together, and only by real recovery: a wake this supervisor
# actually published, a verified healthy watcher whose delivery route for the
# current conversation is also intact, or a home that no longer needs
# supervision at all. A new supervisor merely starting never clears either.
# Every one of those endings has an owner. A failed cycle, a failed retirement,
# and a wake whose publication failed all OPEN the episode here; the two
# boundaries no supervisor survives to reach - no supervision need left, and a
# verifiably healthy watcher - are closed by bin/fm-turnend-guard.sh --codex,
# which is the only other process on the Stop event.
#
# `codex queue` returns success for a conversation that has already exited, so a
# successful publication is NOT proof of delivery. That is safe because the
# actionable event is already durable in state/.wake-queue: a wake published
# into a closed conversation is drained by the next session start rather than
# lost. Never treat the queue exit status as delivery evidence.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
ARM_OUTPUT=
OWNER_LOCK="$STATE/.codex-autoarm.lock"
BINDING="$STATE/.codex-autoarm-session"
FAILURE_NOTICE="$STATE/.codex-autoarm-failure-notified"
FAILURE_EPISODE="$STATE/.codex-autoarm-failure-episode"
RETIRE_WAIT=${FM_CODEX_AUTOARM_RETIRE_WAIT:-50}
PUBLISH_ATTEMPTS=${FM_CODEX_PUBLISH_ATTEMPTS:-3}
PUBLISH_RETRY_DELAY=${FM_CODEX_PUBLISH_RETRY_DELAY:-1}
OWNER_PID=
OWNER_IDENTITY=
AUTOARM_ATTEMPTS=${FM_CODEX_AUTOARM_ATTEMPTS:-2}
case "$AUTOARM_ATTEMPTS" in
  1|2|3) : ;;
  *) AUTOARM_ATTEMPTS=2 ;;
esac
case "$RETIRE_WAIT" in
  ''|*[!0-9]*|0) RETIRE_WAIT=50 ;;
esac
case "$PUBLISH_ATTEMPTS" in
  1|2|3|4|5) : ;;
  *) PUBLISH_ATTEMPTS=3 ;;
esac
case "$PUBLISH_RETRY_DELAY" in
  ''|*[!0-9.]*) PUBLISH_RETRY_DELAY=1 ;;
esac

# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh"

usage() {
  cat <<'EOF'
Usage: fm-codex-stop-autoarm.sh                      Codex Stop hook; payload on stdin
       fm-codex-stop-autoarm.sh --supervise <id> <owner-pid> <owner-identity>
                                                     detached supervisor (internal)

Hook mode arms one home-scoped watcher cycle for the Codex conversation that
emitted the Stop payload, then returns immediately without writing to stdout.
The detached supervisor waits tokenlessly and wakes that conversation with
`codex queue` when the cycle closes with an actionable reason.
EOF
}

# One open, one pass, one snapshot. Each publication of $BINDING is atomic, but
# a sequence of separate reads is not: a replacement landing between two of them
# would mix the session of one record with the pid of another. Both readers of
# this record - here and bin/fm-turnend-guard.sh - take the whole record at once.
binding_snapshot() {
  local line
  BIND_PID=
  BIND_IDENTITY=
  BIND_SESSION=
  BIND_OUTCOME=
  [ -f "$BINDING" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      pid=*) [ -n "$BIND_PID" ] || BIND_PID=${line#pid=} ;;
      identity=*) [ -n "$BIND_IDENTITY" ] || BIND_IDENTITY=${line#identity=} ;;
      session=*) [ -n "$BIND_SESSION" ] || BIND_SESSION=${line#session=} ;;
      outcome=*) [ -n "$BIND_OUTCOME" ] || BIND_OUTCOME=${line#outcome=} ;;
    esac
  done < "$BINDING" 2>/dev/null
  [ -n "$BIND_SESSION" ]
}

# True when the snapshot names a supervisor process that is still the same
# process it recorded. Identity, not just the pid, so a recycled pid is never
# signalled.
binding_owner_live() {
  local current
  case "$BIND_PID" in
    ''|*[!0-9]*) return 1 ;;
  esac
  fm_pid_alive "$BIND_PID" || return 1
  [ -n "$BIND_IDENTITY" ] || return 1
  current=$(fm_pid_identity "$BIND_PID" 2>/dev/null || true)
  [ -n "$current" ] && [ "$current" = "$BIND_IDENTITY" ]
}

main_hook() {
  local session_id codex_bin payload

  # Consume the payload once so a slow writer can never wedge on a full pipe.
  payload=$(cat 2>/dev/null || true)
  [ -n "$payload" ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  session_id=$(printf '%s' "$payload" | jq -r '
    if type == "object" and (.session_id | type) == "string" then .session_id else empty end
  ' 2>/dev/null || true)
  case "$session_id" in
    ''|*[!0-9A-Za-z._-]*) exit 0 ;;
  esac

  fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0

  # Identity: only the lock-owning session's hooks may arm. A prior session may
  # have died leaving its numeric harness pid behind; the shared liveness
  # predicate recognizes only that stale-owner case. Defer the mutating claim
  # until after the unchanged AFK and need gates so an idle or away home stays
  # byte-for-byte inert.
  local recover_session_lock=0 lock_pid
  if ! fm_session_lock_owned_by_self "$STATE"; then
    lock_pid=$(cat "$STATE/.lock" 2>/dev/null || true)
    case "$lock_pid" in
      ''|*[!0-9]*) exit 0 ;;
    esac
    fm_harness_pid_alive "$lock_pid" && exit 0
    recover_session_lock=1
  fi

  [ -e "$STATE/.afk" ] && exit 0
  if ! fm_supervision_needed "$STATE" "$GRACE"; then
    failure_episode_clear
    exit 0
  fi

  # A cycle whose wake cannot be delivered is worse than no cycle: it would look
  # armed to the guard while no event could ever reach this conversation.
  codex_bin=$(command -v codex 2>/dev/null || true)
  [ -n "$codex_bin" ] && [ -x "$codex_bin" ] || exit 0

  if [ "$recover_session_lock" -eq 1 ]; then
    "$SCRIPT_DIR/fm-lock.sh" >/dev/null 2>&1 || exit 0
    fm_session_lock_owned_by_self "$STATE" || exit 0
  fi

  # Already armed for exactly this conversation: nothing to do.
  if binding_snapshot && binding_owner_live; then
    [ "$BIND_SESSION" = "$session_id" ] && exit 0
    # Bound to a different conversation, so its wake would land where nobody is
    # reading. Retire it by exact identity-checked pid and arm a fresh one.
    kill -TERM "$BIND_PID" 2>/dev/null || true
    local i=0
    while [ "$i" -lt "$RETIRE_WAIT" ] && fm_pid_alive "$BIND_PID"; do
      sleep 0.1
      i=$((i + 1))
    done
    if fm_pid_alive "$BIND_PID"; then
      # Retirement failed, so this conversation has NO delivery route: the only
      # supervisor still targets the replaced one, and arming a second beside it
      # would publish the same event twice into two conversations. A failed
      # rebind must not read as success, so open the episode and let the
      # turn-end guard say so out loud.
      : > "$FAILURE_EPISODE" 2>/dev/null || true
      exit 0
    fi
  fi

  # The authority this cycle runs on. The detached child re-establishes it
  # before it arms and again before it publishes, because this check is true
  # only at this instant.
  local owner_pid owner_identity
  owner_pid=$(cat "$STATE/.lock" 2>/dev/null || true)
  case "$owner_pid" in
    ''|*[!0-9]*) exit 0 ;;
  esac
  owner_identity=$(fm_pid_identity "$owner_pid" 2>/dev/null || true)
  [ -n "$owner_identity" ] || exit 0

  "$SCRIPT_DIR/fm-codex-detach.sh" \
    "$SCRIPT_DIR/fm-codex-stop-autoarm.sh" --supervise "$session_id" \
      "$owner_pid" "$owner_identity" \
    >/dev/null 2>&1 || true
  exit 0
}

# Close the failure episode. Only real recovery calls this, so a guard that
# refuses to trust a merely live supervisor stays loud until a watcher is
# genuinely back.
failure_episode_clear() {
  rm -f "$FAILURE_EPISODE" "$FAILURE_NOTICE" 2>/dev/null || true
}

# Remove this supervisor's own arm output, if it has one, and forget the path so
# neither the retry below nor supervisor_cleanup can act on a stale name.
arm_output_discard() {
  [ -z "$ARM_OUTPUT" ] || rm -f "$ARM_OUTPUT" 2>/dev/null || true
  ARM_OUTPUT=
}

write_binding() {  # <session-id> <outcome>
  local session=$1 outcome=$2 tmp
  tmp="$BINDING.tmp.$$"
  {
    printf 'pid=%s\n' "${BASHPID:-$$}"
    printf 'identity=%s\n' "$SUPERVISOR_IDENTITY"
    printf 'session=%s\n' "$session"
    printf 'outcome=%s\n' "$outcome"
    printf 'updated_at=%s\n' "$(date +%s)"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$BINDING" 2>/dev/null
  rm -f "$tmp" 2>/dev/null || true
}

# Publish one marked operational input into the bound conversation. Marking is
# mandatory: bin/fm-operational-input.sh is the single owner of the wire form,
# and an UNMARKED injected message is read by away mode as the captain
# returning (AGENTS.md section 8).
queue_wake() {  # <session-id> <body> -> 0 published, 1 rejected, 2 unencodable
  local session=$1 body=$2 encoded
  encoded=$(printf '%s' "$body" | "$SCRIPT_DIR/fm-operational-input.sh" encode watcher 2>/dev/null) || return 2
  [ -n "$encoded" ] || return 2
  "$CODEX_BIN" queue --thread "$session" --message "$encoded" >/dev/null 2>&1 || return 1
  return 0
}

# A rejected publication is often transient - a client busy with the previous
# turn, a momentary socket failure - and the supervisor is the last process that
# will ever hold this event in memory. Retry it here, bounded, because after this
# exits nothing remains to try again: the durable state/.wake-queue record is
# recovery evidence for the next session start, not an active delivery route.
# An unencodable body is permanent and never retried. Success still means the
# publication was ACCEPTED, never that the conversation consumed it.
publish_wake() {  # <session-id> <body> -> 0 published, 1 not published, 3 superseded
  local session=$1 body=$2 attempt=0 rc
  while :; do
    attempt=$((attempt + 1))
    queue_wake "$session" "$body" && return 0
    rc=$?
    [ "$rc" -eq 2 ] && return 1
    [ "$attempt" -lt "$PUBLISH_ATTEMPTS" ] || return 1
    sleep "$PUBLISH_RETRY_DELAY"
    # Losing the home between retries is not a delivery failure: nothing about
    # this home's supervision is broken, it simply stopped being ours. Say so
    # with its own status so the caller cannot record it as one.
    still_authorized || return 3
  done
}

# The hook's ownership check was true when it forked; this one must be true now.
# A detached child can start seconds later, after a different primary has taken
# the home, and a wake armed on that expired authority lands in a conversation
# nobody is reading.
#
# The question is REPLACEMENT, not survival. A home lock that still names the
# authorizing primary is still this supervisor's home, whether or not that
# process is alive: an exited primary takes its conversation with it, which the
# durable state/.wake-queue record already covers, and no other session has
# claimed the home. A lock naming anyone else, or the same pid reused by a
# different process, is a replacement and must stop this cycle.
originating_primary_owns_home() {
  local lock_pid current
  lock_pid=$(cat "$STATE/.lock" 2>/dev/null || true)
  [ -n "$OWNER_PID" ] && [ "$lock_pid" = "$OWNER_PID" ] || return 1
  fm_pid_alive "$OWNER_PID" || return 0
  current=$(fm_pid_identity "$OWNER_PID" 2>/dev/null || true)
  [ -n "$current" ] && [ "$current" = "$OWNER_IDENTITY" ]
}

# Same primary process, replaced conversation: the newer hook rebinds the home,
# so a supervisor that is no longer the bound one has been superseded in place.
still_the_bound_supervisor() {
  binding_snapshot || return 1
  [ "$BIND_PID" = "${BASHPID:-$$}" ]
}

still_authorized() {
  originating_primary_owns_home && still_the_bound_supervisor
}

main_supervise() {  # <session-id>
  local session=$1 actionable=0 healthy=0 attempt=0 reasons publish_rc=0

  fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
  CODEX_BIN=$(command -v codex 2>/dev/null || true)
  [ -n "$CODEX_BIN" ] && [ -x "$CODEX_BIN" ] || exit 0
  SUPERVISOR_IDENTITY=$(fm_pid_identity "${BASHPID:-$$}" 2>/dev/null || true)
  [ -n "$SUPERVISOR_IDENTITY" ] || exit 0

  # Before anything is claimed or written: the primary that authorized this
  # cycle must still own the home. A child delayed past a primary replacement
  # would otherwise arm on expired authority and wake a retired conversation.
  originating_primary_owns_home || exit 0

  # Single-flight: exactly one supervisor per home. A live holder means the hook
  # raced with an earlier detach that is already arming; stand down silently.
  fm_lock_try_acquire "$OWNER_LOCK" || exit 0
  if ! fm_lock_set_role "$OWNER_LOCK" autoarm; then
    fm_lock_release "$OWNER_LOCK"
    exit 0
  fi

  ARM_CHILD=
  # The arm output this supervisor created, held outside main_supervise's locals
  # so the traps below can reach it. Only ever a path THIS process mktemp'd, so
  # cleanup can never touch a sibling supervisor's or another home's file.
  ARM_OUTPUT=
  # shellcheck disable=SC2329 # Invoked by the traps below and at normal exit.
  supervisor_cleanup() {
    if [ -n "$ARM_CHILD" ] && fm_pid_alive "$ARM_CHILD"; then
      kill -TERM "$ARM_CHILD" 2>/dev/null || true
      wait "$ARM_CHILD" 2>/dev/null || true
    fi
    # A retired supervisor is SIGTERMed mid-cycle every time a new conversation
    # binds to this home, so without this its arm output would be orphaned in
    # the state directory for the life of the home.
    arm_output_discard
    # The binding is a RECORD, not the liveness claim: the owner lock is. Leave
    # the last outcome on disk so an operator can see why a cycle closed, and so
    # a retired supervisor's cleanup can never race away its successor's entry.
    # Every reader already rejects a binding whose pid is dead or reidentified.
    fm_lock_release "$OWNER_LOCK"
  }
  # shellcheck disable=SC2329 # Invoked indirectly by the signal traps below.
  supervisor_signal() {
    trap - HUP TERM INT
    supervisor_cleanup
    exit 143
  }
  trap supervisor_cleanup EXIT
  trap supervisor_signal HUP TERM INT

  write_binding "$session" arming

  # X mode cadence: source the generated config so an X instance polls at its
  # 30s cadence (bin/fm-bootstrap.sh x_mode_setup contract).
  # shellcheck source=/dev/null
  [ -f "$CONFIG/x-mode.env" ] && . "$CONFIG/x-mode.env"

  while [ "$attempt" -lt "$AUTOARM_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    ARM_OUTPUT=$(mktemp "$STATE/.codex-autoarm-output.XXXXXX") || ARM_OUTPUT=
    if [ -n "$ARM_OUTPUT" ]; then
      "$SCRIPT_DIR/fm-watch-arm.sh" >"$ARM_OUTPUT" 2>&1 &
    else
      "$SCRIPT_DIR/fm-watch-arm.sh" >/dev/null 2>&1 &
    fi
    ARM_CHILD=$!
    wait "$ARM_CHILD" 2>/dev/null || true
    ARM_CHILD=

    # AFK may have appeared mid-cycle: the daemon owns triage now, so never
    # wake the conversation behind its back.
    if [ -e "$STATE/.afk" ]; then
      write_binding "$session" afk
      arm_output_discard
      exit 0
    fi

    actionable=0
    if [ -n "$ARM_OUTPUT" ]; then
      grep -Eq '^(signal:|stale:|check:|heartbeat($|:))' "$ARM_OUTPUT" 2>/dev/null && actionable=1
    fi
    [ "$actionable" -eq 1 ] && break

    if fm_watcher_healthy "$STATE" "$SCRIPT_DIR/fm-watch.sh" "$GRACE" "$FM_HOME"; then
      healthy=1
      break
    fi
    [ "$attempt" -lt "$AUTOARM_ATTEMPTS" ] || break
    arm_output_discard
  done

  # The need may have vanished mid-cycle (fleet torn down, X opted out): there is
  # nothing left to supervise, so close quietly instead of waking the captain's
  # conversation.
  if ! fm_supervision_needed "$STATE" "$GRACE"; then
    write_binding "$session" clean
    failure_episode_clear
    arm_output_discard
    exit 0
  fi

  if [ "$healthy" -eq 1 ]; then
    # Another verified watcher already owns this home and is still beating, so
    # this cycle closing early is benign and needs no wake.
    write_binding "$session" clean
    failure_episode_clear
    arm_output_discard
    exit 0
  fi

  reasons=
  [ -n "$ARM_OUTPUT" ] && reasons=$(grep -E '^(watcher:|signal:|stale:|check:|heartbeat)' "$ARM_OUTPUT" 2>/dev/null | head -8)
  arm_output_discard

  if [ "$actionable" -eq 1 ]; then
    if ! still_authorized; then
      write_binding "$session" superseded
      exit 0
    fi
    publish_wake "$session" "$(printf 'FIRSTMATE WATCHER WAKE - drain queued wakes with FM_SUPERVISION_MODEL=autoarm bin/fm-wake-drain.sh and handle the reported wake. Watcher continuity is Stop-hook-owned; do not arm another cycle yourself.\n\n%s' "$reasons")"
    publish_rc=$?
    if [ "$publish_rc" -eq 3 ]; then
      write_binding "$session" superseded
      exit 0
    fi
    if [ "$publish_rc" -eq 0 ]; then
      write_binding "$session" wake
      failure_episode_clear
    else
      # The event survives in state/.wake-queue, but a durable record is not a
      # notification: nothing is left running to deliver it, and this idle
      # conversation may never produce another Stop event on its own. Open the
      # episode so the guard is loud at the next turn end instead of letting an
      # undelivered handoff look like a healthy cycle.
      write_binding "$session" wake-unpublished
      : > "$FAILURE_EPISODE" 2>/dev/null || true
    fi
    exit 0
  fi

  # Open or extend the episode first: it is what keeps the turn-end guard loud on
  # every later turn end, so it must not depend on any message getting through.
  # Then notify at most once per episode, so a broken arm cannot turn into a wake
  # loop, and record that notice only if it was really published.
  if ! still_authorized; then
    write_binding "$session" superseded
    exit 0
  fi
  write_binding "$session" failed
  : > "$FAILURE_EPISODE" 2>/dev/null || true
  if [ ! -e "$FAILURE_NOTICE" ] \
    && publish_wake "$session" "$(printf 'FIRSTMATE WATCHER FAILURE - the Stop-owned background wake could not verify a live watcher after %s bounded attempts. Drain queued wakes, then inspect the automatic arm and watcher startup before ending the turn blind. Do not start a manual background arm from this notice.\n\n%s' "$attempt" "$reasons")"; then
    : > "$FAILURE_NOTICE" 2>/dev/null || true
  fi
  exit 0
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --supervise)
    [ "$#" -eq 4 ] || { usage >&2; exit 2; }
    case "$2" in
      ''|*[!0-9A-Za-z._-]*) echo "error: --supervise requires a session id" >&2; exit 2 ;;
    esac
    case "$3" in
      ''|*[!0-9]*) echo "error: --supervise requires the authorizing primary pid" >&2; exit 2 ;;
    esac
    [ -n "$4" ] || { echo "error: --supervise requires the authorizing primary identity" >&2; exit 2; }
    OWNER_PID=$3
    OWNER_IDENTITY=$4
    main_supervise "$2"
    ;;
  '')
    main_hook
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
