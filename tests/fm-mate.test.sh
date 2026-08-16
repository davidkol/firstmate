#!/usr/bin/env bash
# tests/fm-mate.test.sh - the global mate command resolves a peer-home id and
# delegates its launch to the tracked peer-home launcher.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MATE="$ROOT/bin/fm-mate.sh"
TMP_ROOT=$(fm_test_tmproot fm-mate)
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT

HOMES="$TMP_ROOT/homes"
HOME_PATH="$HOMES/martyrdome"
FAKEBIN="$TMP_ROOT/fakebin"
mkdir -p "$HOME_PATH/data" "$HOME_PATH/state" "$HOME_PATH/config" \
  "$HOME_PATH/projects" "$FAKEBIN"
printf '%s\n' martyrdome > "$HOME_PATH/.fm-peer-home"

cat > "$FAKEBIN/claude" <<'SH'
#!/usr/bin/env bash
printf 'cwd=%s\n' "$PWD"
printf 'home=%s\n' "$FM_HOME"
printf 'argc=%s\n' "$#"
printf 'arg=%s\n' "$@"
SH
chmod +x "$FAKEBIN/claude"

test_resolves_home_and_forwards_harness_arguments() {
  local out
  out=$(FM_HOMES_ROOT="$HOMES" PATH="$FAKEBIN:$PATH" \
    "$MATE" martyrdome claude --model opus) \
    || fail "mate did not launch a known peer home: $out"

  assert_contains "$out" "cwd=$ROOT" "mate did not launch from the tracked Firstmate root"
  assert_contains "$out" "home=$HOME_PATH" "mate did not resolve the named peer home"
  assert_contains "$out" "argc=2" "mate did not preserve the harness argument count"
  assert_contains "$out" "arg=--model" "mate dropped a harness flag"
  assert_contains "$out" "arg=opus" "mate dropped a harness flag value"
  pass "mate resolves a peer-home id and forwards harness arguments"
}

test_works_through_global_symlink() {
  local out
  ln -s "$MATE" "$FAKEBIN/mate"
  out=$(FM_HOMES_ROOT="$HOMES" PATH="$FAKEBIN:$PATH" \
    "$FAKEBIN/mate" martyrdome claude) \
    || fail "symlinked mate command could not locate Firstmate: $out"

  assert_contains "$out" "home=$HOME_PATH" "symlinked mate resolved the wrong home"
  pass "mate locates its tracked code root when invoked through a global symlink"
}

test_refuses_unknown_and_unsafe_ids() {
  local out
  out=$(FM_HOMES_ROOT="$HOMES" PATH="$FAKEBIN:$PATH" \
    "$MATE" missing claude 2>&1) \
    && fail "mate accepted an unknown peer-home id"
  assert_contains "$out" "peer home not found: missing" "unknown-home refusal was unclear"

  out=$(FM_HOMES_ROOT="$HOMES" PATH="$FAKEBIN:$PATH" \
    "$MATE" ../martyrdome claude 2>&1) \
    && fail "mate accepted a path instead of a peer-home id"
  assert_contains "$out" "peer home id must match" "unsafe-id refusal was unclear"
  pass "mate refuses unknown homes and path-like ids"
}

test_requires_home_and_harness() {
  local out
  out=$(FM_HOMES_ROOT="$HOMES" "$MATE" martyrdome 2>&1) \
    && fail "mate accepted a missing harness"
  assert_contains "$out" "usage: mate <project> <harness>" "missing-harness usage was unclear"
  pass "mate requires both a peer-home id and a harness"
}

test_resolves_home_and_forwards_harness_arguments
test_works_through_global_symlink
test_refuses_unknown_and_unsafe_ids
test_requires_home_and_harness
