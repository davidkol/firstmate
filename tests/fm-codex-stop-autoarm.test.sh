#!/usr/bin/env bash
# Behavior tests for the Codex Stop-owned background wake
# (bin/fm-codex-stop-autoarm.sh, docs/supervision-protocols/codex.md).
#
# The hook fires as a Codex Stop command hook. These tests run it hermetically as
# a child of a fake harness (a bash symlink named "codex", reached by absolute
# path and NOT on PATH) whose pid is written into the fixture home's state/.lock.
# A separate recording shim named "codex" IS on PATH, so `codex queue` is captured
# without a real conversation, model, or fleet state. The arm wrapper is a
# per-test fixture, so no real watcher runs.
# shellcheck disable=SC2016 # single quotes are deliberate: $FM_HOME expands inside the fake harness child, and grep needles are literal strings
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-codex-stop-autoarm)
fm_git_identity fmtest fmtest@example.invalid

# This suite detaches REAL supervisors, which survive their parent by design, so
# a failed assertion that skips a test's own reap would otherwise leave one
# parked for ten minutes holding a home lock and an arm child. Reap only
# processes anchored under THIS run's tmproot, then delegate to the shared dir
# cleanup as tests/lib.sh requires of a suite with its own EXIT trap.
codex_autoarm_suite_cleanup() {
  local sig pid
  for sig in TERM KILL; do
    for pid in $(pgrep -f "$TMP_ROOT/.*fm-codex-stop-autoarm.sh --supervise" 2>/dev/null || true); do
      kill -"$sig" "$pid" 2>/dev/null || true
    done
    [ "$sig" = TERM ] && sleep 0.3
  done
  fm_test_cleanup
}
trap codex_autoarm_suite_cleanup EXIT

# The ancestry harness must NOT be the `codex` that PATH resolves, because the
# hook shells the real subcommand for delivery. Keep the two apart.
HARNESSBIN="$TMP_ROOT/harnessbin"
mkdir -p "$HARNESSBIN"
ln -s /bin/bash "$HARNESSBIN/codex"
FAKE_CODEX_HARNESS="$HARNESSBIN/codex"
export FAKE_CODEX_HARNESS

FAKEBIN=$(fm_fakebin "$TMP_ROOT/fakebin")

# Recording `codex` shim. Each queue call writes <dir>/<n>.thread and
# <dir>/<n>.message, so a multi-line wake body survives intact instead of being
# flattened into a single log line.
write_codex_shim() {  # <record-dir> [exit-code]
  local dir=$1 rc=${2:-0}
  cat > "$FAKEBIN/codex" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = queue ]; then
  thread=
  message=
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --thread) thread=\$2; shift 2 ;;
      --message) message=\$2; shift 2 ;;
      *) shift ;;
    esac
  done
  mkdir -p '$dir'
  n=1
  while [ -e '$dir'/"\$n".thread ]; do n=\$((n + 1)); done
  printf '%s' "\$thread" > '$dir'/"\$n".thread
  printf '%s' "\$message" > '$dir'/"\$n".message
  exit $rc
fi
exit 0
SH
  chmod +x "$FAKEBIN/codex"
}

queue_calls() {  # <record-dir>
  local dir=$1 n=0
  while [ -e "$dir/$((n + 1)).thread" ]; do n=$((n + 1)); done
  printf '%s\n' "$n"
}

install_autoarm_scripts() {
  local dir=$1 f
  mkdir -p "$dir/bin"
  for f in fm-codex-stop-autoarm.sh fm-codex-detach.sh fm-primary-scope-lib.sh \
           fm-supervision-lib.sh fm-wake-lib.sh fm-session-lock-lib.sh \
           fm-lock.sh fm-operational-input.sh fm-harness.sh \
           fm-turnend-guard.sh fm-supervision-instructions.sh; do
    cp "$ROOT/bin/$f" "$dir/bin/$f"
  done
  mkdir -p "$dir/docs"
  cp -R "$ROOT/docs/supervision-protocols" "$dir/docs/supervision-protocols"
  chmod +x "$dir/bin/fm-codex-stop-autoarm.sh" "$dir/bin/fm-codex-detach.sh" \
           "$dir/bin/fm-lock.sh" "$dir/bin/fm-operational-input.sh" "$dir/bin/fm-harness.sh" \
           "$dir/bin/fm-turnend-guard.sh" "$dir/bin/fm-supervision-instructions.sh"
}

