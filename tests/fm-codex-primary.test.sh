#!/usr/bin/env bash
# Behavior tests for the supported primary Codex entry and its away-mode
# permission-prompt seatbelt.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAUNCHER="$ROOT/bin/fm-codex-primary.sh"
ORACLE="$ROOT/bin/fm-codex-primary-policy-check.sh"
AWAY_CHECK="$ROOT/bin/fm-codex-away-pretool-check.sh"
ARGV_ORACLE="$ROOT/bin/fm-codex-primary-argv-check.sh"
ROLLOUT_ORACLE="$ROOT/bin/fm-codex-rollout-policy-check.sh"
OPEN="$ROOT/bin/fm-open.sh"
TMP_ROOT=$(fm_test_tmproot fm-codex-primary)
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
CALL_LOG="$TMP_ROOT/codex-calls.log"
CODEX_PARENT_DIR="$TMP_ROOT/codex-parent"
CODEX_PARENT="$CODEX_PARENT_DIR/codex"
ARGV_HOLDER_DIR="$TMP_ROOT/codex-argv-holder"
ARGV_HOLDER="$ARGV_HOLDER_DIR/codex"
export FM_CODEX_TEST_LOG="$CALL_LOG"

mkdir -p "$CODEX_PARENT_DIR" "$ARGV_HOLDER_DIR"
cc "$ROOT/tests/fixtures/fm-codex-rollout-parent.c" -o "$CODEX_PARENT" \
  || fail "could not build Codex process-identity fixture"
cc "$ROOT/tests/fixtures/fm-codex-argv-holder.c" -o "$ARGV_HOLDER" \
  || fail "could not build Codex argv fixture"

cat > "$FAKEBIN/codex" <<'SH'
#!/usr/bin/env bash
set -u
{
  printf 'CALL\n'
  printf 'PWD=%s\n' "$PWD"
  printf 'FM_HOME=%s\n' "${FM_HOME:-}"
  printf 'CODEX_SANDBOX=%s\n' "${CODEX_SANDBOX:-}"
  for arg in "$@"; do
    printf 'ARG=%s\n' "$arg"
  done
} >> "$FM_CODEX_TEST_LOG"

if [ "${1:-}" = doctor ]; then
  case "${FM_CODEX_TEST_POLICY:-good}" in
    good)
      printf '%s\n' '{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"Never","filesystem sandbox":"unrestricted","network sandbox":"enabled"}},"config.load":{"details":{"enabled feature flags":"shell_tool, hooks, sqlite"}}}}'
      ;;
    bad)
      printf '%s\n' '{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"OnRequest","filesystem sandbox":"restricted","network sandbox":"restricted"}},"config.load":{"details":{"enabled feature flags":"shell_tool, hooks, sqlite"}}}}'
      ;;
    hooks-disabled)
      printf '%s\n' '{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"Never","filesystem sandbox":"unrestricted","network sandbox":"enabled"}},"config.load":{"details":{"enabled feature flags":"shell_tool, sqlite"}}}}'
      ;;
    malformed)
      printf '%s\n' '{"codexVersion":"0.147.0","checks":{}}'
      ;;
  esac
  exit 0
fi

printf 'fake-codex-launched\n'
SH
chmod +x "$FAKEBIN/codex"

GOOD_JSON='{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"Never","filesystem sandbox":"unrestricted","network sandbox":"enabled"}},"config.load":{"details":{"enabled feature flags":"shell_tool, hooks, sqlite"}}}}'
BAD_JSON='{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"OnRequest","filesystem sandbox":"restricted","network sandbox":"restricted"}},"config.load":{"details":{"enabled feature flags":"shell_tool, hooks, sqlite"}}}}'
HOOKS_DISABLED_JSON='{"codexVersion":"0.147.0","checks":{"sandbox.helpers":{"details":{"approval policy":"Never","filesystem sandbox":"unrestricted","network sandbox":"enabled"}},"config.load":{"details":{"enabled feature flags":"shell_tool, sqlite"}}}}'

