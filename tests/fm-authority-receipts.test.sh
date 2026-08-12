#!/usr/bin/env bash
# Behavior tests for bin/fm-authority-receipts.sh and the spawn-time gate that
# runs it.
#
# The fixtures are not invented. test_flags_the_shipped_gravity_row reproduces
# the exact table from Delivery's docs/findings.md that recorded a mechanism the
# captain never approved, under a heading claiming seven of his rulings, with the
# one row that mattered citing a technical limitation and no ruling. That row is
# the spec: a check that does not flag it is not this check.
#
# Stated gap: the spawn integration is asserted in the refusal direction only.
# Driving a clean brief all the way through fm-spawn.sh costs a 60-second
# treehouse timeout and leaves a real terminal window behind, which is not worth
# it here - that the check passes a clean brief is covered directly against the
# generated scaffolds, and spawn does nothing to the result but relay it.
#
# The false-positive tests carry as much weight as the detection ones. Two
# earlier versions of this check were correct on the fixture above and unusable
# in practice - one opened a block on any line mentioning the captain, which
# turned the repo's own script tables into pages of findings; one read "owner"
# as an authority word, which flagged 18 rows in a project whose docs merely talk
# about an owner. Both are pinned below so neither returns.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-authority-receipts.sh"
TMP_ROOT=$(fm_test_tmproot fm-authority-receipts)

# Runs the check and captures output; prints nothing itself.
run_check() {
  "$CHECK" "$@" 2>&1
}

test_script_parses() {
  local out rc
  out=$(bash -n "$CHECK" 2>&1); rc=$?
  expect_code 0 "$rc" "bash -n bin/fm-authority-receipts.sh must parse cleanly (got: $out)"
  [ -z "$out" ] || fail "bash -n emitted unexpected output: $out"
  pass "fm-authority-receipts.sh: bash -n succeeds"
}

# The awk program is a single-quoted shell argument. One apostrophe anywhere
# inside it ends that quote and breaks the whole script, which is exactly how
# this script broke while it was being written. Guard the shape, not the prose.
test_awk_program_contains_no_apostrophe() {
  local body
  body=$(awk '/^awk .$/{flag=1; next} /^. "\$\{FILES\[@\]\}"$/{flag=0} flag' "$CHECK")
  [ -n "$body" ] || fail "could not isolate the awk program body"
  case "$body" in
    *"'"*) fail "the awk program contains an apostrophe; it would end the single-quoted argument" ;;
  esac
  pass "fm-authority-receipts.sh: the awk program carries no quote-ending apostrophe"
}

# The failure this exists to prevent, reproduced from Delivery's findings.md
# §40 as it actually shipped.
test_flags_the_shipped_gravity_row() {
  local dir out
  dir="$TMP_ROOT/gravity"; mkdir -p "$dir"
  cat > "$dir/findings.md" <<'EOF'
### The violent veer (captain rulings 2, 4, 5, 6, 7, 8, 9)

Nothing new was built. Three shipped primitives compose:

| Beat | Mechanism | Why that one |
|---|---|---|
| the WARNING JOLT | FL2's existing `burn_veer_onset` | ruling 5 - a warning comes first |
| GRAVITY GOES | `GravityService.cut(room, lead)` cabin-wide | the on-foot controller bleeds the delta-v off in one physics frame |
EOF
  out=$(run_check "$dir/findings.md")
  expect_code 1 "$?" "an unreceipted row must exit 1"
  assert_contains "$out" "GRAVITY GOES" "the row that cited no ruling must be flagged"
  assert_not_contains "$out" "WARNING JOLT" "a row citing 'ruling 5' carries a receipt and must pass"
  pass "fm-authority-receipts.sh: flags the shipped gravity row and spares the receipted one"
}

