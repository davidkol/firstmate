---
name: project-management
description: >-
  Agent-only procedure for Firstmate project management.
  Use before adding, creating, removing, initializing, or reconciling a project.
  Owns project add, create, clone, remove, initialization, state-surface reconciliation, registry, delivery-mode, autonomy, and outward-consent decisions.
user-invocable: false
metadata:
  internal: true
---

# project-management

Use this procedure before adding, creating, removing, or initializing a project.
This skill is the single owner of Firstmate's project-management procedure.
It does not replace `secondmate-provisioning`, which owns project clones inside persistent secondmate homes.

## Preconditions and registry

Projects live flat under `projects/`, and `data/projects.md` is the private fleet registry.
Use the registry format and parser contract owned by the header of `bin/fm-project-mode.sh`.
Keep each registry description useful for identifying the project, but keep delivery posture, captain-private state, and detailed project knowledge in their existing designated homes.
Do not turn the registry into project documentation.

Resolve the project name, destination, delivery mode, and autonomy posture before changing local or remote state.
Keep a newly added clone and its registry entry consistent, and roll back only artifacts created by the incomplete operation when a later initialization step fails and that rollback is safe.
Do not overwrite or repurpose an existing path.

## Delivery posture

Choose the delivery mode when adding or creating the project:

- `no-mistakes` runs the full validation pipeline before a PR and is the default when the captain does not specify a mode.
- `direct-PR` pushes and opens a PR without the no-mistakes pipeline.
- `local-only` has no required remote or PR and lands only through the approved local fast-forward path.

The optional `+yolo` posture changes routine approval authority but does not change the delivery mode.
Default it off, and enable it only on the captain's explicit instruction.
`AGENTS.md` section 7 owns the complete authority boundary and exceptions when it is on.

## Add or clone an existing project

Confirm the source URL, local project name, delivery mode, and autonomy posture.
Clone into `projects/<name>` and add the registry entry only after the destination is known to be unused.
A `no-mistakes` project must have an `origin` remote and must complete the initialization procedure below.
A `direct-PR` project needs an `origin` remote but skips no-mistakes initialization.
A `local-only` project may have no remote and skips no-mistakes initialization.

## Create a project

Creating a GitHub repository is outward-facing.
Before making that remote change, propose the repository name, owner or organization, visibility, and delivery mode, defaulting visibility to private and delivery mode to `no-mistakes`, then obtain the captain's explicit consent for those values.
Use `gh-axi` for the approved GitHub operation and consult its current help rather than relying on remembered flags.
After remote creation succeeds, clone it locally, add the registry entry, and initialize it according to its delivery mode.

For a purely `local-only` project, create a local Git repository under its unused `projects/<name>` path, add the registry entry, and make no GitHub call.
The captain's request to create that local project authorizes this local initialization, but it does not authorize an unmentioned remote repository.

## Initialize

Run no-mistakes initialization only for `no-mistakes` projects:

```sh
cd projects/<name> && no-mistakes init && no-mistakes doctor
```

Initialization configures the local gate and does not vendor a no-mistakes skill into the project.
Do not create a commit merely because initialization ran.
If doctor reports an environment, authentication, or daemon problem, resolve that blocker before dispatching work and never restart the shared daemon from a project operation.

## Reconcile the project's state surfaces

Do this once per project, before dispatching its first task, on newly added projects and on existing ones alike.
It is a reconciliation, not an install: every project that has been worked on already has entry points, handoff documents, question registers, decision records, notes stores and check commands, and in most of them the surface the repo itself routes to is stale.
Seeding a fresh set over the top adds one more surface to the pile, which is the problem this exists to reduce.
`bin/fm-project-reconcile.sh` owns the mechanics; its header and `--help` own the exact flags, report-line prefixes and exit codes.

Run the read-only report against the project clone first.
Reading a project is always allowed, so firstmate runs this itself.
Then route what it reports:

- A `COLLISION:` line means two or more surfaces cover the same job.
  Tell the captain in plain language and file the consolidation as its own backlog item.
  Do not retire a surface on your own, and never delete one.
- A `DISAGREEMENT:` line means two surfaces disagree about what is true, and the captain owns which one survives.
  Load `decision-hold-lifecycle` and register each one as a durable hold with a stated default.
  Never pick a side, and never pre-empt a hold that is already open on the board.
- A `GAP:` line names something absent or unlanded that no script can resolve for the project.
  A missing check command is the one that matters most: it degrades the done checklist to a named gap and never to a silent pass.
  Uncommitted work is reported here too, with the paths named, because state that lives only in a working tree and in no document is how a session rebuilds what the project already has.
  A gap informs the brief; it is not a captain hold and never blocks the seed.
- `SEED:` lines are the plan for what is genuinely missing.

Seeding is a project write, so a crewmate carries it through the project's selected delivery path, the same way it creates a project `AGENTS.md`.
Brief that crewmate to run the script with `--seed` inside its own worktree.
The script refuses `--seed` against a clone under a firstmate home's `projects/` directory, so the boundary holds even if a brief is wrong.

Two files are deliberately never seeded, by captain ruling of 2026-07-28.
There is no repo-side `QUESTIONS.md`, because questions live on firstmate's board, which already reaches the captain and already carries a stated default and a desk-or-play axis; a second register lets a question be open in one place and invisible in the other.
There is no `handoff/<name>.md`, because firstmate is the handoff and a hand-written summary of state firstmate already writes is exactly what goes stale.
What survives from the handoff idea is the habit that whoever picks up work runs the check themselves, which the task instructions already carry.
Existing copies of either file are reported and left alone; propose retiring one only through the captain.

## Remove

Project removal is destructive and is not one of Firstmate's current direct-write exceptions under `projects/`.
Never issue a raw removal command from Firstmate.
First obtain the captain's explicit removal decision, then inspect the current digest and authoritative repositories for in-flight or queued work, registered secondmate clones, linked worktrees, dirty files, unpushed commits, and any other unlanded work.
If any dependency or unlanded work exists, stop and report it before changing the registry.
Until a guarded removal helper and corresponding prime-directive exception exist, report that implementation gap instead of bypassing the project-write boundary.
When a clone has already been removed through an approved guarded path, or the registry is provably stale because no clone exists, remove its registry line so navigation matches reality.
