# Worktree-pool slot ownership verification

Maintainer-verification record for [`bin/fm-treehouse-lib.sh`](../../bin/fm-treehouse-lib.sh) and the cleanup boundary in [`bin/fm-teardown.sh`](../../bin/fm-teardown.sh).
Those two script headers own the contract; this file records the empirical facts the contract rests on, and the end-to-end evidence that the boundary holds.
[`tests/fm-teardown-slot-ownership.test.sh`](../../tests/fm-teardown-slot-ownership.test.sh) is the reusable regression for the same guarantees.

## The guarantee this file exists to hold

One task's cleanup never kills the processes, deletes the files or branch, or returns the pool slot of a different task that now occupies the worktree its record names, including when that task lives in an independent peer home that appears in no registry anywhere.
Genuine cleanup of a slot the task still holds keeps working, leaked-process reaping included.

Attributing the slot correctly is only half of it.
Reading who holds a slot says who held it at the instant of the read, and a free slot can be handed to a new worker while cleanup is still killing, deleting and returning.
So the slot is also *reserved* for the task's whole life by the pool's own durable lease, and every return of a leased slot carries a precondition the pool evaluates atomically with the return.

## Why the pool is the authority, 2026-09-06

macOS 24.6.0, treehouse v2.1.1, bash 3.2, ShellCheck 0.11.0.
All of it ran in a throwaway pool under a scratch directory, against a scratch repository with its own bare origin; no fleet pool, home, project or worker was involved.

Four pool behaviours are what make ownership decidable, and then holdable, without enumerating homes.

A plain `treehouse get` records the allocation it hands out, and clears it the moment the holder dies:

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
That file is read with node, which every home already requires, so ownership never depends on an optional tool and is never hand-parsed out of text.

`treehouse` also resolves *which* pool it is answering about from its own working directory, and a query run somewhere else silently describes a different pool.
In a scratch pool configured with a relative `root`, the same query run from inside the slot answered about a pool that does not contain it at all:

```
$ ( cd <project> && treehouse status --json ) | head -c 60
[{"name":"1","path":"<slot>","status":"leased","lease_id":...
$ ( cd <slot> && treehouse status --json )
[]
```

So occupancy is asked of the pool that governs the slot - the task's project - and a listing that does not name the slot is treated as no answer rather than as a process count of zero.

### The reservation, which is what makes ownership hold through cleanup

`treehouse get --lease --lease-holder <id>` reserves a slot durably: the pool records the lease and never hands that slot to a later `get`, even with nothing running inside it.
With every slot in a one-deep scratch pool leased, a contender was refused outright:

```
$ treehouse get --lease --lease-holder adversary
all 1 worktrees are in use or dirty (max_trees = 1). Run 'treehouse status' to see details, or increase max_trees in treehouse.toml
$ echo $?
1
```

`treehouse return` can be made conditional on that same lease, and the pool evaluates the precondition itself:

```
$ treehouse return --force --if-lease-id deadbeef <slot>
failed to return worktree: lease precondition failed: lease identity does not match worktree <slot>
$ echo $?
1
$ treehouse return --force --if-lease-holder nobody <slot>
failed to return worktree: lease precondition failed: lease holder does not match worktree <slot>
$ echo $?
1
$ treehouse return --force --if-lease-id b0ce9a7930b29a6fbe0c970297b79f21 <slot>
Worktree returned to pool.
```

Together those two are the whole reservation: a task holds its slot from spawn until its own guarded return, so there is no interval in which a contender can enter.
The one thing treehouse v2.1.1 cannot do is reserve a *named* slot after the fact - `get --lease` ignores a path argument and hands out the next free slot instead:

```
$ treehouse get --lease --lease-holder holderC <pool>/1/proj
Leased worktree at <pool>/3/proj
```

That is why the reservation has to start at spawn, and why a task spawned before slots were leased cannot be given one retroactively.

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

The runs below are the refusal texts the current code produces, captured from a disposable lab that builds a scratch project, a scratch pool beside it and a task record naming one of its slots, then invokes `bin/fm-teardown.sh` the way the firstmate does - from a home directory that is not the project, so the pool teardown would resolve by working directory is the wrong pool.
Slot paths are elided as `<slot>`.
Each refusal left the occupant's processes running, its files intact, and the slot still held; the runtime log recorded no `treehouse` call at all.

Foreign tenancy, proven by the pool having handed the slot to a different holder:

```
REFUSED: task-x1 no longer holds the worktree its record names, so cleanup would destroy another task's work.
Evidence: the pool has since handed <slot> to a different holder (owner:41679:1788728705661, not the owner:41277:1788728702457 this task was given).
Nothing was killed, deleted or returned. Let the task that holds <slot> finish and tear that task down, which returns the slot; --force does not override this, because it authorizes discarding this task's work, never another task's.
teardown exit: 1
```

The same refusal stands under `--force`, here for a slot re-leased to a secondmate home after the record was written:

```
$ fm-teardown.sh task-x1 --force
Evidence: the pool has since handed <slot> to a different holder (lease:ffefd35a, not the owner:42888:1788728714664 this task was given).
teardown exit: 1
```

