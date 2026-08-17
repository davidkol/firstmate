#!/usr/bin/env bash
# Behavior tests for canonical project-path resolution and migration.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_git_identity fmtest fmtest@example.invalid

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-project-path.XXXXXX")
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
RESOLVE="$ROOT/bin/fm-project-resolve.sh"
SET_PATH="$ROOT/bin/fm-project-path-set.sh"
new_home() {
  local home
  home=$(mktemp -d "$TMP_ROOT/home.XXXXXX")
  mkdir -p "$home/data" "$home/state" "$home/projects"
  printf '%s\n' "$home"
}

new_repo() {
  local path=$1
  mkdir -p "$path"
  fm_git_init_commit "$path"
  printf '%s\n' "$path"
}

run_resolve() {
  local home=$1 id=$2
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$RESOLVE" "$id"
}

run_set_path() {
  local home=$1
  shift
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$SET_PATH" "$@"
}

run_legacy_identity_check() {
  local home=$1 recorded=$2
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" bash -c \
    '. "$1"; fm_project_legacy_task_requires_identity "$2"' \
    _ "$ROOT/bin/fm-project-lib.sh" "$recorded"
}

set_same_origin() {
  local left=$1 right=$2 origin=$3
  git -C "$left" remote add origin "$origin"
  git -C "$right" remote add origin "$origin"
}

test_resolves_canonical_path_mode_and_yolo() {
  local home repo physical out expected
  home=$(new_home)
  repo=$(new_repo "$TMP_ROOT/captain projects/Martyrdome")
  physical=$(cd "$repo" && pwd -P)
  cat > "$home/data/projects.md" <<EOF
- Martyrdome [validated-main +yolo] - Godot action game
  path: $repo
EOF

  out=$(run_resolve "$home" Martyrdome) || fail "canonical project resolution failed"
  expected=$(printf 'Martyrdome\t%s\tvalidated-main\ton' "$physical")
  [ "$out" = "$expected" ] || fail "resolver returned '$out', expected '$expected'"
  [ "$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-project-mode.sh" Martyrdome)" = "validated-main on" ] \
    || fail "fm-project-mode did not consume the canonical registry record"
  pass "canonical registry resolves path, delivery mode, and yolo"
}

test_primary_refuses_missing_path_without_clone_fallback() {
  local home clone out rc
  home=$(new_home)
  clone=$(new_repo "$home/projects/Martyrdome")
  printf '%s\n' '- Martyrdome [validated-main] - legacy entry' > "$home/data/projects.md"

  set +e
  out=$(run_resolve "$home" Martyrdome 2>&1)
  rc=$?
  set -e

  expect_code 1 "$rc" "primary missing canonical path"
  assert_contains "$out" "PROJECT_PATH_REQUIRED" "missing path refusal did not name migration"
  [ -d "$clone/.git" ] || fail "missing-path refusal touched the retained clone"
  pass "primary project never falls back to a retained managed clone"
}