# The other half of the same failure: the captain's rulings recorded as
# firstmate's paraphrase, with no verbatim record of what he actually said.
test_flags_paraphrased_rulings_and_accepts_dated_quotes() {
  local dir out
  dir="$TMP_ROOT/rulings"; mkdir -p "$dir"
  cat > "$dir/paraphrase.md" <<'EOF'
## The captain's rulings - decided, not open

- An unmanned veer becomes physically violent.
- The autopilot stays broken until the helm is manned.
EOF
  cat > "$dir/quoted.md" <<'EOF'
## The captain's rulings - decided, not open

- 2026-07-27: "An unmanned veer becomes physically violent."
- Ruling 4:
  > "Replace that with sustained force while the autopilot is broken."
EOF
  out=$(run_check "$dir/paraphrase.md")
  expect_code 1 "$?" "paraphrased rulings must exit 1"
  assert_contains "$out" "paraphrase.md:3" "the first paraphrased bullet must be flagged"
  assert_contains "$out" "paraphrase.md:4" "the last bullet in a file must be flagged too"

  out=$(run_check "$dir/quoted.md")
  expect_code 0 "$?" "dated quotes and a numbered ruling are receipts (got: $out)"
  pass "fm-authority-receipts.sh: paraphrase is flagged, a dated quote and a blockquote continuation pass"
}

# Regression: a pending list item is judged only once its continuation lines are
# known, which can be after the next file has already started. Judging it against
# the wrong FILENAME, or dropping it, silently loses the last claim in a file.
test_last_item_of_a_file_survives_the_next_file() {
  local dir out
  dir="$TMP_ROOT/multifile"; mkdir -p "$dir"
  printf '%s\n' '## The captain decided' '- an unreceipted claim' > "$dir/first.md"
  printf '%s\n' '## Unrelated heading' '- an ordinary bullet' > "$dir/second.md"
  out=$(run_check "$dir/first.md" "$dir/second.md")
  expect_code 1 "$?" "the trailing claim in the first file must still be found"
  assert_contains "$out" "first.md:2" "the finding must be reported against its own file"
  assert_not_contains "$out" "second.md" "the second file has no authority heading and must stay clean"
  pass "fm-authority-receipts.sh: a file's trailing list item is judged against its own file"
}

# Only a heading opens a block. An earlier version opened one on any line
# mentioning the captain, which turned docs/scripts.md into 80 findings.
test_a_passing_mention_does_not_open_a_block() {
  local dir out
  dir="$TMP_ROOT/mention"; mkdir -p "$dir"
  cat > "$dir/prose.md" <<'EOF'
## Scripts

A project's captain-approved `yolo` posture relaxes routine decisions.

| Script | What it does |
|---|---|
| `fm-decision-hold.sh` | Record a captain decision hold |
| `fm-teardown.sh` | Return landed worktrees |

- Never tear down unlanded work.
- Report outcomes faithfully.
EOF
  out=$(run_check "$dir/prose.md")
  expect_code 0 "$?" "a passing mention in prose or a table cell must not open a block (got: $out)"
  pass "fm-authority-receipts.sh: only a heading opens an authority block"
}

# A list item is a claim, never a section header. The repo's own definition of
# done says "Any owner decision quoted verbatim, with its date", and an earlier
# version let that line open a block over every bullet beneath it.
test_a_list_item_does_not_open_a_block() {
  local dir out
  dir="$TMP_ROOT/checklist"; mkdir -p "$dir"
  cat > "$dir/dod.md" <<'EOF'
# Definition of done
- [ ] Any owner decision quoted verbatim, with its date.
- [ ] The captain decided nothing here; this is a checklist.
- [ ] Nothing added to a document that no execution touches.
EOF
  out=$(run_check "$dir/dod.md")
  expect_code 0 "$?" "a checklist bullet must not open a block over its siblings (got: $out)"
  pass "fm-authority-receipts.sh: a list item never opens an authority block"
}

# "captain" is the whole vocabulary. Reading "owner" as an authority word flagged
# 18 rows across one project's ordinary documentation index and nothing true.
test_owner_is_not_an_authority_word() {
  local dir out
  dir="$TMP_ROOT/owner"; mkdir -p "$dir"
  cat > "$dir/index.md" <<'EOF'
## What the owner decided

| Document | Size |
|---|---|
| OPEN-QUESTIONS | 55 K |
| PHASE-0-QUESTIONS | 61 K |
EOF
  out=$(run_check "$dir/index.md")
  expect_code 0 "$?" "'owner' must not open an authority block (got: $out)"
  pass "fm-authority-receipts.sh: 'owner' is not read as the captain"
}

# A heading-opened block ends at the next heading, so an unrelated section below
# a rulings section is not judged by it.
test_block_ends_at_the_next_heading() {
  local dir out
  dir="$TMP_ROOT/scope"; mkdir -p "$dir"
  cat > "$dir/scoped.md" <<'EOF'
## The captain's rulings

- 2026-07-27: "sustained force"

## Implementation notes

- the service exposes a discrete impulse only
- the controller bleeds it off in one frame
EOF
  out=$(run_check "$dir/scoped.md")
  expect_code 0 "$?" "the block must end at the next heading (got: $out)"
  pass "fm-authority-receipts.sh: an authority block ends at the next heading"
}