The pool's own record outranks the branch, so a sibling's branch inside a slot the pool still says is ours is a conflict between two signals rather than proof of a foreign tenant.
That is refusable, and forceable, instead of permanently untearable:

```
REFUSED: task-x1 cannot prove it still holds <slot>, so cleanup is unsafe.
Evidence: the pool still records this task as the holder of <slot>, but the slot has another task's branch fm/sibling-task checked out, so its two signals disagree.
Inspect the slot with 'treehouse status' before deciding; --force proceeds once you accept what is in it.
teardown exit: 1
```

A slot allocated to nobody is unreserved, so an empty process list is evidence and not a verdict:

```
REFUSED: task-x1 cannot prove it still holds <slot>, so cleanup is unsafe.
Evidence: <slot> is allocated to nobody, so the pool may hand it to a new worker at any moment; nothing is running in it right now, but that is a snapshot and not a reservation.
Inspect the slot with 'treehouse status' before deciding; --force proceeds once you accept what is in it.
teardown exit: 1
```

`--force` is the escape for unprovable tenancy, and it names what it leaves behind at both destructive boundaries:

```
$ fm-teardown.sh task-x1 --force
REFUSED: task-x1 cannot prove it still holds <slot>, so cleanup is unsafe.
warning: --force tears the task down anyway, leaving behind: whatever currently occupies <slot>
REFUSED: task-x1 cannot prove it still holds <slot>, so returning the worktree is unsafe.
warning: --force tears the task down anyway, leaving behind: whatever currently occupies <slot>
Worktree returned to pool.
teardown exit: 0
```

`--force` does not reach past an authority nobody can read, because that is exactly the state in which the slot may already belong to somebody else.
With the pool state file truncated, both boundaries report the unreadable record, and the return itself then refuses and runs no `treehouse` command:

```
$ fm-teardown.sh task-x1 --force
REFUSED: the worktree pool's own lease record for worktree <slot> could not be read, so this teardown cannot tell whether task-x1 still holds it.
Nothing was removed or returned. Inspect the pool with 'treehouse status' and retry once its state file is readable.
teardown exit: 1
runtime log: ''
```

Genuine cleanup is untouched, and the slot goes back under the exact lease the task was handed at spawn:

```
Worktree returned to pool.
teardown task-x1 complete (window firstmate:fm-task-x1, worktree <slot>)
teardown exit: 0
runtime log: treehouse return --force --if-lease-id lease-abc <slot>
task record: cleaned up
```

### The contested-allocation case, against the real pool

The claim that matters is not that the slot is attributed correctly but that a contender cannot enter *while* cleanup runs.
[`tests/fm-teardown-slot-ownership.test.sh`](../../tests/fm-teardown-slot-ownership.test.sh) proves that against the real `treehouse` rather than a stub: a scratch pool one slot deep, that slot leased to the task, a task-owned process left inside it, and a wrapper that makes a real contender attempt `treehouse get --lease` in the instant between teardown deciding to return the slot and the return happening.
The contender is refused by the pool, the task's own leaked process is still reaped, and the slot comes back available with no contender lease on it:

```
🌳 Setting up worktree...
all 1 worktrees are in use or dirty (max_trees = 1). Run 'treehouse status' to see details, or increase max_trees in treehouse.toml
rc=1
```

That case skips itself, loudly, on a treehouse that cannot lease or cannot return under a lease precondition.

## Known limits

- A task spawned before its slot was leased holds that slot only for as long as its worker lives. Once the worker exits the allocation is empty, so a task with no `fm/` branch - a scout, whose worktree is declared scratch and carries no branch, or a ship worker that died before its first `git checkout -b` - can prove tenancy by neither signal and refuses as unprovable on every later teardown, needing `--force`. This is a standing gap for those tasks, not a transitional one: recording `wt_alloc=` does not close it, because the current record it is compared against is empty. It closes for a task whose slot is leased, because the lease outlives the worker. It cannot be closed retroactively: treehouse v2.1.1's `get --lease` ignores a path argument and hands out the next free slot, so an already-free slot cannot be reserved for the cleanup that is about to run.
- For the same reason, a task spawned before slots were leased has no precondition to put on its return. Its ownership is proven at the boundary but not held through it, so a slot freed by teardown's own reap can in principle be handed to a new worker before the return completes. That window does not exist for a leased task, and it disappears entirely as pre-lease tasks retire.
- A lease outlives the process that took it, which is what makes it a reservation. The cost is that a slot is only released by the task's own teardown or by an aborted spawn cleaning up after itself; a task record destroyed by hand leaves its slot leased until an operator returns it with `treehouse return`.
- Only the macOS/tmux path was exercised end to end. The boundary reads the pool and the worktree, not the runtime, so it is backend-independent by construction; Orca worktrees are not pool slots and resolve as out of scope.
- Everything above was measured in disposable scratch pools built for the purpose. Nothing here is a statement about what any live fleet pool, home or worker currently contains.