test_policy_oracle_accepts_effective_unrestricted_policy() {
  local out rc
  out=$(printf '%s\n' "$GOOD_JSON" | "$ORACLE" 2>&1); rc=$?
  expect_code 0 "$rc" "unrestricted effective-policy report"
  assert_contains "$out" "approval=Never filesystem=unrestricted network=enabled hooks=enabled" \
    "policy oracle did not report the effective values it accepted"
  pass "primary policy oracle accepts and reports the effective unrestricted/no-prompt policy"
}

test_policy_oracle_rejects_restricted_policy() {
  local out rc
  out=$(printf '%s\n' "$BAD_JSON" | "$ORACLE" 2>&1); rc=$?
  expect_code 1 "$rc" "restricted effective-policy report"
  assert_contains "$out" "approval=OnRequest filesystem=restricted network=restricted hooks=enabled" \
    "policy oracle refusal did not report the effective restricted values"
  pass "primary policy oracle deliberately fails on OnRequest/workspace policy"
}

test_policy_oracle_rejects_disabled_hooks() {
  local out rc
  out=$(printf '%s\n' "$HOOKS_DISABLED_JSON" | "$ORACLE" 2>&1); rc=$?
  expect_code 1 "$rc" "disabled effective hook feature"
  assert_contains "$out" "hooks=disabled" \
    "policy oracle did not expose persisted hook disablement"
  pass "primary policy oracle fails closed when effective settings disable hooks"
}

test_policy_oracle_rejects_missing_effective_fields() {
  local out rc
  out=$(printf '%s\n' '{"checks":{}}' | "$ORACLE" 2>&1); rc=$?
  expect_code 1 "$rc" "missing effective-policy fields"
  assert_contains "$out" "could not read Codex's effective sandbox policy" \
    "missing effective fields did not fail visibly"
  pass "primary policy oracle fails closed when doctor omits effective policy"
}

test_launcher_verifies_then_passes_same_policy_to_codex() {
  local out calls
  : > "$CALL_LOG"
  out=$(cd "$TMP_ROOT" && CODEX_SANDBOX=seatbelt CODEX_SANDBOX_NETWORK_DISABLED=1 \
    PATH="$FAKEBIN:$PATH" "$LAUNCHER" resume --last 2>&1) \
    || fail "primary launcher refused a good effective policy: $out"
  assert_contains "$out" "effective policy verified" \
    "primary launcher did not report its effective-policy gate"
  assert_contains "$out" "fake-codex-launched" \
    "primary launcher did not hand off after verification"
  calls=$(grep -c '^CALL$' "$CALL_LOG")
  [ "$calls" -eq 2 ] || fail "launcher must call Codex once for doctor and once for launch, got $calls"
  [ "$(grep -c '^ARG=approval_policy="never"$' "$CALL_LOG")" -eq 2 ] \
    || fail "doctor and launched Codex did not receive the same approval-policy override"
  [ "$(grep -c '^ARG=sandbox_mode="danger-full-access"$' "$CALL_LOG")" -eq 2 ] \
    || fail "doctor and launched Codex did not receive the same sandbox override"
  assert_grep 'ARG=--dangerously-bypass-hook-trust' "$CALL_LOG" \
    "launched primary did not guarantee its tracked safety hooks load"
  [ "$(grep -c '^ARG=--enable$' "$CALL_LOG")" -eq 2 ] \
    || fail "doctor and launched Codex did not receive the same feature-enablement flag"
  [ "$(grep -c '^ARG=hooks$' "$CALL_LOG")" -eq 2 ] \
    || fail "doctor and launched Codex did not explicitly enable tracked hooks"
  assert_grep 'ARG=resume' "$CALL_LOG" "resume subcommand did not reach Codex"
  assert_grep 'ARG=--last' "$CALL_LOG" "resume argument did not reach Codex"
  [ "$(grep -c '^CODEX_SANDBOX=$' "$CALL_LOG")" -eq 2 ] \
    || fail "verified doctor and primary launch inherited a stale restricted-shell marker"
  [ "$(grep -c "^PWD=$ROOT$" "$CALL_LOG")" -eq 2 ] \
    || fail "direct primary entry did not anchor doctor and Codex to the tracked hook root"
  pass "primary launcher proves and propagates one policy to fresh and resumed Codex processes"
}

