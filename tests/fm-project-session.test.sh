#!/usr/bin/env bash
# Behavior tests for one-way project-session prompt custody and launch boundaries.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RUNNER="$ROOT/bin/fm-project-session-run.sh"
LAUNCHER="$ROOT/bin/fm-project-session.sh"
TMP_ROOT=$(fm_test_tmproot fm-project-session)

new_codex_fake() {
  local case_dir=$1 fakebin
  fakebin=$(fm_fakebin "$case_dir")
  cat > "$fakebin/codex" <<'SH'
#!/usr/bin/env bash
set -u
[ ! -e "${FM_FAKE_PROMPT_PATH:?}" ] || exit 91
printf '%s' "$1" > "$FM_FAKE_CAPTURE_DIR/argument-1"
printf '%s' "$2" > "$FM_FAKE_CAPTURE_DIR/argument-2"
printf '%s\n' "$#" > "$FM_FAKE_CAPTURE_DIR/argument-count"
exit "${FM_FAKE_CODEX_EXIT:-0}"
SH
  chmod +x "$fakebin/codex"
  printf '%s\n' "$fakebin"
}

test_runner_preserves_prompt_and_retires_file_before_codex() {
  local case_dir fakebin prompt expected
  case_dir="$TMP_ROOT/runner-bytes"
  mkdir -p "$case_dir/capture"
  fakebin=$(new_codex_fake "$case_dir")
  prompt="$case_dir/private prompt"
  expected="$case_dir/expected"
  # shellcheck disable=SC2016 # The dollar sign is literal prompt custody data.
  printf '%s' 'First line with spaces
Second line has "quotes", a $dollar, and literal newlines.' > "$prompt"
  cp "$prompt" "$expected"

  PATH="$fakebin:$PATH" FM_FAKE_CODEX_EXIT=0 FM_FAKE_PROMPT_PATH="$prompt" \
    FM_FAKE_CAPTURE_DIR="$case_dir/capture" "$RUNNER" "$prompt" \
    || fail 'runner did not return Codex success'

  assert_absent "$prompt" 'runner retained the private prompt file'
  assert_grep '--dangerously-bypass-approvals-and-sandbox' "$case_dir/capture/argument-1" \
    'runner changed the Codex autonomy posture'
  cmp "$expected" "$case_dir/capture/argument-2" || fail 'runner changed prompt bytes'
  assert_grep '2' "$case_dir/capture/argument-count" 'runner passed unexpected Codex arguments'
  pass 'project session runner retires the prompt before preserving every byte for Codex'
}

test_runner_returns_codex_status() {
  local case_dir fakebin prompt rc
  case_dir="$TMP_ROOT/runner-status"
  mkdir -p "$case_dir/capture"
  fakebin=$(new_codex_fake "$case_dir")
  prompt="$case_dir/prompt"
  printf '%s' 'Return the child status.' > "$prompt"

  set +e
  PATH="$fakebin:$PATH" FM_FAKE_CODEX_EXIT=23 FM_FAKE_PROMPT_PATH="$prompt" \
    FM_FAKE_CAPTURE_DIR="$case_dir/capture" "$RUNNER" "$prompt"
  rc=$?
  set -e

  expect_code 23 "$rc" 'runner Codex exit propagation'
  assert_absent "$prompt" 'runner retained the prompt after Codex failure'
  pass 'project session runner returns the Codex terminal status'
}

run_runner_tests() {
  test_runner_preserves_prompt_and_retires_file_before_codex
  test_runner_returns_codex_status
}

make_launcher_fakebin() {
  local fakebin
  fakebin=$(fm_fakebin "$CASE_DIR/fakes")
  cat > "$fakebin/codex" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
set -u
printf 'treehouse|cwd=%s' "$PWD" >> "$FM_FAKE_TOOL_LOG"
printf '|%s' "$@" >> "$FM_FAKE_TOOL_LOG"
printf '\n' >> "$FM_FAKE_TOOL_LOG"
case "${1:-}" in
  get)
    printf '%s\n' "$FM_FAKE_WORKTREE"
    ;;
  return)
    if [ "${FM_FAKE_RETURN_KEEP:-0}" != 1 ]; then
      : > "$FM_FAKE_CASE_DIR/returned"
    fi
    ;;
  status)
    if [ "${FM_FAKE_STATUS_INVALID:-0}" = 1 ]; then
      printf '%s\n' 'not-json'
    elif [ "${FM_FAKE_RETURN_KEEP:-0}" = 1 ] && [ ! -e "$FM_FAKE_CASE_DIR/returned" ]; then
      printf '[{"path":"%s","status":"leased","lease_holder":"project-session:Fixture"}]\n' "$FM_FAKE_WORKTREE"
    else
      printf '[]\n'
    fi
    ;;
  *) exit 2 ;;
