#!/usr/bin/env bash
# tests/fm-peer-home.test.sh - the peer-home contract: a firstmate home the
# captain opens and talks to directly, provisioned by
# "bin/fm-home-seed.sh <id> <home> --peer" and opened by "bin/fm-open.sh".
#
# The invariant under test is that a peer home is a full firstmate over its own
# board with NO copy of this repo: it holds only data/, state/, config/,
# projects/, and a .fm-peer-home marker, and bin/fm-open.sh runs it against the
# tracked code root through FM_HOME. docs/configuration.md "Home kinds" owns the
# distinction from a secondmate home.
#
# Coverage:
#   - seed shape: marker, operational dirs, canonical project registry, and the
#     deliberate absence of a repo copy, a charter, and a secondmates.md route
#   - seed refusals: leased-worktree form, bad id, missing project signal,
#     nesting inside another home, overlap with a registered secondmate home, a
#     non-empty non-home target, an existing secondmate home, and an id mismatch
#   - idempotent re-seed of the same peer home
#   - transactional rollback of a failed peer seed
#   - launcher: FM_HOME export plus code-root cwd, and every refusal path
#   - per-home backend labels, which peer homes need because they share FM_ROOT
#   - per-home session lock, including refusal to a second live harness
#   - a peer session start that sees only its own board and no secondmates
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEED="$ROOT/bin/fm-home-seed.sh"
OPEN="$ROOT/bin/fm-open.sh"
TMP_ROOT=$(fm_test_tmproot fm-peer-home)
# Physically resolved, because the seeder and launcher both canonicalize paths
# and macOS TMPDIR is a symlink. Recreated and re-registered first, mirroring
# fm-session-start.test.sh: fm_test_tmproot's own EXIT trap fires inside the
# command substitution that called it, so the parent shell owns neither the
# directory nor its cleanup registration.
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid

# Pin the harness project store so a scaffolded brief never reads the
# developer's real ~/.claude/projects notes.
export CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config"
mkdir -p "$CLAUDE_CONFIG_DIR/projects"

# --- world -------------------------------------------------------------------

# new_main_home <name> [mode]: an active firstmate home registered against one
# canonical origin-backed project named "hookgame". Echoes the home path.
new_main_home() {
  local name=$1 mode=${2:-direct-PR} home src
  home="$TMP_ROOT/$name/main-home"
  src="$TMP_ROOT/$name/src/hookgame"
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  fm_git_init_commit "$src"
  fm_git_add_origin "$src" "$TMP_ROOT/$name/remote-hookgame.git"
  printf -- '- hookgame [%s] - the hook game (added 2026-07-28)\n  path: %s\n' "$mode" "$src" > "$home/data/projects.md"
  printf '%s\n' "$home"
}

seed_peer() {  # <main-home> <id> <home> [args...]
  local main=$1
  shift
  FM_HOME="$main" "$SEED" "$@" 2>&1
}

# --- seed shape --------------------------------------------------------------

test_seed_shape() {
  local main home out entry
  main=$(new_main_home shape)
  home="$TMP_ROOT/shape/homes/hookgame"

  out=$(seed_peer "$main" hookgame "$home" --peer hookgame) || fail "peer seed failed: $out"
  assert_contains "$out" "home=$home" "seed did not report the peer home path"
  assert_contains "$out" "next: bin/fm-open.sh $home" "seed did not point at the launcher"

  assert_present "$home/.fm-peer-home" "peer marker was not written"
  [ "$(cat "$home/.fm-peer-home")" = hookgame ] || fail "peer marker does not name the peer id"
  for entry in data state config projects; do
    assert_present "$home/$entry" "peer home is missing $entry/"
  done

  # The whole point: no copy of this repo, so nothing can drift out of sync.
  assert_absent "$home/AGENTS.md" "peer home copied AGENTS.md instead of running the tracked code root"
  assert_absent "$home/bin" "peer home copied bin/ instead of running the tracked code root"
  assert_absent "$home/.git" "peer home is a repo checkout instead of a plain operational home"

  # Not a subordinate: no charter overlay, no route in the parent registry.
  assert_absent "$home/data/charter.md" "peer home was given a secondmate charter"
  assert_absent "$home/.fm-secondmate-home" "peer home was marked as a secondmate home"
  assert_absent "$main/data/secondmates.md" "peer seed wrote a secondmate route"

  # It reuses the captain's canonical project instead of creating another clone.
  assert_absent "$home/projects/hookgame" "peer home created a duplicate project clone"
  assert_grep '- hookgame [direct-PR] - the hook game' "$home/data/projects.md" \
    "peer project registry did not carry the source registry line"
  assert_grep "  path: $TMP_ROOT/shape/src/hookgame" "$home/data/projects.md" \
    "peer project registry did not retain the canonical repository path"
  pass "peer seed provisions a marked, repo-free home against the canonical project"
}

