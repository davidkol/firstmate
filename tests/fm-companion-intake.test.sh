#!/usr/bin/env bash
# Static routing-contract and authored artifact-format tests for Companion intake.
# Fresh-model routing remains a separate live verification surface.
# These tests do not prove Companion generation or a genuinely cold Codex read.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AGENTS="$ROOT/AGENTS.md"
SKILL="$ROOT/.agents/skills/companion-intake/SKILL.md"
BEARINGS_SKILL="$ROOT/.agents/skills/bearings/SKILL.md"
FIXTURE="$ROOT/tests/fixtures/companion-intake"
CASES="$FIXTURE/cases.json"
AUTHORED_CONTEXT_CARD="$FIXTURE/context-card.md"
PROJECT="$FIXTURE/project"
ACCEPTANCE_CHECK="$PROJECT/check_grapple_release.py"
MANUAL_ACCEPTANCE="$ROOT/docs/verification/companion-intake.md"
DESIGN_ACCEPTANCE="$ROOT/docs/verification/companion-design-intake.md"
DECISIONS="$ROOT/bin/fm-decision-hold.sh"
SEND="$ROOT/bin/fm-send.sh"
TMP_ROOT=$(fm_test_tmproot fm-companion-intake)

test_root_contract_assigns_narrow_game_status_precedence() {
  local count
  assert_present "$SKILL" "Companion intake skill is missing"
  assert_grep 'name: companion-intake' "$SKILL" "Companion intake skill has the wrong name"
  assert_grep 'user-invocable: false' "$SKILL" "Companion intake skill must be agent-only"
  assert_grep '  internal: true' "$SKILL" "Companion intake skill must be internal"
  assert_grep "load \`companion-intake\` before writing the task brief" "$AGENTS" \
    "game-development intake does not trigger the Companion skill"
  assert_grep "asks for the status or report of a resolved registered game itself, \`companion-intake\` takes precedence" "$AGENTS" \
    "a registered game's own status or report does not take Companion precedence"
  assert_grep "explicit \`/bearings\` and fleet, session, Firstmate, or work-status requests remain Bearings-owned" "$AGENTS" \
    "the root routing seam does not preserve explicit and fleet-scoped Bearings requests"
  assert_grep "Defer only when a request asks for a resolved registered game's own status or report" "$BEARINGS_SKILL" \
    "generic Bearings metadata does not narrowly defer a game's own status or report"
  assert_grep "resolved game project's own status or report; explicit /bearings and fleet, session, Firstmate, or work-status requests remain Bearings-owned" "$SKILL" \
    "Companion metadata does not preserve explicit and fleet-scoped Bearings ownership"
  assert_grep 'Purpose, doctrine, and design intent remain human-owned; never invent a missing value.' "$AGENTS" \
    "root Companion trigger lost the anti-invention boundary"
  assert_grep 'When a concrete design ambiguity affects ordinary work now, launch the separate design-intake scout' "$AGENTS" \
    "root intake contract does not launch separate task-ambiguity discovery"
  assert_grep "loading \`companion-intake\` is not a substitute for either discovery process" "$AGENTS" \
    "root intake contract still permits regular Companion to substitute for separate discovery"
  assert_grep 'single owner of the Companion intake transformation' "$SKILL" \
    "Companion intake skill does not declare ownership"
  count=$(grep -Fc "load \`companion-intake\`" "$AGENTS")
  [ "$count" -eq 1 ] || fail "Companion intake must have exactly one root load trigger, found $count"
  pass "root contract narrowly assigns a game's own status or report to Companion"
}

test_skill_reuses_existing_owners() {
  local phrase
  # shellcheck disable=SC2016 # Backticks below are literal Markdown code spans.
  for phrase in \
    'bin/fm-brief.sh' \
    'AGENTS.md` section 7' \
    '../ask-user-authority/SKILL.md' \
    '../decision-hold-lifecycle/SKILL.md' \
    'separate `bin/fm-brief.sh --design-intake` scout discovers and filters grounded candidates' \
    'Regular Companion presents exactly one pertinent question' \
    'preserves exact answers and corrections' \
    'routes accepted answers into ordinary work through the existing owners' \
    "card's only writer" \
    'do not build a correction ledger or receipt protocol' \
    'mechanical checks to catch execution slips' \
    'planner or architect, executor, and fresh reviewer separation' \
    'do not invent an extra manual review gate' \
    'requests whose object is fleet, session, Firstmate, or work status remain Bearings-owned'; do
    assert_grep "$phrase" "$SKILL" "Companion intake lost existing-owner boundary: $phrase"
  done
  assert_no_grep 'do not create a separate intake agent now' "$SKILL" \
    "Companion intake retained the obsolete no-separate-agent instruction"
  assert_no_grep 'fm-spawn.sh --' "$SKILL" \
    "Companion intake duplicated dispatch mechanics instead of pointing to section 7"
  pass "Companion intake stays modular while reusing brief, authority, dispatch, and review owners"
}

