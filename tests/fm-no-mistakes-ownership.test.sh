#!/usr/bin/env bash
# Static contract tests for crew-owned no-mistakes validation runs.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

validate_contract() {
  awk '
    /^### Validate$/ { found = 1; next }
    found && /^### / { exit }
    found { print }
  ' "$ROOT/AGENTS.md"
}

test_worker_owns_synchronous_driver() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" 'The task worker that starts a no-mistakes run drives the pipeline' \
    "Validate contract does not assign the run to its initiating task worker"
  assert_contains "$contract" "owns every \`bin/fm-validate.sh <id> respond\` call through the next gate or outcome" \
    "Validate contract does not assign every synchronous driver call to the task worker"
  assert_contains "$contract" 'one initial review, one batched remediation, and at most one bounded closure review before tests' \
    "Validate contract does not state the executable review budget"
  assert_contains "$contract" 'A second remediation is refused' \
    "Validate contract allows the old repeated-rereview loop"
  assert_contains "$contract" 'Hard-earned 2026-08-12: raw review responses let one validation reach eleven review/fix passes before its first pipeline test' \
    "Validate contract lost the dated hard-earned review-runaway lesson"
  assert_contains "$contract" 'process every synchronous return until completion or a genuinely new escalation' \
    "Validate contract does not require the task worker to process every synchronous return"
  pass "Validate contract assigns the complete synchronous driver loop to the initiating task worker"
}

test_firstmate_never_responds_for_crew_run() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" "Firstmate never invokes either response command for a crew-owned run." \
    "Validate contract permits Firstmate to respond directly for a crew-owned run"
  pass "Validate contract forbids Firstmate from responding directly for a crew-owned run"
}

test_worker_owns_synchronous_driver
test_firstmate_never_responds_for_crew_run
