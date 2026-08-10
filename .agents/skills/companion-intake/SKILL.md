---
name: companion-intake
description: >-
  Turn natural or dictated game-development requests into faithful, decision-free task content using project-owned sources.
  Use before writing a task brief when intake needs a verbatim request, cleaned reading, project context, pertinent-ambiguity check, captain correction, proportional review evidence, or cold-worker handoff.
  Also use before generic status or report routing when a natural or dictated request names a game project, including read-only game status or report requests.
user-invocable: false
metadata:
  internal: true
---

# Companion intake

This skill is the single owner of the Companion intake transformation.
Keep the boundary modular as inputs plus output so a later captain decision could move it to another agent, but run it in the current intake path and do not create a separate intake agent now.

## Named project precedence

Resolve an explicitly named registered game project before interpreting generic words such as `status` or `report`.
When such a project resolves, this skill owns intake even when the requested game status or report is read-only.
Bearings owns fleet, session, and Firstmate work status only after no named game-project intent resolves.
For a read-only game status or report request, apply the same project-source and pertinent-ambiguity discipline, then use section 7's existing informational-response path instead of forcing a task brief or dispatch.

## Authority boundary

Use this authority order: purpose, doctrine, and design intent are human-originated; architecture, specification, and implementation translate them downward.
Never invent missing design intent or let a mechanical gate stand in for it.
Use mechanical checks to catch execution slips and this authority boundary to catch intent gaps; neither substitutes for the other.
Treat project-owned files as game truth and point to them instead of copying their contents into a second source of truth.

## Intake transformation

1. Preserve the complete request verbatim before interpreting it.
2. Write a cleaned reading that removes transcription noise and repairs readability without adding, dropping, broadening, or narrowing meaning.
3. Inspect the project's authoritative design, implementation, decision, and acceptance sources that bear on the request.
4. Keep a concise private project context card made of the current goal, priorities, built, planned, and unknown state, pertinent open decisions, source pointers with a pertinence rationale, and relevant captain corrections; use the existing project-private equivalent when one exists, otherwise use `data/project-context/<project>.md` in the active Firstmate home.
5. Let the Companion intake that resolved the request be the card's only writer; workers read it through source pointers.
6. Identify only ambiguity whose answer could change the pertinent behavior or implementation boundary.
7. Take the fast path when no pertinent ambiguity remains.
8. When one remains, ask exactly one concise question, route it through the existing [`decision-hold-lifecycle`](../decision-hold-lifecycle/SKILL.md), and park only work that depends on its answer.
9. Let unrelated work continue when it remains decision-free and independently safe.
10. After an answer, rewrite the cleaned reading and task content to the corrected intent while leaving the verbatim request unchanged.
11. Record one plain current correction with its date and source in the context card so a cold worker can receive it; do not build a correction ledger or receipt protocol.

The captain may reject every offered option.
Treat that response as a correction to the interpretation, not as permission to choose the nearest option.

## Intake output

Prepare one task-local intake block with these sections:

- Verbatim request.
- Cleaned reading.
- Authoritative source pointers and why each is pertinent.
- Pertinent ambiguity, written as `None` or exactly one question.
- Desired behavior and explicit non-goals.
- Relevant captain correction, when one changes the current interpretation.
- Seam invariants and acceptance environment.
- Observable done conditions.
- Review risk and required evidence.

Keep the result cold-readable and decision-free before dispatch: a worker may choose implementation mechanics inside the accepted contract, but may not receive an unresolved product or design choice.
Link to repository truth instead of embedding a context dump.

## Existing owners

Use `bin/fm-brief.sh` for the brief scaffold and place the intake block in its task-specific content.
Use `AGENTS.md` section 7 for ship or scout classification, dispatch, authority, validation, and review.
Use [`ask-user-authority`](../ask-user-authority/SKILL.md) if an ask-user finding appears during validation; the implementation worker never answers its own finding.
Do not copy those procedures into this skill or create another handoff document.

## Proportional review evidence

Name the review risk in the task content without replacing the selected delivery path.
Keep planner or architect, executor, and fresh reviewer separation available when risk warrants it, but do not instantiate extra roles by default.

- For a localized mechanical change with no behavior or architecture effect, require its targeted check plus the review already required by the selected path.
- For a behavior, architecture, or cross-seam change, require the full project check, observation of one behavior before stacking more behavior changes, and the fresh reviewer the selected path provides when that depth is warranted.
- If a faster path is too shallow for the risk, use the existing section 7 escalation about switching to no-mistakes; do not invent an extra manual review gate.
