#!/usr/bin/env bash
# Opt-in credentialed Codex regression for the Stop-owned background wake.
#
# It drives a REAL interactive Codex conversation in a detached tmux session,
# because the behavior under test only exists there: `codex queue` resumes a live
# conversation, and `codex exec` has none to resume. It proves, in one isolated
# home, that an idle home arms nothing, that a live home arms a detached
# supervisor without a foreground checkpoint, that a parked supervisor costs no
# model or tool call, that the captain can still use the conversation while it
# waits, and that a worker event resumes that same conversation.
set -u

if [ "${FM_CODEX_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_CODEX_LIVE_E2E=1 to run the Codex continuity regression"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v codex >/dev/null 2>&1 || fail "codex not found"
command -v tmux >/dev/null 2>&1 || fail "tmux not found"

LAB="$ROOT/.codex-live-e2e.$$"
PROJECT="$LAB/project"
HOME_DIR="$LAB/fmhome"
SESSION="fm-codex-live-e2e-$$"
CODEX_VERSION=$(codex --version)
QUIET_SECONDS=${FM_CODEX_LIVE_QUIET_SECONDS:-40}

cleanup() {
  local pid
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  # Retire the detached supervisor by its own recorded pid only: it outlives the
  # conversation by design, so an abandoned lab would otherwise leak a watcher.
  pid=$(sed -n 's/^pid=//p' "$HOME_DIR/state/.codex-autoarm-session" 2>/dev/null | head -1)
  case "$pid" in
    ''|*[!0-9]*) : ;;
    *) kill -TERM "$pid" 2>/dev/null || true ;;
  esac
  pid=$(cat "$HOME_DIR/state/.watch.lock/pid" 2>/dev/null || true)
  case "$pid" in
    ''|*[!0-9]*) : ;;
    *) kill -TERM "$pid" 2>/dev/null || true ;;
  esac
  sleep 1
  rm -rf "$LAB"
}
trap cleanup EXIT

pane() {
  tmux capture-pane -p -S -200 -t "$SESSION" 2>/dev/null || true
}

# The TUI hard-wraps and re-indents a long message, and the wrap point moves with
# the rendered width, so a multi-word needle can straddle two captured lines.
# Strip every whitespace run before matching anything structural.
pane_squashed() {
  pane | tr -d '[:space:]'
}

# Wait until the pane contains <needle>, or fail after <seconds>.
wait_for_pane() {  # <needle> <seconds> <what>
  local needle=$1 limit=$2 what=$3 i=0
  while [ "$i" -lt $((limit * 2)) ]; do
    case "$(pane)" in
      *"$needle"*) return 0 ;;
    esac
    sleep 0.5
    i=$((i + 1))
  done
  fail "$what (pane never showed '$needle'):
$(pane)"
}

# The quiet control measures whether a PARKED supervisor costs a model or tool
# call, so its baseline has to be taken from a pane that has stopped moving. A
# pane captured while the Stop hook's own status line is still up will differ
# from itself a moment later - the hook finishes, the status clears, the TUI
# reflows - and the control then reports the rendering as conversation activity.
# Settled means no in-progress status and byte-identical across three
# consecutive samples.
pane_settled() {  # <seconds>
  local limit=$1 i=0 a b c
  while [ "$i" -lt "$limit" ]; do
    a=$(pane); sleep 0.5; b=$(pane); sleep 0.5; c=$(pane)
    if [ "$a" = "$b" ] && [ "$b" = "$c" ]; then
      case "$a" in
        *"esc to interrupt"*|*"Running hooks"*) : ;;
        *) return 0 ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}

# A pane that merely SHOWS the sentinel proves nothing: the request that asked
# for it is echoed into the same pane, so one occurrence is the prompt, not an
# answer. Wait for a second one, which only a completed assistant turn can add.
pane_occurrences() {  # <needle>
  pane | grep -c -F -- "$1" 2>/dev/null || true
}

wait_for_pane_answer() {  # <needle> <seconds> <what>
  local needle=$1 limit=$2 what=$3 i=0
  while [ "$i" -lt $((limit * 2)) ]; do
    [ "$(pane_occurrences "$needle")" -ge 2 ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  fail "$what (the pane never showed '$needle' as an answer, only as the echoed request):
$(pane)"
}

wait_for_pane_squashed() {  # <whitespace-free needle> <seconds> <what>
  local needle=$1 limit=$2 what=$3 i=0
  while [ "$i" -lt $((limit * 2)) ]; do
    case "$(pane_squashed)" in
      *"$needle"*) return 0 ;;
    esac
    sleep 0.5
    i=$((i + 1))
  done
  fail "$what (pane never showed '$needle'):
$(pane)"
}

