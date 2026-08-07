#!/usr/bin/env bash
# tests/wake-helpers.sh - shared fixtures and mocks for the wake-queue,
# watcher/lock, and supervise-daemon suites. The fake tmux surfaces here encode
# watcher/daemon/composer behavior, so they live here rather than in the generic
# tests/lib.sh. Generic reporters/assertions come from lib.sh, pulled in below.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# fm-wake-drain.sh now calls fm-guard.sh to assert watcher liveness on every
# drain. fm-guard.sh's first check warns when the firstmate PRIMARY checkout
# (FM_ROOT) sits on a feature branch; with no override FM_ROOT resolves to the
# test runner's own checkout, which during validation is on a feature branch, so
# each drain would emit a spurious worktree-tangle banner. Point the tangle check
# at a fresh non-git dir to keep it inert across these suites - the same trick the
# direct fm-guard.sh tests use. A per-call FM_ROOT_OVERRIDE still wins where a
# suite sets its own (e.g. the watcher-lock guard-banner cases).
if [ -z "${FM_ROOT_OVERRIDE:-}" ]; then
  FM_ROOT_OVERRIDE="$(fm_test_tmproot fm-wake-tangle-root)"
  export FM_ROOT_OVERRIDE
fi

# Wedge-alarm notifier recorder (safety seam). The away-mode wedge alarm fires a
# real OS-level desktop notification by default. Point its FM_WEDGE_ALARM_EXEC
# seam at a recorder for every
# daemon/wake suite, so no test - present or future - can post a real macOS,
# herdr, or command: notification: it is impossible to forget, because sourcing this harness
# installs it. The recorder is an on-disk script (a real daemon a test spawns
# inherits the path and records too). It logs "<channel>\t<summary>" to
# $FM_WEDGE_ALARM_LOG, which a test sets to its own file to assert on; unset means
# /dev/null. FM_WEDGE_ALARM_FAIL=<channel> makes the recorder exit non-zero for
# that channel, to exercise graceful degradation. Suites that do not source this
# harness still cannot fire a real notification: the daemon defaults the seam to
# "discard" whenever it is sourced (its library-mode guard).
# Create the recorder dir with mktemp directly (not fm_test_tmproot, whose
# first call installs an EXIT trap that, invoked inside a command-substitution
# subshell, would delete the dir on subshell exit). Register it for the same
# cleanup and install the trap in THIS shell if it is the first registration.
_fm_wedge_rec_dir=$(mktemp -d "${TMPDIR:-/tmp}/fm-wedge-rec.XXXXXX")
if [ "${#FM_TEST_CLEANUP_DIRS[@]}" -eq 0 ]; then trap fm_test_cleanup EXIT; fi
FM_TEST_CLEANUP_DIRS+=("$_fm_wedge_rec_dir")
cat > "$_fm_wedge_rec_dir/rec" <<'REC'
#!/usr/bin/env bash
printf '%s\t%s\n' "${1:-}" "${2:-}" >> "${FM_WEDGE_ALARM_LOG:-/dev/null}"
case " ${FM_WEDGE_ALARM_FAIL:-} " in *" ${1:-} "*) exit 1 ;; esac
exit 0
REC
chmod +x "$_fm_wedge_rec_dir/rec"
export FM_WEDGE_ALARM_EXEC="$_fm_wedge_rec_dir/rec"

# append_wake <state> <kind> <key> <payload>: append a wake record to the durable
# queue in a subshell scoped to <state>, using the production wake library.
append_wake() {
  local state=$1 kind=$2 key=$3 payload=$4 lib="$ROOT/bin/fm-wake-lib.sh"
  FM_STATE_OVERRIDE="$state" bash -c '
    # shellcheck disable=SC1090,SC1091
    . "$1"
    fm_wake_append "$2" "$3" "$4"
  ' _ "$lib" "$kind" "$key" "$payload"
}

