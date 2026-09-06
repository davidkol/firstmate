#!/usr/bin/env bash
# Shared treehouse pool-slot ownership resolution.
#
# WHY: a task's recorded worktree= is a durable claim, not proof of tenancy. When a
# worker exits, treehouse frees the slot immediately (its allocation record is
# cleared) while the task's record still names that path. The pool may then hand the
# same slot to a DIFFERENT task - in this home, in a secondmate home, or in an
# independent peer home that appears in no registry anywhere. Destructive cleanup
# driven by the stale record then kills the new tenant's processes, deletes its
# branch and files, and returns a slot it does not hold.
#
# The pool itself is the only authority on who was handed a slot, so ownership is
# resolved from the pool's own allocation record plus the slot's own occupancy, never
# from a path or a pid alone and never from a registry of homes (a peer home is
# deliberately absent from every registry, so enumerating homes cannot see it).
#
# Two independent signals, either of which can prove foreign tenancy on its own:
#
#   A. ALLOCATION - the pool's record for this exact path, read from the pool state
#      file that treehouse maintains beside its slots. One of:
#        owner:<pid>:<started-at-ms>   handed out by `treehouse get`
#        lease:<lease-id>              handed out by `treehouse get --lease`
#        (empty)                       currently allocated to nobody
#      bin/fm-spawn.sh records the allocation a task was handed as wt_alloc= in
#      state/<id>.meta, so a later reallocation is a plain string mismatch.
#      The pool never reassigns a slot without changing this record, and never hands
#      out a slot that still has live processes in it (verified 2026-09-06, treehouse
#      v2.1.1; see docs/verification/teardown-slot-ownership.md).
#
#   B. OCCUPANCY - the branch the slot currently has checked out. A ship task's
#      worktree is on its own fm/<task-id> branch, so fm/<other-id> is positive proof
#      that another firstmate task is living there. This is what covers tasks spawned
#      before wt_alloc= existed.
#
# Verdicts: owned (at least one signal proves it, neither contradicts), foreign
# (a signal proves another tenant), ambiguous (nothing proves it either way),
# unmanaged (the path is not a treehouse pool slot at all - an Orca worktree, a
# plain git worktree, a test sandbox - where this boundary does not apply).
#
# Callers must treat foreign and ambiguous as refusals BEFORE process termination,
# file deletion, branch deletion, or slot return. bin/fm-teardown.sh owns what
# --force may and may not override.

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
FM_TREEHOUSE_RC_UNREADABLE=2
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
  local state=$1 found
  command -v jq >/dev/null 2>&1 || return "$FM_TREEHOUSE_RC_UNREADABLE"
  found=$(jq -r --arg a "$FM_TREEHOUSE_PATH_RAW" --arg b "$FM_TREEHOUSE_PATH_PHYSICAL" \
    '[.worktrees[]? | select(.path == $a or .path == $b)] | length' "$state" 2>/dev/null) \
    || return "$FM_TREEHOUSE_RC_UNREADABLE"
  case "$found" in
    '') return "$FM_TREEHOUSE_RC_UNREADABLE" ;;
    0|null) return 1 ;;
  esac
  return 0
}