test_rejects_internal_nonroot_and_duplicate_physical_paths() {
  local home internal external out rc
  home=$(new_home)
  internal=$(new_repo "$home/projects/Internal")
  external=$(new_repo "$TMP_ROOT/external")
  mkdir -p "$external/nested"

  cat > "$home/data/projects.md" <<EOF
- Internal [validated-main] - internal clone
  path: $internal
EOF
  set +e
  out=$(run_resolve "$home" Internal 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "internal managed-clone path"
  assert_contains "$out" "inside Firstmate's managed project directory" "internal path refusal was unclear"

  cat > "$home/data/projects.md" <<EOF
- Nested [validated-main] - nested path
  path: $external/nested
EOF
  set +e
  out=$(run_resolve "$home" Nested 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "non-root repository path"
  assert_contains "$out" "not a Git repository root" "non-root refusal was unclear"

  cat > "$home/data/projects.md" <<EOF
- One [validated-main] - first identity
  path: $external
- Two [local-only] - duplicate identity
  path: $external
EOF
  set +e
  out=$(run_resolve "$home" One 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "duplicate physical path"
  assert_contains "$out" "duplicate canonical repository" "duplicate physical path was not refused"
  pass "resolver rejects internal, non-root, and duplicate physical paths"
}

test_secondmate_keeps_provisioned_clone_exception() {
  local home clone physical out expected
  home=$(new_home)
  : > "$home/.fm-secondmate-home"
  clone=$(new_repo "$home/projects/Martyrdome")
  physical=$(cd "$clone" && pwd -P)
  printf '%s\n' '- Martyrdome [direct-PR +yolo] - provisioned clone' > "$home/data/projects.md"

  out=$(run_resolve "$home" Martyrdome) || fail "secondmate clone exception did not resolve"
  expected=$(printf 'Martyrdome\t%s\tdirect-PR\ton' "$physical")
  [ "$out" = "$expected" ] || fail "secondmate resolver returned '$out', expected '$expected'"
  pass "secondmate retains its explicit provisioned-clone exception"
}

test_migration_writes_atomically_and_refuses_inflight_old_clone() {
  local home repo old before out rc
  home=$(new_home)
  repo=$(new_repo "$TMP_ROOT/migrated")
  old=$(new_repo "$home/projects/Martyrdome")
  set_same_origin "$old" "$repo" 'git@github.com:example/Martyrdome.git'
  printf '%s\n' '- Martyrdome [direct-PR +yolo] - game' > "$home/data/projects.md"
  cp "$home/data/projects.md" "$home/before.md"
  cat > "$home/state/live.meta" <<EOF
project=$old
EOF

  set +e
  out=$(run_set_path "$home" Martyrdome "$repo" --mode validated-main 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "migration with in-flight old clone"
  assert_contains "$out" "live.meta" "migration refusal did not identify in-flight metadata"
  cmp -s "$home/data/projects.md" "$home/before.md" || fail "refused migration changed the registry"

  rm "$home/state/live.meta"
  run_set_path "$home" Martyrdome "$repo" --mode validated-main >/dev/null \
    || fail "safe canonical path migration failed"
  assert_grep '- Martyrdome [validated-main +yolo] - game' "$home/data/projects.md" \
    "migration did not update the delivery mode while preserving yolo"
  assert_grep "  path: $(cd "$repo" && pwd -P)" "$home/data/projects.md" \
    "migration did not write the canonical path"
  before=$(run_resolve "$home" Martyrdome) || fail "migrated record did not resolve"
  assert_contains "$before" "$(cd "$repo" && pwd -P)" "migrated record resolved the wrong path"
  pass "migration is atomic, blocks in-flight clone users, and preserves yolo"
}

test_migration_is_per_project_and_checks_remote_identity() {
  local home old_a repo_a old_b wrong out rc
  home=$(new_home)
  old_a=$(new_repo "$home/projects/Alpha")
  old_b=$(new_repo "$home/projects/Beta")
  repo_a=$(new_repo "$TMP_ROOT/canonical-alpha")
  wrong=$(new_repo "$TMP_ROOT/wrong-alpha")
  git -C "$old_a" remote add origin 'git@github.com:example/Alpha.git'
  git -C "$repo_a" remote add origin 'https://github.com/example/Alpha.git'
  git -C "$wrong" remote add origin 'https://github.com/example/Other.git'
  git -C "$old_b" remote add origin 'https://github.com/example/Beta.git'
  cat > "$home/data/projects.md" <<EOF
- Alpha [direct-PR] - first project
- Beta [local-only] - unrelated legacy project
EOF

  set +e
  out=$(run_set_path "$home" Alpha "$wrong" --mode validated-main 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "migration to unrelated remote"
  assert_contains "$out" 'PROJECT_REMOTE_MISMATCH' "migration did not reject an unrelated repository"
  assert_no_grep '^  path:' "$home/data/projects.md" "refused remote mismatch changed the registry"

  run_set_path "$home" Alpha "$repo_a" --mode validated-main >/dev/null \
    || fail "per-project migration failed while Beta remained pathless"
  run_resolve "$home" Alpha >/dev/null || fail "migrated Alpha did not resolve"
  set +e
  out=$(run_resolve "$home" Beta 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "unmigrated Beta resolution"
  assert_contains "$out" 'PROJECT_PATH_REQUIRED: Beta' "unmigrated project refusal named the wrong entry"
  pass "migration is per-project and refuses a different remote identity"
}

test_migration_blocks_physical_alias_of_inflight_old_clone() {
  local home alias repo old out rc
  home=$(new_home)
  old=$(new_repo "$home/projects/Martyrdome")
  repo=$(new_repo "$TMP_ROOT/alias-canonical")
  set_same_origin "$old" "$repo" 'https://github.com/example/Martyrdome.git'
  alias="$TMP_ROOT/home-alias"
  ln -s "$home" "$alias"
  printf '%s\n' '- Martyrdome [direct-PR] - game' > "$home/data/projects.md"
  printf 'project=%s\n' "$alias/projects/Martyrdome" > "$home/state/live.meta"

  set +e
  out=$(run_set_path "$home" Martyrdome "$repo" 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "migration with aliased in-flight old clone"
  assert_contains "$out" 'PROJECT_PATH_IN_USE' "physical alias bypassed the in-flight migration guard"
  pass "migration compares in-flight project paths by physical identity"
}

test_argument_resolution_matches_registry_identity_not_basename() {
  local home repo out expected wrong rc
  home=$(new_home)
  repo=$(new_repo "$TMP_ROOT/directory-name")
  printf -- '- StableId [validated-main] - differently named checkout\n  path: %s\n' "$repo" > "$home/data/projects.md"
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$RESOLVE" "$repo") \
    || fail "canonical path argument did not resolve"
  expected=$(printf 'StableId\t%s\tvalidated-main\toff' "$(cd "$repo" && pwd -P)")
  [ "$out" = "$expected" ] || fail "path argument resolved by basename instead of registry identity: $out"

  wrong=$(new_repo "$home/projects/StableId")
  set +e
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$RESOLVE" "$wrong" 2>&1); rc=$?
  set -e
  expect_code 1 "$rc" "retained clone path argument"
  assert_contains "$out" 'PROJECT_PATH_NOT_REGISTERED' "retained clone path was not refused"
  pass "path arguments resolve only by exact registered physical identity"
}

test_legacy_task_identity_requirement_is_project_specific() {
  local home migrated_repo legacy_clone
  home=$(new_home)
  migrated_repo=$(new_repo "$TMP_ROOT/migrated-project")
  legacy_clone=$(new_repo "$home/projects/Legacy")
  cat > "$home/data/projects.md" <<EOF
- Migrated [validated-main] - migrated
  path: $migrated_repo
- Legacy [direct-PR] - not migrated
EOF

  if run_legacy_identity_check "$home" "$legacy_clone"; then
    fail "an unrelated migrated entry stranded a legacy task"
  fi
  run_legacy_identity_check "$home" "$migrated_repo" \
    || fail "a migrated project's legacy task did not require identity metadata"
  pass "legacy teardown compatibility is scoped to the recorded project"
}

test_secondmate_seed_resolves_new_clone_during_initialization() {
  local home repo remote sub out physical expected
  home=$(new_home)
  repo=$(new_repo "$TMP_ROOT/secondmate-source/Martyrdome")
  remote="$TMP_ROOT/secondmate-source/Martyrdome.git"
  fm_git_add_origin "$repo" "$remote"
  cat > "$home/data/projects.md" <<EOF
- Martyrdome [direct-PR] - canonical source
  path: $repo
EOF
  sub="$TMP_ROOT/secondmate-home"

  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_SECONDMATE_CHARTER='Martyrdome operations' \
    FM_SECONDMATE_SCOPE='Martyrdome operations' \
    "$ROOT/bin/fm-home-seed.sh" ops "$sub" Martyrdome >/dev/null \
    || fail "secondmate seed could not resolve its newly provisioned clone"

  out=$(run_resolve "$sub" Martyrdome) || fail "seeded secondmate project did not resolve"
  physical=$(cd "$sub/projects/Martyrdome" && pwd -P)
  expected=$(printf 'Martyrdome\t%s\tdirect-PR\toff' "$physical")
  [ "$out" = "$expected" ] || fail "seeded secondmate resolver returned '$out', expected '$expected'"
  pass "secondmate seeding activates its provisioned-clone exception before initialization"
}

test_resolves_canonical_path_mode_and_yolo
test_primary_refuses_missing_path_without_clone_fallback
test_rejects_internal_nonroot_and_duplicate_physical_paths
test_secondmate_keeps_provisioned_clone_exception
test_migration_writes_atomically_and_refuses_inflight_old_clone
test_migration_is_per_project_and_checks_remote_identity
test_migration_blocks_physical_alias_of_inflight_old_clone
test_argument_resolution_matches_registry_identity_not_basename
test_legacy_task_identity_requirement_is_project_specific
test_secondmate_seed_resolves_new_clone_during_initialization