test_seed_projectless() {
  local main home out
  main=$(new_main_home projectless)
  home="$TMP_ROOT/projectless/homes/empty"
  out=$(seed_peer "$main" empty "$home" --peer --no-projects) || fail "project-less peer seed failed: $out"
  assert_present "$home/.fm-peer-home" "project-less peer seed did not write the marker"
  [ -z "$(ls -A "$home/projects")" ] || fail "project-less peer seed cloned a project"
  pass "peer seed accepts a deliberate project-less home"
}

test_seed_reseed_is_idempotent() {
  local main home out
  main=$(new_main_home reseed)
  home="$TMP_ROOT/reseed/homes/hookgame"
  seed_peer "$main" hookgame "$home" --peer hookgame >/dev/null || fail "first peer seed failed"
  printf 'captain note\n' > "$home/data/captain.md"
  out=$(seed_peer "$main" hookgame "$home" --peer hookgame) || fail "re-seed failed: $out"
  assert_present "$home/data/captain.md" "re-seed destroyed home-local data"
  [ "$(grep -c '^- hookgame ' "$home/data/projects.md")" = 1 ] || fail "re-seed duplicated the project registry line"
  pass "re-seeding the same peer home is idempotent and preserves its data"
}

# --- seed refusals -----------------------------------------------------------

test_seed_refusals() {
  local main out sub
  main=$(new_main_home refuse)

  out=$(seed_peer "$main" hookgame - --peer hookgame) && fail "peer seed accepted the leased-worktree home form"
  assert_contains "$out" "needs an explicit home path" "leased-worktree refusal did not explain itself"

  out=$(seed_peer "$main" 'bad id!' "$TMP_ROOT/refuse/homes/bad" --peer hookgame) && fail "peer seed accepted an unusable id"
  assert_contains "$out" "peer home id must match" "bad-id refusal did not name the charset"
  assert_absent "$TMP_ROOT/refuse/homes/bad" "bad-id seed created a home anyway"

  out=$(seed_peer "$main" nosig "$TMP_ROOT/refuse/homes/nosig" --peer) && fail "peer seed accepted an omitted project signal"
  assert_contains "$out" "or --no-projects for a project-less home" "omitted project signal did not fail loudly"

  seed_peer "$main" outer "$TMP_ROOT/refuse/homes/outer" --peer hookgame >/dev/null || fail "outer peer seed failed"
  out=$(seed_peer "$main" inner "$TMP_ROOT/refuse/homes/outer/inner" --peer hookgame) && fail "peer seed nested inside another home"
  assert_contains "$out" "is inside firstmate home" "nesting refusal did not name the containing home"

  out=$(seed_peer "$main" sibling "$TMP_ROOT/refuse/homes/outer/../sibling" --peer hookgame) \
    || fail "peer seed refused a legitimate sibling home: $out"

  out=$(seed_peer "$main" other "$TMP_ROOT/refuse/homes/outer" --peer hookgame) && fail "peer seed took over another peer home"
  assert_contains "$out" "is already marked for outer" "id-mismatch refusal did not name the owner"

  out=$(seed_peer "$main" busy "$TMP_ROOT/refuse/src" --peer hookgame) && fail "peer seed accepted a non-empty non-home target"
  assert_contains "$out" "is not empty and is not a peer home" "non-empty refusal did not explain itself"

  sub="$TMP_ROOT/refuse/homes/asecondmate"
  mkdir -p "$sub"
  printf 'sm\n' > "$sub/.fm-secondmate-home"
  out=$(seed_peer "$main" sm "$sub" --peer hookgame) && fail "peer seed converted a secondmate home"
  assert_contains "$out" "is a secondmate home" "secondmate-home refusal did not explain itself"

  mkdir -p "$main/data"
  printf -- '- ops - ops domain (home: %s; scope: ops; projects: hookgame; added 2026-07-28)\n' \
    "$TMP_ROOT/refuse/homes/registered" > "$main/data/secondmates.md"
  out=$(seed_peer "$main" registered "$TMP_ROOT/refuse/homes/registered" --peer hookgame) \
    && fail "peer seed overlapped a registered secondmate home"
  assert_contains "$out" "overlaps registered secondmate home" "registry-overlap refusal did not explain itself"
  rm -f "$main/data/secondmates.md"

  pass "peer seed refuses unusable ids, nesting, occupied targets, and registered secondmate homes"
}

