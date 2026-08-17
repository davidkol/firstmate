#!/usr/bin/env bash
# Behavior tests for bin/fm-ensure-agents-md.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-ensure-agents-md)

test_created_agents_md_includes_self_governance() {
  local repo agents
  repo="$TMP_ROOT/new-project"
  mkdir -p "$repo"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "fm-ensure-agents-md.sh failed for empty project"
  agents="$repo/AGENTS.md"
  assert_present "$agents" "AGENTS.md was not created"
  assert_present "$repo/CLAUDE.md" "CLAUDE.md pointer was not created"
  [ -f "$repo/CLAUDE.md" ] && [ ! -L "$repo/CLAUDE.md" ] \
    || fail "CLAUDE.md is not a regular file"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' > "$repo/.expected-claude"
  cmp -s "$repo/.expected-claude" "$repo/CLAUDE.md" \
    || fail "CLAUDE.md does not contain the canonical pointer"
  assert_grep "## Maintaining this file" "$agents" "self-governance section heading missing"
  assert_grep "Keep this file for knowledge useful to almost every future agent session in this project." "$agents" \
    "self-governance section lost the future-session bar"
  assert_grep "Do not repeat what the codebase already shows; point to the authoritative file or command instead." "$agents" \
    "self-governance section lost pointer-over-copy guidance"
  assert_grep "Prefer rewriting or pruning existing entries over appending new ones." "$agents" \
    "self-governance section lost rewrite-or-prune guidance"
  assert_grep "When updating this file, preserve this bar for all agents and keep entries concise." "$agents" \
    "self-governance section lost all-agents maintenance guidance"
  pass "fm-ensure-agents-md.sh: created AGENTS.md includes self-governance section"
}

test_distinct_claude_md_is_preserved_and_refused() {
  local repo out rc
  repo="$TMP_ROOT/claude-project"
  mkdir -p "$repo"
  cat > "$repo/CLAUDE.md" <<'EOF'
# Existing agent memory

Run tests with `make test`.
EOF
  cp "$repo/CLAUDE.md" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "distinct CLAUDE.md was accepted"
  assert_contains "$out" "conflict:" "distinct CLAUDE.md did not report a conflict"
  assert_absent "$repo/AGENTS.md" "refusal created AGENTS.md"
  cmp -s "$repo/.before" "$repo/CLAUDE.md" || fail "refusal modified CLAUDE.md"
  pass "fm-ensure-agents-md.sh: distinct CLAUDE.md is preserved and refused"
}

test_distinct_memory_files_are_both_preserved_and_refused() {
  local repo out rc
  repo="$TMP_ROOT/distinct-memory-project"
  mkdir -p "$repo"
  printf '# Authoritative memory\n' > "$repo/AGENTS.md"
  printf '# Existing agent memory\n\nRun tests with make test.' > "$repo/CLAUDE.md"
  cp "$repo/AGENTS.md" "$repo/.agents-before"
  cp "$repo/CLAUDE.md" "$repo/.claude-before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "distinct memory files were accepted"
  assert_contains "$out" "conflict:" "distinct memory files did not report a conflict"
  cmp -s "$repo/.agents-before" "$repo/AGENTS.md" || fail "refusal modified AGENTS.md"
  cmp -s "$repo/.claude-before" "$repo/CLAUDE.md" || fail "refusal modified CLAUDE.md"
  pass "fm-ensure-agents-md.sh: distinct memory files are both preserved and refused"
}

test_existing_agents_md_with_symlink_gains_self_governance() {
  local repo agents out count
  repo="$TMP_ROOT/existing-symlinked-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nBuild with make.\n' > "$repo/AGENTS.md"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed for existing AGENTS.md with symlink"
  assert_contains "$out" "updated:" "injection into existing AGENTS.md did not report an update"
  assert_grep "Build with make." "$agents" "injection dropped existing AGENTS.md content"
  assert_grep "## Maintaining this file" "$agents" "existing AGENTS.md did not gain the self-governance section"
  count=$(grep -Fc "## Maintaining this file" "$agents")
  [ "$count" -eq 1 ] || fail "injection wrote $count self-governance sections"
  [ -f "$repo/CLAUDE.md" ] && [ ! -L "$repo/CLAUDE.md" ] \
    || fail "canonical CLAUDE.md symlink was not migrated to a regular pointer"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' > "$repo/.expected-claude"
  cmp -s "$repo/.expected-claude" "$repo/CLAUDE.md" \
    || fail "migrated CLAUDE.md does not contain the canonical pointer"
  # Re-run must be a byte-exact no-op reporting unchanged.
  cp "$agents" "$repo/.after-first"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on idempotent re-run"
  assert_contains "$out" "unchanged:" "idempotent re-run did not report unchanged"
  diff "$repo/.after-first" "$agents" >/dev/null \
    || fail "idempotent re-run modified AGENTS.md"
  pass "fm-ensure-agents-md.sh: canonical symlink migrates to a pointer idempotently"
}