make_primary_dir() {
  local dir=$1
  mkdir -p "$dir/state" "$dir/config"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
  install_autoarm_scripts "$dir"
  printf '%s\n' "$dir"
}

make_crewmate_worktree_dir() {
  local base=$1 dir=$2
  fm_git_worktree "$base" "$dir" fm/codex-autoarm-test-branch
  mkdir -p "$dir/state" "$dir/config"
  : > "$dir/AGENTS.md"
  install_autoarm_scripts "$dir"
  printf '%s\n' "$dir"
}

# Arm fixtures, installed per test as <dir>/bin/fm-watch-arm.sh.
write_arm_fixture() {  # <dir> <kind>
  local dir=$1 kind=$2
  case "$kind" in
    actionable)
      cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$FM_HOME/state/arm-ran"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
printf 'signal: fixture actionable event\n'
exit 0
SH
      ;;
    slow-actionable)
      cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$FM_HOME/state/arm-ran"
sleep "${FM_TEST_ARM_SLEEP:-3}"
printf 'signal: fixture actionable event after wait\n'
exit 0
SH
      ;;
    afk-midcycle)
      cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$FM_HOME/state/arm-ran"
: > "$FM_HOME/state/.afk"
printf 'signal: fixture actionable event\n'
exit 0
SH
      ;;
    failed)
      cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$FM_HOME/state/arm-ran"
printf 'watcher: FAILED - no live watcher with a fresh beacon\n'
exit 1
SH
      ;;
    hang)
      cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$FM_HOME/state/arm-ran"
sleep 600
SH
      ;;
  esac
  chmod +x "$dir/bin/fm-watch-arm.sh"
}

# Run the hook as a child of the fake harness holding the fixture home's lock.
run_autoarm() {  # <dir> <session-id>
  local dir=$1 session=$2 rc=0
  printf '{"session_id":"%s","stop_hook_active":false}' "$session" \
    | FM_HOME="$dir" PATH="$FAKEBIN:$PATH" "$FAKE_CODEX_HARNESS" -c '
        printf "%s\n" "$$" > "$FM_HOME/state/.lock"
        "$FM_HOME/bin/fm-codex-stop-autoarm.sh"
      ' 2>&1 || rc=$?
  return "$rc"
}

# Wait until <file> exists (or the deadline passes). Returns 1 on timeout.
wait_for_file() {  # <path> [deciseconds]
  local path=$1 limit=${2:-100} i=0
  while [ "$i" -lt "$limit" ]; do
    [ -e "$path" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  [ -e "$path" ]
}

binding_field() {  # <dir> <field>
  sed -n "s/^$2=//p" "$1/state/.codex-autoarm-session" 2>/dev/null | head -1
}

wait_for_supervisor_exit() {  # <dir> [deciseconds]
  local dir=$1 limit=${2:-120} i=0 pid
  pid=$(binding_field "$dir" pid)
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  while [ "$i" -lt "$limit" ]; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
    i=$((i + 1))
  done
  ! kill -0 "$pid" 2>/dev/null
}

wait_for_binding_outcome() {  # <dir> <outcome> [deciseconds]
  local dir=$1 want=$2 limit=${3:-120} i=0
  while [ "$i" -lt "$limit" ]; do
    [ "$(binding_field "$dir" outcome)" = "$want" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  [ "$(binding_field "$dir" outcome)" = "$want" ]
}

# Run the record's real consumer: the same Stop-event turn-end guard this home
# would run, on the binding the supervisor actually left behind.
run_guard_codex() {  # <dir> <session-id> [stop-hook-active]
  local dir=$1 session=$2 stop_active=${3:-false} home
  home=$(cd "$dir" && pwd)
  printf '{"cwd":"%s","session_id":"%s","stop_hook_active":%s}' "$home" "$session" "$stop_active" \
    | FM_HOME="$home" FM_CODEX_AUTOARM_SYNC_WAIT_MS=300 \
      bash "$dir/bin/fm-turnend-guard.sh" --codex 2>&1
}

guard_refused() {  # <guard-output> <message>
  local out=$1 message=$2 reason
  reason=$(printf '%s' "$out" | jq -r '.reason' 2>/dev/null || true)
  case "$reason" in
    *"watcher supervision needs Stop-owned automatic recovery"*) return 0 ;;
  esac
  fail "$message (guard output: ${out:-<empty>})"
}

# Break ONLY the supervisor's own wake encoding, so the guard's separate
# turn-end-guard encoding still works and its refusal keeps its typed shape.
write_failing_wake_encoder() {  # <dir>
  cat > "$1/bin/fm-operational-input.sh" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = encode ] && [ "\${2:-}" = watcher ]; then
  exit 1
fi
exec '$ROOT/bin/fm-operational-input.sh' "\$@"
SH
  chmod +x "$1/bin/fm-operational-input.sh"
}