esac
SH
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
printf 'tmux' >> "$FM_FAKE_TOOL_LOG"
printf '|%s' "$@" >> "$FM_FAKE_TOOL_LOG"
printf '\n' >> "$FM_FAKE_TOOL_LOG"
case "${1:-}" in
  display-message)
    printf '%s\n' "${FM_FAKE_TMUX_SESSION:-work}"
    ;;
  list-windows)
    [ -z "${FM_FAKE_EXISTING_WINDOW:-}" ] || printf '%s\n' "$FM_FAKE_EXISTING_WINDOW"
    ;;
  new-window)
    [ "${FM_FAKE_NEW_WINDOW_FAIL:-0}" != 1 ] || exit 17
    command_arg=${!#}
    eval "set -- $command_arg"
    cp "$2" "$FM_FAKE_CAPTURED_PROMPT"
    (stat -c '%a' "$2" 2>/dev/null || stat -f '%Lp' "$2") > "$FM_FAKE_CASE_DIR/prompt-mode"
    rm -f "$2"
    printf '%s\n' '@42'
    ;;
  set-option)
    ;;
  list-clients)
    i=0
    while [ "$i" -lt "${FM_FAKE_CLIENT_COUNT:-1}" ]; do
      printf 'client-%s\n' "$i"
      i=$((i + 1))
    done
    ;;
  select-window)
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/codex" "$fakebin/treehouse" "$fakebin/tmux"
  printf '%s\n' "$fakebin"
}

new_launch_case() {
  local name=$1 seed remote
  CASE_DIR="$TMP_ROOT/launch-$name"
  CASE_HOME="$CASE_DIR/home"
  CASE_REPO="$CASE_DIR/canonical"
  CASE_WORKTREE="$CASE_DIR/leased worktree"
  CASE_CODEX_HOME="$CASE_DIR/codex-home"
  CASE_TOOL_LOG="$CASE_DIR/tools.log"
  CASE_PROMPT="$CASE_DIR/captured-prompt"
  seed="$CASE_DIR/seed"
  remote="$CASE_DIR/origin.git"
  mkdir -p "$CASE_HOME/data" "$CASE_HOME/state" "$CASE_HOME/projects" \
    "$CASE_CODEX_HOME/skills/design-to-code" "$seed/docs"
  : > "$CASE_HOME/data/backlog.md"
  : > "$CASE_CODEX_HOME/skills/design-to-code/SKILL.md"
  : > "$CASE_TOOL_LOG"
  git init -q -b main "$seed"
  printf '%s\n' '# Project status' '- State: waiting.' > "$seed/docs/project-status.md"
  git -C "$seed" add docs/project-status.md
  git -C "$seed" commit -qm initial
  git clone -q --bare "$seed" "$remote"
  git clone -q "$remote" "$CASE_REPO"
  git -C "$CASE_REPO" remote set-head origin -a >/dev/null
  git -C "$CASE_REPO" worktree add -q --detach "$CASE_WORKTREE" refs/remotes/origin/main
  CASE_REMOTE_HEAD=$(git -C "$CASE_REPO" rev-parse refs/remotes/origin/main)
  fm_register_project "$CASE_HOME/data" Fixture "$CASE_REPO" validated-main
  CASE_FAKEBIN=$(make_launcher_fakebin)
}

run_launcher() {
  FM_HOME="$CASE_HOME" FM_ROOT_OVERRIDE="$ROOT" CODEX_HOME="$CASE_CODEX_HOME" \
    TMUX="${RUN_TMUX-/fake}" PATH="$CASE_FAKEBIN:$PATH" \
    FM_FAKE_CASE_DIR="$CASE_DIR" FM_FAKE_WORKTREE="$CASE_WORKTREE" \
    FM_FAKE_TOOL_LOG="$CASE_TOOL_LOG" FM_FAKE_CAPTURED_PROMPT="$CASE_PROMPT" \
    FM_FAKE_CLIENT_COUNT="${RUN_CLIENT_COUNT:-1}" \
    FM_FAKE_EXISTING_WINDOW="${RUN_EXISTING_WINDOW:-}" \
    FM_FAKE_RETURN_KEEP="${RUN_RETURN_KEEP:-0}" \
    FM_FAKE_STATUS_INVALID="${RUN_STATUS_INVALID:-0}" \
    FM_FAKE_NEW_WINDOW_FAIL="${RUN_NEW_WINDOW_FAIL:-0}" \
    "$LAUNCHER" Fixture -- "${RUN_REQUEST:-Implement the approved continuity outcome.}"
}