test_manual_fresh_codex_acceptance_defines_causal_evidence() {
  local phrase
  assert_present "$MANUAL_ACCEPTANCE" "manual fresh-Codex Companion acceptance is missing"
  for phrase in \
    'natural-language request -> project sources -> produced card and brief -> captain correction -> genuinely cold read' \
    'Those deterministic tests do not prove that Companion generated either artifact' \
    "makes \`tests/fm-companion-intake.test.sh\`, \`tests/fixtures/companion-intake/cases.json\`, and the authored \`tests/fixtures/companion-intake/context-card.md\` absent or unreadable" \
    'Okay, we can try it for Delivery Pull up the status report of the game' \
    '/bearings for Delivery' \
    'give me the fleet work status for Delivery' \
    'Pull up the fleet status report' \
    'Start a genuinely cold Codex context' \
    'grapple-release acceptance: velocity=23.00 tether_cleared=true enemy_attach=false'; do
    assert_grep "$phrase" "$MANUAL_ACCEPTANCE" \
      "manual Companion acceptance lost required evidence step: $phrase"
  done
  pass "manual fresh-Codex scenario defines the required transformation and cold-read evidence"
}

test_fixture_has_structured_intake_and_real_project_evidence() {
  local acceptance_output fixture_file
  for fixture_file in \
    "$AUTHORED_CONTEXT_CARD" \
    "$PROJECT/design.json" \
    "$PROJECT/grapple.py" \
    "$PROJECT/status.json" \
    "$PROJECT/open-decisions.json" \
    "$ACCEPTANCE_CHECK"; do
    assert_present "$fixture_file" "Companion project fixture is missing $fixture_file"
  done
  [ -x "$ACCEPTANCE_CHECK" ] || fail "Companion acceptance check is not directly runnable"
  acceptance_output=$("$ACCEPTANCE_CHECK") \
    || fail "Companion project acceptance check failed"
  [ "$acceptance_output" = 'grapple-release acceptance: velocity=23.00 tether_cleared=true enemy_attach=false' ] \
    || fail "Companion project acceptance output was not the observed game behavior"

  python3 - "$ROOT" "$CASES" "$AUTHORED_CONTEXT_CARD" <<'PY' \
    || fail "authored expected fixture violated the structured Companion contract"
import importlib.util
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
cases = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
card = Path(sys.argv[3]).read_text(encoding="utf-8")
project = root / "tests/fixtures/companion-intake/project"

routing_cases = cases["routing_cases"]
assert len(routing_cases) == 4
routing = {case["id"]: case for case in routing_cases}
assert set(routing) == {
    "named_game_is_report_object",
    "explicit_bearings_mentions_game",
    "fleet_work_status_mentions_game",
    "unnamed_fleet_status",
}
positive = routing["named_game_is_report_object"]
assert positive["verbatim"] == "Okay, we can try it for Delivery Pull up the status report of the game"
assert positive["registered_game_project"] == "Delivery"
assert positive["requested_status_object"] == "Delivery game"
assert positive["game_is_requested_object"] is True
assert positive["explicit_bearings"] is False
assert positive["expected_owner"] == "companion-intake"

explicit = routing["explicit_bearings_mentions_game"]
assert explicit["verbatim"] == "/bearings for Delivery"
assert explicit["registered_game_project"] == "Delivery"
assert explicit["game_is_requested_object"] is False
assert explicit["explicit_bearings"] is True
assert explicit["expected_owner"] == "bearings"

fleet_work = routing["fleet_work_status_mentions_game"]
assert fleet_work["verbatim"] == "give me the fleet work status for Delivery"
assert fleet_work["registered_game_project"] == "Delivery"
assert fleet_work["requested_status_object"] == "fleet work"
assert fleet_work["game_is_requested_object"] is False
assert fleet_work["expected_owner"] == "bearings"

unnamed = routing["unnamed_fleet_status"]
assert unnamed["verbatim"] == "Pull up the fleet status report"
assert unnamed["registered_game_project"] is None
assert unnamed["requested_status_object"] == "fleet"
assert unnamed["game_is_requested_object"] is False
assert unnamed["expected_owner"] == "bearings"

clear = cases["clear_request"]
assert clear["verbatim"] == clear["verbatim_in_intake"]
assert clear["meaning_facts"] == clear["cleaned_facts"]
assert clear["cleaned_reading"] != clear["verbatim"]
assert clear["pertinent_ambiguity"] == {
    "status": "none",
    "question": None,
    "unresolved_decisions": [],
}
assert clear["path"] == "fast"

ambiguity = cases["pertinent_ambiguity"]
assert ambiguity["verbatim"] == ambiguity["verbatim_in_intake"]
assert ambiguity["verbatim"].endswith("too... right?")
assert ambiguity["status"] == "open"
assert len(ambiguity["questions"]) == 1
question = ambiguity["questions"][0]
assert question["text"].endswith("swinging?")
assert set(question["could_change"]) == {
    "hook projectile timing",
    "swing acceleration",
}
assert question["dependent_work"] == ["grapple speed tuning"]
assert set(question["unrelated_work_that_can_continue"]) == {
    "release carry-through",
    "enemy attachment restriction",
}

correction = cases["captain_correction"]
assert correction["request_verbatim_after_correction"] == clear["verbatim"]
assert correction["follow_up_verbatim_after_correction"] == ambiguity["verbatim"]
assert correction["rejected_offered_options"] is True
assert "Neither." in correction["verbatim_correction"]
assert "1.15" in correction["cleaned_reading_after_correction"]
assert correction["resolved_ambiguity"] == {
    "status": "none",
    "question": None,
    "unresolved_decisions": [],
}

design = json.loads((project / "design.json").read_text(encoding="utf-8"))
status = json.loads((project / "status.json").read_text(encoding="utf-8"))
decisions = json.loads((project / "open-decisions.json").read_text(encoding="utf-8"))
spec = importlib.util.spec_from_file_location("grapple", project / "grapple.py")
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
tether_cleared, velocity = module.release_grapple(20.0)
assert design["release"]["carry_multiplier"] == 1.15
assert tether_cleared is True and velocity == 23.0
assert "zero" in status["grapple_release_claim"].lower()
assert velocity != 0.0
assert len(decisions["decisions"]) == 1
assert decisions["decisions"][0]["status"] == "open"
assert decisions["decisions"][0]["affects"] == ["pre-fire visual feedback"]

routes = cases["review_routes"]
assert routes["mechanical"]["depth"] == "focused"
assert routes["behavior_change"]["depth"] == "full"
assert routes["mechanical"]["evidence"] != routes["behavior_change"]["evidence"]

handoff = cases["expected_cold_worker_handoff"]
assert handoff["relevant_correction"] == correction["context_entry"]
assert handoff["pertinent_ambiguity"] == correction["resolved_ambiguity"]
assert handoff["review_depth"] == "full"
assert handoff["seam_invariants"]
assert handoff["acceptance_environment"]["check"]
assert handoff["acceptance_environment"]["expected_output"]
assert len(handoff["source_references"]) >= 5
for reference in handoff["source_references"]:
    pointer = reference["pointer"]
    source, _, fragment = pointer.partition("#")
    assert (root / source).is_file(), pointer
    assert reference["rationale"], pointer
    assert reference["rationale"] in card, pointer
    if fragment:
        assert fragment.startswith(("/", "release_grapple")), pointer

assert f"> {clear['verbatim']}" in card
assert f"> {ambiguity['verbatim']}" in card
assert correction["context_entry"] in card
for heading in (
    "## Current goal",
    "## Priorities",
    "### Built",
    "### Planned",
    "### Unknown",
    "## Open decisions",
    "## Source pointers and pertinence",
):
    assert heading in card
assert "stale" in card.lower()
assert decisions["decisions"][0]["question"] in card
PY
  pass "authored expected fixture has exact structure, project-owned sources, and runnable behavior"
}