# Arm output files a supervisor mktemp'd in this home's state directory.
arm_output_count() {  # <dir>
  local f n=0
  for f in "$1"/state/.codex-autoarm-output.*; do
    [ -e "$f" ] && n=$((n + 1))
  done
  printf '%s\n' "$n"
}

wait_for_arm_output() {  # <dir> [deciseconds]
  local dir=$1 limit=${2:-100} i=0
  while [ "$i" -lt "$limit" ]; do
    [ "$(arm_output_count "$dir")" -gt 0 ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  [ "$(arm_output_count "$dir")" -gt 0 ]
}

# Terminate any supervisor a test left running, so a fixture cannot outlive it.
reap_supervisor() {  # <dir>
  local pid
  pid=$(binding_field "$1" pid)
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  kill -TERM "$pid" 2>/dev/null || true
  sleep 0.3
  kill -KILL "$pid" 2>/dev/null || true
}

# --- inert gates -------------------------------------------------------------

test_hook_is_inert_in_a_child_worktree() {
  local base dir
  base=$(make_primary_dir "$TMP_ROOT/scope-base")
  dir=$(make_crewmate_worktree_dir "$base" "$TMP_ROOT/scope-child")
  write_arm_fixture "$dir" actionable
  write_codex_shim "$dir/state/queued"
  : > "$dir/state/task1.meta"
  run_autoarm "$dir" sess-scope
  sleep 0.5
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed inside a child task worktree"
  [ "$(queue_calls "$dir/state/queued")" -eq 0 ] \
    || fail "auto-arm queued a wake from a child task worktree"
  pass "fm-codex-stop-autoarm: inert inside a crewmate worktree"
}

test_hook_is_inert_without_a_session_id() {
  local dir
  dir=$(make_primary_dir "$TMP_ROOT/no-session")
  write_arm_fixture "$dir" actionable
  write_codex_shim "$dir/state/queued"
  : > "$dir/state/task1.meta"
  printf '{"stop_hook_active":false}' \
    | FM_HOME="$dir" PATH="$FAKEBIN:$PATH" "$FAKE_CODEX_HARNESS" -c '
        printf "%s\n" "$$" > "$FM_HOME/state/.lock"
        "$FM_HOME/bin/fm-codex-stop-autoarm.sh"
      ' >/dev/null 2>&1
  sleep 0.5
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed with no conversation to wake"
  pass "fm-codex-stop-autoarm: inert when the Stop payload carries no session id"
}

test_hook_is_inert_for_an_idle_home() {
  local dir
  dir=$(make_primary_dir "$TMP_ROOT/idle-home")
  write_arm_fixture "$dir" actionable
  write_codex_shim "$dir/state/queued"
  run_autoarm "$dir" sess-idle
  sleep 0.5
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed a home with no work in flight"
  pass "fm-codex-stop-autoarm: inert for an idle home"
}

test_hook_is_inert_while_away_mode_is_active() {
  local dir
  dir=$(make_primary_dir "$TMP_ROOT/afk-home")
  write_arm_fixture "$dir" actionable
  write_codex_shim "$dir/state/queued"
  : > "$dir/state/task1.meta"
  : > "$dir/state/.afk"
  run_autoarm "$dir" sess-afk
  sleep 0.5
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed while the away daemon owns supervision"
  pass "fm-codex-stop-autoarm: inert while away mode is active"
}

test_hook_is_inert_when_another_live_session_holds_the_lock() {
  local dir
  dir=$(make_primary_dir "$TMP_ROOT/foreign-lock")
  write_arm_fixture "$dir" actionable
  write_codex_shim "$dir/state/queued"
  : > "$dir/state/task1.meta"
  # A live foreign harness pid: this session's hook must not arm or wake.
  "$FAKE_CODEX_HARNESS" -c 'printf "%s\n" "$$" > "$1/state/.lock"; sleep 30' _ "$dir" &
  local foreign=$!
  sleep 0.5
  printf '{"session_id":"sess-foreign","stop_hook_active":false}' \
    | FM_HOME="$dir" PATH="$FAKEBIN:$PATH" "$FAKE_CODEX_HARNESS" -c \
        '"$FM_HOME/bin/fm-codex-stop-autoarm.sh"' >/dev/null 2>&1
  sleep 0.5
  kill "$foreign" 2>/dev/null || true
  wait "$foreign" 2>/dev/null || true
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed while another live session held the lock"
  pass "fm-codex-stop-autoarm: inert while another live session holds the home lock"
}

test_hook_is_inert_without_a_codex_delivery_command() {
  local dir emptybin
  dir=$(make_primary_dir "$TMP_ROOT/no-codex")
  write_arm_fixture "$dir" actionable
  : > "$dir/state/task1.meta"
  emptybin="$TMP_ROOT/emptybin"
  mkdir -p "$emptybin"
  # A cycle whose wake could never be delivered must not look armed to the guard.
  printf '{"session_id":"sess-nocodex","stop_hook_active":false}' \
    | FM_HOME="$dir" PATH="$emptybin:/usr/bin:/bin" "$FAKE_CODEX_HARNESS" -c '
        printf "%s\n" "$$" > "$FM_HOME/state/.lock"
        "$FM_HOME/bin/fm-codex-stop-autoarm.sh"
      ' >/dev/null 2>&1
  sleep 0.5
  [ ! -e "$dir/state/arm-ran" ] || fail "auto-arm armed with no way to deliver the wake"
  [ ! -f "$dir/state/.codex-autoarm-session" ] \
    || fail "auto-arm claimed the home with no way to deliver the wake"
  pass "fm-codex-stop-autoarm: inert when codex cannot deliver a wake"
}

# --- the delivery path -------------------------------------------------------

test_hook_returns_at_once_and_the_detached_supervisor_delivers_the_wake() {
  local dir q start elapsed thread message decoded kind
  dir=$(make_primary_dir "$TMP_ROOT/deliver")
  q="$dir/state/queued"
  write_arm_fixture "$dir" slow-actionable
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  start=$(date +%s)
  FM_TEST_ARM_SLEEP=3 run_autoarm "$dir" sess-deliver
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -le 2 ] \
    || fail "the Stop hook blocked for ${elapsed}s instead of returning at once"

  wait_for_file "$q/1.message" 120 || fail "the detached supervisor never delivered a wake"
  thread=$(cat "$q/1.thread")
  message=$(cat "$q/1.message")
  [ "$thread" = sess-deliver ] \
    || fail "wake was queued against '$thread', not the conversation that emitted the Stop"
  kind=$(printf '%s' "$message" | "$ROOT/bin/fm-operational-input.sh" kind) \
    || fail "wake was not a current operational input: $message"
  [ "$kind" = watcher ] || fail "wake carried kind '$kind', not watcher"
  decoded=$(printf '%s' "$message" | "$ROOT/bin/fm-operational-input.sh" body)
  assert_contains "$decoded" "bin/fm-wake-drain.sh" "wake body must direct the drain first"
  assert_contains "$decoded" "signal: fixture actionable event after wait" \
    "wake body must carry the real watcher reason line"
  [ "$(queue_calls "$q")" -eq 1 ] || fail "supervisor delivered more than one wake for one cycle"
  pass "fm-codex-stop-autoarm: hook returns at once and the detached supervisor delivers one marked wake"
}