test_launcher_refuses_before_launch_when_effective_policy_is_restricted() {
  local out rc calls
  : > "$CALL_LOG"
  out=$(FM_CODEX_TEST_POLICY=bad PATH="$FAKEBIN:$PATH" "$LAUNCHER" 2>&1); rc=$?
  expect_code 1 "$rc" "launcher restricted-policy refusal"
  assert_contains "$out" "effective policy mismatch" \
    "launcher did not surface the restricted effective policy"
  calls=$(grep -c '^CALL$' "$CALL_LOG")
  [ "$calls" -eq 1 ] || fail "restricted policy must stop after doctor, got $calls Codex calls"
  pass "primary launcher accepts no work when effective policy is restricted"
}

test_launcher_refuses_before_launch_when_effective_hooks_are_disabled() {
  local out rc calls
  : > "$CALL_LOG"
  out=$(FM_CODEX_TEST_POLICY=hooks-disabled PATH="$FAKEBIN:$PATH" "$LAUNCHER" 2>&1); rc=$?
  expect_code 1 "$rc" "launcher disabled-hooks refusal"
  assert_contains "$out" "hooks=disabled" \
    "launcher did not surface effective hook disablement"
  calls=$(grep -c '^CALL$' "$CALL_LOG")
  [ "$calls" -eq 1 ] || fail "disabled hooks must stop after doctor, got $calls Codex calls"
  pass "primary launcher accepts no work when effective settings disable tracked hooks"
}

assert_policy_override_rejected() {
  local out rc
  : > "$CALL_LOG"
  out=$(PATH="$FAKEBIN:$PATH" "$LAUNCHER" "$@" 2>&1); rc=$?
  expect_code 2 "$rc" "caller policy override: $*"
  assert_contains "$out" "primary policy is launcher-owned" \
    "conflicting caller policy did not get a clear refusal: $*"
  [ ! -s "$CALL_LOG" ] \
    || fail "launcher invoked Codex before rejecting a conflicting policy flag: $*"
}

test_launcher_rejects_caller_policy_override() {
  assert_policy_override_rejected -a on-request
  assert_policy_override_rejected --dangerously-bypass-approvals-and-sandbox
  assert_policy_override_rejected -c 'sandbox_mode="workspace-write"'
  assert_policy_override_rejected -c 'sandbox_mode = "workspace-write"'
  assert_policy_override_rejected '-c=approval_policy="on-request"'
  assert_policy_override_rejected '-c=sandbox_mode="workspace-write"'
  assert_policy_override_rejected -c '"approval_policy"="on-request"'
  assert_policy_override_rejected '--config="sandbox_mode"="workspace-write"'
  assert_policy_override_rejected '--config=approval_policy = "on-request"'
  assert_policy_override_rejected -c 'model="gpt-5.6-sol"'
  assert_policy_override_rejected --profile restricted
  assert_policy_override_rejected --disable hooks
  pass "primary launcher refuses caller flags that could replace its verified policy"
}

test_launcher_rejects_root_and_remote_bypasses() {
  local out rc
  for arg in -C --cd --remote; do
    : > "$CALL_LOG"
    out=$(PATH="$FAKEBIN:$PATH" "$LAUNCHER" "$arg" elsewhere 2>&1); rc=$?
    expect_code 2 "$rc" "unsupported primary boundary override: $arg"
    assert_contains "$out" "primary entry is launcher-owned" \
      "unsupported root or remote override did not explain the owned boundary: $arg"
    [ ! -s "$CALL_LOG" ] \
      || fail "launcher invoked Codex before rejecting the boundary override: $arg"
  done
  pass "primary launcher refuses caller flags that bypass its verified local hook root"
}