make_case() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "list-windows" ]; then
  if [ -n "${FM_FAKE_TMUX_WINDOW:-}" ]; then
    printf '%s\n' "${FM_FAKE_TMUX_WINDOW#*:}"
  fi
  exit 0
fi
if [ "${1:-}" = "capture-pane" ]; then
  if [ -n "${FM_FAKE_TMUX_CAPTURE:-}" ]; then
    cat "$FM_FAKE_TMUX_CAPTURE"
  fi
  exit 0
fi
if [ "${1:-}" = "display-message" ]; then
  case "$*" in
    *pane_current_command*) printf '%s\n' "${FM_FAKE_TMUX_CURRENT_COMMAND:-}"; exit 0 ;;
  esac
fi
exit 1
SH
  chmod +x "$fakebin/tmux"
  make_fake_crew_state "$fakebin" >/dev/null
  printf '%s\n' "$dir"
}

# Install a hermetic fake fm-crew-state.sh into <fakebin> and echo its path. The
# watcher's absorb-only-when-provably-working triage calls this (via
# FM_CREW_STATE_BIN) to read a crew's current state on no-verb signal and stale
# paths; the fake returns a canned "state: <s> · source: <src> · <detail>"
# verdict line so a test can fix the provably-working decision without a real
# worktree or no-mistakes.
# A per-id override FM_FAKE_CREW_STATE_<sanitized-id> wins; otherwise the shared
# FM_FAKE_CREW_STATE; otherwise an unknown verdict (NOT provably working), the
# safe default so a test that forgets to set one surfaces rather than absorbs.
make_fake_crew_state() {  # <fakebin>
  local fakebin=$1
  cat > "$fakebin/fm-crew-state.sh" <<'SH'
#!/usr/bin/env bash
set -u
id=${1:-}
key=$(printf '%s' "$id" | tr -c 'A-Za-z0-9' '_')
var="FM_FAKE_CREW_STATE_$key"
val=${!var:-${FM_FAKE_CREW_STATE:-}}
printf '%s\n' "${val:-state: unknown · source: none · fake default}"
exit 0
SH
  chmod +x "$fakebin/fm-crew-state.sh"
  printf '%s\n' "$fakebin/fm-crew-state.sh"
}

make_supercase() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  display-message)
    [ "${FM_FAKE_TMUX_PANE_ALIVE:-1}" = "1" ] || exit 1
    _print=0
    # Return cursor_y when the format asks for it (pane_input_pending).
    for _a in "$@"; do
      case "$_a" in *cursor_y*) printf '%s\n' "${FM_FAKE_TMUX_CURSOR_Y:-0}"; exit 0 ;; esac
      [ "$_a" = "-p" ] && _print=1
    done
    [ "$_print" = 1 ] && printf 'fakepane\n'
    exit 0 ;;
  list-windows)
    [ -n "${FM_FAKE_TMUX_WINDOW:-}" ] && printf '%s\n' "$FM_FAKE_TMUX_WINDOW"
    exit 0 ;;
  capture-pane)
    # Honor a single-line band capture (-S N -E M, both non-negative) for the
    # composer reader's non-bordered compatibility fallback; otherwise (e.g. its
    # structural full-pane scan or fm_pane_is_busy's "-S -40" tail) return the whole capture. -e is accepted and
    # ignored: this fake emits plain text, which the dim-stripper passes through.
    _S=""; _E=""; shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -S) _S="${2:-}"; shift 2; continue ;;
        -E) _E="${2:-}"; shift 2; continue ;;
        *) shift ;;
      esac
    done
    [ -n "${FM_FAKE_TMUX_CAPTURE:-}" ] || exit 0
    if [ -n "$_S" ] && [ -n "$_E" ]; then
      case "$_S$_E" in
        *[!0-9]*) cat "$FM_FAKE_TMUX_CAPTURE" 2>/dev/null ;;
        *) sed -n "$((_S + 1)),$((_E + 1))p" "$FM_FAKE_TMUX_CAPTURE" 2>/dev/null ;;
      esac
    else
      cat "$FM_FAKE_TMUX_CAPTURE" 2>/dev/null
    fi
    exit 0 ;;
  send-keys)
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -l) shift; [ "$#" -gt 0 ] && {
          printf '%s\n' "$1" >> "${FM_FAKE_TMUX_SENT:-/dev/null}"
          # Reflect sent text into capture so pane_input_pending sees it as
          # pending input (text in the composer).
          [ -n "${FM_FAKE_TMUX_CAPTURE:-}" ] && printf '%s\n' "$1" >> "$FM_FAKE_TMUX_CAPTURE"
        } ;;
        Enter)
          # Optionally swallow Enter (file-based flag) to test the retry path.
          if [ -n "${FM_FAKE_TMUX_SWALLOW_FILE:-}" ] && [ -f "$FM_FAKE_TMUX_SWALLOW_FILE" ]; then
            rm -f "$FM_FAKE_TMUX_SWALLOW_FILE"
          else
            printf '[ENTER]\n' >> "${FM_FAKE_TMUX_SENT:-/dev/null}"
            # Enter submits: clear the last line (the typed text) from the
            # capture, simulating the composer being cleared on submit.
            if [ -n "${FM_FAKE_TMUX_CAPTURE:-}" ] && [ -s "$FM_FAKE_TMUX_CAPTURE" ]; then
              _tmp=$(mktemp 2>/dev/null) || _tmp="${FM_FAKE_TMUX_CAPTURE}.tmp"
              sed '$d' "$FM_FAKE_TMUX_CAPTURE" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$FM_FAKE_TMUX_CAPTURE"
              rm -f "$_tmp" 2>/dev/null
            fi
          fi
          ;;
      esac
      shift
    done
    exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/tmux"
  printf '%s\n' "$dir"
}