# Nothing to read is not a clean verdict.
test_absent_and_empty_inputs_refuse_rather_than_pass() {
  local dir out
  dir="$TMP_ROOT/empty"; mkdir -p "$dir/nomarkdown"
  out=$(run_check "$dir/nomarkdown")
  expect_code 2 "$?" "a directory holding no Markdown must refuse, not report clean"
  assert_contains "$out" "no Markdown files found" "the refusal must say what was missing"

  out=$(run_check "$dir/does-not-exist.md")
  expect_code 2 "$?" "an absent path must refuse"

  out=$("$CHECK" 2>&1) || true
  assert_contains "$out" "no paths given" "no arguments must refuse with guidance"
  pass "fm-authority-receipts.sh: nothing to read refuses instead of reporting clean"
}

# Every generated brief must pass its own gate: fm-spawn.sh runs this check
# before launch, so a scaffold that trips it would refuse every dispatch.
test_generated_briefs_pass_the_check() {
  local home out kind
  home="$TMP_ROOT/briefs"
  mkdir -p "$home/data" "$home/state" "$TMP_ROOT/claude-config/projects"
  for kind in ship scout; do
    if [ "$kind" = scout ]; then
      out=$(FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" \
        FM_STATE_OVERRIDE="$home/state" CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config" \
        "$ROOT/bin/fm-brief.sh" "gate-$kind" someproj --scout 2>&1)
    else
      out=$(FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" \
        FM_STATE_OVERRIDE="$home/state" CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config" \
        "$ROOT/bin/fm-brief.sh" "gate-$kind" someproj 2>&1)
    fi
    [ -f "$home/data/gate-$kind/brief.md" ] || fail "$kind brief was not scaffolded ($out)"
    out=$(run_check "$home/data/gate-$kind/brief.md")
    expect_code 0 "$?" "a generated $kind brief must pass the spawn gate (got: $out)"
  done
  pass "fm-authority-receipts.sh: generated ship and scout briefs pass their own gate"
}

# The scaffold blesses a literal bullet to write when the captain ruled on
# nothing, and the gate refusing that exact bullet would block the common case
# through a gate with no skip flag. The blessed wording is lifted out of a
# freshly generated brief rather than retyped here, so the scaffold and the gate
# cannot drift apart without this going red.
test_the_scaffold_blessed_absence_entry_passes() {
  local home brief blessed out
  home="$TMP_ROOT/absence"
  mkdir -p "$home/data"
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" \
    "$ROOT/bin/fm-brief.sh" absence-gate someproj >/dev/null 2>&1
  brief="$home/data/absence-gate/brief.md"
  [ -f "$brief" ] || fail "brief was not scaffolded"
  # shellcheck disable=SC2016  # single quotes are deliberate: this is a literal grep pattern, not a string to expand.
  blessed=$(grep -o '`- None[^`]*`' "$brief" | head -1 | tr -d '`')
  [ -n "$blessed" ] || fail "the scaffold no longer shows a literal absence entry to write"

  awk -v entry="$blessed" '{ sub(/\{CAPTAIN_RULINGS\}/, entry); print }' "$brief" > "$home/absent.md"
  assert_grep "$blessed" "$home/absent.md" "the absence entry was not filled into the brief"
  out=$(run_check "$home/absent.md")
  expect_code 0 "$?" "the scaffold's own absence entry must pass its own gate (got: $out)"

  # The exemption must not swallow a claim: the same slot, filled with a
  # paraphrase, is still refused.
  awk '{ sub(/\{CAPTAIN_RULINGS\}/, "- Gravity goes when you veer."); print }' "$brief" > "$home/claimed.md"
  out=$(run_check "$home/claimed.md")
  expect_code 1 "$?" "an unreceipted claim in the same slot must still be refused"
  assert_contains "$out" "Gravity goes when you veer" "the refusal must quote the claim"

  # Nor may it swallow a claim that merely opens with the word. A bullet that
  # declares absence and then goes on to say something is saying something.
  awk '{ sub(/\{CAPTAIN_RULINGS\}/, "- None of the rulings cover this, so gravity goes when you veer."); print }' \
    "$brief" > "$home/none-then-claim.md"
  out=$(run_check "$home/none-then-claim.md")
  expect_code 1 "$?" "a bullet that opens with none and then claims must be refused"
  assert_contains "$out" "None of the rulings cover this, so gravity goes when you veer" \
    "the refusal must quote the claim that hid behind the absence wording"
  pass "fm-authority-receipts.sh: the scaffold's blessed absence entry passes, a paraphrase does not"
}

