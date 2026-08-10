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
  assert_grep 'single owner of the Companion intake transformation' "$SKILL" \
    "Companion intake skill does not declare ownership"
  count=$(grep -Fc "load \`companion-intake\`" "$AGENTS")
  [ "$count" -eq 1 ] || fail "Companion intake must have exactly one root load trigger, found $count"
  pass "root contract narrowly assigns a game's own status or report to Companion"
}

test_skill_reuses_existing_owners() {
  local phrase
  for phrase in \
    'bin/fm-brief.sh' \
    'AGENTS.md` section 7' \
    '../ask-user-authority/SKILL.md' \
    '../decision-hold-lifecycle/SKILL.md' \
    'do not create a separate intake agent now' \
    "card's only writer" \
    'do not build a correction ledger or receipt protocol' \
    'mechanical checks to catch execution slips' \
    'planner or architect, executor, and fresh reviewer separation' \
    'do not invent an extra manual review gate' \
    'requests whose object is fleet, session, Firstmate, or work status remain Bearings-owned'; do
    assert_grep "$phrase" "$SKILL" "Companion intake lost existing-owner boundary: $phrase"
  done
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

test_root_contract_assigns_narrow_game_status_precedence
test_skill_reuses_existing_owners
test_manual_fresh_codex_acceptance_defines_causal_evidence
test_fixture_has_structured_intake_and_real_project_evidence
test_authored_context_card_copy_is_byte_stable
test_authored_expected_block_fits_existing_brief_format