test_existing_agents_md_without_claude_gains_section_and_pointer() {
  local repo agents out count
  repo="$TMP_ROOT/existing-bare-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nDeploy with kubectl.\n' > "$repo/AGENTS.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed for existing AGENTS.md without CLAUDE.md"
  assert_contains "$out" "updated:" "injection without CLAUDE.md did not report an update"
  [ -f "$repo/CLAUDE.md" ] && [ ! -L "$repo/CLAUDE.md" ] \
    || fail "CLAUDE.md pointer was not created"
  assert_grep "Deploy with kubectl." "$agents" "injection dropped existing AGENTS.md content"
  count=$(grep -Fc "## Maintaining this file" "$agents")
  [ "$count" -eq 1 ] || fail "injection wrote $count self-governance sections"
  pass "fm-ensure-agents-md.sh: existing AGENTS.md without CLAUDE.md gains section and pointer"
}

test_existing_agents_md_with_section_reports_unchanged() {
  local repo agents out
  repo="$TMP_ROOT/fully-formed-project"
  mkdir -p "$repo"
  # Build a fully-formed project (AGENTS.md with the section + correct symlink).
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 \
    || fail "fm-ensure-agents-md.sh failed building the fully-formed fixture"
  agents="$repo/AGENTS.md"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on already-formed project"
  assert_contains "$out" "unchanged:" "already-formed project was not reported unchanged"
  diff "$repo/.before" "$agents" >/dev/null \
    || fail "already-formed AGENTS.md was modified"
  pass "fm-ensure-agents-md.sh: AGENTS.md that already has the section stays unchanged"
}

test_existing_crlf_agents_md_with_section_stays_unchanged() {
  local repo agents out count
  repo="$TMP_ROOT/crlf-formed-project"
  mkdir -p "$repo"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    '## Maintaining this file' \
    '' \
    'Keep this file for knowledge useful to almost every future agent session in this project.' \
    'Do not repeat what the codebase already shows; point to the authoritative file or command instead.' \
    'Prefer rewriting or pruning existing entries over appending new ones.' \
    'When updating this file, preserve this bar for all agents and keep entries concise.' > "$repo/AGENTS.md"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' > "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on CRLF AGENTS.md with the section"
  assert_contains "$out" "unchanged:" "complete CRLF AGENTS.md was not reported unchanged"
  cmp -s "$repo/.before" "$agents" \
    || fail "complete CRLF AGENTS.md was modified"
  count=$(LC_ALL=C grep -a -c '## Maintaining this file' "$agents")
  [ "$count" -eq 1 ] || fail "complete CRLF AGENTS.md has $count self-governance sections"
  pass "fm-ensure-agents-md.sh: CRLF AGENTS.md with the section stays unchanged"
}

test_existing_crlf_agents_md_without_section_preserves_crlf() {
  local repo agents out
  repo="$TMP_ROOT/crlf-injected-project"
  mkdir -p "$repo"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    'Run tests with make test.' > "$repo/AGENTS.md"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' > "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed injecting into CRLF AGENTS.md"
  assert_contains "$out" "updated:" "CRLF AGENTS.md injection did not report an update"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    'Run tests with make test.' \
    '' \
    '## Maintaining this file' \
    '' \
    'Keep this file for knowledge useful to almost every future agent session in this project.' \
    'Do not repeat what the codebase already shows; point to the authoritative file or command instead.' \
    'Prefer rewriting or pruning existing entries over appending new ones.' \
    'When updating this file, preserve this bar for all agents and keep entries concise.' > "$repo/.expected"
  cmp -s "$repo/.expected" "$agents" \
    || fail "CRLF AGENTS.md injection did not preserve CRLF line endings"
  cp "$agents" "$repo/.after-first"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 \
    || fail "fm-ensure-agents-md.sh failed on idempotent CRLF re-run"
  cmp -s "$repo/.after-first" "$agents" \
    || fail "idempotent CRLF re-run modified AGENTS.md"
  pass "fm-ensure-agents-md.sh: CRLF injection preserves line endings idempotently"
}