# The nesting invariant runs both ways: a peer home has no registry entry for a
# secondmate seed to collide with, so only the ancestor-marker walk stands
# between a secondmate clone and a peer home's inside.
test_seed_refuses_secondmate_nested_in_peer_home() {
  local main peer out
  main=$(new_main_home nestsub)
  peer="$TMP_ROOT/nestsub/homes/hookgame"
  seed_peer "$main" hookgame "$peer" --peer hookgame >/dev/null || fail "peer seed failed"

  out=$(seed_peer "$main" ops "$peer/ops" hookgame) && fail "secondmate seed nested inside a peer home"
  assert_contains "$out" "secondmate home $peer/ops is inside firstmate home $peer" \
    "nesting refusal did not name the secondmate home and its containing peer home"
  assert_absent "$peer/ops" "refused secondmate seed cloned a home inside the peer home anyway"
  assert_absent "$main/data/secondmates.md" "refused secondmate seed wrote a registry route"
  pass "secondmate seeding refuses a target nested inside a peer home"
}

test_seed_refuses_local_only_project() {
  local main out
  main=$(new_main_home localonly local-only)
  out=$(seed_peer "$main" solo "$TMP_ROOT/localonly/homes/solo" --peer hookgame) \
    && fail "peer seed cloned a local-only project"
  assert_contains "$out" "needs a shared upstream to reconcile through" \
    "local-only refusal did not give the peer-home reason"
  assert_absent "$TMP_ROOT/localonly/homes/solo" "refused peer seed left a home behind"
  pass "peer seed refuses a local-only project, which has no shared upstream to clone through"
}

test_seed_does_not_depend_on_remote_clone() {
  local main home out
  main=$(new_main_home rollback)
  # A peer shares the canonical checkout, so an unavailable remote must not make
  # it create or require a second clone.
  rm -rf "$TMP_ROOT/rollback/remote-hookgame.git"
  home="$TMP_ROOT/rollback/homes/hookgame"
  out=$(seed_peer "$main" hookgame "$home" --peer hookgame) || fail "peer seed required the unavailable remote: $out"
  assert_absent "$home/projects/hookgame" "peer seed cloned despite canonical-path sharing"
  assert_grep "  path: $TMP_ROOT/rollback/src/hookgame" "$home/data/projects.md" \
    "peer seed lost the canonical path while the remote was unavailable"
  pass "peer seeding shares the canonical checkout and does not depend on cloning its remote"
}

# --- launcher ----------------------------------------------------------------

