# Worktree-pool slot ownership verification

Maintainer-verification record for [`bin/fm-treehouse-lib.sh`](../../bin/fm-treehouse-lib.sh) and the cleanup boundary in [`bin/fm-teardown.sh`](../../bin/fm-teardown.sh).
Those two script headers own the contract; this file records the empirical facts the contract rests on, and the end-to-end evidence that the boundary holds.
[`tests/fm-teardown-slot-ownership.test.sh`](../../tests/fm-teardown-slot-ownership.test.sh) is the reusable regression for the same guarantees.

## The guarantee this file exists to hold

One task's cleanup never kills the processes, deletes the files or branch, or returns the pool slot of a different task that now occupies the worktree its record names, including when that task lives in an independent peer home that appears in no registry anywhere.
Genuine cleanup of a slot the task still holds keeps working, leaked-process reaping included.

## Why the pool is the authority, 2026-09-06

macOS 24.6.0, treehouse v2.1.1, bash 3.2, ShellCheck 0.11.0.
All of it ran in a throwaway pool under a scratch directory, against a scratch repository with its own bare origin; no fleet pool, home, project or worker was involved.

Three pool behaviours are what make ownership decidable without enumerating homes.

`treehouse get` records the allocation it hands out, and clears it the moment the holder dies:

```
$ cat <pool>/treehouse-state.json          # while the holder is alive
{"worktrees":[{"name":"1","path":"<slot>","created_at":"...",
  "owner_pid":77661,"owner_started_at":1788727839262}]}
$ kill -9 77661
$ cat <pool>/treehouse-state.json          # holder dead
{"worktrees":[{"name":"1","path":"<slot>","created_at":"..."}]}
```

A slot with live processes in it is never handed out again, so a task's own leaked processes cannot be sitting in a slot the pool has meanwhile given away:

```
$ treehouse status                          # owner dead, one disowned process left
1     in-use       <slot>
                   sleep (80783)
$ treehouse get --lease --lease-holder homeB
Leased worktree at <pool>/2/scratchproj     # slot 2, not slot 1
```

Those two together are why a cleared allocation record plus this task's own branch is sound proof of tenancy, and why a *different* allocation record is proof of foreign tenancy.

`treehouse status --json` does not expose the allocation, only status and the process list, so the allocation is read from the pool state file that treehouse keeps beside its slots.
A state file that is present but unparseable is therefore treated as an authority that could not answer, never as an empty slot.

## The defect, reproduced before the fix

Two independent peer homes over one scratch project, home A's worker exiting so the pool re-hands its slot to home B, then home A running the real cleanup entry point on its stale record.
Both runs below are pre-fix.

Home B's worker holding uncommitted work:

```
$ fm-teardown.sh hometaskA
teardown: reaping leaked worktree process(es) for hometaskA: 96445
Worktree returned to pool.
teardown hometaskA complete
home B pid 96445: KILLED
home B uncommitted file: DESTROYED
```

Home B's worker with a clean worktree, where every pre-existing guard passes:

```
$ fm-teardown.sh hometaskA
teardown: reaping leaked worktree process(es) for hometaskA: 97532
Worktree returned to pool.
home B pid 97532: KILLED
```

## The boundary, after the fix

Same lab, same entry point, ten cases.
Each refusal below left the occupant's processes running, its files intact, and the slot still held.

Foreign tenancy proven by the occupant's branch, with the pre-fix run's dirty tenant:

```
$ fm-teardown.sh hometaskA
REFUSED: hometaskA no longer holds the worktree its record names, so cleanup would
destroy another task's work.
Evidence: <slot> currently holds another task's branch fm/homeb-live-task.
Nothing was killed, deleted or returned. Correct the stale worktree record for
hometaskA (or let the current holder finish); --force does not override this, because
it authorizes discarding this task's work, never another task's.
teardown exit: 1
home B pid 89535: ALIVE
home B uncommitted file: PRESENT
```

Foreign tenancy proven by the allocation alone, with the occupant on a detached HEAD so no branch could say anything:

```
Evidence: the pool has since handed <slot> to a different holder
(owner:41679:1788728705661, not the owner:41277:1788728702457 this task was given).
teardown exit: 1
home B pid 41705: ALIVE
```

A contested slot re-leased to a secondmate home after the record was written:

```
Evidence: the pool has since handed <slot> to a different holder
(lease:ffefd35a40cff5d8e295a2b0640acb5c, not the owner:42888:1788728714664 this task
was given).
teardown exit: 1
slot now: leased held by homeB-secondmate
```

`--force` does not override foreign tenancy:

```
$ fm-teardown.sh hometaskA --force
REFUSED: hometaskA no longer holds the worktree its record names, ...
teardown exit: 1
home B pid 97262: ALIVE
```

Unprovable tenancy refuses the same way, and `--force` is the escape there, naming what it leaves behind at both destructive boundaries:

```
$ fm-teardown.sh hometaskA --force
REFUSED: hometaskA cannot prove it still holds <slot>, so cleanup is unsafe.
Evidence: <slot> is allocated to a holder this task cannot match
(owner:66870:1788728862652) and carries no branch that identifies its occupant.
warning: --force tears the task down anyway, leaving behind: whatever currently occupies <slot>
REFUSED: hometaskA cannot prove it still holds <slot>, so returning the worktree is unsafe.
warning: --force tears the task down anyway, leaving behind: whatever currently occupies <slot>
teardown exit: 0
```

Genuine cleanup is untouched.
A slot the task still holds is reaped and returned, and its record cleared:

```
$ fm-teardown.sh hometaskA
teardown: reaping leaked worktree process(es) for hometaskA: 44064 44760
Worktree returned to pool.
teardown exit: 0
slot now: available
task record: cleaned up
```

So is the leaked-process reap after the holder died, for a task that recorded its allocation and for one that predates that record and is proven only by its own branch:

```
allocation now: 'owner:63946:1788728838795'; own orphan 64065 still inside; branch fm/hometaskA
teardown: reaping leaked worktree process(es) for hometaskA: 63982 64065
teardown exit: 0
own orphan 64065: reaped
```

A secondmate home is returned under the pool's own lease guard, so the check and the
destructive act are one operation.
The pool refuses a mismatched holder itself and keeps the lease:

```
$ treehouse return --force --if-lease-holder wrong-home <slot>
failed to return worktree: lease precondition failed: lease holder does not match worktree <slot>
$ echo $?
1
$ treehouse status
1     leased       <slot>  (held by homeB-secondmate)
$ treehouse return --force --if-lease-holder homeB-secondmate <slot>
Worktree returned to pool.
```

## Known limits

- A task spawned before `wt_alloc=` was recorded and occupying its slot on a detached HEAD - a scout, whose worktree is declared scratch and carries no branch - can prove tenancy by neither signal, so its cleanup refuses as unprovable and needs `--force`. Every task spawned since records its allocation, so this is a one-time transitional gap rather than a standing one.
- The residual window is one slot that is allocated to nobody, has nothing running in it, and is handed to another task between the check and the destructive step. Nothing is running there to lose, and both destructive boundaries re-check.
- Only the macOS/tmux path was exercised end to end. The boundary reads the pool and the worktree, not the runtime, so it is backend-independent by construction; Orca worktrees are not pool slots and resolve as out of scope.
