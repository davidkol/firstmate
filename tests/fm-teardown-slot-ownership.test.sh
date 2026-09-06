#!/usr/bin/env bash
# Regression tests for worktree-pool slot ownership (bin/fm-treehouse-lib.sh) and the
# cleanup boundary that enforces it (bin/fm-teardown.sh).
#
# A task's recorded worktree= is a claim, not tenancy. An unleased slot is freed the
# moment its worker exits and the pool may hand it to a different task - including one
# in an independent peer home that appears in no registry anywhere, which is why
# ownership is resolved from the pool's own records rather than by enumerating homes.
# Attribution alone is not enough either: the slot has to stay reserved THROUGH the
# destructive steps, which is what the pool's durable lease does.
#
# Matrix, ownership resolution:
#   (a) no pool state file for the path              -> unmanaged (boundary N/A)
#   (b) current allocation equals the recorded one   -> owned
#   (c) current allocation differs from the recorded -> foreign
#   (d) slot carries another task's fm/ branch       -> foreign
#   (e) no recorded allocation, own fm/ branch       -> owned  (pre-wt_alloc tasks)
#   (f) matching allocation, sibling's fm/ branch    -> ambiguous (signals conflict)
#   (g) allocated to nobody, nothing running         -> ambiguous (snapshot, not lease)
#   (h) allocated to nobody, processes still inside  -> ambiguous, naming the count
#   (i) pool state present but unparseable           -> ambiguous (never "vacant")
#   (j) process count comes from the SLOT's pool, not the caller's working directory
#
# Matrix, cleanup boundary:
#   (k) foreign slot                 -> REFUSED with nothing signalled or returned
#   (l) foreign slot with --force    -> still REFUSED (--force is not another task's)
#   (m) ambiguous slot with --force  -> proceeds, naming what it leaves behind
#   (n) owned slot                   -> ordinary cleanup still completes
#   (o) leased slot                  -> returned under the pool's own lease precondition
#   (p) leased slot, treehouse without that precondition -> REFUSED, never unguarded
#   (q) unreadable pool at the return -> REFUSED even under --force
#   (r) teardown invoked from a home whose own pool is a different pool
#   (s) a real lease keeps a real contender out for the whole cleanup
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

# A `treehouse` stub that behaves the way the real one does in the two ways this
# boundary depends on: it resolves WHICH pool it is talking about from its own
# working directory, and its `return --help` advertises the lease preconditions only
# when the build supports them. Every `return` invocation is logged with its full
# argument list, so a test can see the precondition the return actually carried.
write_fake_treehouse() {  # <case-dir> <pool-context-dir> <worktree> <process-count> [no-conditional-return]
  local case_dir=$1 ctx=$2 wt=$3 count=$4 plain=${5:-} procs="" i=0 ctx_real
  ctx_real=$(cd "$ctx" 2>/dev/null && pwd -P) || ctx_real=$ctx
  while [ "$i" -lt "$count" ]; do
    procs="$procs${procs:+,}{\"pid\":$((9000 + i)),\"name\":\"sleep\"}"
    i=$((i + 1))
  done
  mkdir -p "$case_dir/fakebin"
  cat > "$case_dir/fakebin/treehouse" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = get ] && [ "\${2:-}" = --help ]; then
  printf '%s\n' 'Usage: treehouse get [--lease] [--lease-holder <holder>]'
  exit 0
fi
if [ "\${1:-}" = return ] && [ "\${2:-}" = --help ]; then
  if [ -n "$plain" ]; then
    printf '%s\n' 'Usage: treehouse return [--force]'
  else
    printf '%s\n' 'Usage: treehouse return [--force] [--if-lease-id <id>] [--if-lease-holder <holder>]'
  fi
  exit 0
fi
if [ "\${1:-}" = status ]; then
  # The real treehouse resolves the pool from its working directory, so a query run
  # from anywhere else describes a DIFFERENT pool and knows nothing about this slot.
  if [ "\$(pwd -P)" = '$ctx_real' ]; then
    printf '%s\n' '[{"name":"1","path":"$wt","status":"in-use","processes":[$procs]}]'
  else
    printf '%s\n' '[]'
  fi
  exit 0
fi
printf 'treehouse %s\n' "\$*" >> "\${FM_RUNTIME_LOG:-/dev/null}"
exit 0
SH
  chmod +x "$case_dir/fakebin/treehouse"
}