make_bordered_case() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"; fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  printf '╭─────╮\n│ >   │\n╰─────╯\n' > "$dir/composer"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
COMPOSER="${FM_FAKE_COMPOSER:?FM_FAKE_COMPOSER unset}"
write_composer() {
  text=$1
  width=$((${#text} + 4))
  border=
  i=0
  while [ "$i" -lt "$width" ]; do
    border="${border}─"
    i=$((i + 1))
  done
  printf '╭%s╮\n│ > %s │\n╰%s╯\n' "$border" "$text" "$border" > "$COMPOSER"
}
case "${1:-}" in
  display-message)
    print=0
    for a in "$@"; do case "$a" in *cursor_y*) printf '1\n'; exit 0 ;; esac; done
    for a in "$@"; do [ "$a" = "-p" ] && print=1; done
    [ "$print" = 1 ] && printf 'fakepane\n'
    exit 0 ;;
  capture-pane) cat "$COMPOSER" 2>/dev/null; exit 0 ;;
  list-windows) exit 0 ;;
  send-keys)
    shift
    text=""; is_enter=0; lit=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) shift ;;
        -l) lit=1 ;;
        Enter) is_enter=1 ;;
        *) [ "$lit" = 1 ] && text="$1" ;;
      esac
      shift
    done
    if [ "$is_enter" = 1 ]; then
      if [ -n "${FM_FAKE_SWALLOW:-}" ] && [ -f "$FM_FAKE_SWALLOW" ]; then
        [ "${FM_FAKE_PERSIST_SWALLOW:-0}" = 1 ] || rm -f "$FM_FAKE_SWALLOW"
      else
        [ -n "${FM_FAKE_SENT:-}" ] && printf '[ENTER]\n' >> "$FM_FAKE_SENT"
        write_composer ""
      fi
    elif [ "$lit" = 1 ]; then
      [ "${FM_FAKE_SEND_FAIL:-0}" = 1 ] && exit 1
      [ -n "${FM_FAKE_SENT:-}" ] && printf '%s\n' "$text" >> "$FM_FAKE_SENT"
      write_composer "$text"
    fi
    exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/tmux"
  printf '%s\n' "$dir"
}

