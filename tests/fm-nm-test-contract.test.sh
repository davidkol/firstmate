#!/usr/bin/env bash
# Contract: local no-mistakes Test is scoped - present, and neither full-suite
# nor absent.
#
# Firstmate must configure commands.test as a scoped bin/fm-test-run.sh
# selection, so the local gate genuinely is the definition of done. An absent
# command left the regression suite running nowhere, because
# .github/workflows/ci.yml defines the reference lane composition but no hosted
# CI executes it on this fork. A complete tests/*.test.sh walk is equally wrong:
# it makes every prose or skill change pay for the end-to-end lanes. Lint stays
# pinned to bin/fm-lint.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NM="$ROOT/.no-mistakes.yaml"
CI="$ROOT/.github/workflows/ci.yml"

test_nm_yaml_tracked() {
  assert_present "$NM" "tracked .no-mistakes.yaml is missing"
  git -C "$ROOT" ls-files --error-unmatch .no-mistakes.yaml >/dev/null 2>&1 \
    || fail ".no-mistakes.yaml is not tracked by git"
  pass ".no-mistakes.yaml is present and tracked"
}

test_nm_keeps_lint_pin() {
  grep -Fqx "  lint: 'bin/fm-lint.sh'" "$NM" \
    || fail "commands.lint must remain exactly bin/fm-lint.sh"
  pass "commands.lint stays pinned to bin/fm-lint.sh"
}

# Prints the mapped commands.test (string or mapping value), empty when absent.
# Empty / null / absent now fails the contract below.
nm_commands_test_value() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c '
import yaml, sys
doc = yaml.safe_load(open(sys.argv[1])) or {}
cmds = doc.get("commands") or {}
val = cmds.get("test") if isinstance(cmds, dict) else None
if val is None or val is False:
    print("")
elif isinstance(val, str):
    print(val)
else:
    print(repr(val))
' "$NM"
    return
  fi
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
doc = YAML.safe_load(File.read(ARGV[0])) || {}
cmds = doc["commands"] || {}
val = cmds.is_a?(Hash) ? cmds["test"] : nil
if val.nil? || val == false
  puts ""
elsif val.is_a?(String)
  puts val
else
  puts val.inspect
end
' "$NM"
    return
  fi
  # Structural fallback: any commands.test line under the commands block.
  awk '
    /^commands:[[:space:]]*$/ { in_cmds=1; next }
    in_cmds && /^[^[:space:]#]/ { in_cmds=0 }
    in_cmds && /^[[:space:]]+test:[[:space:]]*/ {
      sub(/^[[:space:]]+test:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
      exit
    }
  ' "$NM"
}

test_nm_configures_a_scoped_local_test_command() {
  local val
  val=$(nm_commands_test_value) || fail "failed to read commands.test from .no-mistakes.yaml"
  [ -n "$val" ] \
    || fail "commands.test must be set; an absent command leaves the regression suite running nowhere"
  case "$val" in
    *bin/fm-test-run.sh*) ;;
    *) fail "commands.test must run the one-owner runner bin/fm-test-run.sh; got: $val" ;;
  esac
  # The scope ceiling: never the complete walk, however it is spelled.
  case "$val" in
    *--all*|*'tests/*.test.sh'*|*--proven-isolated*)
      fail "commands.test must stay scoped, not a complete-suite walk; got: $val"
      ;;
  esac
  # Require an explicitly scoped selector rather than accepting anything non-full.
  case "$val" in
    *--changed*|*--family*|*--lane*) ;;
    *) fail "commands.test must select with --changed, --family, or --lane; got: $val" ;;
  esac
  # Without this, an unmapped change selects nothing, reports total=0, and the
  # step succeeds having verified nothing at all.
  case "$val" in
    *--require-nonempty*) ;;
    *) fail "commands.test must pass --require-nonempty so an empty selection cannot pass; got: $val" ;;
  esac
  pass "no-mistakes configures a scoped local Test command: $val"
}

# The local gate cannot run the real-Herdr family without a pinned Herdr, so the
# config must keep saying so. A partial pass must never read as full coverage.
test_nm_documents_the_local_herdr_gap() {
  grep -Fq 'real-herdr-gated' "$NM" \
    || fail ".no-mistakes.yaml must name the real-herdr-gated family as a local gap"
  grep -Fq 'skipped_gate' "$NM" \
    || fail ".no-mistakes.yaml must point at the runner's skipped_gate tally as the honest signal"
  pass ".no-mistakes.yaml documents the real-Herdr coverage gap the local gate cannot close"
}

# ci.yml is the reference definition of what complete coverage means here, and
# the lane composition the scoped local runs are drawn from. It is not currently
# executed on this fork, so it is a reference, never the local gate's backstop.
test_ci_defines_the_reference_lane_composition() {
  assert_present "$CI" "ci.yml is missing"
  # Portable shards and the serial remainder cover every portable behavior
  # script through the one owner, with a deterministic inventory guard.
  grep -Fq 'bin/fm-test-run.sh --lane portable-parallel-1' "$CI" \
    || fail "CI must invoke portable parallel shard 1 through fm-test-run.sh"
  grep -Fq 'bin/fm-test-run.sh --lane portable-parallel-2' "$CI" \
    || fail "CI must invoke portable parallel shard 2 through fm-test-run.sh"
  grep -Fq 'bin/fm-test-run.sh --lane portable-serial' "$CI" \
    || fail "CI must invoke the portable serial remainder through fm-test-run.sh"
  grep -Fq 'bin/fm-test-run.sh --check-coverage' "$CI" \
    || fail "CI must prove complete lane coverage through fm-test-run.sh"
  # Guard against regression to an uninstrumented inline loop that drops timing.
  if grep -Eq 'for test_script in tests/\*\.test\.sh' "$CI"; then
    fail "CI Behavior must not re-spell an inline tests/*.test.sh loop; use fm-test-run.sh"
  fi
  # Preserve other CI lanes this task must not shrink.
  grep -Eq 'name:[[:space:]]*Lint shell scripts' "$CI" \
    || fail "CI must retain the lint job"
  grep -Eq 'name:[[:space:]]*Stock macOS Bash snapshot compatibility' "$CI" \
    || fail "CI must retain the macOS stock Bash compatibility job"
  grep -Eq 'name:[[:space:]]*Repo invariants' "$CI" \
    || fail "CI must retain the repo invariants job"
  grep -Fq 'tests-herdr:' "$CI" \
    || fail "CI must retain the required Herdr Behavior job"
  pass "CI still defines the partitioned reference lane composition and companion jobs"
}

test_nm_yaml_tracked
test_nm_keeps_lint_pin
test_nm_configures_a_scoped_local_test_command
test_nm_documents_the_local_herdr_gap
test_ci_defines_the_reference_lane_composition