# Punctuation is not what makes a bullet a claim. An earlier bound exempted any
# bullet that opened with the letters "none" and carried no punctuation, so all
# three claims below went out under the exemption unjudged. Each asserts a
# mechanism on the captain's behalf and each must be refused; the two real
# absence entries beside them must still pass, or the gate blocks the honest
# common case through a check with no skip flag.
test_an_unpunctuated_claim_is_not_an_absence_entry() {
  local dir out claim
  dir="$TMP_ROOT/absence-bound"
  mkdir -p "$dir"

  for claim in \
    '- nonetheless gravity goes when you veer' \
    '- none whatsoever gravity goes when you veer' \
    '- none of the above and gravity goes cabin wide'
  do
    printf '# What the captain decided\n%s\n' "$claim" > "$dir/claim.md"
    out=$(run_check "$dir/claim.md")
    expect_code 1 "$?" "an unpunctuated claim must be judged, not exempted: $claim"
    assert_contains "$out" "gravity goes" "the refusal must quote the claim: $claim"
  done

  for claim in '- None recorded for this task.' '- None.'; do
    printf '# What the captain decided\n%s\n' "$claim" > "$dir/absent.md"
    out=$(run_check "$dir/absent.md")
    expect_code 0 "$?" "a bullet that only declares absence must pass (got: $out): $claim"
  done
  pass "fm-authority-receipts.sh: absence wording does not carry an unpunctuated claim out"
}

# A fenced block is a sample, not structure. Reading it as structure fails both
# ways: a shell comment inside one closes the authority block, which is the
# exact evasion this check exists to stop, and a literal bullet inside one is
# read as a claim and refuses a brief that is fine.
test_a_fenced_code_block_is_not_read_as_structure() {
  local dir out
  dir="$TMP_ROOT/fenced"; mkdir -p "$dir"
  cat > "$dir/evasion.md" <<'EOF'
## The captain decided

```sh
# rebuild the veer
```

- an unreceipted claim
EOF
  cat > "$dir/sample.md" <<'EOF'
## The captain decided

- 2026-07-27: "An unmanned veer becomes physically violent."

```
- literal bullet inside a code block
| literal | table row |
```
EOF
  out=$(run_check "$dir/evasion.md")
  expect_code 1 "$?" "a comment inside a fence must not close the authority block"
  assert_contains "$out" "evasion.md:7" "the claim after the fence must still be judged"

  out=$(run_check "$dir/sample.md")
  expect_code 0 "$?" "a bullet or table row inside a fence is not a claim (got: $out)"
  pass "fm-authority-receipts.sh: a fenced block neither closes a block nor makes a claim"
}

# Evidence attaches. A bullet keeps the lines below it that are not themselves
# list items, so the quote that receipts it may sit in an indented blockquote,
# with or without the blank line that conventionally precedes one. Refusing
# either shape sends firstmate to fix a brief that already quotes him properly.
test_a_bullet_keeps_its_indented_evidence() {
  local dir out
  dir="$TMP_ROOT/continuation"; mkdir -p "$dir"
  cat > "$dir/attached.md" <<'EOF'
## The captain decided

- On the veer:
  > "An unmanned veer becomes physically violent." (2026-07-27)
EOF
  cat > "$dir/spaced.md" <<'EOF'
## The captain decided

- On the veer:

  > "An unmanned veer becomes physically violent." (2026-07-27)
EOF
  cat > "$dir/sibling.md" <<'EOF'
## The captain decided

- 2026-07-27: "An unmanned veer becomes physically violent."
- gravity goes when you veer
EOF
  out=$(run_check "$dir/attached.md")
  expect_code 0 "$?" "an indented blockquote is the bullet's receipt (got: $out)"

  out=$(run_check "$dir/spaced.md")
  expect_code 0 "$?" "a blank line before an indented quote must not end the bullet (got: $out)"

  out=$(run_check "$dir/sibling.md")
  expect_code 1 "$?" "a bullet at the same indentation is still a claim of its own"
  assert_contains "$out" "sibling.md:4" "the unreceipted sibling bullet must be flagged"
  pass "fm-authority-receipts.sh: a bullet keeps the indented evidence written under it"
}