test_authored_context_card_copy_is_byte_stable() {
  local home copied_card first_digest second_digest
  home="$TMP_ROOT/copy-home"
  copied_card="$home/data/project-context/GrappleGame.md"
  mkdir -p "$(dirname "$copied_card")"

  python3 - "$AUTHORED_CONTEXT_CARD" "$copied_card" <<'PY' \
    || fail "authored context-card fixture could not be copied"
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.write_bytes(source.read_bytes())
PY

  first_digest=$(python3 - "$copied_card" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
  )
  second_digest=$(python3 - "$copied_card" "$CASES" <<'PY' \
    || fail "independent parser read lost authored request or correction text"
import hashlib
import json
import sys
from pathlib import Path

card_path = Path(sys.argv[1])
cases = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
card = card_path.read_text(encoding="utf-8")
assert f"> {cases['clear_request']['verbatim']}" in card
assert f"> {cases['pertinent_ambiguity']['verbatim']}" in card
assert cases["captain_correction"]["context_entry"] in card
for reference in cases["expected_cold_worker_handoff"]["source_references"]:
    assert reference["rationale"] in card
print(hashlib.sha256(card_path.read_bytes()).hexdigest())
PY
  )
  [ "$first_digest" = "$second_digest" ] \
    || fail "authored context-card copy changed across independent parser reads"
  cmp -s "$AUTHORED_CONTEXT_CARD" "$copied_card" \
    || fail "context-card copy is not byte-identical to its authored fixture"
  pass "authored Markdown context card is byte-stable across copy and parser reads"
}