test_launcher_rejects_noninteractive_and_service_subcommands() {
  local out rc subcommand
  for subcommand in exec e review delete mcp-server apply a fork; do
    : > "$CALL_LOG"
    out=$(PATH="$FAKEBIN:$PATH" "$LAUNCHER" "$subcommand" 2>&1); rc=$?
    expect_code 2 "$rc" "unsupported primary Codex subcommand: $subcommand"
    assert_contains "$out" "supports only fresh or resumed interactive sessions" \
      "unsupported primary subcommand did not explain the verified lifecycle boundary: $subcommand"
    [ ! -s "$CALL_LOG" ] \
      || fail "launcher invoked Codex before rejecting unsupported subcommand: $subcommand"
  done
  pass "primary launcher limits its accepted-work contract to fresh and resumed interactive sessions"
}

test_resume_accepts_session_and_prompt_words_that_match_subcommands() {
  local out
  : > "$CALL_LOG"
  out=$(PATH="$FAKEBIN:$PATH" "$LAUNCHER" resume review delete 2>&1) \
    || fail "resume rejected subcommand-shaped session or prompt words: $out"
  assert_contains "$out" "fake-codex-launched" \
    "resume collision fixture did not reach the verified interactive launch"
  assert_grep 'ARG=resume' "$CALL_LOG" "resume mode did not reach Codex"
  assert_grep 'ARG=review' "$CALL_LOG" "subcommand-shaped resume session id was dropped"
  assert_grep 'ARG=delete' "$CALL_LOG" "subcommand-shaped resume prompt was dropped"
  pass "resume grammar keeps session ids and prompts distinct from top-level subcommands"
}

make_peer_home() {
  local home=$1
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  printf 'policy-peer\n' > "$home/.fm-peer-home"
}

test_peer_codex_entry_routes_through_primary_launcher() {
  local home="$TMP_ROOT/peer" out calls
  make_peer_home "$home"
  home=$(cd "$home" && pwd -P)
  : > "$CALL_LOG"
  out=$(PATH="$FAKEBIN:$PATH" "$OPEN" "$home" codex resume --last 2>&1) \
    || fail "peer Codex entry failed: $out"
  assert_contains "$out" "effective policy verified" \
    "peer Codex entry bypassed the primary policy gate"
  calls=$(grep -c '^CALL$' "$CALL_LOG")
  [ "$calls" -eq 2 ] || fail "peer Codex entry did not verify then launch, got $calls calls"
  [ "$(grep -c "^FM_HOME=$home$" "$CALL_LOG")" -eq 2 ] \
    || fail "peer policy probe and launch did not share the selected FM_HOME"
  [ "$(grep -c "^PWD=$ROOT$" "$CALL_LOG")" -eq 2 ] \
    || fail "peer policy probe and launch did not run from the tracked code root"
  pass "documented peer-home Codex entry is policy-gated before launch"
}

run_away_check() { # <home> <permission-mode> <command>
  local home=$1 mode=$2 command=$3 payload
  payload=$(jq -cn --arg mode "$mode" --arg command "$command" \
    '{hook_event_name:"PreToolUse",permission_mode:$mode,tool_name:"Bash",tool_input:{command:$command}}')
  printf '%s' "$payload" | FM_HOME="$home" "$AWAY_CHECK"
}

test_restricted_away_declaration_is_refused_before_execution() {
  local home="$TMP_ROOT/away-declare" out rc
  mkdir -p "$home/state"
  out=$(run_away_check "$home" default 'bin/fm-afk-launch.sh start' 2>&1); rc=$?
  expect_code 2 "$rc" "restricted away declaration"
  assert_contains "$out" "[codex-away-permission]" \
    "away declaration refusal omitted its stable reason code"
  assert_contains "$out" "relaunch with bin/fm-codex-primary.sh" \
    "away declaration refusal did not identify the executable correction"
  pass "restricted primary cannot begin away mode through an interactive permission path"
}

