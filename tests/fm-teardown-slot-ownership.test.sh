#!/usr/bin/env bash
# Regression tests for worktree-pool slot ownership (bin/fm-treehouse-lib.sh) and the
# cleanup boundary that enforces it (bin/fm-teardown.sh).
#
# A task's recorded worktree= is a claim, not tenancy. When a worker exits, the pool
# frees the slot at once and may hand it to a different task - including one in an
# independent peer home that appears in no registry anywhere, which is why ownership
# is resolved from the pool's own records rather than by enumerating homes.
#
# Matrix, ownership resolution:
#   (a) no pool state file for the path              -> unmanaged (boundary N/A)
#   (b) current allocation equals the recorded one   -> owned
#   (c) current allocation differs from the recorded -> foreign
#   (d) slot carries another task's fm/ branch       -> foreign
#   (e) no recorded allocation, own fm/ branch       -> owned  (pre-wt_alloc tasks)
#   (f) allocated to nobody, nothing running         -> owned
#   (g) allocated to nobody, processes still inside  -> ambiguous
#   (h) pool state present but unparseable           -> ambiguous (never "vacant")
#
# Matrix, cleanup boundary:
#   (i) foreign slot                 -> REFUSED with nothing signalled or returned
#   (j) foreign slot with --force    -> still REFUSED (--force is not another task's)
#   (k) ambiguous slot with --force  -> proceeds, naming what it leaves behind
#   (l) owned slot                   -> ordinary cleanup still completes
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

# shellcheck source=bin/fm-treehouse-lib.sh disable=SC1091
. "$ROOT/bin/fm-treehouse-lib.sh"

TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-teardown-slot-ownership)

# A pool laid out the way treehouse lays one out: <pool>/<slot>/<repo>, with the
# state file the pool keeps beside its slots. Echoes the worktree path.
make_pool_slot() {  # <case-dir> <slot-name>
  local case_dir=$1 slot=$2 wt
  wt="$case_dir/pool/$slot/repo"
  mkdir -p "$wt"
  printf '%s\n' "$wt"
}

# Write the pool state file for one slot. <allocation> is "", "owner:<pid>:<started>"
# or "lease:<id>:<holder>".
write_pool_state() {  # <case-dir> <worktree> <allocation>
  local case_dir=$1 wt=$2 alloc=$3 entry
  case "$alloc" in
    owner:*)
      entry=$(printf '"owner_pid": %s, "owner_started_at": %s' \
        "$(printf '%s' "$alloc" | cut -d: -f2)" "$(printf '%s' "$alloc" | cut -d: -f3)") ;;
    lease:*)
      entry=$(printf '"leased": true, "lease_id": "%s", "lease_holder": "%s"' \
        "$(printf '%s' "$alloc" | cut -d: -f2)" "$(printf '%s' "$alloc" | cut -d: -f3)") ;;
    *) entry='"created_at": "2026-09-06T00:00:00-07:00"' ;;
  esac
  printf '{"worktrees":[{"name":"1","path":"%s",%s}]}\n' "$wt" "$entry" \
    > "$case_dir/pool/treehouse-state.json"
}

# A `treehouse` stub whose status reports the given process count for the slot.
fake_treehouse_with_processes() {  # <case-dir> <worktree> <count>
  local case_dir=$1 wt=$2 count=$3 procs="" i=0
  while [ "$i" -lt "$count" ]; do
    procs="$procs${procs:+,}{\"pid\":$((9000 + i)),\"name\":\"sleep\"}"
    i=$((i + 1))
  done
  mkdir -p "$case_dir/fakebin"
  cat > "$case_dir/fakebin/treehouse" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = status ]; then
  printf '%s\n' '[{"name":"1","path":"$wt","status":"in-use","processes":[$procs]}]'
  exit 0
fi
printf 'treehouse %s\n' "\$*" >> "\${FM_RUNTIME_LOG:-/dev/null}"
exit 0
SH
  chmod +x "$case_dir/fakebin/treehouse"
}

classify() {  # <worktree> <task-id> <recorded-allocation>
  PATH="${CLASSIFY_PATH:-$PATH}" bash -c '
    . "$1/bin/fm-treehouse-lib.sh"
    fm_treehouse_classify_slot "$2" "$3" "$4"
  ' _ "$ROOT" "$1" "$2" "$3"
}

verdict_of() { printf '%s' "${1%%$'\t'*}"; }

expect_verdict() {  # <expected> <actual-line> <description>
  local got
  got=$(verdict_of "$2")
  [ "$got" = "$1" ] || fail "$3: expected $1, got $got (${2#*$'\t'})"
  pass "$3"
}

# --- ownership resolution ---------------------------------------------------

test_unmanaged_path_is_out_of_scope() {
  local case_dir wt
  case_dir="$TMP_ROOT/unmanaged"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  expect_verdict unmanaged "$(classify "$wt" task-x1 "")" \
    "(a) a path with no pool state file is out of this boundary's scope"
}