# Claims do not inherit. The failure this check exists to catch is firstmate's
# own substitution written beside the captain's real rulings, and indenting it
# one level under a genuine dated quote must not be a way to carry it. The
# reverse laundering matters just as much: a dated child does not receipt the
# unreceipted parent it hangs from.
test_a_sub_bullet_is_judged_on_its_own_text() {
  local dir out
  dir="$TMP_ROOT/nesting"; mkdir -p "$dir"
  cat > "$dir/nested-claim.md" <<'EOF'
## The captain decided

- 2026-07-27: "An unmanned veer becomes physically violent."
  - and gravity goes cabin-wide when you veer
EOF
  cat > "$dir/laundered-parent.md" <<'EOF'
## The captain decided

- Gravity goes when you veer.
  - see the log for 2026-07-27
EOF
  out=$(run_check "$dir/nested-claim.md")
  expect_code 1 "$?" "a claim nested under a real ruling must still be judged"
  assert_contains "$out" "nested-claim.md:4" "the finding must point at the sub-bullet, not its parent"
  assert_contains "$out" "and gravity goes cabin-wide when you veer" "the refusal must quote the nested claim"
  assert_not_contains "$out" "physically violent" "the receipted parent must not be flagged"

  out=$(run_check "$dir/laundered-parent.md")
  expect_code 1 "$?" "a dated child must not receipt its parent"
  assert_contains "$out" "laundered-parent.md:3" "the unreceipted parent must be flagged on its own line"
  assert_contains "$out" "Gravity goes when you veer" "the refusal must quote the parent"
  pass "fm-authority-receipts.sh: a sub-bullet neither borrows a receipt nor lends one"
}

# The gate itself. fm-spawn.sh reaches the brief checks before any backend or
# worktree side effect, so this creates no windows.
#
# The harness is named explicitly. Left off, fm-spawn.sh resolves it from
# config/crew-harness and then from whatever harness it detects around itself,
# and a suite running detached from any harness ancestry detects none - so spawn
# aborts on the missing launch template long before the brief is read, and this
# reads as the gate failing when the gate was never reached.
run_spawn_gate() {
  local home=$1 id=$2 proj=$3
  FM_ROOT_OVERRIDE='' \
    FM_HOME="$home" \
    FM_DATA_OVERRIDE="$home/data" \
    FM_STATE_OVERRIDE="$home/state" \
    FM_PROJECTS_OVERRIDE="$home" \
    FM_CONFIG_OVERRIDE='' \
    FM_SPAWN_NO_GUARD=1 \
    FM_BACKEND=tmux \
    "$ROOT/bin/fm-spawn.sh" "$id" "$proj" claude 2>&1
}

test_spawn_refuses_a_brief_that_claims_the_captain_without_a_receipt() {
  local home out
  home="$TMP_ROOT/spawn"
  mkdir -p "$home/data/gated" "$home/state" "$home/proj"
  cat > "$home/data/gated/brief.md" <<'EOF'
# Task
build the violent veer

# What the captain decided
- Gravity goes when you veer.
EOF
  out=$(run_spawn_gate "$home" gated "$home/proj")
  expect_code 1 "$?" "spawn must refuse a brief with an unreceipted claim"
  assert_contains "$out" "claims the captain's authority with no receipt" \
    "the refusal must name what is wrong"
  assert_contains "$out" "Gravity goes when you veer" "the refusal must quote the offending line"
  assert_contains "$out" "What firstmate worked out" "the refusal must name the fix"
  pass "fm-spawn.sh: refuses to launch a worker on an unreceipted claim of the captain"
}