test_restricted_shell_cannot_enter_away_lifecycle() {
  local home="$TMP_ROOT/restricted-shell" out rc
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
  out=$(CODEX_SANDBOX=seatbelt CODEX_SANDBOX_NETWORK_DISABLED=1 \
    FM_HOME="$home" "$ROOT/bin/fm-afk-launch.sh" start 2>&1); rc=$?
  expect_code 2 "$rc" "restricted Codex away launcher"
  assert_contains "$out" "[codex-away-permission]" \
    "restricted-shell refusal omitted its stable reason code"
  assert_contains "$out" "relaunch with bin/fm-codex-primary.sh" \
    "restricted-shell refusal did not identify the verified primary entry"
  assert_absent "$home/state/.afk" \
    "restricted away launcher wrote the durable away flag before refusing"
  assert_absent "$home/state/.afk-launch.lock" \
    "restricted away launcher reached the sandbox-sensitive identity lock"
  pass "away launcher refuses inside Codex's restricted shell before sandbox-sensitive work"
}

test_restricted_shell_cannot_bypass_launcher_with_direct_daemon_entry() {
  local home="$TMP_ROOT/restricted-direct" out rc
  mkdir -p "$home/state"
  out=$(CODEX_SANDBOX=seatbelt FM_HOME="$home" "$ROOT/bin/fm-afk-start.sh" 2>&1); rc=$?
  expect_code 2 "$rc" "restricted Codex direct away entry"
  assert_contains "$out" "[codex-away-permission]" \
    "direct daemon entry bypassed the restricted-shell guard"
  assert_absent "$home/state/.afk" \
    "direct restricted daemon entry wrote the away flag before refusing"
  pass "shared daemon entry cannot bypass the restricted Codex away guard"
}

write_rollout() { # <codex-home> <thread-id> <approval> <sandbox>
  local codex_home=$1 thread_id=$2 approval=$3 sandbox=$4 rollout
  rollout="$codex_home/sessions/2026/08/12/rollout-fixture-$thread_id.jsonl"
  mkdir -p "$(dirname "$rollout")"
  jq -cn --arg approval "$approval" --arg sandbox "$sandbox" \
    '{type:"turn_context",payload:{approval_policy:$approval,sandbox_policy:{type:$sandbox}}}' > "$rollout"
}

test_restricted_effective_rollout_cannot_enter_away_lifecycle() {
  local home="$TMP_ROOT/unverified-full" codex_home="$TMP_ROOT/codex-restricted" rollout out rc
  mkdir -p "$home/state"
  write_rollout "$codex_home" raw-on-request-danger-full on-request danger-full-access
  rollout="$codex_home/sessions/2026/08/12/rollout-fixture-raw-on-request-danger-full.jsonl"
  out=$(FM_HOME="$home" "$CODEX_PARENT" "$rollout" - \
    "$ROOT/bin/fm-afk-launch.sh" start 2>&1); rc=$?
  expect_code 2 "$rc" "unverified full-access Codex away entry"
  assert_contains "$out" "unverified or restricted Codex session" \
    "raw on-request/danger-full Codex was mistaken for the verified primary"
  assert_absent "$home/state/.afk" \
    "unverified full-access Codex wrote the away flag before refusing"
  pass "raw Codex cannot enter away mode merely because its sandbox is unrestricted"
}

test_unsigned_codex_impersonator_cannot_enter_guard_boundary() {
  local codex_home="$TMP_ROOT/codex-unrestricted" rollout out rc
  write_rollout "$codex_home" verified-thread never danger-full-access
  rollout="$codex_home/sessions/2026/08/12/rollout-fixture-verified-thread.jsonl"
  out=$("$CODEX_PARENT" "$rollout" - "$AWAY_CHECK" --entry 2>&1); rc=$?
  expect_code 2 "$rc" "unsigned Codex process impersonator"
  assert_contains "$out" "unverified or restricted Codex session" \
    "unsigned Codex-named parent authenticated through a fabricated unrestricted rollout"
  pass "away entry rejects a Codex-named process that is not the signed OpenAI executable"
}

