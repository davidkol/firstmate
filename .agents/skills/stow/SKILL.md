---
name: stow
description: Sweep the current session for uncaptured durable knowledge and file it to disk before a context reset. Use when the captain invokes /stow (e.g. "/stow", "stow what you've learned"), before a session reset or context compaction, periodically to keep operational memory current, and before promoting a home-local learning into firstmate's shared tracked surface.
user-invocable: true
metadata:
  internal: true
---

<!-- maintainers: this is the firstmate-internal skill. The public, installer-facing counterpart lives at skills/stow/SKILL.md - deliberately a separate file with no shared code or environment branching. Keep them independent. -->

# stow

Sweep this session for durable knowledge that only exists in conversation right now, and write it to the disk locations firstmate already prints in the next session-start context digest.
The goal is a session that is safe to reset or destroy because everything durable has already been captured.

## What it does

1. **Sweep the session for uncaptured durable knowledge.**
   Read back over this conversation and look for:
   - Operational learnings: fleet-local facts and gotchas discovered while operating firstmate (a script's sharp edge, a harness quirk, a recurring false alarm and its real cause).
   - Captain preferences expressed in passing: a working-style or approval preference the captain stated conversationally rather than through the destination selected by AGENTS.md's knowledge-routing table.
   - Project-intrinsic facts discovered: build, test, release, or architecture facts about a project that belong in that project's own `AGENTS.md`.
   - Decisions made: a standing choice the captain made this session that should outlive it.
   - Undone next steps: anything left open that has not yet been filed as backlog work.

2. **Route each finding using AGENTS.md's knowledge-routing table.**
   AGENTS.md (section 6, "Knowledge routing") is the single source of truth for where each kind of knowledge belongs.
   Read that table and route each finding there instead of re-deriving the mapping here.

3. **Write within firstmate's existing write boundaries.**
   This skill does not grant any new write permission; it only prompts firstmate to use the boundaries that already exist (AGENTS.md section 1):
   - Captain preferences and fleet-local operational facts: hand-write directly to the destination selected by AGENTS.md's knowledge-routing table, using inspect-then-update every time.
     Before writing, inspect the destination, find the existing bullet or section the finding duplicates or supersedes, and rewrite it in place rather than adding a new trailing entry.
     `data/learnings.md` may not exist yet; create it on first local learning, in the same dated, evidence-backed, curated style as the captain-preference files.
     If it holds an `fm-promotion` marker line, that block belongs to `bin/fm-learning-promote.sh`: curate around it and leave its shape alone, because `land` refuses a block it did not write rather than risk deleting entries that are not part of it, and this file is gitignored with no recovery.
   - Project-intrinsic knowledge: never hand-write a project's `AGENTS.md`.
     Route it through a normal ship task so a crewmate records it via `bin/fm-ensure-agents-md.sh` and commits it through that project's delivery pipeline, exactly as section 6 describes.
     If the fleet is live, delegate this to a crewmate rather than doing it inline.
   - Knowledge generalizable to every firstmate user: this repo's own `AGENTS.md` (or other shared, tracked material), shipped through the normal branch -> no-mistakes -> PR -> captain-merge pipeline for this repo (section 1), never hand-committed straight to `main`.
   - Task-scoped notes: inspect the relevant backlog item with `tasks-axi show <id> --full`, judge whether the new note is new, duplicate, superseding, or obsolete, then write a considered replacement body with `tasks-axi update <id> --body-file <path>`.
     When the replacement intentionally supersedes prior state that should remain recoverable, add `--archive-body` to that update command so the prior body stays recoverable without copying it into the replacement.
     Never append.
     If hand-editing `data/backlog.md` per the active backend, make the same inspect-then-update edit in place.
   - Undone next steps: file each as a queued backlog item (section 10), with `blocked-by` recorded if it genuinely depends on something else.

4. **Curate with inspect-then-update.**
   Every write starts by reading the current destination and deciding how the finding changes what is already there.
   Use this checklist before writing:
   - Which existing bullet, section, or task body does this supersede?
   - Can this be a one-sentence rewrite instead of a new entry?
   - Should an older bullet or note be deleted, retired, or archived because it is now obsolete?
   When a finding overlaps or supersedes something already on disk, rewrite or prune the existing entry instead of piling on a new one.
   Graduation moves are limited to exactly three: promote a learning into firstmate's shared tracked surface under "Promoting a learning into the tracked repo" below, fold it into the captain-preference destination selected by AGENTS.md, or delete a stale entry.
   Do not invent other graduation paths.

5. **Report to the captain.**
   Summarize, in plain outcome language (section 9): what was stowed and where, what was filed to the backlog, and whether the session is now safe to reset or destroy - i.e. whether every durable finding from this sweep now lives on disk rather than only in this conversation.
   If something could not be captured yet (for example, project-intrinsic knowledge waiting on a crewmate to land it), say so explicitly rather than reporting the session fully safe.

## Promoting a learning into the tracked repo

A home's `data/learnings.md` is gitignored and home-local, and there is deliberately no shared learnings file between homes, because a shared file is the thing that rots.
The only path that reaches every home runs upward: the lesson lands in this repo's shared tracked material through the normal delivery path, and every home picks it up on its next update.

**A learning graduates onto that path only when it is true in more than one project and somebody makes it checkable.**
If it cannot be made checkable it stays a note, and most good knowledge stays a note.
A lesson true of one project belongs in that project's `AGENTS.md` or `notes/`, and a lesson true of how the captain works belongs in this home's `data/captain.md`; neither is a promotion.
Promotion is the rare move, never the tidy default.

Promotion runs in two phases with a gate between them, because retiring the local entry before the tracked change lands destroys it, and never retiring it leaves the same lesson in two places:

1. `bin/fm-learning-promote.sh start <slug> --to <path> --evidence <where it proved true> --checkable <what makes it checkable> --landed-text <the distinguishing phrase the landed change will put in the destination>` records the promotion in flight in this home's `data/learnings.md`, so the session-start digest prints it every session until it is finished.
   It refuses an unstated graduation case and a destination no other home would receive; it cannot judge whether your stated evidence is true, so that judgment stays with you and the review pipeline.
   Choose `--landed-text` from the sentence you actually intend to add, not a paraphrase, because it is the only thing proving this lesson landed rather than someone else's.
2. Ship the tracked change through this repo's normal branch, no-mistakes, PR, and captain-merge path, exactly like any other shared-material change.
   Never hand-commit it to the default branch.
3. `bin/fm-learning-promote.sh land <slug>` refuses until the destination on the default branch actually contains that phrase, and on success replaces the in-flight record with a one-line pointer to the tracked owner.
   A merely changed destination is not enough: `AGENTS.md` is touched by nearly every shared-material PR, so a weaker check would retire a lesson that never landed.
   Delete the original local entry that pointer supersedes in the same pass, so the lesson lives in exactly one place.

Read `bin/fm-learning-promote.sh --help` for exact flags, paths, and refusals.
Inside step 2 the destination is chosen by the knowledge-placement decision tree in the `firstmate-coding-guidelines` skill, as a deliberate reviewed repo change; that is not this sweep writing to a skill, and the exclusion below is unchanged.

## Scope exclusion: no skill storage

`/stow` must **never** store, create, or edit a skill as a destination for any finding.
There is no "graduate this to a skill" move in this skill's routing.
This is a deliberate, standing exclusion, not an oversight: even with the two-tier skill layout, a stow sweep is a memory-routing operation, not a way to author or mutate skills.
Writing learnings into either `.agents/skills/` or public `skills/` would still risk mixing fleet-local material with shared firstmate behavior or standalone installer-facing behavior.
Until a human deliberately scopes a skill change as firstmate repo work, route generalizable knowledge to the shared `AGENTS.md` (or other shared, tracked material) via the pipeline, and fleet-local knowledge to `data/`, never to a skill.