test_authored_expected_block_fits_existing_brief_format() {
  local home brief copied_card task_block
  home="$TMP_ROOT/brief-home"
  copied_card="$home/data/project-context/GrappleGame.md"
  mkdir -p "$home/data/project-context" "$home/state" "$TMP_ROOT/claude-config/projects"
  cp "$AUTHORED_CONTEXT_CARD" "$copied_card"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config" \
    "$ROOT/bin/fm-brief.sh" companion-grapple GrappleGame >/dev/null 2>&1 \
    || fail "authored expected block could not scaffold the existing Firstmate brief"
  brief="$home/data/companion-grapple/brief.md"

  python3 - "$CASES" "$brief" <<'PY' \
    || fail "authored expected fixture could not fill the Firstmate brief format"
import json
import sys
from pathlib import Path

cases = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
brief_path = Path(sys.argv[2])
clear = cases["clear_request"]
ambiguity = cases["pertinent_ambiguity"]
correction = cases["captain_correction"]
handoff = cases["expected_cold_worker_handoff"]
sources = "\n".join(
    f"- `{item['pointer']}` - {item['rationale']}"
    for item in handoff["source_references"]
)
non_goals = "\n".join(f"- {item}." for item in handoff["non_goals"])
invariants = "\n".join(f"- {item}" for item in handoff["seam_invariants"])
done = "\n".join(f"- {item}" for item in handoff["observable_done"])
task = f"""## Verbatim request

### Initial request

> {clear['verbatim']}

### Follow-up

> {ambiguity['verbatim']}

## Cleaned reading

{correction['cleaned_reading_after_correction']}
Keep enemy attachment disabled.

## Project context card

`data/project-context/GrappleGame.md`

## Authoritative sources

{sources}

## Desired behavior

{handoff['desired_behavior']}

## Relevant correction

{handoff['relevant_correction']}

## Pertinent ambiguity

None.

## Non-goals

{non_goals}

## Seam invariants

{invariants}

## Acceptance environment

- Check: `{handoff['acceptance_environment']['check']}`.
- Expected observation: `{handoff['acceptance_environment']['expected_output']}`.

## Observable done

{done}

## Review evidence

Behavior-changing: run the full project check, observe grapple release once, and use the selected path's fresh reviewer.
"""
text = brief_path.read_text(encoding="utf-8")
text = text.replace("{TASK}\n", task + "\n", 1)
text = text.replace(
    "{CAPTAIN_RULINGS}\n",
    f"- \"{correction['verbatim_correction']}\" - 2026-08-10.\n",
    1,
)
text = text.replace(
    "{FIRSTMATE_INFERENCE}\n",
    "- The cited design, code, status, decision, and acceptance sources make the corrected release behavior implementation-ready.\n",
    1,
)
brief_path.write_text(text, encoding="utf-8")
PY

  "$ROOT/bin/fm-authority-receipts.sh" "$brief" >/dev/null 2>&1 \
    || fail "authored expected brief did not pass the existing authority-receipts reader"
  for placeholder in '{TASK}' '{CAPTAIN_RULINGS}' '{FIRSTMATE_INFERENCE}'; do
    ! grep -Fxq "$placeholder" "$brief" || fail "authored expected brief retained $placeholder"
  done
  task_block=$(awk '
    /^# Task$/ { found = 1; next }
    found && /^# What the captain decided$/ { exit }
    found { print }
  ' "$brief")
  assert_contains "$task_block" '## Verbatim request' "filled brief lost the verbatim request"
  assert_contains "$task_block" '> Make the grapple faster, too... right?' \
    "filled brief did not preserve verbatim follow-up punctuation"
  assert_contains "$task_block" '## Authoritative sources' "filled brief lost source pointers"
  assert_contains "$task_block" '## Seam invariants' "filled brief lost seam invariants"
  assert_contains "$task_block" '## Acceptance environment' "filled brief lost the acceptance environment"
  assert_contains "$task_block" $'## Pertinent ambiguity\n\nNone.' \
    "filled brief still exposes a pertinent worker decision"

  python3 - "$CASES" "$brief" "$copied_card" <<'PY' \
    || fail "independent format reader lost authored ambiguity, correction, or source rationale"
import json
import sys
from pathlib import Path

cases = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
brief = Path(sys.argv[2]).read_text(encoding="utf-8")
card = Path(sys.argv[3]).read_text(encoding="utf-8")
handoff = cases["expected_cold_worker_handoff"]
assert handoff["pertinent_ambiguity"] == {
    "status": "none",
    "question": None,
    "unresolved_decisions": [],
}
assert cases["captain_correction"]["context_entry"] in brief
assert cases["captain_correction"]["context_entry"] in card
for reference in handoff["source_references"]:
    assert reference["pointer"] in brief
    assert reference["rationale"] in brief
    assert reference["rationale"] in card
PY
  pass "authored expected task block fits the real brief scaffold and preserves cited text"
}

make_design_home() {  # <name>
  local home="$TMP_ROOT/$1" fakebin
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  fakebin=$(fm_fakebin "$home")
  fm_fake_exit0 "$fakebin" treehouse no-mistakes gh gh-axi
  printf '%s\n' "$home"
}

tasks_in() {  # <home> <tasks-axi args...>
  local home=$1
  shift
  (cd "$home" && tasks-axi "$@")
}

run_decisions() {  # <home> <command args...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$DECISIONS" "$@"
}

write_design_origin() {  # <home> <id>
  local home=$1 id=$2
  fm_write_meta "$home/state/$id.meta" \
    "window=firstmate:fm-$id" \
    "worktree=$home/projects/Delivery-$id" \
    "project=$home/projects/Delivery" \
    "harness=codex" \
    "backend=tmux" \
    "kind=scout" \
    "mode=scout"
}

assert_hold_rejected_before_identity() {  # <home> <key> <hold args...>
  local home=$1 key=$2 before after out
  shift 2
  before=$(grep -cE '^- \[ \] .*decision-' "$home/data/backlog.md" || true)
  out="$home/rejected-$RANDOM"
  if run_decisions "$home" hold sample-intake "$key" "$@" > "$out.out" 2> "$out.err"; then
    fail "malformed hold input unexpectedly succeeded for key '$key'"
  fi
  after=$(grep -cE '^- \[ \] .*decision-' "$home/data/backlog.md" || true)
  [ "$before" = "$after" ] \
    || fail "malformed hold input created a backlog identity for key '$key'"
}

make_design_send_stubs() {  # <home>
  local fakebin=$1/fakebin
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  send-keys)
    shift
    literal=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=1; shift ;;
        *) break ;;
      esac
    done
    if [ "$literal" = 1 ]; then
      printf '%s' "${1:-}" >> "$FM_SEND_LOG"
    fi
    exit 0
    ;;
  display-message)
    for arg in "$@"; do
      case "$arg" in
        *cursor_y*) printf '1\n'; exit 0 ;;
      esac
    done
    printf 'fakepane\n'
    exit 0
    ;;
  capture-pane)
    printf '╭────╮\n│    │\n╰────╯\n'
    exit 0
    ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  cat > "$fakebin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/sleep"
}

