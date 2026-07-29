#!/usr/bin/env bash
# Behavior tests for the upward learning-promotion path: the checked gate that
# stops a home-local learning being retired before its tracked replacement
# lands, and the contract that keeps promotion rare.
# shellcheck disable=SC2016 # Literal Markdown backticks in contract assertions.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROMOTE="$ROOT/bin/fm-learning-promote.sh"

# Build a fake code root plus an empty home, export the overrides every case
# uses, and set T to the temp root. Sets globals, so call it directly rather than
# in a subshell.
setup_home() {
  local root
  T=$(fm_test_tmproot fm-learning-promote)
  root="$T/root"
  fm_git_init_commit "$root"
  printf '# Agents\n' > "$root/AGENTS.md"
  printf 'data/\n' > "$root/.gitignore"
  git -C "$root" add -A
  git -C "$root" -c user.name=t -c user.email=t@e.invalid commit -qm agents
  mkdir -p "$T/home/data"
  export FM_ROOT_OVERRIDE="$root" FM_HOME="$T/home" FM_DATA_OVERRIDE="$T/home/data"
}

# Land a real change to <path> on the code root's default branch.
land_tracked_change() {  # <root> <path>
  printf 'a promoted lesson\n' >> "$1/$2"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@e.invalid commit -qm promoted
}

test_start_records_an_in_flight_promotion() {
  local learnings out
  setup_home
  learnings="$T/home/data/learnings.md"

  assert_absent "$learnings" "learnings.md existed before the first promotion"
  out=$("$PROMOTE" start pane-tangle --to AGENTS.md \
    --evidence 'hit on both hookgame and Delivery' \
    --checkable 'the tangle check names the case') || fail "start failed: $out"

  assert_present "$learnings" "start did not create the home's learnings file"
  assert_grep 'slug=pane-tangle to=AGENTS.md' "$learnings" "start did not record the promotion marker"
  assert_grep 'True in more than one project: hit on both hookgame and Delivery' "$learnings" \
    "start did not record the stated evidence"
  assert_grep 'Checkable by: the tangle check names the case' "$learnings" \
    "start did not record what makes the lesson checkable"
  assert_grep 'land pane-tangle' "$learnings" "start did not record how to finish the promotion"

  out=$("$PROMOTE" list) || fail "list failed"
  assert_contains "$out" "waiting	pane-tangle	AGENTS.md" "list did not report the promotion as waiting"
  pass "start records a durable in-flight promotion the session digest will print"
}