wait_for_exit() {
  local pid=$1 limit=${2:-50} i=0
  fm_wake_track "$pid"
  while [ "$i" -lt "$limit" ]; do
    if ! is_live_non_zombie "$pid"; then
      wait "$pid"
      return "$?"
    fi
    sleep 0.1
    i=$((i + 1))
  done
  # Timed out. Take the whole tree down, not just $pid: its children inherited
  # this suite's stderr, so orphaning them holds the run's output pipe open long
  # after the suite has exited (see the reaping notes below).
  fm_wake_reap_tree "$pid"
  wait "$pid" 2>/dev/null || true
  return 124
}

is_live_non_zombie() {
  local pid=$1 stat
  fm_wake_track "$pid"
  kill -0 "$pid" 2>/dev/null || return 1
  stat=$(ps -p "$pid" -o stat= 2>/dev/null || true)
  case "$stat" in
    Z*) return 1 ;;
  esac
  return 0
}

# --- background-process reaping ---------------------------------------------
#
# The suites sourcing this harness spawn real watchers, arms and daemons. A test
# that exits while one is still running does not merely leak a process: that
# child inherited the test's stderr, which under bin/fm-test-run.sh's serial
# path is the write end of the pipe `tee` reads. `tee` then never sees EOF, so
# the RUN parks indefinitely - long after the test itself exited and printed its
# verdict - and every later script waits behind it. That is how one failed
# assertion in tests/fm-watcher-lock.test.sh wedged a whole validation run: a
# red test must still end the run.
#
# TERM first, and wait for it: bin/fm-watch-arm.sh tears its own watcher child
# down from its TERM trap. KILL is the last resort for whatever has not gone by
# FM_TEST_REAP_GRACE.
FM_TEST_REAP_GRACE=${FM_TEST_REAP_GRACE:-5}

# Bash's job table is bookkeeping, not an inventory of what a suite spawned: a
# job leaves it the moment it is `wait`ed, and it never named that job's own
# children at all. Either way the process is still alive and still holding the
# run's output pipe. The PROCESS GROUP is the durable key instead - descendants
# inherit it, and it survives both the leader's death and re-parenting to init.
# Monitor mode is what makes it usable: with it every background job becomes its
# own group leader (pgid == the job's own pid), so a group names exactly one
# suite job and everything that job started. Enable it before any suite spawns.
set -m

# Every pgid decision below is gated on knowing this shell's OWN group, because
# that group holds bin/fm-test-run.sh and the `tee` reading this suite's output.
# An unreadable or non-numeric answer is normalised to empty, and empty means the
# pgid path is skipped entirely rather than compared against nothing: the guard
# fails closed, back to pid-scoped reaping.
FM_TEST_SELF_PGID=$(ps -p "$$" -o pgid= 2>/dev/null | tr -d '[:space:]')
case "$FM_TEST_SELF_PGID" in ''|*[!0-9]*) FM_TEST_SELF_PGID= ;; esac
FM_TEST_REAP_PGIDS=" "
FM_TEST_REAP_SEEN=" "

# fm_wake_process_table: one snapshot of the live process table, columns in a
# fixed order: PID PGID PPID STAT. Every walk below indexes those positions, so
# the order is settled here and nowhere else - in a reaper, reading a ppid where
# a pgid was meant is not a style slip, it signals the wrong processes.
fm_wake_process_table() {
  ps -A -o pid= -o pgid= -o ppid= -o stat= 2>/dev/null || true
}