run_design_send() {  # <home> <log> <fm-send args...>
  local home=$1 log=$2
  shift 2
  env PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$home" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_SEND_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" "$@" 2>/dev/null
}

terminal_order_valid() {  # <event-log>
  awk '
    $0 == "first-steer" && !first { first = NR }
    $0 == "complete" && !complete { complete = NR }
    $0 == "second-steer" && !second { second = NR }
    $0 == "done" && !done { done = NR }
    END { exit !(first && complete && second && done && first < complete && complete < second && second < done) }
  ' "$1"
}

test_design_intake_contract_routes_without_new_machinery() {
  local home brief
  home="$TMP_ROOT/design-contract"
  mkdir -p "$home/data" "$home/state"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-brief.sh" design-contract Delivery --design-intake >/dev/null 2>&1 \
    || fail "could not generate the design-intake routing contract"
  brief="$home/data/design-contract/brief.md"

  for phrase in \
    'Classify the answerability axis before the disposition' \
    "\`discussion\` maps only to \`--answerable desk\`" \
    "\`play\` maps only to \`--answerable play\`" \
    'independently verify semantic equivalence' \
    'do not create a second hold' \
    'Do not add a dependency edge to any affected task while the answer is pending' \
    "add the decision-hold dependency immediately before the existing \`resolve\` command" \
    'first still-valid new shortlist item' \
    'one pertinent independently matched existing question' \
    'Shortlist rank is used only for that immediate handoff and is never persisted' \
    'Later retrieval presents exactly one pertinent context-appropriate question'; do
    assert_grep "$phrase" "$brief" "design-intake routing contract lost: $phrase"
  done
  assert_absent "$ROOT/.agents/skills/design-intake" \
    "implementation added a prohibited design-intake skill"
  assert_absent "$ROOT/.agents/skills/companion-design-intake" \
    "implementation added a prohibited companion-design-intake skill"
  pass "design-intake static contract routes duplicate, axis, dependency, and handoff behavior through existing owners"
}

