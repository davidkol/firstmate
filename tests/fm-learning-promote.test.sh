#!/usr/bin/env bash
# Behavior tests for the upward learning-promotion path: the checked gate that
# stops a home-local learning being retired before its tracked replacement
# lands, and the contract that keeps promotion rare.
# shellcheck disable=SC2016 # Literal Markdown backticks in contract assertions.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROMOTE="$ROOT/bin/fm-learning-promote.sh"

# The distinguishing phrase a promotion says will appear in the destination once
# the tracked change lands. Landing it is what `land` requires as proof.
LANDED_TEXT='the promoted lesson sentence'

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

# Land the promoted text itself into <path> on the default branch - the real
# landing the gate is meant to recognise.
land_tracked_change() {  # <root> <path>
  printf '%s\n' "$LANDED_TEXT" >> "$1/$2"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@e.invalid commit -qm promoted
}

# Land an UNRELATED change to <path>: the file changes, but the promoted text is
# nowhere in it. This is the ordinary case of another PR touching AGENTS.md.
land_unrelated_change() {  # <root> <path>
  printf 'an unrelated shared-material change\n' >> "$1/$2"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@e.invalid commit -qm unrelated
}

test_start_records_an_in_flight_promotion() {
  local learnings out
  setup_home
  learnings="$T/home/data/learnings.md"

  assert_absent "$learnings" "learnings.md existed before the first promotion"
  out=$("$PROMOTE" start pane-tangle --to AGENTS.md \
    --evidence 'hit on both hookgame and Delivery' \
    --checkable 'the tangle check names the case' \
    --landed-text 'a worktree tangle names the stranded checkout') || fail "start failed: $out"

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

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --checkable 'a check exists' --landed-text "$LANDED_TEXT" 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a promotion with no stated cross-project evidence"
  assert_contains "$out" "--evidence" "refusal did not name the missing evidence"

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --landed-text "$LANDED_TEXT" 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a promotion with nothing making it checkable"
  assert_contains "$out" "--checkable" "refusal did not name the missing checkability"

  out=$("$PROMOTE" start pane-tangle --to data/learnings.md \
    --evidence 'two projects' --checkable 'a check exists' --landed-text "$LANDED_TEXT" 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a gitignored destination no other home receives"
  assert_contains "$out" "gitignored" "refusal did not name the unreachable destination"

  # Whitespace would be recorded in full but read back truncated at the space,
  # so land would gate on the wrong path and destroy the record it protects.
  out=$("$PROMOTE" start pane-tangle --to 'AGENTS.md extra' \
    --evidence 'two projects' --checkable 'a check exists' --landed-text "$LANDED_TEXT" 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted a destination the whitespace-delimited marker cannot record"
  assert_contains "$out" "whitespace" "refusal did not name the unrecordable destination path"

  assert_absent "$learnings" "a refused start still wrote to the home's learnings file"
  pass "start refuses an unstated graduation case and a destination no home would receive"
}

test_start_refuses_a_duplicate_in_flight_slug() {
  local out code before after
  setup_home
  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null \
    || fail "first start failed"
  before=$(cat "$T/home/data/learnings.md")

  out=$("$PROMOTE" start pane-tangle --to README.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" 2>&1) \
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
  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null \
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

  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null \
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

test_land_refuses_when_an_unrelated_change_touched_the_destination() {
  local learnings out code
  setup_home
  learnings="$T/home/data/learnings.md"

  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null || fail "start failed"

  # The destination really changes on the default branch, exactly as it would
  # when any other shared-material PR lands - but this promotion's lesson is not
  # in it. A gate that only proved the file changed would go green here and
  # destroy an in-flight record whose lesson never landed.
  land_unrelated_change "$T/root" AGENTS.md

  out=$("$PROMOTE" list) || fail "list failed"
  assert_contains "$out" "waiting	pane-tangle	AGENTS.md" \
    "list called an unrelated change to the destination a landing"

  out=$("$PROMOTE" land pane-tangle 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "land retired a record because an unrelated change touched the destination"
  assert_contains "$out" "does not contain the promoted text" "refusal did not name the missing promoted text"
  assert_grep 'Promotion in flight' "$learnings" "a refused land destroyed the in-flight record"

  # And it still lands once the lesson itself is really there.
  land_tracked_change "$T/root" AGENTS.md
  out=$("$PROMOTE" land pane-tangle) || fail "land failed after the real landing: $out"
  assert_grep 'was promoted to `AGENTS.md`' "$learnings" "land did not leave a pointer after the real landing"
  pass "land requires the promoted text itself, not merely a changed destination"
}

test_start_refuses_landed_text_the_destination_already_carries() {
  local learnings out code
  setup_home
  learnings="$T/home/data/learnings.md"

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text '# Agents' 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "start accepted landed text the destination already carries"
  assert_contains "$out" "already appears" "refusal did not say the phrase proves nothing"
  assert_absent "$learnings" "a refused start still wrote to the home's learnings file"

  out=$("$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' 2>&1) \
    && code=0 || code=$?
  expect_code 1 "$code" "start accepted a promotion with no landed text to prove it landed"
  assert_contains "$out" "--landed-text" "refusal did not name the missing landed text"
  pass "start refuses landed text that could never prove a landing"
}

test_land_refuses_a_block_whose_terminating_blank_line_is_gone() {
  local learnings out code before
  setup_home
  learnings="$T/home/data/learnings.md"

  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null || fail "start failed"
  land_tracked_change "$T/root" AGENTS.md

  # Hand curation removed the blank line that closes the block, and further
  # curated entries follow. Deleting through to the next blank line would eat
  # them, in a gitignored file with no recovery.
  printf -- '- 2026-07-02 a curated learning below the block.\n\n' >> "$learnings"
  perl -0pi -e 's/\n\n- 2026-07-02/\n- 2026-07-02/' "$learnings"
  before=$(cat "$learnings")

  out=$("$PROMOTE" land pane-tangle 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "land deleted through a block with no terminating blank line"
  assert_contains "$out" "delete entries that are not part of it" "refusal did not name the malformed block"
  [ "$(cat "$learnings")" = "$before" ] || fail "a refused land still edited the learnings file"
  assert_grep '- 2026-07-02 a curated learning below the block.' "$learnings" \
    "land destroyed a curated entry below an unterminated block"
  pass "land refuses an unterminated block instead of eating the entries below it"
}

test_land_refuses_a_slug_that_carries_two_marker_lines() {
  local learnings out code before
  setup_home
  learnings="$T/home/data/learnings.md"

  "$PROMOTE" start pane-tangle --to AGENTS.md --evidence 'two projects' --checkable 'a check' \
    --landed-text "$LANDED_TEXT" >/dev/null || fail "start failed"
  land_tracked_change "$T/root" AGENTS.md

  # Hand curation left a second line that begins with the marker and names the
  # same slug, with curated entries below it and no blank line until past them.
  # The block start wrote is well formed, so a guard that proves only the first
  # block passes - while a rewriter that fires on every match deletes the proven
  # block AND everything from this stray marker down to the next blank line.
  {
    printf -- '<!-- fm-promotion slug=pane-tangle to=AGENTS.md started=2026-07-02 -->\n'
    printf -- '- 2026-07-02 a curated learning beside the stray marker.\n'
    printf -- '- 2026-07-03 another curated learning.\n'
    printf '\n'
  } >> "$learnings"
  before=$(cat "$learnings")

  out=$("$PROMOTE" land pane-tangle 2>&1) && code=0 || code=$?
  expect_code 1 "$code" "land acted on a slug carrying more than one marker line"
  assert_contains "$out" "more than one" "refusal did not name the duplicated record"
  [ "$(cat "$learnings")" = "$before" ] || fail "a refused land still edited the learnings file"
  assert_grep '- 2026-07-02 a curated learning beside the stray marker.' "$learnings" \
    "land destroyed a curated entry beside a stray second marker"
  assert_grep '- 2026-07-03 another curated learning.' "$learnings" \
    "land destroyed a curated entry beside a stray second marker"
  assert_grep 'Promotion in flight' "$learnings" "a refused land destroyed the in-flight record"
  pass "land refuses a slug with two marker lines instead of eating the entries around one"
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
test_land_refuses_when_an_unrelated_change_touched_the_destination
test_start_refuses_landed_text_the_destination_already_carries
test_land_refuses_a_block_whose_terminating_blank_line_is_gone
test_land_refuses_a_slug_that_carries_two_marker_lines
test_stow_skill_owns_the_graduation_rule
test_agents_routes_upward_without_restating_the_mechanics