# The binding is what lets a turn-end guard allow a stop, so a publication that
# succeeded and one that failed must never leave the same record.
test_a_published_wake_is_recorded_and_the_guard_accepts_it() {
  local dir q out status
  dir=$(make_primary_dir "$TMP_ROOT/wake-published")
  q="$dir/state/queued"
  write_arm_fixture "$dir" actionable
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-published
  wait_for_binding_outcome "$dir" wake \
    || fail "a successful publication recorded outcome '$(binding_field "$dir" outcome)'"
  [ "$(queue_calls "$q")" -eq 1 ] || fail "the supervisor did not publish exactly one wake"
  out=$(run_guard_codex "$dir" sess-published); status=$?
  expect_code 0 "$status" "the guard must allow the stop whose wake was published"
  [ -z "$out" ] || fail "the guard refused a published wake: $out"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a published wake is recorded as such and the guard accepts it"
}

test_an_unencodable_wake_is_recorded_unpublished_and_the_guard_refuses_it() {
  local dir q out status reason
  dir=$(make_primary_dir "$TMP_ROOT/wake-unencodable")
  q="$dir/state/queued"
  write_arm_fixture "$dir" actionable
  write_codex_shim "$q"
  write_failing_wake_encoder "$dir"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-unencodable
  wait_for_binding_outcome "$dir" wake-unpublished \
    || fail "an unencodable wake recorded outcome '$(binding_field "$dir" outcome)'"
  [ "$(queue_calls "$q")" -eq 0 ] \
    || fail "an unencodable wake was still handed to codex queue"
  out=$(run_guard_codex "$dir" sess-unencodable); status=$?
  expect_code 0 "$status" "the guard must still emit its structured continuation"
  reason=$(printf '%s' "$out" | jq -r '.reason')
  assert_contains "$reason" "watcher supervision needs Stop-owned automatic recovery" \
    "a wake that was never encoded must not allow a blind stop"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: an unencodable wake records unpublished and the guard refuses it"
}

