#!/usr/bin/env bash
# Behavior tests for one-way project-session prompt custody and launch boundaries.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RUNNER="$ROOT/bin/fm-project-session-run.sh"
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

case "${1:-all}" in
  all|runner) run_runner_tests ;;
  *) fail "unknown fm-project-session test selection: $1" ;;
esac

printf 'all selected fm-project-session tests passed\n'