# An unfilled placeholder is the other way a provenance section reaches a worker
# saying nothing. It clears the receipts check in silence - a bare
# {CAPTAIN_RULINGS} is prose, not a claim - so the spawn gate refuses it
# separately, and must say which tokens are still unfilled rather than that
# something somewhere is wrong.
test_spawn_refuses_a_brief_with_an_unreplaced_placeholder() {
  local home out
  home="$TMP_ROOT/spawn-placeholder"
  mkdir -p "$home/data/unfilled" "$home/state" "$home/proj"
  cat > "$home/data/unfilled/brief.md" <<'EOF'
# Task
build the violent veer

# What the captain decided
{CAPTAIN_RULINGS}

# What firstmate worked out
- the engine bleeds the impulse off in one frame
EOF
  out=$(run_spawn_gate "$home" unfilled "$home/proj")
  expect_code 1 "$?" "spawn must refuse a brief that still carries a placeholder"
  assert_contains "$out" "unreplaced scaffold placeholders" "the refusal must name what is wrong"
  assert_contains "$out" "{CAPTAIN_RULINGS}" "the refusal must name the unfilled placeholder"
  assert_not_contains "$out" "{TASK}" \
    "the refusal must name only the placeholders actually unfilled"
  pass "fm-spawn.sh: refuses a brief whose provenance section is still a placeholder"
}

test_spawn_refuses_invalid_core_delivery_fields_before_launch() {
  local home case_name brief out
  home="$TMP_ROOT/spawn-doctrine-core"
  mkdir -p "$home/data" "$home/state" "$home/proj"

  for case_name in missing duplicate placeholder illegal; do
    brief="$home/data/$case_name/brief.md"
    mkdir -p "$(dirname "$brief")"
    case "$case_name" in
      missing)
        printf '%s\n' '# Delivery contract' '- task-tier: T0' > "$brief"
        ;;
      duplicate)
        printf '%s\n' '# Delivery contract' '- task-tier: T0' '- task-tier: T1' \
          '- outcome: tests/fm-authority-receipts.test.sh#duplicate => dispatch refuses the ambiguous tier' > "$brief"
        ;;
      placeholder)
        printf '%s\n' '# Delivery contract' '- task-tier: T0' '- outcome: TODO' > "$brief"
        ;;
      illegal)
        printf '%s\n' '# Delivery contract' '- task-tier: T9' \
          '- outcome: tests/fm-authority-receipts.test.sh#illegal => dispatch refuses the illegal tier' > "$brief"
        ;;
    esac

    out=$(run_spawn_gate "$home" "$case_name" "$home/proj")
    expect_code 1 "$?" "$case_name: spawn must refuse an invalid core delivery field"
    assert_contains "$out" 'invalid delivery contract' \
      "$case_name: spawn did not refuse at the delivery-contract gate"
  done
  pass "fm-spawn.sh: missing, duplicate, placeholder, and illegal core fields fail before launch"
}

