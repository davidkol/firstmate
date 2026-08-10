#!/usr/bin/env bash
# Contract and representative-flow tests for the Companion intake skill.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AGENTS="$ROOT/AGENTS.md"
SKILL="$ROOT/.agents/skills/companion-intake/SKILL.md"
FIXTURE="$ROOT/tests/fixtures/companion-intake"
CASES="$FIXTURE/cases.json"
TMP_ROOT=$(fm_test_tmproot fm-companion-intake)

test_root_trigger_reaches_single_owner() {
  local count
  assert_present "$SKILL" "Companion intake skill is missing"
  assert_grep 'name: companion-intake' "$SKILL" "Companion intake skill has the wrong name"
  assert_grep 'user-invocable: false' "$SKILL" "Companion intake skill must be agent-only"
  assert_grep '  internal: true' "$SKILL" "Companion intake skill must be internal"
  assert_grep "load \`companion-intake\` before writing the task brief" "$AGENTS" \
    "game-development intake does not trigger the Companion skill"
  assert_grep 'Purpose, doctrine, and design intent remain human-owned; never invent a missing value.' "$AGENTS" \
    "root Companion trigger lost the anti-invention boundary"
  assert_grep 'single owner of the Companion intake transformation' "$SKILL" \
    "Companion intake skill does not declare ownership"
  count=$(grep -Fc "load \`companion-intake\`" "$AGENTS")
  [ "$count" -eq 1 ] || fail "Companion intake must have exactly one root trigger, found $count"
  pass "root game-development trigger reaches one internal Companion intake owner"
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
    'do not invent an extra manual review gate'; do
    assert_grep "$phrase" "$SKILL" "Companion intake lost existing-owner boundary: $phrase"
  done
  assert_no_grep 'fm-spawn.sh --' "$SKILL" \
    "Companion intake duplicated dispatch mechanics instead of pointing to section 7"
  pass "Companion intake stays modular while reusing brief, authority, dispatch, and review owners"
}

test_fixture_covers_clear_ambiguity_correction_and_cold_handoff() {
  python3 - "$ROOT" "$CASES" <<'PY' \
    || fail "representative game fixture violated the Companion intake contract"
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
cases = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

clear = cases["clear_request"]
assert clear["verbatim"] == clear["verbatim_in_output"]
assert clear["meaning_facts"] == clear["cleaned_facts"]
assert clear["cleaned_reading"] != clear["verbatim"]
assert clear["pertinent_question"] is None
assert clear["path"] == "fast"

ambiguity = cases["pertinent_ambiguity"]
assert len(ambiguity["questions"]) == 1
assert ambiguity["dependent_work"] == ["grapple speed tuning"]
assert set(ambiguity["unrelated_work_that_can_continue"]) == {
    "release carry-through",
    "enemy attachment restriction",
}

correction = cases["captain_correction"]
assert correction["request_verbatim_after_correction"] == clear["verbatim"]
assert correction["rejected_offered_options"] is True
assert "Neither." in correction["verbatim_correction"]
assert "1.15" in correction["cleaned_reading_after_correction"]

context_card = cases["context_card"]
assert context_card["source_pointers"]
assert context_card["current_correction"] == correction["context_entry"]
for pointer in context_card["source_pointers"]:
    source, fragment = pointer.split("#", 1)
    assert (root / source).is_file(), pointer
    assert fragment.startswith("/"), pointer

routes = cases["review_routes"]
assert routes["mechanical"]["depth"] == "focused"
assert routes["behavior_change"]["depth"] == "full"
assert routes["mechanical"]["evidence"] != routes["behavior_change"]["evidence"]

handoff = cases["cold_worker_handoff"]
assert handoff["relevant_correction"] == correction["context_entry"]
assert handoff["unresolved_decisions"] == []
assert handoff["review_depth"] == "full"
assert handoff["seam_invariants"]
assert handoff["acceptance_environment"]["scene"]
assert handoff["acceptance_environment"]["check"]
for pointer in handoff["source_pointers"]:
    source, fragment = pointer.split("#", 1)
    assert (root / source).is_file(), pointer
    assert fragment.startswith("/"), pointer

design = json.loads((root / "tests/fixtures/companion-intake/project/design.json").read_text(encoding="utf-8"))
implementation = json.loads((root / "tests/fixtures/companion-intake/project/implementation.json").read_text(encoding="utf-8"))
assert design["document_role"] == "authoritative project-owned design intent"
assert implementation["document_role"] == "authoritative project-owned implementation state"
PY
  pass "representative game fixture covers the fast path, one pertinent question, correction, and cold handoff"
}