test_a_failed_queue_publication_is_recorded_unpublished_and_the_guard_refuses_it() {
  local dir q out status reason
  dir=$(make_primary_dir "$TMP_ROOT/wake-queue-failed")
  q="$dir/state/queued"
  write_arm_fixture "$dir" actionable
  write_codex_shim "$q" 1
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-queue-failed
  wait_for_binding_outcome "$dir" wake-unpublished \
    || fail "a failed publication recorded outcome '$(binding_field "$dir" outcome)'"
  [ "$(queue_calls "$q")" -eq 1 ] \
    || fail "the failing publication was never attempted"
  out=$(run_guard_codex "$dir" sess-queue-failed); status=$?
  expect_code 0 "$status" "the guard must still emit its structured continuation"
  reason=$(printf '%s' "$out" | jq -r '.reason')
  assert_contains "$reason" "watcher supervision needs Stop-owned automatic recovery" \
    "a wake codex queue rejected must not allow a blind stop"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a rejected publication records unpublished and the guard refuses it"
}

test_quiet_idle_produces_no_wake_and_no_repeat_delivery() {
  local dir q before after
  dir=$(make_primary_dir "$TMP_ROOT/quiet")
  q="$dir/state/queued"
  write_arm_fixture "$dir" hang
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-quiet
  wait_for_file "$dir/state/arm-ran" 60 || fail "the detached supervisor never armed"
  before=$(date +%s)
  sleep 3
  after=$(date +%s)
  [ "$((after - before))" -ge 3 ] || fail "quiet window was not observed"
  [ "$(queue_calls "$q")" -eq 0 ] || fail "a quiet idle cycle published a wake"
  [ "$(wc -l < "$dir/state/arm-ran")" -eq 1 ] \
    || fail "a quiet idle cycle re-ran the arm instead of waiting"
  [ "$(binding_field "$dir" outcome)" = arming ] \
    || fail "a waiting supervisor did not record the arming outcome"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a quiet idle cycle waits without publishing anything"
}