assert_no_allocation() {
  assert_no_grep 'treehouse|cwd=' "$CASE_TOOL_LOG" "$1"
  assert_no_grep 'tmux|new-window' "$CASE_TOOL_LOG" "$1"
}

test_missing_skill_and_tmux_refuse_before_allocation() {
  local output rc
  new_launch_case missing-skill
  rm "$CASE_CODEX_HOME/skills/design-to-code/SKILL.md"
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" 'missing standard skill preflight'
  assert_contains "$output" 'standard Codex skill installer' 'missing skill refusal omitted setup route'
  assert_no_allocation 'missing skill allocated a lease or window'

  new_launch_case missing-tmux
  RUN_TMUX=
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  RUN_TMUX=/fake
  expect_code 1 "$rc" 'missing tmux environment preflight'
  assert_contains "$output" 'requires tmux' 'missing tmux refusal was unclear'
  assert_no_allocation 'missing tmux environment allocated a lease or window'
  pass 'project session preflights skill and tmux before allocation'
}

test_existing_window_and_session_branch_refuse_before_allocation() {
  local output rc
  new_launch_case duplicate-window
  RUN_EXISTING_WINDOW=project:Fixture
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  RUN_EXISTING_WINDOW=
  expect_code 1 "$rc" 'duplicate project window preflight'
  assert_contains "$output" 'work:project:Fixture already exists' 'duplicate window refusal omitted the stable target'
  assert_no_allocation 'duplicate window allocated a lease'

  new_launch_case duplicate-branch
  git -C "$CASE_REPO" branch --no-track project-session/Fixture refs/remotes/origin/main
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" 'existing project-session branch preflight'
  assert_contains "$output" 'fm-project-status.sh Fixture' 'session-branch refusal omitted the disposition reader'
  assert_no_allocation 'existing project-session branch allocated a lease'
  pass 'project session refuses preserved windows and branches before allocation'
}

test_dirty_lease_reports_failed_guarded_rollback() {
  local output rc escaped_worktree
  new_launch_case dirty-lease
  printf '%s\n' dirty > "$CASE_WORKTREE/dirty.txt"
  RUN_RETURN_KEEP=1
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  RUN_RETURN_KEEP=0
  expect_code 1 "$rc" 'dirty lease verification'
  assert_grep 'treehouse|cwd=' "$CASE_TOOL_LOG" 'dirty lease never invoked Treehouse'
  assert_grep 'return|--if-lease-holder|project-session:Fixture' "$CASE_TOOL_LOG" \
    'dirty lease rollback omitted the holder guard'
  printf -v escaped_worktree '%q' "$CASE_WORKTREE"
  assert_contains "$output" "treehouse return --if-lease-holder project-session:Fixture $escaped_worktree" \
    'failed rollback omitted the exact recovery command'
  assert_no_grep 'tmux|new-window' "$CASE_TOOL_LOG" 'dirty lease created a project window'
  pass 'project session verifies guarded rollback and reports a retained lease'
}

test_wrong_head_returns_lease_before_window() {
  local output rc
  new_launch_case wrong-head
  printf '%s\n' mismatch > "$CASE_WORKTREE/mismatch.txt"
  git -C "$CASE_WORKTREE" add mismatch.txt
  git -C "$CASE_WORKTREE" commit -qm mismatch
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" 'leased HEAD mismatch'
  assert_present "$CASE_DIR/returned" 'HEAD mismatch did not release the fixture lease'
  assert_grep 'return|--if-lease-holder|project-session:Fixture' "$CASE_TOOL_LOG" \
    'HEAD mismatch rollback omitted the holder guard'
  assert_no_grep 'tmux|new-window' "$CASE_TOOL_LOG" 'HEAD mismatch created a project window'
  assert_contains "$output" 'leased HEAD does not match its remote default' 'HEAD mismatch refusal was unclear'
  pass 'project session verifies the remote-default commit and guarded rollback before launch'
}