classify() {  # <worktree> <task-id> <recorded-allocation> [pool-context-dir]
  PATH="${CLASSIFY_PATH:-$PATH}" bash -c '
    . "$1/bin/fm-treehouse-lib.sh"
    fm_treehouse_classify_slot "$2" "$3" "$4" "$5"
  ' _ "$ROOT" "$1" "$2" "$3" "${4:-}"
}

verdict_of() { printf '%s' "${1%%$'\t'*}"; }
reason_of() { printf '%s' "${1#*$'\t'}"; }

expect_verdict() {  # <expected> <actual-line> <description>
  local got
  got=$(verdict_of "$2")
  [ "$got" = "$1" ] || fail "$3: expected $1, got $got ($(reason_of "$2"))"
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
  write_pool_state "$case_dir" "$wt" lease:abc123:task-x1
  expect_verdict owned "$(classify "$wt" task-x1 lease:abc123)" \
    "(b) the lease the task was handed still being current proves tenancy"
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

# The pool's own allocation record is the authority on who was HANDED the slot, so a
# sibling's branch inside a slot the pool still says is ours is a conflict between
# two signals, not proof of another tenant. Calling it foreign would make the task
# untearable-down forever, because foreign is deliberately not forceable.
test_matching_allocation_with_a_sibling_branch_is_a_conflict() {
  local case_dir wt line
  case_dir="$TMP_ROOT/alloc-vs-branch"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" lease:abc123:task-x1
  git init -q -b fm/some-other-task "$wt"
  git -C "$wt" commit -q --allow-empty -m "a sibling branch checked out in our slot"
  line=$(classify "$wt" task-x1 lease:abc123)
  expect_verdict ambiguous "$line" \
    "(f) a matching allocation with a sibling's branch is a conflict, not a foreign tenant"
  assert_contains "$(reason_of "$line")" "signals disagree" \
    "(f) the conflict between the two signals was not reported"
}

# "Nothing was running when we looked" is a snapshot: the pool can hand a free slot
# to a new worker at any moment, including while this cleanup runs. So an empty
# process list may sharpen the evidence but must never become a verdict.
test_vacant_slot_is_never_proof_of_ownership() {
  local case_dir wt line
  case_dir="$TMP_ROOT/vacant"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  write_fake_treehouse "$case_dir" "$case_dir" "$wt" 0
  line=$(CLASSIFY_PATH="$case_dir/fakebin:$PATH" classify "$wt" task-x1 "" "$case_dir")
  expect_verdict ambiguous "$line" \
    "(g) a slot allocated to nobody is unreserved, so cleanup of it is never proven safe"
  assert_contains "$(reason_of "$line")" "not a reservation" \
    "(g) the reason did not say why an empty slot still is not ours"
}

test_unallocated_slot_with_occupants_is_ambiguous() {
  local case_dir wt line
  case_dir="$TMP_ROOT/occupied"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  write_fake_treehouse "$case_dir" "$case_dir" "$wt" 2
  line=$(CLASSIFY_PATH="$case_dir/fakebin:$PATH" classify "$wt" task-x1 "" "$case_dir")
  expect_verdict ambiguous "$line" \
    "(h) processes this task cannot claim keep an unallocated slot ambiguous"
  assert_contains "$(reason_of "$line")" "2 process(es)" \
    "(h) the occupants the operator has to decide about were not counted"
}

test_unreadable_pool_state_is_ambiguous() {
  local case_dir wt
  case_dir="$TMP_ROOT/corrupt"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" owner:4242:1788000000000
  # Truncate the record mid-object: the file is still there, but nothing in it parses.
  printf '{"worktrees":[{"name":"1","path":"%s",\n' "$wt" > "$case_dir/pool/treehouse-state.json"
  expect_verdict ambiguous "$(classify "$wt" task-x1 owner:4242:1788000000000)" \
    "(i) a pool record that cannot be read is never treated as an empty slot"
}

# treehouse answers about the pool its WORKING DIRECTORY resolves to. Teardown runs
# from the firstmate home, whose pool is a different pool, so a process count taken
# there describes nothing about the task's slot. A pool that does not list the slot
# is no answer at all and must never read as a count of zero.
test_process_count_comes_from_the_slots_own_pool() {
  local case_dir wt elsewhere right wrong
  case_dir="$TMP_ROOT/pool-context"; mkdir -p "$case_dir"
  elsewhere="$case_dir/another-home"; mkdir -p "$elsewhere"
  wt=$(make_pool_slot "$case_dir" 1)
  write_pool_state "$case_dir" "$wt" ""
  write_fake_treehouse "$case_dir" "$case_dir" "$wt" 3

  right=$(cd "$elsewhere" && CLASSIFY_PATH="$case_dir/fakebin:$PATH" \
    classify "$wt" task-x1 "" "$case_dir")
  assert_contains "$(reason_of "$right")" "3 process(es)" \
    "(j) the slot's own pool was not queried when the caller sat in another directory"

  wrong=$(CLASSIFY_PATH="$case_dir/fakebin:$PATH" classify "$wt" task-x1 "" "$elsewhere")
  assert_contains "$(reason_of "$wrong")" "could not say what is running in it" \
    "(j) a pool that does not list the slot was read as an empty slot instead of as no answer"
  pass "the slot's occupancy is read from the pool that governs it, and a non-answer stays a non-answer"
}

# The two failures of a pool lookup mean opposite things and must not collapse:
# "this path is not a pool slot" leaves nothing to guard, while "the pool could not
# answer" must stop a destructive return.
test_lease_holder_separates_unmanaged_from_unreadable() {
  local case_dir wt rc=0
  case_dir="$TMP_ROOT/lease-holder-rc"; mkdir -p "$case_dir"
  wt=$(make_pool_slot "$case_dir" 1)

  fm_treehouse_lease_holder "$wt" >/dev/null 2>&1 || rc=$?
  expect_code 1 "$rc" "a path that is no pool slot at all must report exactly that"

  write_pool_state "$case_dir" "$wt" lease:abc123:task-x1
  printf '{"worktrees":[{"name":"1","path":"%s",\n' "$wt" > "$case_dir/pool/treehouse-state.json"
  rc=0
  fm_treehouse_lease_holder "$wt" >/dev/null 2>&1 || rc=$?
  expect_code "$FM_TREEHOUSE_RC_UNREADABLE" "$rc" \
    "a pool whose state cannot be parsed must report an unreadable authority, not an absent one"
  pass "the unmanaged and unreadable failures stay distinguishable at every caller"
}

# A spawn that leases a slot and then fails has no record naming the path it took,
# so releasing it again means asking the pool which slot that holder leases. The
# lookup has to name exactly one slot, and say nothing at all when the holder has
# none - releasing the wrong slot would be the very act this boundary prevents.
test_leased_slot_lookup_finds_only_its_own_holder() {
  local case_dir status got rc
  case_dir="$TMP_ROOT/leased-lookup"; mkdir -p "$case_dir/project"
  status='[{"name":"1","path":"/pool/1/repo","status":"leased","lease_holder":"task-x1","processes":[]},'
  status="$status"'{"name":"2","path":"/pool/2/repo","status":"leased","lease_holder":"other-task","processes":[]},'
  status="$status"'{"name":"3","path":"/pool/3/repo","status":"available","processes":[]}]'
  mkdir -p "$case_dir/fakebin"
  cat > "$case_dir/fakebin/treehouse" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = status ] && printf '%s\n' '$status'
exit 0
SH
  chmod +x "$case_dir/fakebin/treehouse"

  got=$(PATH="$case_dir/fakebin:$PATH" fm_treehouse_leased_slot_path "$case_dir/project" task-x1)
  [ "$got" = /pool/1/repo ] \
    || fail "the pool's own record of this holder's slot was not found (got '$got')"

  rc=0
  PATH="$case_dir/fakebin:$PATH" fm_treehouse_leased_slot_path "$case_dir/project" nobody >/dev/null 2>&1 \
    || rc=$?
  [ "$rc" -ne 0 ] || fail "a holder with no lease was answered with a slot to release"
  pass "an aborted spawn can find exactly its own leased slot, and nothing when it holds none"
}