test_representative_flow_fills_real_brief_scaffold() {
  local home brief task_block
  home="$TMP_ROOT/home"
  mkdir -p "$home/data" "$home/state" "$TMP_ROOT/claude-config/projects"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config" \
    "$ROOT/bin/fm-brief.sh" companion-grapple GrappleGame >/dev/null 2>&1 \
    || fail "representative Companion flow could not scaffold the existing Firstmate brief"
  brief="$home/data/companion-grapple/brief.md"

  python3 - "$CASES" "$brief" <<'PY' \
    || fail "representative Companion flow could not fill the Firstmate brief"
import json
import sys
from pathlib import Path

cases = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
brief_path = Path(sys.argv[2])
clear = cases["clear_request"]
correction = cases["captain_correction"]
handoff = cases["cold_worker_handoff"]
sources = "\n".join(f"- `{pointer}`" for pointer in handoff["source_pointers"])
non_goals = "\n".join(f"- {item}." for item in handoff["non_goals"])
invariants = "\n".join(f"- {item}" for item in handoff["seam_invariants"])
done = "\n".join(f"- {item}" for item in handoff["observable_done"])
task = f"""## Verbatim request

> {clear['verbatim']}

## Cleaned reading

{correction['cleaned_reading_after_correction']}
Keep enemy attachment disabled.

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

- Scene: `{handoff['acceptance_environment']['scene']}`.
- Check: `{handoff['acceptance_environment']['check']}`.

## Observable done

{done}

## Review evidence

Behavior-changing: run the full project check, observe traversal behavior, and use the selected path's fresh reviewer.
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
    "- The cited design and implementation sources make the corrected release behavior implementation-ready.\n",
    1,
)
brief_path.write_text(text, encoding="utf-8")
PY

  "$ROOT/bin/fm-authority-receipts.sh" "$brief" >/dev/null 2>&1 \
    || fail "representative Companion brief did not pass the existing authority-receipts reader"
  for placeholder in '{TASK}' '{CAPTAIN_RULINGS}' '{FIRSTMATE_INFERENCE}'; do
    ! grep -Fxq "$placeholder" "$brief" || fail "representative brief retained $placeholder"
  done
  task_block=$(awk '
    /^# Task$/ { found = 1; next }
    found && /^# What the captain decided$/ { exit }
    found { print }
  ' "$brief")
  assert_contains "$task_block" '## Verbatim request' "filled brief lost the verbatim request"
  assert_contains "$task_block" '## Authoritative sources' "filled brief lost source pointers"
  assert_contains "$task_block" '## Seam invariants' "filled brief lost seam invariants"
  assert_contains "$task_block" '## Acceptance environment' "filled brief lost the acceptance environment"
  assert_contains "$task_block" '## Pertinent ambiguity' "filled brief lost ambiguity disposition"
  assert_contains "$task_block" $'## Pertinent ambiguity\n\nNone.' \
    "filled brief still exposes a worker decision"
  assert_not_contains "$task_block" '?' "decision-free task content still contains an unresolved question"
  pass "representative game request becomes a cold-readable decision-free Firstmate brief"
}

test_root_trigger_reaches_single_owner
test_skill_reuses_existing_owners
test_fixture_covers_clear_ambiguity_correction_and_cold_handoff
test_representative_flow_fills_real_brief_scaffold