test_spoofed_or_inherited_marker_cannot_override_restricted_rollout() {
  local codex_home="$TMP_ROOT/codex-marker-spoof" fake_home="$TMP_ROOT/codex-fabricated" rollout out rc
  write_rollout "$codex_home" restricted-marker-spoof on-request danger-full-access
  write_rollout "$fake_home" fabricated-good never danger-full-access
  rollout="$codex_home/sessions/2026/08/12/rollout-fixture-restricted-marker-spoof.jsonl"
  out=$(CODEX_HOME="$fake_home" CODEX_THREAD_ID='' \
    FM_CODEX_PRIMARY_POLICY_VERIFIED=codex-0.147-primary-v1 \
    "$CODEX_PARENT" "$rollout" - "$AWAY_CHECK" --entry 2>&1); rc=$?
  expect_code 2 "$rc" "spoofed environment and fabricated rollout"
  assert_contains "$out" "unverified or restricted Codex session" \
    "caller-controlled environment overrode the restricted live Codex rollout"
  pass "away entry derives effective policy from live process identity, not caller-controlled environment"
}

test_missing_effective_rollout_fails_closed() {
  local out rc
  out=$("$CODEX_PARENT" - "$AWAY_CHECK" --entry 2>&1); rc=$?
  expect_code 2 "$rc" "missing current-thread rollout"
  assert_contains "$out" "unverified or restricted Codex session" \
    "missing rollout did not fail closed"
  pass "away entry fails closed when current-thread effective policy cannot be read"
}

test_rollout_oracle_requires_every_open_context_to_be_unrestricted() {
  local codex_home="$TMP_ROOT/codex-rollout-oracle" good restricted missing out rc
  write_rollout "$codex_home" good never danger-full-access
  write_rollout "$codex_home" restricted on-request danger-full-access
  missing="$codex_home/sessions/2026/08/12/rollout-fixture-missing.jsonl"
  printf '%s\n' '{"type":"event_msg","payload":{}}' > "$missing"
  good="$codex_home/sessions/2026/08/12/rollout-fixture-good.jsonl"
  restricted="$codex_home/sessions/2026/08/12/rollout-fixture-restricted.jsonl"

  out=$("$ROLLOUT_ORACLE" "$good" 2>&1); rc=$?
  expect_code 0 "$rc" "one unrestricted authenticated rollout"
  [ -z "$out" ] || fail "accepted rollout oracle must be silent, got: $out"
  out=$("$ROLLOUT_ORACLE" "$good" "$restricted" 2>&1); rc=$?
  expect_code 1 "$rc" "mixed unrestricted and restricted authenticated rollouts"
  assert_contains "$out" "not no-prompt/full-access" \
    "mixed rollout set did not expose its restricted member"
  out=$("$ROLLOUT_ORACLE" "$missing" 2>&1); rc=$?
  expect_code 1 "$rc" "rollout missing an effective turn context"
  pass "rollout oracle requires every authenticated process-open context to be no-prompt/full-access"
}

test_live_argv_oracle_requires_launcher_policy_without_later_override() {
  local out rc suffix pid

  PATH="$ARGV_HOLDER_DIR:$PATH" codex \
    --dangerously-bypass-hook-trust \
    -c 'approval_policy="never"' \
    -c 'sandbox_mode="danger-full-access"' \
    --enable hooks resume --last &
  pid=$!
  sleep 0.05
  out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  expect_code 0 "$rc" "supported immutable primary argv"
  [ -z "$out" ] || fail "accepted argv oracle must be silent, got: $out"

  PATH="$ARGV_HOLDER_DIR:$PATH" codex -a on-request -s danger-full-access &
  pid=$!
  sleep 0.05
  out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  expect_code 1 "$rc" "raw restricted Codex argv"
  assert_contains "$out" "does not carry the supported primary policy prefix" \
    "raw restricted argv did not fail its launch-posture check"

  PATH="$ARGV_HOLDER_DIR:$PATH" codex \
    --dangerously-bypass-hook-trust \
    -c 'approval_policy="never"' \
    -c 'sandbox_mode="danger-full-access"' \
    --enable hooks resume --last -c 'sandbox_mode="workspace-write"' &
  pid=$!
  sleep 0.05
  out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  expect_code 1 "$rc" "late policy override in live argv"
  assert_contains "$out" "later unsupported policy layer" \
    "late live-argv override was not rejected"

  for suffix in \
    '-aon-request' \
    '-sworkspace-write' \
    '-capproval_policy="on-request"' \
    '-prestricted'; do
    PATH="$ARGV_HOLDER_DIR:$PATH" codex \
      --dangerously-bypass-hook-trust \
      -c 'approval_policy="never"' \
      -c 'sandbox_mode="danger-full-access"' \
      --enable hooks resume --last "$suffix" &
    pid=$!
    sleep 0.05
    out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    expect_code 1 "$rc" "attached short policy layer in live argv: $suffix"
    assert_contains "$out" "later unsupported policy layer" \
      "attached short live-argv override was not rejected: $suffix"
  done
  pass "live argv oracle binds away entry to the launcher's immutable policy posture"
}