test_open_launches_against_the_code_root() {
  local main home out
  main=$(new_main_home open)
  home="$TMP_ROOT/open/homes/hookgame"
  seed_peer "$main" hookgame "$home" --peer hookgame >/dev/null || fail "peer seed failed"

  # shellcheck disable=SC2016 # The launched command must expand these itself.
  out=$("$OPEN" "$home" sh -c 'printf "FM_HOME=%s\ncwd=%s\n" "$FM_HOME" "$PWD"') || fail "fm-open.sh failed: $out"
  assert_contains "$out" "FM_HOME=$home" "fm-open.sh did not export the peer home"
  assert_contains "$out" "cwd=$ROOT" "fm-open.sh did not run from the tracked code root"
  pass "fm-open.sh runs the harness from the code root with FM_HOME set to the peer home"
}

test_open_refusals() {
  local main home out rc
  main=$(new_main_home openrefuse)
  home="$TMP_ROOT/openrefuse/homes/hookgame"
  seed_peer "$main" hookgame "$home" --peer hookgame >/dev/null || fail "peer seed failed"

  out=$("$OPEN" "$TMP_ROOT/openrefuse/homes/hokgame" true 2>&1); rc=$?
  expect_code 1 "$rc" "mistyped home"
  assert_contains "$out" "does not exist or is not a directory" "mistyped home was not refused clearly"

  out=$("$OPEN" "$main" true 2>&1); rc=$?
  expect_code 1 "$rc" "non-peer directory"
  assert_contains "$out" "is not a peer firstmate home" "a non-peer directory was not refused"
  assert_contains "$out" "bin/fm-home-seed.sh" "refusal did not point at the seeder"

  out=$("$OPEN" "$home" fm-definitely-not-a-harness 2>&1); rc=$?
  expect_code 1 "$rc" "missing harness"
  assert_contains "$out" "harness command not found on PATH" "a missing harness was not refused"

  out=$("$OPEN" "$home" 2>&1); rc=$?
  expect_code 1 "$rc" "missing command argument"
  assert_contains "$out" "usage: fm-open.sh" "an omitted harness did not print usage"

  # A marker that does not name a usable id would poison the per-home backend
  # label, so it is refused rather than defaulted.
  printf 'bad id!\n' > "$home/.fm-peer-home"
  out=$("$OPEN" "$home" true 2>&1); rc=$?
  expect_code 1 "$rc" "unusable marker id"
  assert_contains "$out" "does not name a usable peer home id" "an unusable marker id was not refused"

  # A hand-written marker with no trailing newline is one the backends accept,
  # so the launcher guarding them must accept it too.
  printf 'hookgame' > "$home/.fm-peer-home"
  # shellcheck disable=SC2016 # The launched command must expand FM_HOME itself.
  out=$("$OPEN" "$home" sh -c 'printf "FM_HOME=%s\n" "$FM_HOME"' 2>&1) \
    || fail "a marker without a trailing newline was refused: $out"
  assert_contains "$out" "FM_HOME=$home" "fm-open.sh did not open a newline-less marker home"
  printf 'hookgame\n' > "$home/.fm-peer-home"

  rm -rf "$home/state"
  out=$("$OPEN" "$home" true 2>&1); rc=$?
  expect_code 1 "$rc" "missing operational dir"
  assert_contains "$out" "is missing state/" "a half-built home was not refused"

  pass "fm-open.sh refuses mistyped, non-peer, unusable, and half-built homes"
}