# fm_wake_track <pid>...: fold each pid's process group into the reap inventory.
#
# A group is recorded only when the pid is a LIVE DIRECT CHILD of this shell, so
# the inventory can never name a group this suite does not own - the guard that
# matters, because a stray reap would reach a sibling firstmate home's real
# watcher. A group id outlives the child that leads it, so a recorded group stays
# for the rest of the suite - see the note below on that being append-only. Each
# pid is inspected once - but only once it HAS been inspected: an unreadable
# process table leaves a pid unseen so the next observation retries it, rather
# than forfeiting its group for good.
fm_wake_track() {
  local pid fresh table line pgid ppid
  # Monitor mode may be inactive, or this shell's own group unreadable: either
  # way a job's group is not provably distinct from the one holding the runner
  # and its `tee`. Record nothing - the pid walk still covers jobs and children.
  [ -n "$FM_TEST_SELF_PGID" ] || return 0
  fresh=
  for pid in "$@"; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    case "$FM_TEST_REAP_SEEN" in *" $pid "*) continue ;; esac
    fresh="$fresh $pid"
  done
  [ -n "$fresh" ] || return 0
  table=$(fm_wake_process_table)
  [ -n "$table" ] || return 0
  for pid in $fresh; do
    FM_TEST_REAP_SEEN="$FM_TEST_REAP_SEEN$pid "
    line=$(printf '%s\n' "$table" | awk -v p="$pid" '$1 == p { print $2" "$3; exit }')
    [ -n "$line" ] || continue
    pgid=${line% *}
    ppid=${line#* }
    [ "$ppid" = "$$" ] || continue
    case "$pgid" in ''|*[!0-9]*) continue ;; esac
    [ "$pgid" -gt 1 ] || continue
    [ "$pgid" != "$FM_TEST_SELF_PGID" ] || continue
    case "$FM_TEST_REAP_PGIDS" in *" $pgid "*) continue ;; esac
    FM_TEST_REAP_PGIDS="$FM_TEST_REAP_PGIDS$pgid "
  done
}

# ACCEPTED RISK, recorded deliberately: the pgid inventory above is append-only.
# Nothing removes a group once recorded, so a recorded pgid could in principle be
# recycled by the kernel onto an unrelated group leader and be signalled at
# teardown. The precondition is that the OS wraps the ENTIRE pid space within a
# single suite run - on the order of 100k process creations, against the low
# thousands the heaviest suite here makes - which is why this is accepted rather
# than mitigated. A prune was tried and removed: at teardown an already-empty
# group expands to zero members by itself, and a recycled one is non-empty and so
# would be kept, so pruning changed nothing in either case.
#
# The job table drops a job as soon as it is waited, so record its group first.
wait() {
  fm_wake_track "$@"
  builtin wait "$@"
}

# fm_wake_own_children: this shell's live direct children, by pid.
fm_wake_own_children() {
  fm_wake_process_table | awk -v p="$$" '$3 == p { print $1 }'
}

# fm_wake_reap_members <pgids> <root-pids>: echo every LIVE pid that belongs to
# one of <pgids>, or that is one of <root-pids> or a descendant of them.
#
# Membership is resolved BY PID against the process table - never a pattern
# match, and never a `kill -TERM -<pgid>` group broadcast. `pkill -f
# bin/fm-watch.sh` (or any other -f pattern) matches every firstmate home's
# watcher on this machine, including a sibling home's real supervision.
fm_wake_reap_members() {
  local pgids=$1 roots=$2 table live frontier next seen pid child g
  table=$(fm_wake_process_table)
  # Only pids the table still shows, and never a zombie. A root that has already
  # exited must leave the set: keeping it would defeat the caller's members-empty
  # early return - making every teardown burn the whole grace - and would aim the
  # post-grace KILL at a number the kernel is already free to hand to a stranger.
  live=" $(printf '%s\n' "$table" | awk '$4 !~ /^Z/ { printf "%s ", $1 }')"
  frontier=$roots
  if [ -n "$FM_TEST_SELF_PGID" ]; then
    for g in $pgids; do
      case "$g" in ''|*[!0-9]*) continue ;; esac
      [ "$g" -gt 1 ] || continue
      [ "$g" != "$FM_TEST_SELF_PGID" ] || continue
      frontier="$frontier $(printf '%s\n' "$table" | awk -v x="$g" '$2 == x { printf "%s ", $1 }')"
    done
  fi
  seen=" "
  while [ -n "$frontier" ]; do
    next=
    for pid in $frontier; do
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      [ "$pid" -gt 1 ] || continue
      [ "$pid" != "$$" ] || continue
      case "$live" in *" $pid "*) ;; *) continue ;; esac
      case "$seen" in *" $pid "*) continue ;; esac
      seen="$seen$pid "
      for child in $(printf '%s\n' "$table" | awk -v p="$pid" '$3 == p { print $1 }'); do
        next="$next $child"
      done
    done
    frontier=$next
  done
  seen=${seen# }
  seen=${seen% }
  [ -n "$seen" ] || return 0
  # shellcheck disable=SC2086 # deliberate word split: one pid per line.
  printf '%s\n' $seen
}