test_spawn_binds_captain_outcome_to_the_receipted_provenance_block() {
  local home brief out
  home="$TMP_ROOT/spawn-doctrine-authority"
  mkdir -p "$home/data/unbound" "$home/data/vague" "$home/data/generic" "$home/data/punctuation" "$home/data/ambiguous" "$home/data/prefix" "$home/state" "$home/proj"
  brief="$home/data/unbound/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain decision 2026-08-03 => the requested behavior is delivered' \
    '' \
    '# What the captain decided' \
    '- None recorded for this task.' \
    > "$brief"

  out=$(run_spawn_gate "$home" unbound "$home/proj")
  expect_code 1 "$?" "spawn must refuse a captain-sourced outcome absent from captain provenance"
  assert_contains "$out" 'invalid delivery contract' \
    "the unbound outcome did not reach the delivery-contract gate"
  assert_contains "$out" 'must identify exactly one receipted entry' \
    "the refusal did not name the provenance binding"

  brief="$home/data/vague/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain => enable X' \
    '' \
    '# What the captain decided' \
    '- Captain decision 2026-08-03: "Do not enable X."' \
    > "$brief"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the misleading case must clear the existing receipt check to reproduce the boundary failure"
  out=$(run_spawn_gate "$home" vague "$home/proj")
  expect_code 1 "$?" "spawn must not bind a generic captain word to an unrelated receipted decision"
  assert_contains "$out" 'must use captain decision <complete-id>' \
    "the vague captain source was not refused as a noncanonical receipt pointer"

  brief="$home/data/generic/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: decision 1 => enable X' \
    '' \
    '# What the captain decided' \
    '- Captain decision 1: "Do not enable X."' \
    > "$brief"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the generic-pointer case must clear the existing receipt check to reproduce the boundary failure"
  out=$(run_spawn_gate "$home" generic "$home/proj")
  expect_code 1 "$?" "spawn must reject an ambiguous generic decision pointer"
  assert_contains "$out" 'must use captain decision <complete-id>' \
    "the generic decision pointer was not refused at the delivery-contract gate"

  brief="$home/data/punctuation/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: decision#1 => enable X' \
    '' \
    '# What the captain decided' \
    '- Captain decision #1: "Do not enable X."' \
    > "$brief"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the punctuation-pointer case must clear the receipt check to reproduce the boundary failure"
  out=$(run_spawn_gate "$home" punctuation "$home/proj")
  expect_code 1 "$?" "spawn must reject a punctuation-shaped generic decision pointer"
  assert_contains "$out" 'must use captain decision <complete-id>' \
    "the punctuation-shaped decision pointer bypassed the canonical receipt syntax"

  brief="$home/data/ambiguous/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain decision 2026-08-03 => the requested behavior is delivered' \
    '' \
    '# What the captain decided' \
    '- captain decision 2026-08-03: "Deliver behavior A."' \
    '- captain decision 2026-08-03: "Deliver behavior B."' \
    > "$brief"
  out=$("$ROOT/bin/fm-doctrine-contract.sh" check "$brief" 2>&1)
  expect_code 1 "$?" "an outcome source shared by two provenance entries does not identify a specific receipt"
  assert_contains "$out" 'must identify exactly one receipted entry' \
    "the ambiguous receipt pointer was not refused"

  brief="$home/data/prefix/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain decision 1 => dispatch uses decision one' \
    '' \
    '# What the captain decided' \
    '- Captain decision 10: "A different decision."' \
    > "$brief"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the prefix case must clear the existing receipt check to reproduce the binding defect"
  out=$(run_spawn_gate "$home" prefix "$home/proj")
  expect_code 1 "$?" "spawn must not bind captain decision 1 to captain decision 10"
  assert_contains "$out" 'must identify exactly one receipted entry' \
    "the receipt-prefix mismatch was not refused at the delivery-contract gate"

  sed 's/captain decision 1 =>/captain decision 10 =>/' "$brief" > "$brief.exact"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief.exact" \
    || fail "the complete matching numbered receipt should remain accepted"

  brief="$home/data/unbound/brief.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain decision 2026-08-03 => the requested behavior is delivered' \
    '' \
    '# What the captain decided' \
    '- captain decision 2026-08-03: "Deliver the requested behavior."' \
    > "$brief"
  "$ROOT/bin/fm-authority-receipts.sh" "$brief" \
    || fail "the bound captain source should pass the existing receipt check"
  "$ROOT/bin/fm-doctrine-contract.sh" check "$brief" \
    || fail "the outcome source repeated in receipted captain provenance should pass"
  pass "fm-spawn.sh: captain outcomes identify one specific receipted provenance entry"
}

test_review_intent_forwards_only_the_matched_captain_receipt() {
  local brief out
  brief="$TMP_ROOT/reviewer-authority.md"
  printf '%s\n' \
    '# Delivery contract' \
    '- task-tier: T0' \
    '- outcome: captain decision 1 => enable X' \
    '' \
    '# What the captain decided' \
    '- Captain decision 1: "Do not enable X."' \
    '- Captain decision 2: "Keep Y enabled."' \
    > "$brief"

  out=$("$ROOT/bin/fm-doctrine-contract.sh" review-intent "$brief") \
    || fail "a structurally valid contradictory target should reach independent review"
  assert_contains "$out" 'matched captain authority receipt:' \
    "the reviewer interface did not label the matched authority receipt"
  assert_contains "$out" '- Captain decision 1: "Do not enable X."' \
    "the reviewer cannot inspect the authoritative text that contradicts the outcome"
  assert_not_contains "$out" 'Captain decision 2' \
    "the reviewer received the whole provenance block instead of the one matched receipt"
  pass "fm-doctrine-contract.sh: review intent exposes exactly the matched captain receipt"
}

