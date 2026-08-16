---
name: companion-intake
description: >-
  Turn natural or dictated game-development requests into faithful, decision-free task content using project-owned sources.
  Use before writing a task brief when intake needs a verbatim request, cleaned reading, project context, pertinent-ambiguity check, captain correction, proportional review evidence, or cold-worker handoff.
  Also use before generic status or report routing when a natural or dictated request asks for a resolved game project's own status or report; explicit /bearings and fleet, session, Firstmate, or work-status requests remain Bearings-owned even when they mention that game.
user-invocable: false
metadata:
  internal: true
---

# Companion intake

This skill is the single owner of the Companion intake transformation.
Keep the boundary modular as inputs plus output so existing dispatch and decision owners can consume it without a second protocol.

## Design-question responsibility split

Broad target-design collaboration and concrete task ambiguity use separate paths.
Loading this skill does not perform explicit design-question discovery and is not a substitute for either scout.

When the captain is collaboratively constructing or revising a broad game-design target, use `bin/fm-brief.sh --target-design-intake`.
That scout produces an internal evidence report and a separate captain-facing clean bulk questionnaire by default.
Regular Companion presents only the questionnaire and uses one-at-a-time dialogue only when the captain requests it.
Do not register decision holds or add task dependencies for exploratory target-design questions.
Preserve each answered question, its offered context, and the exact answer before synthesis in one dated private decision file per stable key.
After preservation, reconcile the living target in batches without asking for a separate booking approval for every prose replacement.

When one concrete ambiguity can change ordinary work now, the separate `bin/fm-brief.sh --design-intake` scout discovers and filters grounded candidates from project-owned sources.
Regular Companion presents exactly one pertinent question through the existing decision-hold lifecycle, preserves exact answers and corrections, and routes accepted answers into ordinary work through the existing owners.

## Game status precedence

Resolve an explicitly named registered game project and the requested status or report object before interpreting generic words such as `status` or `report`.
When the resolved game itself is that object, this skill owns intake even when the requested game status or report is read-only.
Do not infer that a game is the requested object merely because a fleet-status request mentions it.
Explicit `/bearings` and requests whose object is fleet, session, Firstmate, or work status remain Bearings-owned even when they mention the resolved game.
For a read-only game status or report request, apply the same project-source and pertinent-ambiguity discipline, then use section 7's existing informational-response path instead of forcing a task brief or dispatch.

## Authority boundary

Use this authority order: purpose, doctrine, and design intent are human-originated; architecture, specification, and implementation translate them downward.
Never invent missing design intent or let a mechanical gate stand in for it.
Use mechanical checks to catch execution slips and this authority boundary to catch intent gaps; neither substitutes for the other.
Human and authoritative designer sources define the target, current code and observed runtime define the present, and agent-authored artifacts remain provisional claims regardless of where the project stores them.
Load [`delivery-doctrine`](../delivery-doctrine/SKILL.md) before shaping a ship contract, and terminate its canonical outcome at an authoritative source rather than a queued task, report, comment, test, status line, memory, or agent-authored plan.

## Intake transformation

1. Preserve the complete request verbatim before interpreting it.
2. Write a cleaned reading that removes transcription noise and repairs readability without adding, dropping, broadening, or narrowing meaning.
3. Inspect the project's authoritative design, implementation, decision, and acceptance sources that bear on the request.
4. Keep the concise private project context card to authoritative source pointers with a pertinence rationale, pertinent open decisions, and exact dated captain corrections; read current code and runtime on demand instead of copying goal, priority, built, planned, or unknown summaries into a second intent surface.
5. Let the Companion intake that resolved the request be the card's only writer; workers read it through source pointers.
6. Identify only ambiguity whose answer could change the pertinent behavior or implementation boundary.
7. Take the fast path when no pertinent ambiguity remains.
8. When one remains, present exactly one concise pertinent question through the existing [`decision-hold-lifecycle`](../decision-hold-lifecycle/SKILL.md) with an honest default that lets work continue and no pre-answer task dependency.
9. After an answer, preserve it exactly with its date, update or create authorized ordinary work, add the decision dependency immediately before the existing resolve command clears it, and leave unrelated work unblocked.
10. Rewrite the cleaned reading and task content to the corrected intent while leaving the verbatim request unchanged.
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

For a ship, translate that block into the two required delivery-contract fields and only the applicable conditional evidence lines through `delivery-doctrine`.

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

- For a localized mechanical change with no behavior or architecture effect, require its direct oracle plus the review already required by the selected path.
- For behavior, architecture, cross-seam, platform, and correction work, apply the tier-specific evidence in `delivery-doctrine` and the fresh reviewer the selected path already provides.
- Keep that evidence depth independent from the selected delivery topology and do not invent an extra manual review gate.