test_repeat_stop_from_the_same_conversation_does_not_start_a_second_supervisor() {
  local dir first second
  dir=$(make_primary_dir "$TMP_ROOT/same-session")
  write_arm_fixture "$dir" hang
  write_codex_shim "$dir/state/queued"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-same
  wait_for_file "$dir/state/arm-ran" 60 || fail "the first supervisor never armed"
  first=$(binding_field "$dir" pid)
  run_autoarm "$dir" sess-same
  sleep 1
  second=$(binding_field "$dir" pid)
  [ "$first" = "$second" ] \
    || fail "a second Stop from the same conversation replaced supervisor $first with $second"
  [ "$(wc -l < "$dir/state/arm-ran")" -eq 1 ] \
    || fail "a second Stop from the same conversation started a second arm"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a repeat Stop from the same conversation reuses the live supervisor"
}

# Retirement signals a supervisor that is still mid-arm, so its own arm output
# must go with it. Otherwise every conversation restart while work is in flight
# orphans one file in the home's state directory for the life of the home.
test_a_retired_supervisor_removes_its_own_arm_output() {
  local dir first leftover q
  dir=$(make_primary_dir "$TMP_ROOT/retire-output")
  q="$dir/state/queued"
  write_arm_fixture "$dir" hang
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-old
  wait_for_file "$dir/state/arm-ran" 60 || fail "the first supervisor never armed"
  wait_for_arm_output "$dir" 60 || fail "the armed supervisor never created its arm output"
  first=$(binding_field "$dir" pid)

  write_arm_fixture "$dir" actionable
  run_autoarm "$dir" sess-new
  wait_for_file "$q/1.thread" 120 || fail "the replacement supervisor never delivered a wake"
  kill -0 "$first" 2>/dev/null && fail "the retired supervisor $first is still running"
  leftover=$(arm_output_count "$dir")
  [ "$leftover" -eq 0 ] \
    || fail "retiring a supervisor orphaned $leftover arm output file(s) in the state directory"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a retired supervisor takes its own arm output with it"
}

test_stop_from_a_new_conversation_retires_the_stale_supervisor() {
  local dir first second q
  dir=$(make_primary_dir "$TMP_ROOT/new-session")
  q="$dir/state/queued"
  write_arm_fixture "$dir" hang
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-old
  wait_for_file "$dir/state/arm-ran" 60 || fail "the first supervisor never armed"
  first=$(binding_field "$dir" pid)

  # A restarted or replaced conversation must own its own wake target, or the
  # wake would be published where nobody is reading.
  write_arm_fixture "$dir" actionable
  run_autoarm "$dir" sess-new
  wait_for_file "$q/1.thread" 120 || fail "the replacement supervisor never delivered a wake"
  second=$(binding_field "$dir" pid)
  [ "$first" != "$second" ] || fail "the stale supervisor was never retired"
  kill -0 "$first" 2>/dev/null && fail "the stale supervisor $first is still running"
  [ "$(cat "$q/1.thread")" = sess-new ] \
    || fail "wake was published to the retired conversation, not the current one"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a Stop from a new conversation retires the stale supervisor and rebinds"
}

test_away_mode_appearing_mid_cycle_suppresses_the_wake() {
  local dir q
  dir=$(make_primary_dir "$TMP_ROOT/afk-mid")
  q="$dir/state/queued"
  write_arm_fixture "$dir" afk-midcycle
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  run_autoarm "$dir" sess-afkmid
  wait_for_file "$dir/state/arm-ran" 60 || fail "the supervisor never armed"
  sleep 1
  [ "$(queue_calls "$q")" -eq 0 ] || fail "a wake was published after away mode took over"
  [ "$(binding_field "$dir" outcome)" = afk ] \
    || fail "the supervisor did not record the away-mode handoff"
  pass "fm-codex-stop-autoarm: away mode appearing mid-cycle suppresses the wake"
}

test_arm_failure_notifies_once_per_episode() {
  local dir q
  dir=$(make_primary_dir "$TMP_ROOT/failure")
  q="$dir/state/queued"
  write_arm_fixture "$dir" failed
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-fail
  wait_for_file "$q/1.message" 120 || fail "a verified arm failure produced no operator notice"
  assert_contains "$(cat "$q/1.message")" "FIRSTMATE WATCHER FAILURE" \
    "the failure notice must name the automatic mechanism failure"
  assert_contains "$(cat "$q/1.message")" "Do not start a manual background arm" \
    "the failure notice must not invite a manual background arm loop"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-fail
  sleep 1
  [ "$(queue_calls "$q")" -eq 1 ] \
    || fail "a continuous failure episode published a repeated notice"
  pass "fm-codex-stop-autoarm: a failure episode notifies exactly once"
}

