#!/usr/bin/env bash
# Behavior tests for bin/fm-project-reconcile.sh.
#
# The fixtures below are miniatures of the five real projects the reconciler was
# built against: a repo whose entry point routes to a stale handoff, a repo whose
# entry point names a branch that does not exist, a repo with no remote, and a
# repo with no verification at all. Each one is the shape that made an installer
# the wrong answer.
# shellcheck disable=SC2016  # backticked command names must reach the fixtures verbatim.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-project-reconcile)
RECONCILE="$ROOT/bin/fm-project-reconcile.sh"

# Run the reconciler offline so no test ever depends on network or gh-axi.
reconcile() { "$RECONCILE" --offline "$@" 2>&1; }

git_in() { git -C "$1" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' "${@:2}"; }

# A committed repo with no surfaces at all.
new_bare_project() {  # <name>
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  printf 'x\n' > "$repo/source.txt"
  git_in "$repo" add -A
  git_in "$repo" commit -qm initial
  printf '%s\n' "$repo"
}

commit_all() {  # <repo> <message> [iso-date]
  git_in "$1" add -A
  if [ "$#" -ge 3 ]; then
    GIT_AUTHOR_DATE=$3 GIT_COMMITTER_DATE=$3 git_in "$1" commit -qm "$2"
  else
    git_in "$1" commit -qm "$2"
  fi
}

test_bare_project_seeds_the_full_set_and_nothing_else() {
  local repo out
  repo=$(new_bare_project bare)
  out=$(reconcile --seed "$repo") || fail "seeding a bare project failed:"$'\n'"$out"

  assert_present "$repo/AGENTS.md" "AGENTS.md was not seeded"
  assert_present "$repo/CLAUDE.md" "CLAUDE.md symlink was not seeded"
  [ -L "$repo/CLAUDE.md" ] || fail "CLAUDE.md is not a symlink to AGENTS.md"
  assert_present "$repo/script/setup" "script/setup was not seeded"
  assert_present "$repo/script/check" "script/check was not seeded"
  assert_present "$repo/script/run" "script/run was not seeded"
  assert_present "$repo/DECISIONS.md" "DECISIONS.md was not seeded"
  assert_present "$repo/notes" "notes/ was not seeded"
  [ -x "$repo/script/check" ] || fail "seeded script/check is not executable"

  assert_grep "quoted" "$repo/DECISIONS.md" "DECISIONS.md lost the verbatim-quote rule"
  assert_grep "One small dated note per file" "$repo/notes/README.md" \
    "notes/ lost the one-dated-note-per-file convention"

  # The two files revision 1 wanted and the captain excluded on 2026-07-28.
  assert_absent "$repo/QUESTIONS.md" "QUESTIONS.md must never be seeded"
  assert_absent "$repo/handoff" "handoff/ must never be seeded"
  assert_not_contains "$out" "QUESTIONS.md" "the report offered to seed QUESTIONS.md"
  pass "fm-project-reconcile.sh: a bare project gets the full set, and neither excluded file"
}

test_existing_surfaces_are_reported_not_duplicated() {
  local repo out
  repo=$(new_bare_project existing)
  mkdir -p "$repo/docs" "$repo/notes" "$repo/script"
  printf '# Agent memory\n\nRun `tests/gate.sh`.\n' > "$repo/AGENTS.md"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  printf '# Decisions\n\n2026-01-01: keep it.\n' > "$repo/DECISIONS.md"
  printf '# note\n' > "$repo/notes/2026-01-01-a.md"
  printf '# Handoff\n' > "$repo/docs/handoff.md"
  printf '# Status\n' > "$repo/docs/STATUS.md"
  commit_all "$repo" surfaces

  out=$(reconcile --seed "$repo") || fail "seeding a surfaced project failed:"$'\n'"$out"

  assert_contains "$out" "SURFACE: entry-point repo AGENTS.md" "AGENTS.md was not inventoried"
  assert_contains "$out" "SURFACE: decision-record repo DECISIONS.md" "DECISIONS.md was not inventoried"
  assert_contains "$out" "COLLISION: handoff - 2 surfaces" "two handoff surfaces were not reported as a collision"
  assert_contains "$out" "PRESENT: AGENTS.md" "AGENTS.md was not reported as already present"
  assert_contains "$out" "PRESENT: DECISIONS.md" "DECISIONS.md was not reported as already present"
  assert_contains "$out" "PRESENT: notes" "the existing notes store was not reported as already present"
  assert_not_contains "$out" "SEED: DECISIONS.md" "a second decision record was planned over an existing one"
  assert_not_contains "$out" "SEED: AGENTS.md" "a second entry point was planned over an existing one"

  assert_grep "Run \`tests/gate.sh\`." "$repo/AGENTS.md" "the existing AGENTS.md was rewritten"
  assert_grep "2026-01-01: keep it." "$repo/DECISIONS.md" "the existing DECISIONS.md was rewritten"
  assert_absent "$repo/notes/README.md" "a second notes convention was written into an existing store"
  pass "fm-project-reconcile.sh: existing surfaces are inventoried, collided and left untouched"
}

test_a_notes_store_under_another_name_is_present_not_reseeded() {
  local repo out
  repo=$(new_bare_project renamed-notes)
  # findings/ is one of the notes-store names the surveyed repos actually used.
  # A different name for the store is a naming difference, not an absence.
  mkdir -p "$repo/findings"
  printf '# a lesson\n' > "$repo/findings/2026-01-01-a.md"
  commit_all "$repo" findings

  out=$(reconcile --seed "$repo") || fail "seeding alongside a renamed notes store failed:"$'\n'"$out"
  assert_contains "$out" "SURFACE: notes-store repo findings" "the renamed notes store was not inventoried"
  assert_contains "$out" "PRESENT: notes" "a notes store under another name was not reported as present"
  assert_not_contains "$out" "SEED: notes" "a second notes store was planned over an existing one"
  assert_not_contains "$out" "COLLISION: notes-store" "seeding manufactured the collision it exists to prevent"
  assert_absent "$repo/notes" "a second notes store was written next to the existing one"
  pass "fm-project-reconcile.sh: a notes store under another name is present, not a second one to seed"
}

test_an_out_of_repo_memory_store_does_not_suppress_an_in_repo_notes_store() {
  local repo out key config
  repo=$(new_bare_project memory-only-notes)
  config="$TMP_ROOT/claude-config-notes"
  key=$(cd "$repo" && pwd -P | tr '/.' '--')
  mkdir -p "$config/projects/$key/memory"
  printf '# a lesson\n' > "$config/projects/$key/memory/one.md"

  # The whole point of the memory-outside-repo gap is that this store is
  # invisible from an isolated worktree, so it can never stand in for one the
  # repo carries.
  out=$(CLAUDE_CONFIG_DIR="$config" "$RECONCILE" --offline "$repo" 2>&1)
  assert_contains "$out" "SEED: notes (would create)" \
    "an out-of-repo memory store suppressed seeding an in-repo notes store"
  pass "fm-project-reconcile.sh: an out-of-repo store never stands in for an in-repo notes store"
}

test_disagreement_stops_and_asks_without_writing() {
  local repo out rc
  repo=$(new_bare_project stale-pointer)
  mkdir -p "$repo/docs"
  printf '# Agent memory\n\nStart at docs/baton.md.\n' > "$repo/AGENTS.md"
  printf '# Baton\n' > "$repo/docs/baton.md"
  printf '# Handoff\n' > "$repo/docs/handoff.md"
  commit_all "$repo" surfaces '2026-01-01T00:00:00Z'
  # A later commit makes the handoff the newer of the two same-job surfaces,
  # while the entry point still routes to the baton.
  printf '# Handoff\n\nupdated\n' > "$repo/docs/handoff.md"
  commit_all "$repo" "newer handoff" '2026-06-01T00:00:00Z'

  out=$(reconcile "$repo")
  assert_contains "$out" "DISAGREEMENT: stale-entry-pointer-handoff" \
    "a stale entry-point route was not reported as a disagreement"
  assert_contains "$out" "docs/baton.md" "the disagreement did not name the surface the entry point routes to"

  out=$(reconcile --seed "$repo"); rc=$?
  expect_code 3 "$rc" "seeding with an open disagreement"
  assert_contains "$out" "REFUSED:" "an open disagreement did not refuse the seed"
  assert_contains "$out" "captain owns which one survives" "the refusal did not say who decides"
  assert_absent "$repo/script/check" "an open disagreement still wrote to the project"
  assert_absent "$repo/DECISIONS.md" "an open disagreement still wrote to the project"
  # A refused run still shows the plan, but never claims to have created anything:
  # grepping SEED lines is the documented way to consume this report.
  assert_contains "$out" "SEED: script/check (would create)" "the refused run hid the plan"
  assert_not_contains "$out" "(creating)" "a refused run reported surfaces as created"

  out=$(reconcile --seed --accept-disagreement stale-entry-pointer-handoff "$repo") ||
    fail "seeding after the disagreement was ruled on failed:"$'\n'"$out"
  assert_contains "$out" "(accepted)" "a ruled-on disagreement was not marked accepted"
  assert_present "$repo/script/check" "seeding did not proceed after the disagreement was ruled on"
  pass "fm-project-reconcile.sh: a disagreement stops and asks, and writes nothing until it is ruled on"
}

test_entry_point_naming_a_missing_branch_is_a_disagreement() {
  local repo out
  repo=$(new_bare_project missing-branch)
  git_in "$repo" branch -m master
  printf '# Agent memory\n\nmain is the default branch for pull requests.\n' > "$repo/AGENTS.md"
  commit_all "$repo" entry

  out=$(reconcile "$repo")
  assert_contains "$out" "DISAGREEMENT: entry-point-names-missing-branch-main" \
    "an entry point naming a branch with no ref was not reported"
  pass "fm-project-reconcile.sh: an entry point naming a branch that does not exist is a disagreement"
}

test_a_branch_word_in_prose_is_not_a_missing_branch() {
  local repo out
  repo=$(new_bare_project prose-branch-word)
  git_in "$repo" branch -m master
  # "main" is an ordinary English word. A detector that reads it as a branch name
  # puts a question the captain cannot answer onto the board.
  printf '# Agent memory\n\nThe main entry point is src/index.ts. Run the main loop with make run.\n' \
    > "$repo/AGENTS.md"
  commit_all "$repo" entry

  out=$(reconcile "$repo")
  assert_not_contains "$out" "DISAGREEMENT:" \
    "the word main in ordinary prose was read as a branch name"
  pass "fm-project-reconcile.sh: the branch words in prose raise nothing without branch-shaped context"
}

test_no_check_command_degrades_to_a_named_gap_never_a_silent_pass() {
  local repo out rc
  repo=$(new_bare_project no-check)
  out=$(reconcile "$repo")
  assert_contains "$out" "GAP: check-command" "a project with no verification did not report the gap"
  assert_contains "$out" "never a silent pass" "the check gap did not state that a silent pass is the failure"

  out=$(reconcile --seed "$repo") || fail "seeding failed:"$'\n'"$out"
  out=$("$repo/script/check" 2>&1); rc=$?
  expect_code 78 "$rc" "the seeded gap stub"
  [ "$rc" -ne 0 ] || fail "the seeded check stub passed silently with no check behind it"
  assert_contains "$out" "no check command defined for this project yet" \
    "the seeded gap stub did not name the gap"
  pass "fm-project-reconcile.sh: no check command degrades to a named gap that cannot pass silently"
}

test_the_seeded_gap_stub_keeps_reporting_the_gap_until_it_is_replaced() {
  local repo out
  repo=$(new_bare_project stub-rerun)
  reconcile --seed "$repo" >/dev/null || fail "seeding a project with no check failed"

  # The stub exits 78 forever until someone writes the real command, so a re-run
  # that stopped reporting the gap would read as "this project verifies".
  out=$(reconcile "$repo")
  assert_contains "$out" "GAP: check-command" \
    "the check gap disappeared once the placeholder stub existed"
  assert_contains "$out" "still the seeded placeholder" \
    "the re-run did not say the surface is a placeholder rather than a check"
  assert_contains "$out" "SURFACE: check-command repo script/check - a seeded placeholder" \
    "the placeholder was inventoried as a real check command"
  pass "fm-project-reconcile.sh: a seeded placeholder keeps the check gap named instead of hiding it"
}

test_existing_check_command_is_wrapped_under_the_conventional_name() {
  local repo out rc
  repo=$(new_bare_project wrapped-check)
  mkdir -p "$repo/tests"
  printf '#!/bin/sh\necho gate ran\nexit 0\n' > "$repo/tests/gate.sh"
  chmod +x "$repo/tests/gate.sh"
  commit_all "$repo" gate

  out=$(reconcile "$repo")
  assert_contains "$out" "SURFACE: check-command repo ./tests/gate.sh - under another name" \
    "an existing check under another name was not inventoried"
  assert_not_contains "$out" "GAP: check-command" "a project with a check reported a check gap"

  reconcile --seed "$repo" >/dev/null || fail "seeding a project with an existing check failed"
  out=$("$repo/script/check" 2>&1); rc=$?
  expect_code 0 "$rc" "the seeded wrapper around an existing check"
  assert_contains "$out" "gate ran" "the seeded script/check did not run the command it wraps"
  assert_present "$repo/tests/gate.sh" "the wrapped command was renamed instead of wrapped"
  assert_grep "exec ./tests/gate.sh" "$repo/script/check" "the wrapper does not exec the original command"
  pass "fm-project-reconcile.sh: an existing check keeps its name and gains the conventional one"
}

test_check_command_from_project_config_is_anchored_to_the_repo() {
  local repo out rc
  repo=$(new_bare_project config-check)
  mkdir -p "$repo/tests"
  printf '#!/bin/sh\necho configured gate ran\n' > "$repo/tests/gate.sh"
  chmod +x "$repo/tests/gate.sh"
  # The project's own config names the script bare, the way that config resolves
  # it. A wrapper that execs it verbatim would search PATH instead of the repo.
  printf 'commands:\n  test: tests/gate.sh\n' > "$repo/.no-mistakes.yaml"
  commit_all "$repo" configured-gate

  out=$(reconcile "$repo")
  assert_contains "$out" "SURFACE: check-command repo ./tests/gate.sh" \
    "a config-supplied check command was not anchored to the repo"

  reconcile --seed "$repo" >/dev/null || fail "seeding a project with a configured check failed"
  out=$(cd "$TMP_ROOT" && "$repo/script/check" 2>&1); rc=$?
  expect_code 0 "$rc" "the wrapper around a config-supplied check"
  assert_contains "$out" "configured gate ran" \
    "the wrapper did not reach the check its config names"
  pass "fm-project-reconcile.sh: a check command read from project config is anchored, not left to PATH"
}

test_repo_with_no_remote_reports_what_landed_means() {
  local repo out
  repo=$(new_bare_project no-remote)
  out=$(reconcile "$repo")
  assert_contains "$out" "LANDING: no remote" "a repo with no remote did not say so"
  assert_contains "$out" "merged into local main" "a repo with no remote did not say what landed means"
  assert_contains "$out" "no push target" "a repo with no remote did not name the missing push target"
  pass "fm-project-reconcile.sh: a repo with no remote reports what landed means instead of assuming a push"
}

test_pr_delivery_mode_against_a_repo_with_no_remote_is_a_disagreement() {
  local repo home out rc
  repo=$(new_bare_project mode-vs-remote)
  home="$TMP_ROOT/home-mode"
  mkdir -p "$home/data"
  printf -- '- mode-vs-remote [no-mistakes] - a project (added 2026-07-28)\n' > "$home/data/projects.md"

  out=$(FM_HOME="$home" "$RECONCILE" --offline --project mode-vs-remote "$repo" 2>&1)
  assert_contains "$out" "DISAGREEMENT: delivery-mode-vs-remote" \
    "a PR delivery mode against a remoteless repo was not reported"
  assert_contains "$out" "no origin remote" "the disagreement did not name the missing remote"

  out=$(FM_HOME="$home" "$RECONCILE" --offline --seed --project mode-vs-remote "$repo" 2>&1); rc=$?
  expect_code 3 "$rc" "seeding a project whose delivery mode cannot land"
  pass "fm-project-reconcile.sh: a PR delivery mode with nowhere to push stops and asks"
}

test_an_unregistered_project_reports_the_lookup_instead_of_inventing_a_mode() {
  local repo home out rc
  repo=$(new_bare_project unregistered)
  home="$TMP_ROOT/home-unregistered"
  mkdir -p "$home/data"
  printf -- '- somebody-else - a project (added 2026-07-28)\n' > "$home/data/projects.md"

  # The mode lookup falls back to no-mistakes and warns when it cannot resolve a
  # name. The fallback is not a record, so checking it against the remote would
  # manufacture a hold about a mode nobody ever chose.
  out=$(FM_HOME="$home" "$RECONCILE" --offline --project unregistered "$repo" 2>&1)
  assert_not_contains "$out" "DISAGREEMENT: delivery-mode-vs-remote" \
    "an unregistered project's fallback mode was reported as a registry record"
  assert_contains "$out" "GAP: delivery-mode-unresolved" \
    "an unresolved registry lookup was not reported at all"
  assert_contains "$out" "not in registry" "the gap did not say why the mode is unresolved"

  out=$(FM_HOME="$home" "$RECONCILE" --offline --seed --project unregistered "$repo" 2>&1); rc=$?
  expect_code 0 "$rc" "seeding a project the registry does not list"
  assert_present "$repo/script/check" "an unresolved registry lookup blocked the seed"
  pass "fm-project-reconcile.sh: an unregistered project reports the lookup and never blocks on a fallback"
}

test_uncommitted_work_is_a_named_gap_that_lists_the_paths() {
  local repo out rc
  repo=$(new_bare_project uncommitted)
  printf 'the current state of the work\n' > "$repo/engine.md"
  printf 'more\n' >> "$repo/source.txt"

  # A dirty tree is not two surfaces disagreeing about which is authoritative, so
  # it must not manufacture a hold the captain cannot answer. It still has to be
  # loud and specific: a gap saying only "the tree is dirty" is the same defect in
  # a politer voice.
  out=$(reconcile "$repo")
  assert_contains "$out" "GAP: uncommitted-state" "a dirty tree was not reported at all"
  assert_contains "$out" "engine.md" "the gap did not name the uncommitted path"
  assert_contains "$out" "source.txt" "the gap did not name the modified path"
  assert_not_contains "$out" "DISAGREEMENT: uncommitted-state" \
    "unlanded work was still routed to the captain as a hold"

  out=$(reconcile --seed "$repo"); rc=$?
  expect_code 0 "$rc" "seeding a project with unlanded work"
  assert_present "$repo/DECISIONS.md" "unlanded work blocked the seed"
  pass "fm-project-reconcile.sh: unlanded work is a gap that names the paths, not a hold that blocks the seed"
}

test_a_long_uncommitted_list_is_capped_with_the_remainder_stated() {
  local repo out i
  repo=$(new_bare_project many-uncommitted)
  for i in 1 2 3 4 5 6 7 8; do
    printf 'x\n' > "$repo/work-$i.txt"
  done

  out=$(reconcile "$repo")
  assert_contains "$out" "GAP: uncommitted-state - 8 path(s)" "the full uncommitted count was not reported"
  assert_contains "$out" "and 2 more" "the paths beyond the listing cap were dropped without saying so"
  pass "fm-project-reconcile.sh: a long uncommitted list is capped with the remainder stated, not silently cut"
}

test_non_bare_origin_is_reported_as_a_push_hazard() {
  local repo origin out
  origin=$(new_bare_project origin-working-copy)
  repo=$(new_bare_project clone-of-working-copy)
  git_in "$repo" remote add origin "$origin"

  out=$(reconcile "$repo")
  assert_contains "$out" "non-bare working repo" "an origin that is a working copy was not reported"
  assert_contains "$out" "refuses a push to its checked-out branch" \
    "the push hazard did not say why the push fails"
  assert_contains "$out" "merged into local" "the hazard did not say what landed means instead"
  pass "fm-project-reconcile.sh: an origin that is itself a working copy is reported as a push hazard"
}

test_seed_refuses_inside_a_firstmate_owned_clone() {
  local home repo out rc
  home="$TMP_ROOT/home-boundary"
  mkdir -p "$home/data" "$home/projects"
  printf -- '- alpha - a project (added 2026-07-28)\n' > "$home/data/projects.md"
  repo="$home/projects/alpha"
  mkdir -p "$repo"
  git -C "$repo" init -q
  printf 'x\n' > "$repo/source.txt"
  git_in "$repo" add -A
  git_in "$repo" commit -qm initial

  out=$(reconcile "$repo") || fail "the read-only report was refused:"$'\n'"$out"
  assert_contains "$out" "SEED: script/check (would create)" \
    "the read-only report was suppressed inside a firstmate-owned clone"

  out=$(reconcile --seed "$repo"); rc=$?
  expect_code 4 "$rc" "seeding a firstmate-owned clone"
  assert_contains "$out" "firstmate-owned project clone" "the boundary refusal did not name the reason"
  assert_contains "$out" "delivery path" "the boundary refusal did not point at the delivery path"
  assert_absent "$repo/script" "seeding wrote into a firstmate-owned clone"
  assert_absent "$repo/DECISIONS.md" "seeding wrote into a firstmate-owned clone"
  pass "fm-project-reconcile.sh: --seed refuses the copy firstmate reads and points at the delivery path"
}

test_existing_excluded_files_are_reported_and_left_alone() {
  local repo out
  repo=$(new_bare_project already-excluded)
  mkdir -p "$repo/handoff"
  printf '# Questions\n\n1. Q one?\n' > "$repo/QUESTIONS.md"
  printf '# Handoff\n' > "$repo/handoff/david.md"
  commit_all "$repo" excluded

  out=$(reconcile --seed "$repo") || fail "seeding alongside the excluded files failed:"$'\n'"$out"
  assert_contains "$out" "SURFACE: question-register repo QUESTIONS.md" \
    "an existing QUESTIONS.md was not inventoried"
  assert_contains "$out" "SURFACE: handoff repo handoff" "an existing handoff/ was not inventoried"
  assert_grep "1. Q one?" "$repo/QUESTIONS.md" "an existing QUESTIONS.md was rewritten"
  assert_present "$repo/handoff/david.md" "an existing handoff file was removed"
  pass "fm-project-reconcile.sh: existing copies of the excluded files are reported, never rewritten or removed"
}

test_external_memory_store_is_inventoried_as_a_surface() {
  local repo out key config
  repo=$(new_bare_project external-memory)
  config="$TMP_ROOT/claude-config"
  # The store is keyed by the physically-resolved path, which is what the script
  # resolves and what the harness itself uses.
  key=$(cd "$repo" && pwd -P | tr '/.' '--')
  mkdir -p "$config/projects/$key/memory"
  printf '# a lesson\n' > "$config/projects/$key/memory/one.md"

  out=$(CLAUDE_CONFIG_DIR="$config" "$RECONCILE" --offline "$repo" 2>&1)
  assert_contains "$out" "SURFACE: notes-store external" "an out-of-repo notes store was not inventoried"
  assert_contains "$out" "GAP: memory-outside-repo" "an out-of-repo notes store was not named as a gap"
  assert_contains "$out" "invisible from every isolated worktree" \
    "the gap did not say why an absolute-path store disappears"
  pass "fm-project-reconcile.sh: a state surface outside the repo is inventoried and named as a gap"
}

test_a_non_git_directory_still_reports_and_seeds() {
  local repo out
  repo="$TMP_ROOT/not-a-repo"
  mkdir -p "$repo"
  out=$(reconcile --seed "$repo") || fail "reconciling a non-git directory failed:"$'\n'"$out"
  assert_contains "$out" "LANDING: not a git repository" "a non-git directory did not say so"
  assert_present "$repo/script/check" "a non-git directory was not seeded"
  pass "fm-project-reconcile.sh: a directory that is not a git repository still reports and seeds"
}

test_a_large_surface_count_is_summarised_never_silently_truncated() {
  local repo out i
  repo=$(new_bare_project many-handoffs)
  mkdir -p "$repo/docs"
  for i in 1 2 3 4 5 6 7 8 9; do
    printf '# handoff %s\n' "$i" > "$repo/docs/session-$i-handoff.md"
  done
  commit_all "$repo" handoffs

  out=$(reconcile "$repo")
  assert_contains "$out" "COLLISION: handoff - 9 surfaces" "the full collision count was not reported"
  assert_contains "$out" "and 3 more" "the surfaces beyond the listing cap were dropped without saying so"
  pass "fm-project-reconcile.sh: a long surface list is capped with the remainder stated, not silently cut"
}

test_bare_project_seeds_the_full_set_and_nothing_else
test_existing_surfaces_are_reported_not_duplicated
test_a_notes_store_under_another_name_is_present_not_reseeded
test_an_out_of_repo_memory_store_does_not_suppress_an_in_repo_notes_store
test_disagreement_stops_and_asks_without_writing
test_entry_point_naming_a_missing_branch_is_a_disagreement
test_a_branch_word_in_prose_is_not_a_missing_branch
test_no_check_command_degrades_to_a_named_gap_never_a_silent_pass
test_the_seeded_gap_stub_keeps_reporting_the_gap_until_it_is_replaced
test_existing_check_command_is_wrapped_under_the_conventional_name
test_check_command_from_project_config_is_anchored_to_the_repo
test_repo_with_no_remote_reports_what_landed_means
test_pr_delivery_mode_against_a_repo_with_no_remote_is_a_disagreement
test_an_unregistered_project_reports_the_lookup_instead_of_inventing_a_mode
test_uncommitted_work_is_a_named_gap_that_lists_the_paths
test_a_long_uncommitted_list_is_capped_with_the_remainder_stated
test_non_bare_origin_is_reported_as_a_push_hazard
test_seed_refuses_inside_a_firstmate_owned_clone
test_existing_excluded_files_are_reported_and_left_alone
test_external_memory_store_is_inventoried_as_a_surface
test_a_non_git_directory_still_reports_and_seeds
test_a_large_surface_count_is_summarised_never_silently_truncated
