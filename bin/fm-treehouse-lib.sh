#!/usr/bin/env bash
# Shared treehouse pool-slot ownership resolution.
#
# WHY: a task's recorded worktree= is a durable claim, not proof of tenancy. When a
# worker exits, an unleased slot is freed immediately (its allocation record is
# cleared) while the task's record still names that path. The pool may then hand the
# same slot to a DIFFERENT task - in this home, in a secondmate home, or in an
# independent peer home that appears in no registry anywhere. Destructive cleanup
# driven by the stale record then kills the new tenant's processes, deletes its
# branch and files, and returns a slot it does not hold.
#
# The pool itself is the only authority on who was handed a slot, so ownership is
# resolved from the pool's own allocation record plus the slot's own branch, never
# from a path or a pid alone and never from a registry of homes (a peer home is
# deliberately absent from every registry, so enumerating homes cannot see it).
#
# RESERVATION, not just attribution. Reading the record only says who holds the slot
# at the instant of the read; it cannot stop the pool from handing a free slot to a
# new worker while cleanup is midway through killing, deleting and returning. So a
# task's slot is held by the pool's own durable LEASE for the task's whole life:
# bin/fm-spawn.sh acquires it with `treehouse get --lease --lease-holder <task-id>`,
# and bin/fm-teardown.sh releases it with `treehouse return --if-lease-id`, whose
# precondition the pool evaluates atomically with the return. A leased slot is never
# handed out by a later `treehouse get` and never pruned, even with nothing running
# inside it, so there is no interval in which a contesting worker can enter
# (verified 2026-09-06, treehouse v2.1.1; docs/verification/teardown-slot-ownership.md).
#
# Two independent signals, either of which can prove foreign tenancy on its own:
#
#   A. ALLOCATION - the pool's record for this exact path, read from the pool state
#      file that treehouse maintains beside its slots. One of:
#        lease:<lease-id>              handed out by `treehouse get --lease`
#        owner:<pid>:<started-at-ms>   handed out by a plain `treehouse get`
#        (empty)                       currently allocated to nobody
#      bin/fm-spawn.sh records the allocation a task was handed as wt_alloc= in
#      state/<id>.meta, so a later reallocation is a plain string mismatch.
#
#   B. OCCUPANCY - the branch the slot currently has checked out. A ship task's
#      worktree is on its own fm/<task-id> branch, so fm/<other-id> is positive proof
#      that another firstmate task is living there. This is what covers tasks spawned
#      before wt_alloc= existed.
#
# Verdicts: owned (at least one signal proves it, neither contradicts), foreign
# (a signal proves another tenant), ambiguous (nothing proves it either way, or the
# two signals contradict each other), unmanaged (the path is not a treehouse pool
# slot at all - an Orca worktree, a plain git worktree, a test sandbox - where this
# boundary does not apply).
#
# Callers must treat foreign and ambiguous as refusals BEFORE process termination,
# file deletion, branch deletion, or slot return. bin/fm-teardown.sh owns what
# --force may and may not override.
#
# JSON is parsed with node, which every home already requires (docs/configuration.md
# "Toolchain"), so ownership never depends on an optional tool and is never hand-
# parsed out of text. A parser that cannot answer reads as unreadable, never as an
# empty or vacant slot.

FM_TREEHOUSE_RC_UNREADABLE=2