wait_for_file() {  # <path> <seconds> <what>
  local path=$1 limit=$2 what=$3 i=0
  while [ "$i" -lt $((limit * 2)) ]; do
    [ -e "$path" ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  fail "$what (never appeared: $path)"
}

say() {  # <text> - type one captain message and submit it
  tmux send-keys -t "$SESSION" "$1"
  sleep 1
  tmux send-keys -t "$SESSION" Enter
}

binding_field() {  # <field>
  sed -n "s/^$1=//p" "$HOME_DIR/state/.codex-autoarm-session" 2>/dev/null | head -1
}

mkdir -p "$LAB"
git clone -q "$ROOT" "$PROJECT"
# A local clone contains only committed objects, so project this candidate diff
# into the isolated clone before asking Codex to exercise the behavior.
# A local clone carries only committed objects, so any uncommitted candidate has
# to be projected into it. An EMPTY diff means the clone already has the exact
# candidate, which is the shape of a pipeline commit or any clean checkout: that
# is success, not a failure to apply. Keep the failure for a diff that genuinely
# will not apply, and write it to a file so binary hunks survive byte for byte.
CANDIDATE_DIFF="$LAB/candidate.diff"
git -C "$ROOT" diff --binary HEAD > "$CANDIDATE_DIFF" \
  || fail "could not read the candidate diff from $ROOT"
if [ -s "$CANDIDATE_DIFF" ]; then
  git -C "$PROJECT" apply "$CANDIDATE_DIFF" \
    || fail "could not project the candidate diff into the isolated Codex clone"
fi
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"

# The candidate's own liveness and watcher-health predicates, so the successor
# check below asks the same question the guard and the arm layer ask. Source it
# only once the isolated home exists and is pointed at, because the library
# resolves and creates a state directory from the environment as it loads; at
# the top of this file that would be the developer's own checkout.
FM_HOME="$HOME_DIR"
FM_STATE_OVERRIDE="$HOME_DIR/state"
# shellcheck source=/dev/null
. "$PROJECT/bin/fm-wake-lib.sh"

PROMPT='You are a Firstmate primary session for this isolated test home. Reply with exactly READY and nothing else. Later, if you receive a firstmate supervision notification, run bin/fm-wake-drain.sh once and report in one line what it said.'

tmux new-session -d -s "$SESSION" -x 200 -y 50 -c "$PROJECT" \
  "FM_HOME='$HOME_DIR' FM_POLL=3 FM_SIGNAL_GRACE=2 exec codex \
     --enable hooks \
     --dangerously-bypass-hook-trust \
     --dangerously-bypass-approvals-and-sandbox \
     '$PROMPT'" \
  || fail "could not start the isolated Codex conversation"

# A fresh lab directory is untrusted, so accept the one trust prompt if it shows.
i=0
while [ "$i" -lt 40 ]; do
  case "$(pane)" in
    *"Do you trust the contents of this directory"*)
      tmux send-keys -t "$SESSION" Enter
      break
      ;;
    *READY*) break ;;
  esac
  sleep 0.5
  i=$((i + 1))
done
wait_for_pane_answer READY 120 "the isolated Codex conversation never completed its first turn"

# --- idle home: the Stop hook must arm nothing ------------------------------
[ ! -f "$HOME_DIR/state/.codex-autoarm-session" ] \
  || fail "Codex armed a supervisor for a home with no work in flight"
[ ! -e "$HOME_DIR/state/.watch.lock" ] \
  || fail "Codex started a watcher for a home with no work in flight"

# --- live home: one turn end arms a detached supervisor ----------------------
printf 'window=fm:fm-live\nworktree=%s\nkind=ship\nharness=codex\n' "$PROJECT" \
  > "$HOME_DIR/state/live.meta"
say 'Reply with exactly ARMED and nothing else.'
wait_for_pane_answer ARMED 120 "the Codex conversation never finished the arming turn"
wait_for_file "$HOME_DIR/state/.codex-autoarm-session" 30 \
  "the Stop hook never armed a supervisor for a home with work in flight"

SUPERVISOR=$(binding_field pid)
CONVERSATION=$(binding_field session)
case "$SUPERVISOR" in ''|*[!0-9]*) fail "the supervisor record has no pid" ;; esac
case "$CONVERSATION" in
  ????????-????-????-????-????????????) : ;;
  *) fail "the supervisor is not bound to a conversation id: '$CONVERSATION'" ;;
esac
kill -0 "$SUPERVISOR" 2>/dev/null || fail "the detached supervisor did not survive the Stop hook"
[ "$(ps -o ppid= -p "$SUPERVISOR" | tr -d ' ')" = 1 ] \
  || fail "the supervisor is still a child of the hook process instead of being detached"
wait_for_file "$HOME_DIR/state/.last-watcher-beat" 30 "the armed watcher never beat"