# The one notice is the whole of the episode's messaging, so every later turn end
# has to stay loud at the guard instead. A supervisor that has merely started
# records outcome=arming within milliseconds, long before its arm can report, so
# treating that as recovery would end the turn blind and silent.
test_a_continuing_failure_episode_stays_loud_at_the_guard() {
  local dir q out
  dir=$(make_primary_dir "$TMP_ROOT/failure-loud")
  q="$dir/state/queued"
  write_arm_fixture "$dir" failed
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-loud
  wait_for_file "$q/1.message" 120 || fail "a verified arm failure produced no operator notice"

  # The next Stop detaches a fresh supervisor that parks in its arm, which is
  # exactly the live-but-unproven state the guard used to accept.
  write_arm_fixture "$dir" hang
  run_autoarm "$dir" sess-loud
  wait_for_binding_outcome "$dir" arming \
    || fail "the second cycle never started a supervisor to judge"
  out=$(run_guard_codex "$dir" sess-loud)
  guard_refused "$out" "a live supervisor ended the turn blind while the failure episode was unresolved"
  [ "$(queue_calls "$q")" -eq 1 ] \
    || fail "the still-unresolved episode published a repeated notice"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: a continuing failure episode keeps the guard loud on later cycles"
}

# One forced continuation per turn: the shared loop guard, not an unbounded nag.
test_the_failure_episode_continuation_is_bounded_to_one_per_turn() {
  local dir q out status home
  dir=$(make_primary_dir "$TMP_ROOT/failure-bounded")
  q="$dir/state/queued"
  write_arm_fixture "$dir" failed
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-bounded
  wait_for_file "$q/1.message" 120 || fail "a verified arm failure produced no operator notice"
  write_arm_fixture "$dir" hang
  run_autoarm "$dir" sess-bounded
  wait_for_binding_outcome "$dir" arming || fail "the second cycle never started a supervisor"

  out=$(run_guard_codex "$dir" sess-bounded false)
  guard_refused "$out" "the unresolved episode did not force its one continuation"
  out=$(run_guard_codex "$dir" sess-bounded true); status=$?
  expect_code 0 "$status" "the stop after a forced continuation must be allowed"
  [ -z "$out" ] || fail "the unresolved episode forced a second continuation in one turn: $out"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: an unresolved episode forces at most one continuation per turn"
}

# The episode marker must not depend on any message getting through, and a notice
# that never published must not consume the episode's one notice.
test_an_unpublishable_failure_notice_does_not_silence_the_episode() {
  local dir q out
  dir=$(make_primary_dir "$TMP_ROOT/failure-unpublished")
  q="$dir/state/queued"
  write_arm_fixture "$dir" failed
  write_codex_shim "$q" 1
  : > "$dir/state/task1.meta"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-nonotice
  wait_for_file "$q/1.thread" 120 || fail "the first notice was never attempted"
  wait_for_supervisor_exit "$dir" || fail "the first supervisor never finished its cycle"
  assert_absent "$dir/state/.codex-autoarm-failure-notified" \
    "a notice that never published was recorded as delivered"

  write_codex_shim "$q"
  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-nonotice
  wait_for_file "$q/2.message" 120 \
    || fail "an unpublishable first notice silenced the episode's later notices"
  assert_contains "$(cat "$q/2.message")" "FIRSTMATE WATCHER FAILURE" \
    "the retried notice must still name the automatic mechanism failure"

  write_arm_fixture "$dir" hang
  run_autoarm "$dir" sess-nonotice
  wait_for_binding_outcome "$dir" arming || fail "the third cycle never started a supervisor"
  out=$(run_guard_codex "$dir" sess-nonotice)
  guard_refused "$out" "an episode whose first notice failed to publish lost its loud guard"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: an unpublishable failure notice neither silences nor suppresses the episode"
}