# An inherited FM_*_OVERRIDE outranks FM_HOME in every consumer, so a launcher
# that only exported FM_HOME would open a session reporting this peer home while
# reading another home's board - the isolation the whole feature sells.
test_open_clears_inherited_directory_overrides() {
  local main home decoy out
  main=$(new_main_home overrides)
  home="$TMP_ROOT/overrides/homes/hookgame"
  decoy="$TMP_ROOT/overrides/decoy"
  seed_peer "$main" hookgame "$home" --peer hookgame >/dev/null || fail "peer seed failed"
  mkdir -p "$decoy/data" "$decoy/state" "$decoy/config" "$decoy/projects"
  printf -- '- decoyproj [local-only] - a decoy board (added 2026-07-28)\n' > "$decoy/data/projects.md"
  printf 'not-a-pid\n' > "$decoy/state/.lock"

  # shellcheck disable=SC2016 # The launched command must resolve these itself.
  out=$(FM_STATE_OVERRIDE="$decoy/state" FM_DATA_OVERRIDE="$decoy/data" \
    FM_PROJECTS_OVERRIDE="$decoy/projects" FM_CONFIG_OVERRIDE="$decoy/config" \
    "$OPEN" "$home" sh -c '
      printf "mode=%s\n" "$(./bin/fm-project-mode.sh hookgame 2>/dev/null)"
      printf "lock=%s\n" "$(./bin/fm-lock.sh status)"
      printf "projects=%s\n" "${FM_PROJECTS_OVERRIDE:-$FM_HOME/projects}"
      printf "config=%s\n" "${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
    ' 2>&1) || fail "fm-open.sh failed with inherited overrides: $out"

  assert_contains "$out" "mode=direct-PR off" "the opened session read data/ from the decoy home, not the peer home"
  assert_contains "$out" "lock=lock: free" "the opened session read state/ from the decoy home, not the peer home"
  assert_contains "$out" "projects=$home/projects" "the opened session resolved projects/ outside the peer home"
  assert_contains "$out" "config=$home/config" "the opened session resolved config/ outside the peer home"
  assert_not_contains "$out" "$decoy" "the opened session still resolved part of its board to the decoy home"
  pass "fm-open.sh clears inherited directory overrides so the session resolves inside the peer home"
}

# --- per-home identity -------------------------------------------------------

test_backend_labels_separate_peer_homes() {
  local main a b tag_primary tag_a tag_b label_primary label_a label_b
  main=$(new_main_home labels)
  a="$TMP_ROOT/labels/homes/hookgame"
  b="$TMP_ROOT/labels/homes/delivery"
  seed_peer "$main" hookgame "$a" --peer hookgame >/dev/null || fail "peer seed a failed"
  seed_peer "$main" delivery "$b" --peer hookgame >/dev/null || fail "peer seed b failed"

  hometag() {  # <home>
    FM_HOME="$1" FM_ROOT="$ROOT" bash -c '. "$0"; fm_backend_hometag' "$ROOT/bin/fm-backend-hometag-lib.sh"
  }
  tag_primary=$(hometag "$ROOT")
  tag_a=$(hometag "$a")
  tag_b=$(hometag "$b")
  case "$tag_primary" in firstmate-*) : ;; *) fail "primary hometag changed shape: $tag_primary" ;; esac
  case "$tag_a" in peer-hookgame-*) : ;; *) fail "peer hometag is not peer-scoped: $tag_a" ;; esac
  [ "$tag_a" != "$tag_b" ] || fail "two peer homes sharing FM_ROOT collided on one hometag: $tag_a"

  herdr_label() {  # <home>
    FM_HOME="$1" FM_ROOT="$ROOT" bash -c \
      '. "$0"/bin/fm-backend.sh; fm_backend_source herdr >/dev/null 2>&1; fm_backend_herdr_workspace_label' "$ROOT"
  }
  label_primary=$(herdr_label "$ROOT")
  label_a=$(herdr_label "$a")
  label_b=$(herdr_label "$b")
  [ "$label_primary" = firstmate ] || fail "primary herdr workspace label changed: $label_primary"
  [ "$label_a" = peer-hookgame ] || fail "peer herdr workspace label is wrong: $label_a"
  [ "$label_b" = peer-delivery ] || fail "peer herdr workspace label is wrong: $label_b"
  pass "peer homes sharing one code root get distinct backend labels, and the primary's are unchanged"
}