# Driven against a real scaffold rather than a fixture, because the trap is in
# the scaffold's own text: a generated brief explains that it "cannot inspect the
# task text that replaces `{TASK}` later", so a substring match would refuse every
# unguarded brief forever, filled or not.
# The filled brief deliberately keeps an unreceipted ruling, so spawn refuses at
# the receipts gate immediately after this one. Reaching that second refusal is
# the proof the placeholder gate passed it through, and it costs nothing;
# driving a wholly clean brief any further starts a real terminal window and
# waits out a 60-second treehouse timeout, which is the stated gap above.
test_spawn_lets_a_filled_generated_brief_past_the_placeholder_gate() {
  local home brief out
  home="$TMP_ROOT/spawn-filled"
  mkdir -p "$home/data" "$home/state" "$home/proj" "$TMP_ROOT/claude-config-spawn/projects"
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" \
    FM_STATE_OVERRIDE="$home/state" CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config-spawn" \
    "$ROOT/bin/fm-brief.sh" filled someproj >/dev/null 2>&1
  brief="$home/data/filled/brief.md"
  [ -f "$brief" ] || fail "brief was not scaffolded"

  out=$(run_spawn_gate "$home" filled "$home/proj")
  expect_code 1 "$?" "a freshly generated brief still carries every placeholder"
  assert_contains "$out" "{TASK}" "the refusal must name the unfilled task placeholder"
  assert_contains "$out" "{TASK_TIER}" "the refusal must name the unfilled tier placeholder"
  assert_contains "$out" "{OUTCOME}" "the refusal must name the unfilled outcome placeholder"
  assert_contains "$out" "{CAPTAIN_RULINGS}" "the refusal must name the unfilled rulings placeholder"
  assert_contains "$out" "{FIRSTMATE_INFERENCE}" "the refusal must name the unfilled inference placeholder"

  awk '{
    if ($0 == "{TASK}") print "Replace the veer impulse with sustained force."
    else if ($0 == "- task-tier: {TASK_TIER}") print "- task-tier: T2"
    else if ($0 == "- outcome: {OUTCOME}") print "- outcome: captain decision 2026-08-03 => sustained veer force moves the crew"
    else if ($0 == "# Delivery doctrine - implementation slice") {
      print "- player: normal launch -> trigger the veer -> observe sustained crew movement"
      print $0
    }
    else if ($0 == "{CAPTAIN_RULINGS}") print "- Gravity goes when you veer."
    else if ($0 == "{FIRSTMATE_INFERENCE}") print "- the engine bleeds the impulse off in one frame"
    else print
  }' "$brief" > "$brief.filled" && mv "$brief.filled" "$brief"
  # shellcheck disable=SC2016  # single quotes are deliberate: this is a literal grep pattern, not a string to expand.
  assert_grep 'replaces `{TASK}` later' "$brief" \
    "the scaffold must still carry the prose mention of the token that this gate has to survive"

  out=$(run_spawn_gate "$home" filled "$home/proj")
  expect_code 1 "$?" "the filled brief must still be refused, now for its unreceipted ruling"
  assert_not_contains "$out" "unreplaced scaffold placeholders" \
    "a filled brief must clear the placeholder gate despite the brief's own prose mention of the token"
  assert_contains "$out" "claims the captain's authority" \
    "reaching the receipts gate is the proof the placeholder gate passed the brief through"
  pass "fm-spawn.sh: a filled generated brief clears the placeholder gate"
}

test_help_includes_entire_header() {
  local out
  out=$("$CHECK" --help)
  assert_contains "$out" "find claims made under the captain" "help must render the header"
  assert_contains "$out" "What it does NOT check" \
    "help must carry the stated limits, because an overclaimed check is this defect"
  pass "fm-authority-receipts.sh: --help renders the full header"
}

test_script_parses
test_awk_program_contains_no_apostrophe
test_flags_the_shipped_gravity_row
test_flags_paraphrased_rulings_and_accepts_dated_quotes
test_last_item_of_a_file_survives_the_next_file
test_a_passing_mention_does_not_open_a_block
test_a_list_item_does_not_open_a_block
test_owner_is_not_an_authority_word
test_block_ends_at_the_next_heading
test_absent_and_empty_inputs_refuse_rather_than_pass
test_generated_briefs_pass_the_check
test_the_scaffold_blessed_absence_entry_passes
test_an_unpunctuated_claim_is_not_an_absence_entry
test_a_fenced_code_block_is_not_read_as_structure
test_a_bullet_keeps_its_indented_evidence
test_a_sub_bullet_is_judged_on_its_own_text
test_spawn_refuses_a_brief_that_claims_the_captain_without_a_receipt
test_spawn_refuses_a_brief_with_an_unreplaced_placeholder
test_spawn_refuses_invalid_core_delivery_fields_before_launch
test_spawn_binds_captain_outcome_to_the_receipted_provenance_block
test_review_intent_forwards_only_the_matched_captain_receipt
test_spawn_lets_a_filled_generated_brief_past_the_placeholder_gate
test_help_includes_entire_header