# Recovery is the only thing that closes an episode, and it returns the home to
# quiet operation: no continuation, no repeated notice.
test_recovery_closes_the_failure_episode_and_the_home_goes_quiet() {
  local dir q out status
  dir=$(make_primary_dir "$TMP_ROOT/failure-recovered")
  q="$dir/state/queued"
  write_arm_fixture "$dir" failed
  write_codex_shim "$q"
  : > "$dir/state/task1.meta"

  FM_CODEX_AUTOARM_ATTEMPTS=1 run_autoarm "$dir" sess-recover
  wait_for_file "$q/1.message" 120 || fail "a verified arm failure produced no operator notice"

  write_arm_fixture "$dir" actionable
  run_autoarm "$dir" sess-recover
  wait_for_binding_outcome "$dir" wake 120 || fail "the recovering cycle never published its wake"
  assert_absent "$dir/state/.codex-autoarm-failure-episode" \
    "an actionable wake left the failure episode open"
  assert_absent "$dir/state/.codex-autoarm-failure-notified" \
    "an actionable wake left the consumed notice marker behind"

  out=$(run_guard_codex "$dir" sess-recover); status=$?
  expect_code 0 "$status" "a recovered home must end its turn without a continuation"
  [ -z "$out" ] || fail "a recovered home still forced a continuation: $out"
  reap_supervisor "$dir"
  pass "fm-codex-stop-autoarm: recovery closes the episode and the home goes quiet"
}

# --- home isolation ----------------------------------------------------------

test_a_second_home_is_never_woken_and_never_consumes_the_first_homes_events() {
  local a b q_a q_b
  a=$(make_primary_dir "$TMP_ROOT/home-a")
  b=$(make_primary_dir "$TMP_ROOT/home-b")
  q_a="$a/state/queued"
  q_b="$b/state/queued"
  write_arm_fixture "$a" actionable
  write_arm_fixture "$b" hang
  : > "$a/state/task1.meta"
  : > "$b/state/task1.meta"

  # Home B arms and parks first, so a leaking wake would be visible on its log.
  write_codex_shim "$q_b"
  run_autoarm "$b" sess-home-b
  wait_for_file "$b/state/arm-ran" 60 || fail "home B never armed"

  write_codex_shim "$q_a"
  run_autoarm "$a" sess-home-a
  wait_for_file "$q_a/1.thread" 120 || fail "home A never delivered its own wake"
  sleep 1

  [ "$(cat "$q_a/1.thread")" = sess-home-a ] \
    || fail "home A woke a conversation other than its own"
  [ "$(queue_calls "$q_b")" -eq 0 ] || fail "home A's event woke home B"
  [ "$(wc -l < "$b/state/arm-ran")" -eq 1 ] \
    || fail "home B's supervisor consumed home A's cycle"
  [ "$(binding_field "$b" session)" = sess-home-b ] \
    || fail "home B's binding was rewritten by home A"
  reap_supervisor "$b"
  pass "fm-codex-stop-autoarm: a second home is neither woken nor drained by the first"
}

test_hook_is_inert_in_a_child_worktree
test_hook_is_inert_without_a_session_id
test_hook_is_inert_for_an_idle_home
test_hook_is_inert_while_away_mode_is_active
test_hook_is_inert_when_another_live_session_holds_the_lock
test_hook_is_inert_without_a_codex_delivery_command
test_hook_returns_at_once_and_the_detached_supervisor_delivers_the_wake
test_a_published_wake_is_recorded_and_the_guard_accepts_it
test_an_unencodable_wake_is_recorded_unpublished_and_the_guard_refuses_it
test_a_failed_queue_publication_is_recorded_unpublished_and_the_guard_refuses_it
test_quiet_idle_produces_no_wake_and_no_repeat_delivery
test_repeat_stop_from_the_same_conversation_does_not_start_a_second_supervisor
test_stop_from_a_new_conversation_retires_the_stale_supervisor
test_a_retired_supervisor_removes_its_own_arm_output
test_away_mode_appearing_mid_cycle_suppresses_the_wake
test_arm_failure_notifies_once_per_episode
test_a_continuing_failure_episode_stays_loud_at_the_guard
test_the_failure_episode_continuation_is_bounded_to_one_per_turn
test_an_unpublishable_failure_notice_does_not_silence_the_episode
test_recovery_closes_the_failure_episode_and_the_home_goes_quiet
test_a_second_home_is_never_woken_and_never_consumes_the_first_homes_events