test_lowercase_agents_md_refuses_case_fragile_symlink() {
  local repo out rc
  repo="$TMP_ROOT/lowercase-project"
  mkdir -p "$repo"
  printf '# project memory\n' > "$repo/agents.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit for a lowercase agents.md"
  assert_contains "$out" "conflict:" "lowercase agents.md did not report a conflict"
  assert_contains "$out" "agents.md" "conflict message did not name the offending file"
  assert_absent "$repo/CLAUDE.md" "a case-fragile CLAUDE.md symlink was created for lowercase agents.md"
  [ ! -L "$repo/CLAUDE.md" ] || fail "a case-fragile CLAUDE.md symlink was created for lowercase agents.md"
  assert_present "$repo/agents.md" "the real lowercase agents.md was disturbed"
  pass "fm-ensure-agents-md.sh: refuses a case-variant lowercase agents.md (issue #389)"
}

test_dangling_canonical_symlink_is_preserved_and_refused() {
  local repo out rc
  repo="$TMP_ROOT/dangling-canonical-symlink"
  mkdir -p "$repo"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "dangling CLAUDE.md symlink was accepted"
  assert_contains "$out" "conflict:" "dangling CLAUDE.md symlink did not report a conflict"
  [ -L "$repo/CLAUDE.md" ] || fail "refusal replaced the dangling CLAUDE.md symlink"
  [ "$(readlink "$repo/CLAUDE.md")" = "AGENTS.md" ] || fail "refusal changed the symlink target"
  assert_absent "$repo/AGENTS.md" "refusal created AGENTS.md"
  pass "fm-ensure-agents-md.sh: dangling canonical symlink is preserved and refused"
}

test_canonical_pointer_without_agents_md_creates_authoritative_memory() {
  local repo
  repo="$TMP_ROOT/canonical-pointer-only"
  mkdir -p "$repo"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' > "$repo/CLAUDE.md"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 \
    || fail "canonical CLAUDE.md pointer without AGENTS.md was refused"
  assert_present "$repo/AGENTS.md" "AGENTS.md was not created for the canonical pointer"
  [ -f "$repo/CLAUDE.md" ] && [ ! -L "$repo/CLAUDE.md" ] \
    || fail "canonical CLAUDE.md pointer changed type"
  assert_grep '## Maintaining this file' "$repo/AGENTS.md" \
    "created AGENTS.md lacks the maintenance section"
  pass "fm-ensure-agents-md.sh: canonical pointer can seed authoritative AGENTS.md"
}

test_wrong_symlink_preserves_both_memory_surfaces() {
  local repo out rc
  repo="$TMP_ROOT/wrong-symlink"
  mkdir -p "$repo"
  printf '# Authoritative memory\n' > "$repo/AGENTS.md"
  printf '# Other memory\n' > "$repo/OTHER.md"
  ln -s OTHER.md "$repo/CLAUDE.md"
  cp "$repo/AGENTS.md" "$repo/.agents-before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "wrong CLAUDE.md symlink was accepted"
  assert_contains "$out" "conflict:" "wrong CLAUDE.md symlink did not report a conflict"
  cmp -s "$repo/.agents-before" "$repo/AGENTS.md" || fail "refusal modified AGENTS.md"
  [ -L "$repo/CLAUDE.md" ] && [ "$(readlink "$repo/CLAUDE.md")" = OTHER.md ] \
    || fail "refusal modified the wrong CLAUDE.md symlink"
  pass "fm-ensure-agents-md.sh: wrong symlink preserves both memory surfaces"
}

test_non_regular_claude_md_preserves_agents_md() {
  local repo out rc
  repo="$TMP_ROOT/non-regular-claude"
  mkdir -p "$repo/CLAUDE.md"
  printf '# Authoritative memory\n' > "$repo/AGENTS.md"
  cp "$repo/AGENTS.md" "$repo/.agents-before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "non-regular CLAUDE.md was accepted"
  assert_contains "$out" "conflict:" "non-regular CLAUDE.md did not report a conflict"
  cmp -s "$repo/.agents-before" "$repo/AGENTS.md" || fail "refusal modified AGENTS.md"
  [ -d "$repo/CLAUDE.md" ] || fail "refusal modified non-regular CLAUDE.md"
  pass "fm-ensure-agents-md.sh: non-regular CLAUDE.md preserves AGENTS.md"
}

test_created_agents_md_includes_self_governance
test_distinct_claude_md_is_preserved_and_refused
test_distinct_memory_files_are_both_preserved_and_refused
test_existing_agents_md_with_symlink_gains_self_governance
test_existing_agents_md_without_claude_gains_section_and_pointer
test_existing_agents_md_with_section_reports_unchanged
test_existing_crlf_agents_md_with_section_stays_unchanged
test_existing_crlf_agents_md_without_section_preserves_crlf
test_lowercase_agents_md_refuses_case_fragile_symlink
test_dangling_canonical_symlink_is_preserved_and_refused
test_canonical_pointer_without_agents_md_creates_authoritative_memory
test_wrong_symlink_preserves_both_memory_surfaces
test_non_regular_claude_md_preserves_agents_md