# fm_wake_reap_scope <pgids> <root-pids>: take everything in that scope down.
#
# Membership is re-derived on every pass, never reused from one snapshot:
# bin/fm-watch-arm.sh forks its watcher and assigns `child=$!` as two separate
# statements, so a fork that lands after the first look must still be caught.
# CONT before TERM, because a SIGSTOPped process never runs its handler: the
# arm's TERM trap does `kill -TERM "$child"; wait "$child"`, so a stopped watcher
# leaves the arm blocked in `wait` until the grace expires, and the arm is then
# KILLed with the stopped watcher still orphaned onto the run's output pipe.
# Each member is TERMed once; KILL is for whatever is still alive at the grace.
fm_wake_reap_scope() {
  local pgids=$1 roots=$2 deadline members pid signalled
  signalled=" "
  deadline=$((SECONDS + FM_TEST_REAP_GRACE))
  while :; do
    members=$(fm_wake_reap_members "$pgids" "$roots")
    [ -n "$members" ] || return 0
    for pid in $members; do
      case "$signalled" in *" $pid "*) continue ;; esac
      signalled="$signalled$pid "
      kill -CONT "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
    done
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 0.1
  done
  for pid in $(fm_wake_reap_members "$pgids" "$roots"); do
    kill -KILL "$pid" 2>/dev/null || true
  done
}

# fm_wake_reap_tree <pid>...: reap the named processes and everything they
# started, scoped to those pids only - other still-wanted jobs of this suite must
# survive, so this deliberately ignores the suite-wide inventory.
fm_wake_reap_tree() {
  local roots="$*" pgids pid pgid
  pgids=
  if [ -n "$FM_TEST_SELF_PGID" ]; then
    for pid in $roots; do
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      pgid=$(ps -p "$pid" -o pgid= 2>/dev/null | tr -d '[:space:]')
      case "$pgid" in ''|*[!0-9]*) continue ;; esac
      [ "$pgid" -gt 1 ] || continue
      [ "$pgid" != "$FM_TEST_SELF_PGID" ] || continue
      pgids="$pgids $pgid"
    done
  fi
  fm_wake_reap_scope "$pgids" "$roots"
}

fm_wake_reap_jobs() {
  local pid kids
  kids=$(fm_wake_own_children)
  # shellcheck disable=SC2086 # deliberate word split: pids are one per line.
  fm_wake_track $kids
  fm_wake_reap_scope "$FM_TEST_REAP_PGIDS" "$kids"
  # Reap exit statuses so no zombie outlives this shell. Only this shell's own
  # children can be waited for; their descendants are not ours to wait on.
  for pid in $kids; do
    wait "$pid" 2>/dev/null || true
  done
}

# Stop surviving background processes BEFORE the registered temp roots are
# removed, then hand off to the library's own dir cleanup.
fm_wake_test_cleanup() {
  fm_wake_reap_jobs
  fm_test_cleanup
}

trap fm_wake_test_cleanup EXIT

hash_text() {
  if command -v md5 >/dev/null 2>&1; then
    printf '%s' "$1" | md5 -q
  else
    printf '%s' "$1" | md5sum | cut -d' ' -f1
  fi
}

dead_pid() {
  local p=999999
  while kill -0 "$p" 2>/dev/null; do
    p=$((p + 1))
  done
  printf '%s\n' "$p"
}