# fm_treehouse_json <mode> <key> <alt-key>   [document on stdin]
# The one structured reader for both treehouse documents: the pool state file
# ({"worktrees":[...]}) and `treehouse status --json` (a bare array).
# Modes keyed on the slot path, where <key>/<alt-key> are the two accepted forms of
# one path (see fm_treehouse_physical):
#   allocation    the allocation record described above, empty for a free slot
#   lease_holder  the label recorded as the lease holder, empty when not leased
#   processes     how many live processes the pool sees inside the slot
# Mode keyed on a lease holder, where <key> is the holder label:
#   leased_path   the path of the single slot that holder currently leases
# Exit codes: 0 with the value, 1 when the document simply has no such entry, and
# FM_TREEHOUSE_RC_UNREADABLE when it cannot be parsed or answers ambiguously. The
# last two mean opposite things - an authority with nothing to say versus an
# authority that could not answer - so they must never collapse into each other.
fm_treehouse_json() {  # <mode> <key> <alt-key>
  command -v node >/dev/null 2>&1 || return "$FM_TREEHOUSE_RC_UNREADABLE"
  node -e '
const fs = require("fs");
const mode = process.argv[1], key = process.argv[2], alt = process.argv[3];
let doc;
try { doc = JSON.parse(fs.readFileSync(0, "utf8")); } catch (e) { process.exit(2); }
const list = Array.isArray(doc) ? doc
  : (doc && Array.isArray(doc.worktrees) ? doc.worktrees : null);
if (!list) process.exit(2);
// The pool state file marks a lease with leased:true; the status document
// reports the same lease as status:"leased". Both are the pool describing one
// leased slot, so both count.
const leased = (w) => w.leased === true || w.status === "leased";
const match = mode === "leased_path"
  ? (w) => leased(w) && String(w.lease_holder || "") === key
  : (w) => w.path === key || w.path === alt;
const hits = list.filter((w) => w && typeof w === "object" && match(w));
if (hits.length === 0) process.exit(1);
if (hits.length > 1) process.exit(2);
const w = hits[0];
let out;
if (mode === "allocation") {
  if (leased(w) && typeof w.lease_id === "string" && w.lease_id !== "") {
    out = "lease:" + w.lease_id;
  } else if (Number(w.owner_pid) > 0) {
    out = "owner:" + Number(w.owner_pid) + ":" + Number(w.owner_started_at || 0);
  } else {
    out = "";
  }
} else if (mode === "lease_holder") {
  out = leased(w) ? String(w.lease_holder || "") : "";
} else if (mode === "processes") {
  if (!Array.isArray(w.processes)) process.exit(2);
  out = String(w.processes.length);
} else if (mode === "leased_path") {
  if (typeof w.path !== "string" || w.path === "") process.exit(2);
  out = w.path;
} else {
  process.exit(2);
}
process.stdout.write(out + "\n");
' "$1" "$2" "${3:-}"
}

# fm_treehouse_physical <worktree-path>
# Sets FM_TREEHOUSE_PATH_RAW and FM_TREEHOUSE_PATH_PHYSICAL. A pool records slots by
# the path treehouse itself resolved, which may be either form once any prefix of it
# is a symlink (/var -> /private/var on macOS), so every lookup below accepts both.
fm_treehouse_physical() {  # <worktree-path>
  FM_TREEHOUSE_PATH_RAW=$1
  FM_TREEHOUSE_PATH_PHYSICAL=$(cd "$1" 2>/dev/null && pwd -P) || FM_TREEHOUSE_PATH_PHYSICAL=$1
}

# fm_treehouse_state_lists_path <state-file>
# Call after fm_treehouse_physical has resolved the path being looked up.
fm_treehouse_state_lists_path() {  # <state-file>
  local state=$1 rc=0
  [ -r "$state" ] || return "$FM_TREEHOUSE_RC_UNREADABLE"
  fm_treehouse_json allocation "$FM_TREEHOUSE_PATH_RAW" "$FM_TREEHOUSE_PATH_PHYSICAL" \
    < "$state" >/dev/null 2>&1 || rc=$?
  return "$rc"
}