test_session_lock_is_per_peer_home() {
  local main a b fakebin holder out
  main=$(new_main_home lock)
  a="$TMP_ROOT/lock/homes/hookgame"
  b="$TMP_ROOT/lock/homes/delivery"
  seed_peer "$main" hookgame "$a" --peer --no-projects >/dev/null || fail "peer seed a failed"
  seed_peer "$main" delivery "$b" --peer --no-projects >/dev/null || fail "peer seed b failed"

  # A live process whose command name matches a verified harness, so the lock
  # sees a genuine foreign session rather than a stale pid. The trailing no-op
  # keeps bash from exec'ing into a non-harness sleep, as in
  # fm-claude-stop-autoarm.test.sh.
  fakebin=$(fm_fakebin "$TMP_ROOT/lock")
  ln -s /bin/bash "$fakebin/claude"
  "$fakebin/claude" -c 'sleep 120; :' & holder=$!
  printf '%s\n' "$holder" > "$a/state/.lock"

  # Acquire from under a harness-named parent rather than this suite's own
  # ancestry: fm-lock.sh resolves the acquiring session by walking its parents,
  # so a run whose ancestry holds no verified harness (a detached gate driver,
  # CI) would fail on that instead of on the contested lock. The trailing
  # commands keep bash from exec'ing away the harness-named process, and pass the
  # real exit status back out.
  # shellcheck disable=SC2016  # single quotes are deliberate: "$0", $?, and "$rc" must reach the harness-named child shell verbatim, not expand here.
  out=$(FM_HOME="$a" "$fakebin/claude" -c '"$0"; rc=$?; exit "$rc"' \
    "$ROOT/bin/fm-lock.sh" 2>&1) && fail "a second session took a held peer-home lock"
  assert_contains "$out" "another live firstmate session holds the lock" "held peer-home lock was not refused clearly"

  out=$(FM_HOME="$b" "$ROOT/bin/fm-lock.sh" status 2>&1)
  [ "$out" = "lock: free" ] || fail "one peer home's lock leaked into another: $out"

  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  pass "each peer home owns its own session lock"
}

# --- the session a peer home opens -------------------------------------------

test_peer_session_start_sees_only_its_own_board() {
  local main home out
  main=$(new_main_home digest)
  home="$TMP_ROOT/digest/homes/hookgame"
  seed_peer "$main" hookgame "$home" --peer hookgame >/dev/null || fail "peer seed failed"
  printf -- '- alpha - a main-home project (added 2026-07-28)\n' >> "$main/data/projects.md"
  printf -- '- ops - ops domain (home: /nonexistent; scope: ops; projects: alpha; added 2026-07-28)\n' \
    > "$main/data/secondmates.md"

  out=$(FM_HOME="$home" FM_FLEET_SYNC_BOOTSTRAP_TIMEOUT=1 "$ROOT/bin/fm-session-start.sh" 2>&1) \
    || fail "peer session start failed"
  assert_contains "$out" "SESSION START - $home" "peer session start did not name its own home"
  assert_contains "$out" "the hook game" "peer session start did not show its own project registry"
  assert_not_contains "$out" "a main-home project" "peer session start leaked the active home's registry"
  assert_not_contains "$out" "ops domain" "peer session start leaked the active home's secondmate routes"
  # A peer home is nobody's parent and nobody's subordinate.
  assert_contains "$out" "SUPERVISION OPERATING INSTRUCTIONS" \
    "peer session start did not emit the full firstmate supervision block"
  pass "a peer session start sees only its own board and gets the full firstmate protocol"
}

test_seed_shape
test_seed_projectless
test_seed_reseed_is_idempotent
test_seed_refusals
test_seed_refuses_secondmate_nested_in_peer_home
test_seed_refuses_local_only_project
test_seed_does_not_depend_on_remote_clone
test_open_launches_against_the_code_root
test_open_refusals
test_open_clears_inherited_directory_overrides
test_backend_labels_separate_peer_homes
test_session_lock_is_per_peer_home
test_peer_session_start_sees_only_its_own_board
echo "# all fm-peer-home tests passed"