# fm_treehouse_allocation <worktree-path>
# Prints the pool's CURRENT allocation record for the slot - "owner:<pid>:<started>",
# "lease:<id>", or empty when the slot is allocated to nobody. Fails when the path is
# not a pool slot, or when the pool's own state cannot be read or parsed: an
# unreadable authority is never treated as "nobody is here".
fm_treehouse_allocation() {  # <worktree-path>
  local wt=$1 state record rc
  fm_treehouse_physical "$wt"
  state=$(fm_treehouse_pool_state_file "$wt") || { rc=$?; return "$rc"; }
  record=$(jq -r --arg a "$FM_TREEHOUSE_PATH_RAW" --arg b "$FM_TREEHOUSE_PATH_PHYSICAL" '
    .worktrees[]? | select(.path == $a or .path == $b)
    | if (.leased == true and (.lease_id // "") != "")
      then "lease:" + .lease_id
      elif ((.owner_pid // 0) > 0)
      then "owner:" + (.owner_pid|tostring) + ":" + ((.owner_started_at // 0)|tostring)
      else "" end
  ' "$state" 2>/dev/null) || return "$FM_TREEHOUSE_RC_UNREADABLE"
  printf '%s\n' "$record"
}

# fm_treehouse_lease_holder <worktree-path>
# Prints the label the pool records as the current lease holder of the slot, or
# empty when the slot carries no lease. Fails when the pool cannot be read.
fm_treehouse_lease_holder() {  # <worktree-path>
  local wt=$1 state holder
  fm_treehouse_physical "$wt"
  state=$(fm_treehouse_pool_state_file "$wt") || return 1
  holder=$(jq -r --arg a "$FM_TREEHOUSE_PATH_RAW" --arg b "$FM_TREEHOUSE_PATH_PHYSICAL" '
    .worktrees[]? | select(.path == $a or .path == $b)
    | if (.leased == true) then (.lease_holder // "") else "" end
  ' "$state" 2>/dev/null) || return 1
  printf '%s\n' "$holder"
}

# fm_treehouse_slot_process_count <worktree-path>
# Prints how many live processes the pool currently sees inside the slot. Fails when
# the pool cannot answer, so a caller can refuse rather than assume the slot is empty.
fm_treehouse_slot_process_count() {  # <worktree-path>
  local wt=$1 count
  command -v treehouse >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  fm_treehouse_physical "$wt"
  count=$(treehouse status --json 2>/dev/null \
    | jq -r --arg a "$FM_TREEHOUSE_PATH_RAW" --arg b "$FM_TREEHOUSE_PATH_PHYSICAL" \
      '[.[]? | select(.path == $a or .path == $b) | .processes[]?] | length' 2>/dev/null) || return 1
  case "$count" in ''|null|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$count"
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

# fm_treehouse_classify_slot <worktree-path> <task-id> <recorded-allocation>
# Prints one line: "<verdict><TAB><operator-readable reason>", where verdict is
# unmanaged | owned | foreign | ambiguous. The reason travels in the same line
# because callers read this through a command substitution, where a second variable
# set inside the function would never reach them.
# <recorded-allocation> is the task's own wt_alloc= from state/<id>.meta, empty for a
# task spawned before that was recorded.
fm_treehouse_classify_slot() {  # <worktree-path> <task-id> <recorded-allocation>
  local wt=$1 id=$2 recorded=$3 current branch_owner procs alloc_rc
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

  # Either signal alone is enough to prove the slot belongs to somebody else.
  if [ -n "$recorded" ] && [ -n "$current" ] && [ "$current" != "$recorded" ]; then
    printf 'foreign\t%s\n' "the pool has since handed $wt to a different holder ($current, not the $recorded this task was given)"
    return 0
  fi
  if [ -n "$branch_owner" ] && [ "$branch_owner" != "$id" ]; then
    printf 'foreign\t%s\n' "$wt currently holds another task's branch fm/$branch_owner"
    return 0
  fi

  # Neither signal contradicts; now require one of them to positively prove tenancy.
  if [ -n "$recorded" ] && [ -n "$current" ] && [ "$current" = "$recorded" ]; then
    printf 'owned\t%s\n' "the pool still records this task as the holder of $wt"
    return 0
  fi
  if [ -n "$branch_owner" ] && [ "$branch_owner" = "$id" ]; then
    printf 'owned\t%s\n' "$wt still holds this task's own branch fm/$id"
    return 0
  fi

  # Nothing proves tenancy. A slot the pool has allocated to nobody, with nothing
  # running in it, holds no work to protect, so cleanup of it is harmless.
  if [ -z "$current" ]; then
    if procs=$(fm_treehouse_slot_process_count "$wt") && [ "$procs" = 0 ]; then
      printf 'owned\t%s\n' "$wt is allocated to nobody and has nothing running in it"
      return 0
    fi
    printf 'ambiguous\t%s\n' "$wt is allocated to nobody but still has processes running in it that this task cannot claim"
    return 0
  fi

  printf 'ambiguous\t%s\n' "$wt is allocated to a holder this task cannot match ($current) and carries no branch that identifies its occupant"
}