# fm_treehouse_pool_state_file <worktree-path>
# Prints the pool state file that governs <worktree-path>, or fails when the path is
# not a slot of any pool. treehouse lays a pool out as <pool-dir>/<slot>/<repo-name>,
# so the governing state file is two levels up; it counts only when it actually
# lists this exact path, which keeps an unrelated directory two levels under some
# other pool from resolving here.
# Exit codes: 0 with the state file path when a pool records this exact slot,
# FM_TREEHOUSE_RC_UNREADABLE when a pool state file is there but cannot be read, and 1
# when no pool records the path at all. The two failures mean opposite things - one is
# an authority that could not answer, the other is an authority that has nothing to
# say - so they must never collapse into each other.
# Callers read this through a command substitution, so they must call
# fm_treehouse_physical themselves; the copy this makes stays in its own subshell.
fm_treehouse_pool_state_file() {  # <worktree-path>
  local wt=$1 pool state rc unreadable=0
  [ -n "$wt" ] || return 1
  fm_treehouse_physical "$wt"
  for pool in "$(dirname "$(dirname "$FM_TREEHOUSE_PATH_PHYSICAL")")" \
              "$(dirname "$(dirname "$FM_TREEHOUSE_PATH_RAW")")"; do
    state="$pool/treehouse-state.json"
    [ -f "$state" ] || continue
    rc=0
    fm_treehouse_state_lists_path "$state" || rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$state"
      return 0
    fi
    [ "$rc" -ne "$FM_TREEHOUSE_RC_UNREADABLE" ] || unreadable=1
  done
  [ "$unreadable" -eq 0 ] || return "$FM_TREEHOUSE_RC_UNREADABLE"
  return 1
}

# fm_treehouse_allocation <worktree-path>
# Prints the pool's CURRENT allocation record for the slot - "lease:<id>",
# "owner:<pid>:<started>", or empty when the slot is allocated to nobody. Returns 1
# when the path is not a pool slot, and FM_TREEHOUSE_RC_UNREADABLE when the pool's own
# state cannot be read or parsed: an unreadable authority is never "nobody is here".
fm_treehouse_allocation() {  # <worktree-path>
  local wt=$1 state record rc=0
  fm_treehouse_physical "$wt"
  state=$(fm_treehouse_pool_state_file "$wt") || { rc=$?; return "$rc"; }
  record=$(fm_treehouse_json allocation "$FM_TREEHOUSE_PATH_RAW" "$FM_TREEHOUSE_PATH_PHYSICAL" \
    < "$state" 2>/dev/null) || return "$FM_TREEHOUSE_RC_UNREADABLE"
  printf '%s\n' "$record"
}

# fm_treehouse_lease_id <allocation-record>
# Prints the lease identity inside a lease allocation record, empty for any other
# record. That identity is what `treehouse return --if-lease-id` checks atomically.
fm_treehouse_lease_id() {  # <allocation-record>
  case "$1" in
    lease:?*) printf '%s\n' "${1#lease:}" ;;
    *) printf '%s\n' "" ;;
  esac
}

# fm_treehouse_lease_holder <worktree-path>
# Prints the label the pool records as the current lease holder of the slot, or
# empty when the slot carries no lease. Returns 1 when the path is not a pool slot at
# all and FM_TREEHOUSE_RC_UNREADABLE when the pool cannot be read - the same two
# distinct failures as fm_treehouse_allocation, because a caller that cannot read the
# authority must refuse rather than proceed unguarded.
fm_treehouse_lease_holder() {  # <worktree-path>
  local wt=$1 state holder rc=0
  fm_treehouse_physical "$wt"
  state=$(fm_treehouse_pool_state_file "$wt") || { rc=$?; return "$rc"; }
  holder=$(fm_treehouse_json lease_holder "$FM_TREEHOUSE_PATH_RAW" "$FM_TREEHOUSE_PATH_PHYSICAL" \
    < "$state" 2>/dev/null) || return "$FM_TREEHOUSE_RC_UNREADABLE"
  printf '%s\n' "$holder"
}

# fm_treehouse_leased_slot_path <pool-context-dir> <holder>
# Prints the slot that <holder> currently leases in the pool <pool-context-dir>
# resolves to, or fails when the pool cannot answer or names no such slot. Used to
# release a lease whose path was never recorded, e.g. a spawn that leased a slot and
# then failed before it could write the task record.
fm_treehouse_leased_slot_path() {  # <pool-context-dir> <holder>
  # Neither local is named "status" or "path": both are special variables in zsh,
  # where the first is read-only and the second is the array tied to PATH.
  local ctx=$1 holder=$2 listing slot
  command -v treehouse >/dev/null 2>&1 || return 1
  [ -n "$holder" ] || return 1
  [ -n "$ctx" ] && [ -d "$ctx" ] || return 1
  listing=$( cd "$ctx" 2>/dev/null && treehouse status --json 2>/dev/null ) || return 1
  [ -n "$listing" ] || return 1
  slot=$(printf '%s\n' "$listing" | fm_treehouse_json leased_path "$holder" 2>/dev/null) || return 1
  [ -n "$slot" ] || return 1
  printf '%s\n' "$slot"
}

