# Canonical Project Repositories

## Summary

Firstmate will register the captain's existing project repository as the one canonical local repository for each primary or peer home.
Firstmate-private state remains under `FM_HOME`, but Firstmate will no longer require or present a duplicate managed project clone for migrated primary and peer projects.
Treehouse will create every ordinary ship or scout worktree from the canonical repository.

## Observed failure

Martyrdome target documents were merged to GitHub and synchronized into Firstmate's managed clone.
Firstmate then reported that local Martyrdome `main` was synchronized and linked the captain to files inside that managed clone without identifying or inspecting the captain's actual repository.
The captain's working repository remained at an older commit, so the completion report was locally false even though the remote publication was correct.

## Accepted decisions

- Each project has exactly one canonical working repository path.
- Martyrdome's canonical path is `~/projects/Godot/Martyrdome`.
- A missing, moved, or invalid canonical repository stops work and never falls back to an internal clone.
- Primary and peer homes use the canonical repository as the Treehouse anchor.
- Firstmate may retain private per-project material, but that material is not a Git clone and is never presented as the project.
- Validated work normally lands by guarded local fast-forward followed by a direct push to the remote, without a pull request.
- A task may explicitly select local-only landing.
- The captain's separate informed approval remains required before validation, landing, or pushing.
- A temporary remote task branch is allowed during validated-main delivery and is removed after the default branch safely contains it.
- A guarded update may preserve non-conflicting untracked files.
- Existing secondmate-owned project clones remain an explicit temporary exception until their independent-home synchronization is separately redesigned.
- The existing Orca-owned worktree backend remains outside this Treehouse-provider change.
- Existing managed clones are retained inactive until the captain separately approves their deletion.

## Registry contract

`data/projects.md` remains the single private project registry.
Each migrated project entry gains one indented `path:` field containing its canonical absolute repository path.
The path may contain spaces because the resolver consumes the entire field value after `path:`.

An entry has this shape:

```markdown
- Martyrdome [validated-main +yolo] - Godot action game, boss encounters
  path: /home/example/projects/Godot/Martyrdome
```

One central resolver owns project identity, canonical-path parsing, delivery mode, and autonomy posture.
It returns the project id, physical absolute repository root, mode, and yolo state.
It rejects duplicate project ids, duplicate physical repository roots, relative paths, absent paths, paths that are not Git repository roots, and paths that resolve inside an `FM_HOME/projects` managed-clone directory for a primary or peer project.
Registry entries without `path:` remain visible for migration diagnostics but cannot dispatch, synchronize, brief, or land ordinary primary or peer project work.

## Task and Treehouse flow

Briefing, spawning, synchronization, reconciliation, landing, completion reporting, and captain-facing project file links consume the central resolver rather than constructing `$FM_HOME/projects/<name>`.
Task metadata records both `project_id=` and the resolved physical `project=` path.

For a Treehouse-backed spawn, Firstmate launches Treehouse from the canonical repository.
After acquisition, Firstmate verifies that the result is a linked worktree, that its physical root differs from the canonical checkout, and that its Git common directory matches the canonical repository's Git common directory.
A mismatch refuses the spawn before the worker starts.

Secondmates continue resolving their provisioned clones under their own homes during this change.
Their metadata and documentation must name that exception so the primary or peer canonical-path claim is not overstated.

## Guarded synchronization

Registry-driven synchronization enumerates only registered canonical paths.
It does not scan retained directories under `FM_HOME/projects`, so a retained clone cannot remain active or become an identity fallback.

A remote update may fast-forward the canonical checkout only when all of these conditions hold:

- the canonical path still resolves to the registered repository root;
- the checkout is on its default branch;
- the index has no staged, unmerged, or tracked working-tree changes;
- the local default branch is an ancestor of the remote default branch;
- every untracked path is proven non-conflicting with the incoming tree update.

The untracked-file preflight uses Git's own checkout or read-tree collision behavior against the proposed target tree rather than a hand-written exact-name comparison.
An exact-file collision or file-directory collision refuses without moving `HEAD`, changing the index, or touching working files.

## Validated landing

The existing `validated-main` flow remains the no-PR delivery mechanism.
Its reviewed task head may exist temporarily as `origin/fm/<task-id>` for recovery and review identity.
After separate informed approval, guarded landing verifies the task's project id, canonical path, Git common-directory identity, validated head, default branch, remote default branch, tracked state, and untracked collision state.

A successful landing performs these actions in order:

1. Fetch the current remote default and temporary task branch.
2. Prove that the validated head fast-forwards both local and remote default branches.
3. Fast-forward the canonical checkout while preserving non-conflicting untracked files.
4. Push the default branch directly to `origin`.
5. Confirm that the remote default branch contains the landed commit.
6. Delete the temporary remote task branch when it is redundant.
7. Report the canonical path and exact landed commit.

A refusal preserves the task branch and Treehouse worktree.
A rejected default-branch push leaves the landed commit in the canonical checkout and preserves the temporary remote branch for recovery.

## Migration

Migration is explicit and per project.
It refuses while any in-flight task metadata names the old managed clone.
It verifies the requested canonical repository and remote identity before atomically adding the registry path and changing the project's delivery mode.
It does not infer a canonical path from a matching basename or remote URL.

Martyrdome migrates to `~/projects/Godot/Martyrdome` with `validated-main` delivery.
Its existing untracked `notes.md` is preserved.
Its retained managed clone becomes inactive because no registry-driven operation enumerates it.
Deletion of that clone is a separate destructive action and is not part of this change.

## Captain-facing reporting

Every delivery or synchronization result names the repository surface it actually verified.
Project file links use the canonical working repository.
Firstmate-private reports may link to private state only when they are explicitly labeled as private Firstmate artifacts.
An unidentified, missing, stale, or blocked captain repository is reported as such and is never replaced by a statement about another local copy.

## Focused validation

Validation stays proportional and uses existing test owners where possible.

- One resolver and migration fixture covers a valid canonical path, a missing or non-root path refusal, duplicate physical identity, and retained-clone exclusion.
- One real Treehouse acquisition proves a distinct linked worktree with the canonical Git common directory.
- One guarded synchronization and landing fixture proves that a non-conflicting untracked file survives, the default branch fast-forwards, the remote default branch receives the commit, no pull request is created, and the temporary task branch is retired.
- The same landing fixture proves that tracked or staged changes, a wrong branch, divergence, a moved remote default, and exact-file or file-directory untracked collisions refuse without moving `HEAD` or modifying files.
- Existing documentation-audience and shell lint checks run only for touched surfaces.

No full runtime-backend matrix or unrelated repository test suite is required for this change.

## Non-goals

- Deleting existing managed clones.
- Redesigning secondmate project isolation.
- Replacing Treehouse.
- Changing Orca's worktree ownership.
- Removing the temporary reviewed remote task branch from validated-main.
- Automatically resolving dirty or divergent repositories.
- Changing the captain's separate validation and landing approval rule.