test_matching_allocation_is_owned() {
  local case_dir wt
  case_dir="$TMP_ROOT/alloc-match"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" owner:4242:1788000000000
  expect_verdict owned "$(classify "$wt" task-x1 owner:4242:1788000000000)" \
    "(b) the allocation the task was handed still being current proves tenancy"
}

test_changed_allocation_is_foreign() {
  local case_dir wt
  case_dir="$TMP_ROOT/alloc-changed"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" owner:9999:1788000009999
  expect_verdict foreign "$(classify "$wt" task-x1 owner:4242:1788000000000)" \
    "(c) the pool having handed the slot to a different holder proves foreign tenancy"
}

test_reassigned_to_a_lease_is_foreign() {
  local case_dir wt
  case_dir="$TMP_ROOT/alloc-leased"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" lease:abc123:another-home
  expect_verdict foreign "$(classify "$wt" task-x1 owner:4242:1788000000000)" \
    "(c) a slot re-leased to another home reads as foreign, not as merely changed"
}

test_another_tasks_branch_is_foreign() {
  local case_dir wt
  case_dir="$TMP_ROOT/branch-foreign"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  git init -q -b fm/other-task "$wt"
  git -C "$wt" commit -q --allow-empty -m "the occupying task's work"
  expect_verdict foreign "$(classify "$wt" task-x1 "")" \
    "(d) another task's branch in the slot proves foreign tenancy on its own"
}

test_own_branch_proves_ownership_without_a_recorded_allocation() {
  local case_dir wt
  case_dir="$TMP_ROOT/branch-own"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" owner:9999:1788000009999
  git init -q -b fm/task-x1 "$wt"
  git -C "$wt" commit -q --allow-empty -m "this task's own work"
  expect_verdict owned "$(classify "$wt" task-x1 "")" \
    "(e) a task with no recorded allocation is still proven by its own branch"
}

test_vacant_slot_is_owned() {
  local case_dir wt
  case_dir="$TMP_ROOT/vacant"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  fake_treehouse_with_processes "$case_dir" "$wt" 0
  expect_verdict owned "$(CLASSIFY_PATH="$case_dir/fakebin:$PATH" classify "$wt" task-x1 "")" \
    "(f) a slot allocated to nobody with nothing running holds no work to protect"
}

test_unallocated_slot_with_occupants_is_ambiguous() {
  local case_dir wt
  case_dir="$TMP_ROOT/occupied"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  fake_treehouse_with_processes "$case_dir" "$wt" 2
  expect_verdict ambiguous "$(CLASSIFY_PATH="$case_dir/fakebin:$PATH" classify "$wt" task-x1 "")" \
    "(g) processes this task cannot claim keep an unallocated slot ambiguous"
}

test_unreadable_pool_state_is_ambiguous() {
  local case_dir wt
  case_dir="$TMP_ROOT/corrupt"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" owner:4242:1788000000000
  # Truncate the record mid-object: the file is still there, but nothing in it parses.
  printf '{"worktrees":[{"name":"1","path":"%s",\n' "$wt" > "$case_dir/pool/treehouse-state.json"
  expect_verdict ambiguous "$(classify "$wt" task-x1 owner:4242:1788000000000)" \
    "(h) a pool record that cannot be read is never treated as an empty slot"
}

# --- the cleanup boundary ---------------------------------------------------

# A full teardown sandbox whose worktree IS a pool slot. Echoes the case dir.
make_teardown_case() {  # <name> <allocation> [recorded-allocation]
  local name=$1 alloc=$2 recorded=${3:-} case_dir wt
  case_dir="$TMP_ROOT/$name"
  mkdir -p "$case_dir/state" "$case_dir/data" "$case_dir/config" "$case_dir/fakebin"
  touch "$case_dir/state/.last-watcher-beat"
  : > "$case_dir/runtime.log"

  git init -q --bare "$case_dir/origin.git"
  git -C "$case_dir/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$case_dir/origin.git" "$case_dir/_seed" 2>/dev/null
  git -C "$case_dir/_seed" commit -q --allow-empty -m baseline
  git -C "$case_dir/_seed" push -q origin main
  rm -rf "$case_dir/_seed"
  git clone -q "$case_dir/origin.git" "$case_dir/project"
  git -C "$case_dir/project" remote set-head origin main 2>/dev/null || true

  wt="$case_dir/pool/1/repo"
  mkdir -p "$case_dir/pool/1"
  git -C "$case_dir/project" worktree add -q -b fm/task-x1 "$wt" main
  write_pool_state "$case_dir" "$wt" "$alloc"
  fake_treehouse_with_processes "$case_dir" "$wt" 1

  fm_fake_exit0 "$case_dir/fakebin" tmux gh gh-axi no-mistakes tasks-axi lsof
  fm_write_meta "$case_dir/state/task-x1.meta" \
    "window=firstmate:fm-task-x1" \
    "endpoint_task_id=task-x1" \
    "worktree=$wt" \
    "project=$case_dir/project" \
    "kind=ship" \
    "mode=local-only" \
    ${recorded:+"wt_alloc=$recorded"}
  printf '%s\n' "$case_dir"
}