# fm_treehouse_slot_process_count <worktree-path> <pool-context-dir>
# Prints how many live processes the pool currently sees inside the slot.
# treehouse resolves which pool it is talking about from its own working directory,
# so this must run from a directory that resolves to the pool governing the slot -
# the task's project, never whatever directory the caller happened to be invoked
# from (a firstmate home's pool is a different pool). A result that does not list
# this exact slot is the wrong pool or no answer at all, so it fails rather than
# reporting a process count of zero: an unprovable slot must never read as an empty
# one. This only ever sharpens a refusal's evidence; it can never grant ownership,
# because "nothing was running at the instant of the read" is a snapshot and not a
# reservation.
fm_treehouse_slot_process_count() {  # <worktree-path> <pool-context-dir>
  local wt=$1 ctx=$2 listing count
  command -v treehouse >/dev/null 2>&1 || return 1
  [ -n "$ctx" ] && [ -d "$ctx" ] || return 1
  fm_treehouse_physical "$wt"
  listing=$( cd "$ctx" 2>/dev/null && treehouse status --json 2>/dev/null ) || return 1
  [ -n "$listing" ] || return 1
  count=$(printf '%s\n' "$listing" \
    | fm_treehouse_json processes "$FM_TREEHOUSE_PATH_RAW" "$FM_TREEHOUSE_PATH_PHYSICAL" 2>/dev/null) \
    || return 1
  case "$count" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$count"
}

# fm_treehouse_supports_lease
# True when the installed treehouse can durably reserve a slot, which is how a task
# holds its worktree for its whole life rather than only while a process is alive.
fm_treehouse_supports_lease() {
  command -v treehouse >/dev/null 2>&1 || return 1
  treehouse get --help 2>&1 | grep -Eq '(^|[^[:alnum:]_-])--lease([^[:alnum:]_-]|$)'
}

# fm_treehouse_supports_conditional_return
# True when the installed treehouse can make the RETURN itself conditional on the
# lease still being ours. Both flags are probed because both are used: --if-lease-id
# for a task worktree (the exact lease it was handed) and --if-lease-holder for a
# secondmate home (leased under the home's own id). Without them there is no way to
# make the ownership check and the destructive return one operation, so callers must
# refuse rather than fall back to an unguarded return.
fm_treehouse_supports_conditional_return() {
  local help
  command -v treehouse >/dev/null 2>&1 || return 1
  help=$(treehouse return --help 2>&1) || return 1
  printf '%s\n' "$help" | grep -Eq '(^|[^[:alnum:]_-])--if-lease-id([^[:alnum:]_-]|$)' || return 1
  printf '%s\n' "$help" | grep -Eq '(^|[^[:alnum:]_-])--if-lease-holder([^[:alnum:]_-]|$)'
}

# fm_treehouse_branch_owner <worktree-path>
# Prints the firstmate task id that the slot's checked-out branch belongs to, or
# empty when the branch names no task (a detached HEAD, the default branch, or any
# branch outside the fm/ namespace). Fails when the branch cannot be read at all.
fm_treehouse_branch_owner() {  # <worktree-path>
  local wt=$1 branch
  [ -d "$wt" ] || return 1
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || return 1
  # symbolic-ref, not rev-parse --abbrev-ref: it reports the checked-out branch even
  # when that branch has no commit yet, and fails cleanly on a detached HEAD, which
  # names no task and so proves nothing either way.
  branch=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null) || branch=
  case "$branch" in
    fm/?*) printf '%s\n' "${branch#fm/}" ;;
    *) printf '%s\n' "" ;;
  esac
}