test_rollback_requires_readable_release_evidence() {
  local output rc
  new_launch_case unreadable-release
  printf '%s\n' dirty > "$CASE_WORKTREE/dirty.txt"
  RUN_STATUS_INVALID=1
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  RUN_STATUS_INVALID=0
  expect_code 1 "$rc" 'unreadable Treehouse release status'
  assert_contains "$output" 'lease release could not be verified' \
    'unreadable Treehouse status was treated as proof of release'
  assert_contains "$output" 'treehouse return --if-lease-holder project-session:Fixture' \
    'unverified release omitted the guarded recovery command'
  assert_no_grep 'tmux|new-window' "$CASE_TOOL_LOG" 'unverified rollback created a project window'
  pass 'project session fails closed when Treehouse release evidence is unreadable'
}

test_new_window_failure_returns_lease() {
  local output rc
  new_launch_case new-window-failure
  RUN_NEW_WINDOW_FAIL=1
  set +e
  output=$(run_launcher 2>&1); rc=$?
  set -e
  RUN_NEW_WINDOW_FAIL=0
  expect_code 1 "$rc" 'tmux new-window failure'
  assert_present "$CASE_DIR/returned" 'tmux failure did not release the fixture lease'
  assert_grep 'return|--if-lease-holder|project-session:Fixture' "$CASE_TOOL_LOG" \
    'tmux failure rollback omitted the holder guard'
  assert_absent "$CASE_PROMPT" 'failed tmux launch exposed the private prompt copy'
  pass 'project session rolls back the guarded lease when tmux cannot create the window'
}

test_success_preserves_prompt_and_firstmate_state_boundary() {
  local output state_before state_after backlog_before escaped_worktree
  new_launch_case success
  mkdir -p "$CASE_REPO/docs/target-design"
  printf '%s\n' changed > "$CASE_REPO/docs/target-design/player-combat.md"
  printf '%s\n' note > "$CASE_REPO/notes.md"
  # shellcheck disable=SC2016 # The dollar sign is literal captain-request data.
  RUN_REQUEST='Invoke $design-to-code while preserving "quoted intent".
Second literal request line.'
  state_before="$CASE_DIR/before-state"
  state_after="$CASE_DIR/after-state"
  backlog_before="$CASE_DIR/before-backlog"
  find "$CASE_HOME/state" -mindepth 1 -maxdepth 1 -print | sort > "$state_before"
  cp "$CASE_HOME/data/backlog.md" "$backlog_before"

  output=$(run_launcher) || fail 'ordinary one-client project-session launch failed'
  RUN_REQUEST=

  find "$CASE_HOME/state" -mindepth 1 -maxdepth 1 -print | sort > "$state_after"
  cmp "$state_before" "$state_after" || fail 'launcher created Firstmate state'
  cmp "$backlog_before" "$CASE_HOME/data/backlog.md" || fail 'launcher changed the Firstmate backlog'
  assert_contains "$output" "PROJECT_SESSION project=Fixture window=work:project:Fixture window_id=@42 worktree=$CASE_WORKTREE" \
    'success output omitted stable project window identity'
  printf -v escaped_worktree '%q' "$CASE_WORKTREE"
  assert_contains "$output" "PROJECT_SESSION_CLEANUP treehouse return --if-lease-holder project-session:Fixture $escaped_worktree" \
    'success output omitted guarded cleanup command'
  assert_contains "$output" 'docs/target-design/player-combat.md' 'canonical modified path was not disclosed'
  assert_contains "$output" 'notes.md' 'canonical untracked path was not disclosed'
  assert_present "$CASE_PROMPT" 'fake tmux did not receive the private prompt'
  assert_grep 'You are the project-local orchestrator for Fixture.' "$CASE_PROMPT" 'prompt omitted project identity'
  # shellcheck disable=SC2016 # The dollar sign is literal prompt-contract data.
  assert_grep 'Invoke $design-to-code before shaping or executing the captain' "$CASE_PROMPT" 'prompt omitted skill invocation'
  assert_grep 'Before trusting any document, run git status, git log --oneline -15, git rev-parse HEAD, and compare HEAD with the remote default branch.' "$CASE_PROMPT" 'prompt omitted repository-first orientation'
  assert_grep 'Create and remain on project-session/Fixture before writing or committing anything; dispatch workers from this session HEAD, never local main.' "$CASE_PROMPT" 'prompt omitted deterministic branch custody'
  assert_grep 'Read AGENTS.md and the authoritative project sources it routes you to.' "$CASE_PROMPT" 'prompt omitted project authority routing'
  assert_grep 'Firstmate has handed the captain into this project session and is not supervising, steering, retrying, reviewing, or holding worker custody.' "$CASE_PROMPT" 'prompt blurred the one-way boundary'
  assert_grep 'Do not read or write Firstmate private task data.' "$CASE_PROMPT" 'prompt omitted the private-state prohibition'
  assert_grep 'Update docs/project-status.md only at meaningful handoffs and commit every update on project-session/Fixture.' "$CASE_PROMPT" 'prompt omitted committed handoff ownership'
  assert_grep "Session commit: $CASE_REMOTE_HEAD." "$CASE_PROMPT" 'prompt omitted the verified session commit'
  assert_grep 'Remote default ref: refs/remotes/origin/main.' "$CASE_PROMPT" 'prompt omitted the remote default ref'
  assert_grep 'Uncommitted canonical-checkout paths absent from this lease: docs/target-design/player-combat.md and notes.md.' "$CASE_PROMPT" 'prompt omitted literal drift disclosure'
  assert_grep 'Captain request:' "$CASE_PROMPT" 'prompt omitted the request boundary'
  # shellcheck disable=SC2016 # The dollar sign is literal prompt-custody data.
  assert_grep 'Invoke $design-to-code while preserving "quoted intent".' "$CASE_PROMPT" 'prompt changed literal quotes or dollar data'
  assert_grep 'Second literal request line.' "$CASE_PROMPT" 'prompt changed literal request newlines'
  assert_grep '600' "$CASE_DIR/prompt-mode" 'launcher did not protect the private prompt as mode 0600'
  assert_no_grep 'fm-send' "$CASE_PROMPT" 'prompt added a Firstmate return channel'
  assert_no_grep 'fm-spawn' "$CASE_PROMPT" 'prompt added Firstmate worker mechanics'
  assert_no_grep 'state/' "$CASE_PROMPT" 'prompt exposed Firstmate state paths'
  assert_no_grep 'status file' "$CASE_PROMPT" 'prompt added a status-file mechanism'
  assert_no_grep 'watcher' "$CASE_PROMPT" 'prompt added watcher mechanics'
  assert_no_grep 'checkpoint' "$CASE_PROMPT" 'prompt added checkpoint mechanics'
  assert_no_grep 'resume' "$CASE_PROMPT" 'prompt added resume mechanics'
  assert_grep "tmux|new-window|-d|-P|-F|#{window_id}|-t|work:|-n|project:Fixture|-c|$CASE_WORKTREE" "$CASE_TOOL_LOG" \
    'tmux window did not use the stable target, id capture, and leased cwd'
  [ "$(grep -c '^tmux|set-option|-w|-t|@42|' "$CASE_TOOL_LOG")" -eq 2 ] \
    || fail 'launcher did not disable both tmux rename paths'
  assert_grep 'tmux|select-window|-t|work:project:Fixture' "$CASE_TOOL_LOG" \
    'one-client launch did not hand off the attached captain client'
  pass 'project session publishes literal custody through one stable window without Firstmate state'
}