test_target_design_intake_routes_bulk_without_task_holds() {
  local home brief
  home="$TMP_ROOT/target-design-contract"
  mkdir -p "$home/data" "$home/state"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-brief.sh" target-design-contract Martyrdome --target-design-intake >/dev/null 2>&1 \
    || fail "could not generate the target-design intake contract"
  brief="$home/data/target-design-contract/brief.md"

  assert_grep 'When the captain is collaboratively constructing or revising a broad game-design target, launch the target-design intake scout' "$AGENTS" \
    "root routing does not distinguish broad target design from task ambiguity"
  assert_grep 'Broad target-design collaboration and concrete task ambiguity use separate paths' "$SKILL" \
    "Companion does not own the target-design versus task-ambiguity split"
  assert_grep 'bin/fm-brief.sh --target-design-intake' "$SKILL" \
    "Companion does not route broad target design to its scaffold owner"
  assert_grep 'clean bulk questionnaire by default' "$SKILL" \
    "Companion does not carry the captain's default bulk presentation"
  assert_grep 'one-at-a-time dialogue only when the captain requests it' "$SKILL" \
    "Companion does not preserve the optional dialogue mode"
  assert_grep 'Preserve each answered question, its offered context, and the exact answer before synthesis' "$SKILL" \
    "Companion does not preserve bulk answers before synthesis"
  assert_grep 'reconcile the living target in batches' "$SKILL" \
    "Companion does not batch target prose reconciliation"

  assert_grep 'captain-facing questionnaire' "$brief" \
    "target-design scaffold lacks its separate captain surface"
  assert_grep 'Do not register decision holds' "$brief" \
    "target-design scaffold leaks questions into ordinary work holds"
  assert_no_grep 'first still-valid new shortlist item' "$brief" \
    "target-design scaffold inherited one-question presentation"
  pass "target-design intake routes clean bulk Q&A separately from task-blocking ambiguity"
}