# fm_treehouse_classify_slot <worktree-path> <task-id> <recorded-allocation> <pool-context-dir>
# Prints one line: "<verdict><TAB><operator-readable reason>", where verdict is
# unmanaged | owned | foreign | ambiguous. The reason travels in the same line
# because callers read this through a command substitution, where a second variable
# set inside the function would never reach them.
# <recorded-allocation> is the task's own wt_alloc= from state/<id>.meta, empty for a
# task spawned before that was recorded. <pool-context-dir> is the task's project,
# the directory from which treehouse resolves the pool that governs the slot.
#
# The allocation is the pool's own record and outranks the branch, so a slot whose
# current allocation is exactly the one this task was handed is never called foreign
# on the strength of a branch: a sibling task's branch checked out inside a slot the
# pool still says is ours is a CONFLICT between the two signals, which is ambiguous
# (refused, but overridable by an operator who has looked) rather than proof of a
# foreign tenant (refused absolutely).
fm_treehouse_classify_slot() {  # <worktree-path> <task-id> <recorded-allocation> <pool-context-dir>
  local wt=$1 id=$2 recorded=$3 ctx=${4:-} current branch_owner procs alloc_rc
  fm_treehouse_physical "$wt"

  alloc_rc=0
  current=$(fm_treehouse_allocation "$wt") || alloc_rc=$?
  if [ "$alloc_rc" -ne 0 ]; then
    if [ "$alloc_rc" -eq "$FM_TREEHOUSE_RC_UNREADABLE" ]; then
      printf 'ambiguous\t%s\n' "the worktree pool's own record for $wt could not be read"
    else
      printf 'unmanaged\t%s\n' "$wt is not a worktree-pool slot"
    fi
    return 0
  fi

  branch_owner=$(fm_treehouse_branch_owner "$wt" 2>/dev/null) || branch_owner=

  # The pool having handed the slot to a different holder is proof of foreign
  # tenancy on its own, and nothing about the slot's contents can argue with it.
  if [ -n "$recorded" ] && [ -n "$current" ] && [ "$current" != "$recorded" ]; then
    printf 'foreign\t%s\n' "the pool has since handed $wt to a different holder ($current, not the $recorded this task was given)"
    return 0
  fi

  # The pool positively proving tenancy outranks the branch, which is a weaker
  # signal derived from the slot's contents rather than from the pool's own record.
  if [ -n "$recorded" ] && [ -n "$current" ] && [ "$current" = "$recorded" ]; then
    if [ -n "$branch_owner" ] && [ "$branch_owner" != "$id" ]; then
      printf 'ambiguous\t%s\n' "the pool still records this task as the holder of $wt, but the slot has another task's branch fm/$branch_owner checked out, so its two signals disagree"
      return 0
    fi
    printf 'owned\t%s\n' "the pool still records this task as the holder of $wt"
    return 0
  fi

  # No allocation proves tenancy either way; the branch decides on its own.
  if [ -n "$branch_owner" ] && [ "$branch_owner" != "$id" ]; then
    printf 'foreign\t%s\n' "$wt currently holds another task's branch fm/$branch_owner"
    return 0
  fi
  if [ -n "$branch_owner" ] && [ "$branch_owner" = "$id" ]; then
    printf 'owned\t%s\n' "$wt still holds this task's own branch fm/$id"
    return 0
  fi

  # Nothing proves tenancy. A slot allocated to nobody is not a safe slot: the pool
  # may hand it to a new worker at any moment, including while this cleanup runs, so
  # an empty process list is evidence for the operator and never a verdict.
  if [ -z "$current" ]; then
    if procs=$(fm_treehouse_slot_process_count "$wt" "$ctx"); then
      if [ "$procs" = 0 ]; then
        printf 'ambiguous\t%s\n' "$wt is allocated to nobody, so the pool may hand it to a new worker at any moment; nothing is running in it right now, but that is a snapshot and not a reservation"
      else
        printf 'ambiguous\t%s\n' "$wt is allocated to nobody but still has $procs process(es) running in it that this task cannot claim"
      fi
    else
      printf 'ambiguous\t%s\n' "$wt is allocated to nobody and the pool could not say what is running in it"
    fi
    return 0
  fi

  printf 'ambiguous\t%s\n' "$wt is allocated to a holder this task cannot match ($current) and carries no branch that identifies its occupant"
}