test_live_argv_oracle_keeps_prompt_text_out_of_policy_parsing() {
  local prompt out rc pid

  for prompt in \
    'Explain the -c flag' \
    'Review -sandbox docs'; do
    PATH="$ARGV_HOLDER_DIR:$PATH" codex \
      --dangerously-bypass-hook-trust \
      -c 'approval_policy="never"' \
      -c 'sandbox_mode="danger-full-access"' \
      --enable hooks "$prompt" &
    pid=$!
    sleep 0.05
    out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    expect_code 0 "$rc" "prompt text that mentions a policy-shaped token: $prompt"
    [ -z "$out" ] || fail "accepted prompt argv oracle must be silent, got: $out"
  done

  PATH="$ARGV_HOLDER_DIR:$PATH" codex \
    --dangerously-bypass-hook-trust \
    -c 'approval_policy="never"' \
    -c 'sandbox_mode="danger-full-access"' \
    --enable hooks -- '-please review' &
  pid=$!
  sleep 0.05
  out=$("$ARGV_ORACLE" "$pid" </dev/null 2>&1); rc=$?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  expect_code 0 "$rc" "option-shaped prompt after the argument terminator"
  [ -z "$out" ] || fail "accepted terminated prompt argv oracle must be silent, got: $out"
  pass "live argv oracle parses kernel argument boundaries instead of prompt text"
}

test_multiple_fabricated_rollouts_do_not_authenticate_unsigned_parent() {
  local codex_home="$TMP_ROOT/codex-ambiguous" rollout_one rollout_two out rc
  write_rollout "$codex_home" good-one never danger-full-access
  write_rollout "$codex_home" good-two never danger-full-access
  rollout_one="$codex_home/sessions/2026/08/12/rollout-fixture-good-one.jsonl"
  rollout_two="$codex_home/sessions/2026/08/12/rollout-fixture-good-two.jsonl"
  out=$("$CODEX_PARENT" "$rollout_one" "$rollout_two" - "$AWAY_CHECK" --entry 2>&1); rc=$?
  expect_code 2 "$rc" "ambiguous live Codex rollouts"
  assert_contains "$out" "unverified or restricted Codex session" \
    "ambiguous live rollout identity did not fail closed"
  pass "multiple fabricated rollouts cannot authenticate an unsigned Codex-named parent"
}

test_active_away_restricted_command_is_refused() {
  local home="$TMP_ROOT/away-active" out rc
  mkdir -p "$home/state"
  printf '1\n' > "$home/state/.afk"
  out=$(run_away_check "$home" default 'printf routine-operation' 2>&1); rc=$?
  expect_code 2 "$rc" "restricted command while away"
  assert_contains "$out" "away mode is active" \
    "active-away refusal did not explain the durable state boundary"
  pass "active away mode refuses a restricted shell call before it can ask for approval"
}