# --- the cleanup boundary ---------------------------------------------------

# A full teardown sandbox whose worktree IS a pool slot. Echoes the case dir.
make_teardown_case() {  # <name> <allocation> [recorded-allocation] [no-conditional-return]
  local name=$1 alloc=$2 recorded=${3:-} plain=${4:-} case_dir wt
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
  write_fake_treehouse "$case_dir" "$case_dir/project" "$wt" 1 "$plain"

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

# Teardown is invoked by the firstmate from its OWN home, never from the task's
# project, which is exactly why the pool it resolves by working directory is the
# wrong pool. Every case below runs from such a home.
run_case_teardown() {  # <case-dir> [--force]
  local case_dir=$1; shift
  local home="$case_dir/firstmate-home"
  mkdir -p "$home"
  ( cd "$home" && \
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" \
    FM_CONFIG_OVERRIDE="$case_dir/config" \
    FM_RUNTIME_LOG="$case_dir/runtime.log" \
    PATH="$case_dir/fakebin:$PATH" \
      "$TEARDOWN" task-x1 "$@" )
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

  expect_code 1 "$rc" "(k) teardown should refuse a slot this task no longer holds"
  grep -q REFUSED "$case_dir/stderr" || fail "(k) no REFUSED line"
  [ ! -s "$case_dir/runtime.log" ] \
    || fail "(k) a runtime command ran before the refusal: $(cat "$case_dir/runtime.log")"
  assert_present "$case_dir/state/task-x1.meta" "(k) the task record was cleared despite refusing"
  git -C "$case_dir/pool/1/repo" rev-parse --verify -q fm/some-other-task >/dev/null \
    || fail "(k) the occupying task's branch was deleted despite refusing"
  assert_no_grep "state/task-x1.meta" "$case_dir/stderr" \
    "(k) the refusal told the operator to hand-edit the task record"
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

  expect_code 1 "$rc" "(l) --force should not override foreign slot ownership"
  [ ! -s "$case_dir/runtime.log" ] \
    || fail "(l) --force ran a runtime command against another task's slot"
  git -C "$case_dir/pool/1/repo" rev-parse --verify -q fm/some-other-task >/dev/null \
    || fail "(l) --force deleted the occupying task's branch"
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

  expect_code 0 "$rc" "(m) --force should proceed once ownership is merely unproven"
  grep -q "cannot prove it still holds" "$case_dir/stderr" \
    || fail "(m) the unproven-ownership refusal was not reported before --force overrode it"
  grep -q "leaving behind" "$case_dir/stderr" \
    || fail "(m) --force did not name what it leaves behind"
  pass "unproven ownership refuses loudly and names what --force would leave behind"
}

test_owned_slot_is_still_torn_down() {
  local case_dir rc
  case_dir=$(make_teardown_case owned-proceeds owner:4242:1788000000000 owner:4242:1788000000000)

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "(n) a slot this task still holds should be torn down normally: $(cat "$case_dir/stderr")"
  ! grep -q REFUSED "$case_dir/stderr" || fail "(n) genuine owned cleanup was refused"
  grep -q 'treehouse return --force' "$case_dir/runtime.log" \
    || fail "(n) the worktree was never returned to the pool: $(cat "$case_dir/runtime.log")"
  [ ! -f "$case_dir/state/task-x1.meta" ] || fail "(n) the task record survived a completed cleanup"
  pass "genuine owned cleanup still reaps, returns the slot and clears the record"
}

# The return of a leased slot has to carry the pool's own precondition, so the pool
# refuses a slot whose lease moved instead of this script deciding from a read that
# may already be stale.
test_leased_slot_is_returned_under_its_lease() {
  local case_dir rc
  case_dir=$(make_teardown_case leased-guarded lease:lease-abc:task-x1 lease:lease-abc)

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 0 "$rc" "(o) a leased slot this task holds should be torn down: $(cat "$case_dir/stderr")"
  assert_grep "treehouse return --force --if-lease-id lease-abc" "$case_dir/runtime.log" \
    "(o) the return did not carry the lease precondition the task was handed"
  pass "a leased slot is returned only under the pool's own lease precondition"
}

# Without the precondition there is no way to make the check and the return one
# operation, and an unguarded retry is exactly the act the precondition prevents.
test_missing_conditional_return_refuses_rather_than_returning_unguarded() {
  local case_dir rc
  case_dir=$(make_teardown_case leased-no-precondition lease:lease-abc:task-x1 lease:lease-abc no-conditional)

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "(p) a treehouse that cannot enforce the lease precondition must stop teardown"
  grep -q REFUSED "$case_dir/stderr" || fail "(p) no REFUSED line for the missing precondition"
  [ ! -s "$case_dir/runtime.log" ] \
    || fail "(p) a runtime command ran before the refusal: $(cat "$case_dir/runtime.log")"
  assert_present "$case_dir/state/task-x1.meta" "(p) the task record was cleared despite refusing"
  git -C "$case_dir/pool/1/repo" rev-parse --verify -q fm/task-x1 >/dev/null \
    || fail "(p) the branch was deleted before the refusal"
  pass "a treehouse that cannot enforce the lease precondition refuses instead of returning unguarded"
}

# --force authorizes discarding this task's work; it cannot authorize acting on an
# authority nobody can read, because that is the state in which the slot may already
# belong to somebody else.
test_unreadable_pool_refuses_the_return_even_under_force() {
  local case_dir rc
  case_dir=$(make_teardown_case unreadable-return lease:lease-abc:task-x1)
  git -C "$case_dir/pool/1/repo" checkout -q --detach
  printf '{"worktrees":[{"name":"1","path":"%s",\n' "$case_dir/pool/1/repo" \
    > "$case_dir/pool/treehouse-state.json"

  set +e
  run_case_teardown "$case_dir" --force > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "(q) an unreadable pool must stop the return even under --force"
  assert_no_grep "treehouse return" "$case_dir/runtime.log" \
    "(q) the slot was returned while the pool's own record could not be read"
  pass "an unreadable pool record refuses the destructive return rather than proceeding unguarded"
}

# Teardown runs from the firstmate home, whose own pool is a different pool. The
# occupancy evidence in its refusal can only come from the task's own pool.
test_ownership_is_decided_from_the_tasks_pool_not_the_homes() {
  local case_dir rc
  case_dir=$(make_teardown_case home-pool-context "")
  git -C "$case_dir/pool/1/repo" checkout -q --detach

  set +e
  run_case_teardown "$case_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e

  expect_code 1 "$rc" "(r) an unreserved slot must refuse cleanup invoked from the firstmate home"
  grep -q "1 process(es) running in it" "$case_dir/stderr" \
    || fail "(r) the occupancy evidence did not come from the task's own pool: $(cat "$case_dir/stderr")"
  pass "ownership evidence is read from the task's pool even though teardown runs from another"
}

# --- the reservation itself, against the real pool --------------------------

# The strongest claim this boundary makes is not that it attributes the slot
# correctly but that a contender cannot enter WHILE cleanup runs. Prove it against
# the real treehouse: hold the slot by lease, let an adversary try to take it at the
# last instant before the destructive return, and check it was kept out.
test_a_real_lease_keeps_a_contender_out_through_cleanup() {
  local case_dir proj pool wt lease_id sleep_pid rc real_treehouse
  command -v treehouse >/dev/null 2>&1 \
    || { echo "skip: treehouse not found (the reservation proof needs the real pool)"; return 0; }
  fm_treehouse_supports_lease \
    || { echo "skip: installed treehouse cannot lease a slot"; return 0; }
  fm_treehouse_supports_conditional_return \
    || { echo "skip: installed treehouse cannot return under a lease precondition"; return 0; }
  real_treehouse=$(command -v treehouse)

  case_dir="$TMP_ROOT/real-lease"
  mkdir -p "$case_dir/state" "$case_dir/data" "$case_dir/config" "$case_dir/fakebin" \
    "$case_dir/firstmate-home"
  touch "$case_dir/state/.last-watcher-beat"

  git init -q --bare "$case_dir/origin.git"
  git -C "$case_dir/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$case_dir/origin.git" "$case_dir/_seed" 2>/dev/null
  git -C "$case_dir/_seed" commit -q --allow-empty -m baseline
  git -C "$case_dir/_seed" push -q origin main
  rm -rf "$case_dir/_seed"
  proj="$case_dir/project"
  git clone -q "$case_dir/origin.git" "$proj"
  git -C "$proj" remote set-head origin main 2>/dev/null || true
  # One slot only, so an adversary that gets anything at all has taken ours.
  printf 'max_trees = 1\nroot = "./"\n' > "$proj/treehouse.toml"
  git -C "$proj" add treehouse.toml
  git -C "$proj" commit -q -m "scratch pool config"
  git -C "$proj" push -q origin main

  wt=$( cd "$proj" && "$real_treehouse" get --lease --lease-holder task-x1 2>/dev/null ) \
    || { echo "skip: could not lease a scratch slot"; return 0; }
  [ -n "$wt" ] || { echo "skip: the scratch pool handed back no slot"; return 0; }
  pool=$(dirname "$(dirname "$wt")")
  git -C "$wt" checkout -q -b fm/task-x1
  lease_id=$(fm_treehouse_lease_id "$(fm_treehouse_allocation "$wt")")
  [ -n "$lease_id" ] || fail "(s) the scratch pool recorded no lease id for the slot it just leased"

  # A task-owned process left behind inside the slot, so the leaked-process reap is
  # exercised in the same run as the reservation.
  ( cd "$wt" && exec sleep 300 ) >/dev/null 2>&1 &
  sleep_pid=$!

  # The wrapper is the interleaving: an adversary tries to take the slot in the
  # instant between teardown deciding to return it and the return happening.
  cat > "$case_dir/fakebin/treehouse" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = return ] && [ "\${2:-}" != --help ]; then
  ( cd '$proj' && '$real_treehouse' get --lease --lease-holder adversary ) \\
    > '$case_dir/adversary.out' 2>&1
  printf 'rc=%s\n' "\$?" >> '$case_dir/adversary.out'
fi
exec '$real_treehouse' "\$@"
SH
  chmod +x "$case_dir/fakebin/treehouse"
  fm_fake_exit0 "$case_dir/fakebin" tmux gh gh-axi no-mistakes tasks-axi lsof

  fm_write_meta "$case_dir/state/task-x1.meta" \
    "window=firstmate:fm-task-x1" \
    "endpoint_task_id=task-x1" \
    "worktree=$wt" \
    "project=$proj" \
    "kind=ship" \
    "mode=local-only" \
    "wt_alloc=lease:$lease_id"

  set +e
  ( cd "$case_dir/firstmate-home" && \
    FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$case_dir/state" \
    FM_DATA_OVERRIDE="$case_dir/data" FM_CONFIG_OVERRIDE="$case_dir/config" \
    PATH="$case_dir/fakebin:$PATH" "$TEARDOWN" task-x1 ) \
    > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  set -e
  kill -9 "$sleep_pid" 2>/dev/null || true

  expect_code 0 "$rc" "(s) cleanup of a slot this task holds by lease must still succeed: $(cat "$case_dir/stderr")"
  assert_present "$case_dir/adversary.out" "(s) the adversary never ran, so nothing was contested"
  assert_grep "rc=" "$case_dir/adversary.out" \
    "(s) the adversary attempt recorded no result, so the interleaving proved nothing"
  assert_no_grep "rc=0" "$case_dir/adversary.out" \
    "(s) a contender acquired a slot while cleanup was running: $(cat "$case_dir/adversary.out")"
  if grep -q "$(basename "$wt")" "$case_dir/adversary.out" 2>/dev/null; then
    fail "(s) the contender was handed the very slot being cleaned up"
  fi
  kill -0 "$sleep_pid" 2>/dev/null \
    && fail "(s) the task's own leaked process survived a completed cleanup"
  ( cd "$proj" && "$real_treehouse" status 2>/dev/null ) > "$case_dir/after.txt"
  assert_no_grep "adversary" "$case_dir/after.txt" \
    "(s) the pool ended up holding a lease for the contender"
  assert_no_grep "task-x1" "$case_dir/after.txt" \
    "(s) the task's own lease was not released by a completed cleanup"
  # Leave nothing leased behind in the scratch pool.
  ( cd "$proj" && "$real_treehouse" return --force "$wt" >/dev/null 2>&1 ) || true
  rm -rf "$pool"
  pass "a real lease keeps a real contender out of the slot for the whole of cleanup"
}

test_unmanaged_path_is_out_of_scope
test_matching_allocation_is_owned
test_changed_allocation_is_foreign
test_reassigned_to_a_lease_is_foreign
test_another_tasks_branch_is_foreign
test_own_branch_proves_ownership_without_a_recorded_allocation
test_matching_allocation_with_a_sibling_branch_is_a_conflict
test_vacant_slot_is_never_proof_of_ownership
test_unallocated_slot_with_occupants_is_ambiguous
test_unreadable_pool_state_is_ambiguous
test_process_count_comes_from_the_slots_own_pool
test_lease_holder_separates_unmanaged_from_unreadable
test_leased_slot_lookup_finds_only_its_own_holder
test_foreign_slot_refuses_before_any_destruction
test_force_never_overrides_foreign_ownership
test_force_overrides_ambiguous_ownership
test_owned_slot_is_still_torn_down
test_leased_slot_is_returned_under_its_lease
test_missing_conditional_return_refuses_rather_than_returning_unguarded
test_unreadable_pool_refuses_the_return_even_under_force
test_ownership_is_decided_from_the_tasks_pool_not_the_homes
test_a_real_lease_keeps_a_contender_out_through_cleanup