# --- quiet parked window: no model or tool call ------------------------------
pane_settled 120 || fail "the pane never settled after arming, so a quiet baseline would measure the TUI rather than the supervisor:
$(pane)"
PARKED=$(pane)
sleep "$QUIET_SECONDS"
[ "$(pane)" = "$PARKED" ] \
  || fail "the parked supervisor produced conversation activity during a quiet window:
$(diff <(printf '%s\n' "$PARKED") <(pane) || true)"
kill -0 "$SUPERVISOR" 2>/dev/null || fail "the supervisor died during the quiet window"

# --- the captain can still use the conversation while it waits ---------------
say 'Reply with exactly INTERACTIVE and nothing else.'
wait_for_pane INTERACTIVE 120 "the captain could not use the conversation while the supervisor waited"
[ "$(binding_field pid)" = "$SUPERVISOR" ] \
  || fail "a captain turn replaced the live supervisor instead of reusing it"

# --- a worker event resumes this same conversation ---------------------------
printf 'needs-decision: worker asks whether to open the new window\n' \
  >> "$HOME_DIR/state/live.status"
# Wait on the marked wire prefix: it can only come from a delivered wake, never
# from the launch prompt or from anything the model wrote itself.
wait_for_pane_squashed "FIRSTMATE_OP:v1watcher:" 180 \
  "the worker event never resumed the idle Codex conversation"
# Resumption is proven; the handling turn still has to run, so wait for the
# drained request rather than asserting it the instant the wake lands.
wait_for_pane_squashed "workeraskswhethertoopenthenewwindow" 180 \
  "the resumed conversation never drained the worker's own request"
PANE_AFTER=$(pane_squashed)
case "$PANE_AFTER" in
  *"FIRSTMATE_OP:v1watcher:FIRSTMATEWATCHERWAKE"*) : ;;
  *) fail "the wake reached the conversation unmarked, which away mode would read as the captain returning:
$(pane)" ;;
esac
case "$PANE_AFTER" in
  *"live.status"*) : ;;
  *) fail "the wake did not carry the real watcher reason line:
$(pane)" ;;
esac
case "$PANE_AFTER" in
  *fm-watch-checkpoint.sh*)
    fail "the conversation fell back to a foreground checkpoint" ;;
esac
i=0
while [ "$i" -lt 120 ] && [ -s "$HOME_DIR/state/.wake-queue" ]; do
  sleep 0.5
  i=$((i + 1))
done
[ ! -s "$HOME_DIR/state/.wake-queue" ] \
  || fail "the resumed conversation left the delivered wake queued"

# The handling turn's own Stop re-arms without the model doing anything.
wait_for_file "$HOME_DIR/state/.codex-autoarm-session" 30 "the supervisor record vanished"
i=0
while [ "$i" -lt 240 ]; do
  [ "$(binding_field pid)" != "$SUPERVISOR" ] && break
  sleep 0.5
  i=$((i + 1))
done
[ "$(binding_field pid)" != "$SUPERVISOR" ] \
  || fail "the cycle did not re-arm after delivering its wake"
[ "$(binding_field session)" = "$CONVERSATION" ] \
  || fail "the re-armed supervisor bound to a different conversation"

# A different pid value is not a successor. Verify the record names a process
# that is genuinely alive and still the process it recorded, and that the
# watcher underneath it is the one the shared predicate accepts as healthy.
SUCCESSOR=$(binding_field pid)
SUCCESSOR_IDENTITY=$(binding_field identity)
kill -0 "$SUCCESSOR" 2>/dev/null \
  || fail "the re-armed record names a supervisor that is not running"
[ -n "$SUCCESSOR_IDENTITY" ] \
  && [ "$(fm_pid_identity "$SUCCESSOR")" = "$SUCCESSOR_IDENTITY" ] \
  || fail "the re-armed record names a pid that is no longer the process it recorded"
i=0
while [ "$i" -lt 120 ]; do
  fm_watcher_healthy "$HOME_DIR/state" "$PROJECT/bin/fm-watch.sh" 300 "$HOME_DIR" && break
  sleep 0.5
  i=$((i + 1))
done
fm_watcher_healthy "$HOME_DIR/state" "$PROJECT/bin/fm-watch.sh" 300 "$HOME_DIR" \
  || fail "the re-armed cycle never produced a watcher the shared health predicate accepts"
[ ! -e "$HOME_DIR/state/.codex-autoarm-failure-episode" ] \
  || fail "the re-armed cycle left an unresolved failure episode"

printf 'ok - %s live E2E: idle armed nothing, a detached supervisor waited without model cost, the captain kept the conversation, and one worker event resumed it\n' \
  "$CODEX_VERSION"