test_full_access_away_command_remains_allowed() {
  local home="$TMP_ROOT/away-full" out rc
  mkdir -p "$home/state"
  printf '1\n' > "$home/state/.afk"
  out=$(run_away_check "$home" bypassPermissions 'printf routine-operation' 2>&1); rc=$?
  expect_code 0 "$rc" "full-access command while away"
  [ -z "$out" ] || fail "full-access away command must be silent, got: $out"
  pass "away guard does not suppress an already-authorized full-access routine path"
}

test_attended_restricted_non_away_command_remains_allowed() {
  local home="$TMP_ROOT/attended" out rc
  mkdir -p "$home/state"
  out=$(run_away_check "$home" default 'printf attended-operation' 2>&1); rc=$?
  expect_code 0 "$rc" "attended restricted non-away command"
  [ -z "$out" ] || fail "attended non-away command must be silent, got: $out"
  pass "away guard leaves ordinary attended policy behavior outside its scope"
}

test_restricted_inspection_of_away_scripts_remains_allowed() {
  local home="$TMP_ROOT/inspect" command out rc
  mkdir -p "$home/state"
  for command in \
    "rg 'start' bin/fm-afk-launch.sh" \
    "sed -n '1,80p' bin/fm-afk-start.sh"; do
    out=$(run_away_check "$home" default "$command" 2>&1); rc=$?
    expect_code 0 "$rc" "restricted inspection of away implementation"
    [ -z "$out" ] || fail "inspection of away implementation must be silent, got: $out"
  done
  pass "away guard distinguishes lifecycle entry from inspection of its scripts"
}

test_tracked_codex_hook_executes_away_guard() {
  local home="$TMP_ROOT/hook" hook payload out rc
  mkdir -p "$home/state"
  hook=$(jq -r '.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("fm-codex-away-pretool-check.sh")) | .command' \
    "$ROOT/.codex/hooks.json")
  [ -n "$hook" ] || fail "tracked Codex PreToolUse hook does not register the away guard"
  payload=$(jq -cn '{hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_input:{command:"bin/fm-afk-launch.sh start"}}')
  out=$(printf '%s' "$payload" | FM_HOME="$home" bash -lc "$hook" 2>&1); rc=$?
  expect_code 2 "$rc" "tracked Codex away-hook execution"
  assert_contains "$out" "[codex-away-permission]" \
    "tracked hook execution did not reach the away guard"
  pass "tracked Codex hook executes the away guard and preserves its blocking exit"
}

test_policy_oracle_accepts_effective_unrestricted_policy
test_policy_oracle_rejects_restricted_policy
test_policy_oracle_rejects_disabled_hooks
test_policy_oracle_rejects_missing_effective_fields
test_launcher_verifies_then_passes_same_policy_to_codex
test_launcher_refuses_before_launch_when_effective_policy_is_restricted
test_launcher_refuses_before_launch_when_effective_hooks_are_disabled
test_launcher_rejects_caller_policy_override
test_launcher_rejects_root_and_remote_bypasses
test_launcher_rejects_noninteractive_and_service_subcommands
test_resume_accepts_session_and_prompt_words_that_match_subcommands
test_peer_codex_entry_routes_through_primary_launcher
test_restricted_away_declaration_is_refused_before_execution
test_restricted_shell_cannot_enter_away_lifecycle
test_restricted_shell_cannot_bypass_launcher_with_direct_daemon_entry
test_restricted_effective_rollout_cannot_enter_away_lifecycle
test_unsigned_codex_impersonator_cannot_enter_guard_boundary
test_spoofed_or_inherited_marker_cannot_override_restricted_rollout
test_missing_effective_rollout_fails_closed
test_rollout_oracle_requires_every_open_context_to_be_unrestricted
test_live_argv_oracle_requires_launcher_policy_without_later_override
test_live_argv_oracle_keeps_prompt_text_out_of_policy_parsing
test_multiple_fabricated_rollouts_do_not_authenticate_unsigned_parent
test_active_away_restricted_command_is_refused
test_full_access_away_command_remains_allowed
test_attended_restricted_non_away_command_remains_allowed
test_restricted_inspection_of_away_scripts_remains_allowed
test_tracked_codex_hook_executes_away_guard