test_report_fields_execute_directly_and_answer_routing_is_nonblocking() {
  local home origin hold row existing_origin existing_hold show decision_file
  command -v tasks-axi >/dev/null 2>&1 || fail "tasks-axi is required for Companion intake routing evidence"
  home=$(make_design_home direct-hold)
  origin=sample-intake
  write_design_origin "$home" "$origin"
  printf 'working: inspecting Delivery sources\n' > "$home/state/$origin.status"

  hold=$(run_decisions "$home" hold "$origin" gravity-driver-contention \
    --title "Should competing gravity drivers remain as current chaos?" \
    --reason "Two live gravity drivers can restore the same room during one veer" \
    --default "Keep current contention until the next playtest" \
    --answerable play \
    --repo Delivery) || fail "schema-valid generated fields did not pass directly to the real hold command"
  [ "$hold" = 'sample-intake-decision-gravity-driver-contention' ] \
    || fail "direct hold command returned an unexpected identity: $hold"
  row=$(run_decisions "$home" list --answerable play) || fail "play hold listing failed"
  [ "$row" = "$(printf 'play\t%s\t%s\t%s' "$hold" \
    'Keep current contention until the next playtest' \
    'Should competing gravity drivers remain as current chaos?')" ] \
    || fail "play fields changed between the report-compatible command and the real list: $row"

  existing_origin=earlier-intake
  write_design_origin "$home" "$existing_origin"
  existing_hold=$(run_decisions "$home" hold "$existing_origin" bridge-role-order \
    --title "Should the bridge role order remain fixed?" \
    --reason "Current role churn leaves bridge order open for discussion" \
    --default "Keep the current bridge order" \
    --answerable desk \
    --repo Delivery) || fail "could not create the independently matched desk hold"
  row=$(run_decisions "$home" list --answerable desk) || fail "desk hold listing failed"
  assert_contains "$row" "$(printf 'desk\t%s\tKeep the current bridge order' "$existing_hold")" \
    "discussion-to-desk routing did not survive the real list command"
  [ "$(grep -cE '^- \[ \] sample-intake-decision-bridge-role-order ' "$home/data/backlog.md" || true)" = 0 ] \
    || fail "the independently matched existing hold was duplicated under the new intake origin"

  assert_hold_rejected_before_identity "$home" 'bad key' \
    --title "Malformed key" --reason "Malformed key must fail" \
    --default "Keep current behavior" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" multiline-title \
    --title $'First line\nSecond line' --reason "Multiline title must fail" \
    --default "Keep current behavior" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" parenthesized-reason \
    --title "Parenthesized reason" --reason "Current behavior has two options (today)" \
    --default "Keep current behavior" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" parenthesized-default \
    --title "Parenthesized default" --reason "Current behavior needs a safe default" \
    --default "Keep current behavior (today)" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" reserved-reason \
    --title "Reserved reason" --reason "Reason | default if unanswered: hidden" \
    --default "Keep current behavior" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" reserved-default \
    --title "Reserved default" --reason "Default must not carry markers" \
    --default "Keep current behavior | answerable: desk" --answerable desk --repo Delivery
  assert_hold_rejected_before_identity "$home" comma-default \
    --title "Comma default" --reason "Default must survive the real reader" \
    --default "Keep current behavior, then retest" --answerable desk --repo Delivery

  tasks_in "$home" add sample-gravity-work "Apply the chosen gravity behavior" \
    --kind ship --repo Delivery >/dev/null || fail "could not create ordinary affected work"
  show=$(tasks_in "$home" show sample-gravity-work --full)
  assert_contains "$show" "blocked: no" "a waiting question pre-blocked affected ordinary work"
  mkdir -p "$home/data/$origin"
  decision_file="$home/data/$origin/decision-gravity-driver-contention.md"
  printf '2026-08-11: Keep current contention until the next playtest.\n' > "$decision_file"
  if run_decisions "$home" resolve "$origin" gravity-driver-contention \
    --decision-file "$decision_file" --routed-to sample-gravity-work \
    > "$home/early-resolve.out" 2> "$home/early-resolve.err"; then
    fail "real resolve succeeded before answer-time dependency routing"
  fi
  show=$(tasks_in "$home" show sample-gravity-work --full)
  assert_contains "$show" "blocked: no" "failed early resolution blocked ordinary work"
  tasks_in "$home" block sample-gravity-work --by "$hold" >/dev/null \
    || fail "could not add the answer-time decision dependency"
  show=$(tasks_in "$home" show sample-gravity-work --full)
  assert_contains "$show" "blocked: yes" "answer-time dependency was not observed before resolve"
  run_decisions "$home" resolve "$origin" gravity-driver-contention \
    --decision-file "$decision_file" --routed-to sample-gravity-work >/dev/null \
    || fail "real resolve did not clear the immediately preceding answer-time dependency"
  show=$(tasks_in "$home" show sample-gravity-work --full)
  assert_contains "$show" "blocked: no" "real resolve left ordinary work blocked"
  show=$(tasks_in "$home" show "$hold" --full)
  assert_contains "$show" "state: done" "real resolve did not close the routed captain hold"
  pass "report fields feed the real hold command and only answer-time routing briefly blocks ordinary work"
}