run_case_teardown() {  # <case-dir> [--force]
  local case_dir=$1; shift
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$case_dir/state" \
  FM_DATA_OVERRIDE="$case_dir/data" \
  FM_CONFIG_OVERRIDE="$case_dir/config" \
  FM_RUNTIME_LOG="$case_dir/runtime.log" \
  PATH="$case_dir/fakebin:$PATH" \
    "$TEARDOWN" task-x1 "$@"
}

# Point the slot at another task, so ownership resolves foreign.
make_slot_foreign() {  # <case-dir>
  local case_dir=$1 wt="$1/pool/1/repo"
  git -C "$wt" checkout -q -b fm/some-other-task
}

test_foreign_slot_refuses_before_any_destruction() {
  local case_dir rc
  case_dir=$(make_teardown_case foreign-refuses owner:9999:1788000009999 owner:4242:1788000000000)
  make_slot_foreign "$case_dir"

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "(i) teardown should refuse a slot this task no longer holds"
  grep -q REFUSED "$case_dir/stderr" || fail "(i) no REFUSED line"
  [ ! -s "$case_dir/runtime.log" ] \
    || fail "(i) a runtime command ran before the refusal: $(cat "$case_dir/runtime.log")"
  assert_present "$case_dir/state/task-x1.meta" "(i) the task record was cleared despite refusing"
  git -C "$case_dir/pool/1/repo" rev-parse --verify -q fm/some-other-task >/dev/null \
    || fail "(i) the occupying task's branch was deleted despite refusing"
  pass "a slot handed to another task refuses cleanup before anything is signalled or returned"
}

test_force_never_overrides_foreign_ownership() {
  local case_dir rc
  case_dir=$(make_teardown_case foreign-force owner:9999:1788000009999 owner:4242:1788000000000)
  make_slot_foreign "$case_dir"

  set +e
  run_case_teardown "$case_dir" --force > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "(j) --force should not override foreign slot ownership"
  [ ! -s "$case_dir/runtime.log" ] \
    || fail "(j) --force ran a runtime command against another task's slot"
  git -C "$case_dir/pool/1/repo" rev-parse --verify -q fm/some-other-task >/dev/null \
    || fail "(j) --force deleted the occupying task's branch"
  pass "--force discards this task's work, never the work of the task now holding the slot"
}

test_force_overrides_ambiguous_ownership() {
  local case_dir rc
  case_dir=$(make_teardown_case ambiguous-force owner:9999:1788000009999)
  git -C "$case_dir/pool/1/repo" checkout -q --detach

  set +e
  run_case_teardown "$case_dir" --force > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "(k) --force should proceed once ownership is merely unproven"
  grep -q "cannot prove it still holds" "$case_dir/stderr" \
    || fail "(k) the unproven-ownership refusal was not reported before --force overrode it"
  grep -q "leaving behind" "$case_dir/stderr" \
    || fail "(k) --force did not name what it leaves behind"
  pass "unproven ownership refuses loudly and names what --force would leave behind"
}

test_owned_slot_is_still_torn_down() {
  local case_dir rc
  case_dir=$(make_teardown_case owned-proceeds owner:4242:1788000000000 owner:4242:1788000000000)

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "(l) a slot this task still holds should be torn down normally: $(cat "$case_dir/stderr")"
  ! grep -q REFUSED "$case_dir/stderr" || fail "(l) genuine owned cleanup was refused"
  grep -q 'treehouse return --force' "$case_dir/runtime.log" \
    || fail "(l) the worktree was never returned to the pool: $(cat "$case_dir/runtime.log")"
  [ ! -f "$case_dir/state/task-x1.meta" ] || fail "(l) the task record survived a completed cleanup"
  pass "genuine owned cleanup still reaps, returns the slot and clears the record"
}

test_unmanaged_path_is_out_of_scope
test_matching_allocation_is_owned
test_changed_allocation_is_foreign
test_reassigned_to_a_lease_is_foreign
test_another_tasks_branch_is_foreign
test_own_branch_proves_ownership_without_a_recorded_allocation
test_vacant_slot_is_owned
test_unallocated_slot_with_occupants_is_ambiguous
test_unreadable_pool_state_is_ambiguous
test_foreign_slot_refuses_before_any_destruction
test_force_never_overrides_foreign_ownership
test_force_overrides_ambiguous_ownership
test_owned_slot_is_still_torn_down