test_start_refuses_an_ungraduated_or_unreachable_promotion() {
  local learnings out code
  setup_home
  learnings="$T/home/data/learnings.md"

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --checkable 'a check exists' 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a promotion with no stated cross-project evidence"
  assert_contains "$out" "--evidence" "refusal did not name the missing evidence"

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a promotion with nothing making it checkable"
  assert_contains "$out" "--checkable" "refusal did not name the missing checkability"

  out=$("$PROMOTE" start pane-tangle --to data/learnings.md \
    --evidence 'two projects' --checkable 'a check exists' 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a gitignored destination no other home receives"
  assert_contains "$out" "gitignored" "refusal did not name the unreachable destination"

  # Whitespace would be recorded in full but read back truncated at the space,
  # so land would gate on the wrong path and destroy the record it protects.
  out=$("$PROMOTE" start pane-tangle --to 'AGENTS.md extra' \
    --evidence 'two projects' --checkable 'a check exists' 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a destination the whitespace-delimited marker cannot record"
  assert_contains "$out" "whitespace" "refusal did not name the unrecordable destination path"

  assert_absent "$learnings" "a refused start still wrote to the home's learnings file"
  pass "start refuses an unstated graduation case and a destination no home would receive"
}

test_start_refuses_a_duplicate_in_flight_slug() {
  local out code before after
  setup_home
  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' >/dev/null \
    || fail "first start failed"
  before=$(cat "$T/home/data/learnings.md")

  out=$("$PROMOTE" start pane-tangle --to README.md --evidence 'two projects' --checkable 'a check' 2>&1) \
    && code=0 || code=$?
  expect_code 1 "$code" "start accepted a second promotion for a slug already in flight"
  assert_contains "$out" "already in flight" "duplicate refusal did not say why"

  after=$(cat "$T/home/data/learnings.md")
  [ "$before" = "$after" ] || fail "a refused duplicate start still edited the learnings file"
  pass "start refuses a duplicate in-flight slug without touching the record"
}

test_land_refuses_until_the_tracked_change_is_on_the_default_branch() {
  local out code
  setup_home
  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' >/dev/null \
    || fail "start failed"

  # An unrelated commit must not read as the promotion landing.
  git -C "$T/root" commit -q --allow-empty -m unrelated

  out=$("$PROMOTE" land pane-tangle 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "land retired a local entry whose tracked replacement had not landed"
  assert_contains "$out" "not landed" "refusal did not name the unlanded destination"
  assert_grep 'Promotion in flight' "$T/home/data/learnings.md" \
    "a refused land destroyed the in-flight record"
  pass "land refuses while the destination is unchanged, so the lesson is never lost"
}

test_land_replaces_the_record_with_one_pointer() {
  local learnings out
  setup_home
  learnings="$T/home/data/learnings.md"
  printf '# Operational learnings\n\n- 2026-07-01 an unrelated curated learning.\n' > "$learnings"

  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' >/dev/null \
    || fail "start failed"
  land_tracked_change "$T/root" AGENTS.md

  out=$("$PROMOTE" list) || fail "list failed"
  assert_contains "$out" "landed	pane-tangle	AGENTS.md" "list did not report the landed promotion"

  out=$("$PROMOTE" land pane-tangle) || fail "land failed: $out"
  assert_contains "$out" "landed: pane-tangle -> AGENTS.md" "land did not report the landing"
  assert_contains "$out" "prune the local entry" "land did not ask for the superseded entry to be pruned"

  assert_no_grep 'Promotion in flight' "$learnings" "land left the in-flight record behind"
  assert_no_grep 'fm-promotion' "$learnings" "land left the machine marker behind"
  assert_grep 'was promoted to `AGENTS.md`' "$learnings" "land did not leave a pointer to the tracked owner"
  assert_grep '- 2026-07-01 an unrelated curated learning.' "$learnings" \
    "land destroyed unrelated curated learnings"

  out=$("$PROMOTE" list) || fail "list failed after landing"
  [ -z "$out" ] || fail "a landed promotion is still listed as in flight: $out"
  pass "land swaps the in-flight record for one pointer and leaves other learnings alone"
}

test_stow_skill_owns_the_graduation_rule() {
  local stow="$ROOT/.agents/skills/stow/SKILL.md"

  assert_grep 'true in more than one project' "$stow" "stow skill lost the graduation rule"
  assert_grep 'it stays a note' "$stow" "stow skill lost the default that most knowledge stays a note"
  assert_grep 'bin/fm-learning-promote.sh start' "$stow" "stow skill does not name the promotion entry point"
  assert_grep 'bin/fm-learning-promote.sh land' "$stow" "stow skill does not name the landing gate"
  assert_grep 'before promoting a home-local learning' "$stow" \
    "stow skill's description does not trigger on a promotion"
  pass "stow skill owns the graduation rule and the two-phase promotion procedure"
}

test_agents_routes_upward_without_restating_the_mechanics() {
  local agents="$ROOT/AGENTS.md"

  assert_grep 'Load `stow` before promoting a home-local learning' "$agents" \
    "AGENTS.md lost the promotion load trigger"
  assert_grep 'true in more than one project and somebody can make it checkable' "$agents" \
    "AGENTS.md lost the inline graduation gate"
  assert_no_grep 'fm-learning-promote.sh start' "$agents" \
    "AGENTS.md restates promotion mechanics that the script header owns"
  pass "AGENTS.md routes a general lesson upward and leaves the mechanics to their owner"
}

test_start_records_an_in_flight_promotion
test_start_refuses_an_ungraduated_or_unreachable_promotion
test_start_refuses_a_duplicate_in_flight_slug
test_land_refuses_until_the_tracked_change_is_on_the_default_branch
test_land_replaces_the_record_with_one_pointer
test_stow_skill_owns_the_graduation_rule
test_agents_routes_upward_without_restating_the_mechanics