test_report_ready_requires_first_steer_then_completion_then_second_steer() {
  local home origin send_log events bad_complete bad_done
  home=$(make_design_home report-ready-order)
  make_design_send_stubs "$home"
  origin=sample-report-ready
  write_design_origin "$home" "$origin"
  printf 'blocked [key=report-ready]: report ready for decision reconciliation\n' \
    > "$home/state/$origin.status"
  send_log="$home/send.log"
  events="$home/events.log"
  : > "$send_log"
  : > "$events"

  if run_decisions "$home" complete "$origin" --none \
    > "$home/early-complete.out" 2> "$home/early-complete.err"; then
    fail "complete --none succeeded while report-ready was open"
  fi
  run_design_send "$home" "$send_log" "$origin" --resolve-key report-ready \
    "Decision reconciliation is complete. Stay stopped and do not report done until a second message says the completion check passed." \
    || fail "the real first steer did not resolve report-ready"
  printf 'first-steer\n' >> "$events"
  assert_grep 'resolved [key=report-ready]:' "$home/state/$origin.status" \
    "the first steer did not close report-ready through the real status fold"
  assert_no_grep 'done:' "$home/state/$origin.status" \
    "the first steer permitted terminal done before completion"
  assert_contains "$(cat "$send_log")" "do not report done" \
    "the first steer did not explicitly withhold terminal completion"

  run_decisions "$home" complete "$origin" --none >/dev/null \
    || fail "complete --none did not succeed after report-ready resolution"
  printf 'complete\n' >> "$events"
  : > "$send_log"
  run_design_send "$home" "$send_log" "$origin" \
    "The completion check passed. Append the terminal done line now." \
    || fail "the real second ordinary steer failed"
  printf 'second-steer\n' >> "$events"
  assert_contains "$(cat "$send_log")" "Append the terminal done line now" \
    "the second steer did not authorize terminal completion"
  [ "$(grep -cF 'resolved [key=report-ready]:' "$home/state/$origin.status")" = 1 ] \
    || fail "the ordinary second steer unexpectedly resolved a key"
  printf 'done: design-intake report reconciled\n' >> "$home/state/$origin.status"
  printf 'done\n' >> "$events"
  terminal_order_valid "$events" || fail "the observed real lifecycle was not terminally ordered"

  bad_complete="$home/bad-complete-order.log"
  printf 'complete\nfirst-steer\nsecond-steer\ndone\n' > "$bad_complete"
  if terminal_order_valid "$bad_complete"; then
    fail "ordering assertion accepted completion before the first steer"
  fi
  bad_done="$home/bad-done-order.log"
  printf 'first-steer\ncomplete\ndone\nsecond-steer\n' > "$bad_done"
  if terminal_order_valid "$bad_done"; then
    fail "ordering assertion accepted terminal done before the second steer"
  fi
  pass "report-ready closes through the real first steer before completion and done waits for the ordinary second steer"
}

test_design_intake_verification_owner_reserves_model_discovery_for_cold_delivery() {
  local phrase
  assert_present "$DESIGN_ACCEPTANCE" "separate design-intake verification owner is missing"
  for phrase in \
    'genuinely cold Delivery acceptance' \
    'Static tests prove format and routing only' \
    'must not be run in the implementation writer lane' \
    'SPACEGAME.md' \
    'docs/execution.md' \
    'docs/findings.md' \
    'docs/reviews/z5-playtest-kit.md' \
    'data/delivery-game-status-report/decision-fl5c-helm-view.md' \
    'newly started bare Codex process' \
    'Zero new holds is a valid result' \
    'first steer' \
    'second ordinary steer' \
    'Static fixtures did not prove model generation'; do
    assert_grep "$phrase" "$DESIGN_ACCEPTANCE" \
      "separate design-intake verification owner lost: $phrase"
  done
  python3 - "$ROOT/docs/documentation-audiences.json" <<'PY' \
    || fail "separate design-intake verification owner is not classified"
import json
import sys

inventory = json.load(open(sys.argv[1], encoding="utf-8"))
matches = [
    item for item in inventory["surfaces"]
    if item.get("path") == "docs/verification/companion-design-intake.md"
]
assert matches == [{
    "path": "docs/verification/companion-design-intake.md",
    "audience": "maintainer-verification",
}]
PY
  pass "separate design-intake verification owner reserves model discovery for the later cold Delivery process"
}

test_root_contract_assigns_narrow_game_status_precedence
test_skill_reuses_existing_owners
test_manual_fresh_codex_acceptance_defines_causal_evidence
test_fixture_has_structured_intake_and_real_project_evidence
test_authored_context_card_copy_is_byte_stable
test_authored_expected_block_fits_existing_brief_format
test_design_intake_contract_routes_without_new_machinery
test_target_design_intake_routes_bulk_without_task_holds
test_report_fields_execute_directly_and_answer_routing_is_nonblocking
test_report_ready_requires_first_steer_then_completion_then_second_steer
test_design_intake_verification_owner_reserves_model_discovery_for_cold_delivery