test_multiple_clients_abstain_from_selection() {
  local output
  new_launch_case multiple-clients
  RUN_CLIENT_COUNT=2
  output=$(run_launcher) || fail 'multi-client project-session launch failed'
  RUN_CLIENT_COUNT=1
  assert_grep 'tmux|new-window' "$CASE_TOOL_LOG" 'multi-client launch did not create a window'
  assert_no_grep 'tmux|select-window' "$CASE_TOOL_LOG" 'multi-client launch guessed which client to move'
  assert_contains "$output" 'PROJECT_SESSION_HANDOFF select window work:project:Fixture manually' \
    'multi-client launch omitted the exact manual target'
  pass 'project session leaves multiple attached clients untouched and prints the stable target'
}

run_launcher_tests() {
  test_missing_skill_and_tmux_refuse_before_allocation
  test_existing_window_and_session_branch_refuse_before_allocation
  test_dirty_lease_reports_failed_guarded_rollback
  test_wrong_head_returns_lease_before_window
  test_rollback_requires_readable_release_evidence
  test_new_window_failure_returns_lease
  test_success_preserves_prompt_and_firstmate_state_boundary
  test_multiple_clients_abstain_from_selection
}

case "${1:-all}" in
  all)
    run_runner_tests
    run_launcher_tests
    ;;
  runner) run_runner_tests ;;
  launcher) run_launcher_tests ;;
  *) fail "unknown fm-project-session test selection: $1" ;;
esac

printf 'all selected fm-project-session tests passed\n'
