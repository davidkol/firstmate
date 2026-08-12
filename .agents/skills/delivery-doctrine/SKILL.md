---
name: delivery-doctrine
description: >-
  Agent-only procedure for shaping and reviewing every ship task under the Designer -> Runtime -> Player doctrine.
  Load before writing or materially changing a ship brief, before evaluating whether its evidence depth is proportional, and before routing a false-canon correction.
user-invocable: false
metadata:
  internal: true
---

# Delivery doctrine

Use this procedure to shape the task-local delivery contract before dispatch.
The contract is an execution boundary, not a second intent database or completion receipt.

## Authority boundary

Human and authoritative designer sources define the target.
Executing code and observed runtime define the present.
A queued task, plan, report, comment, test, status line, memory, or agent-authored brief is a provisional claim.
Copying one of those claims into a brief never promotes it to designer intent.
When a provisional source quotes a human decision, follow it to the exact primary words or authoritative receipt and cite that source in the outcome.
Preserve the generated brief's existing captain-versus-Firstmate provenance split and the spawn-time captain-authority receipt check.

## Two-field core

Every ship brief contains exactly one legal `task-tier` and one canonical `outcome` in its `# Delivery contract` block.
The outcome has the shape `<authoritative human/source pointer> => <observable result>`.
It names one source that actually owns the target and one result that a worker and reviewer can observe.
Do not fill either core field with an agent summary, `N/A`, a placeholder, or a copied claim whose authority has not been checked.

Use these tiers:

- `T0` documentation or mechanical work with no intended product-runtime behavior change.
- `T1` one small defect on one local execution path with a bounded objective oracle.
- `T2` one localized player-visible outcome inside one subsystem.
- `T3` new or rewired architecture, cross-system composition, platform/native boundaries, or high-blast-radius behavior.
- `T4` a false-canon correction, either alone or as `T4/T0`, `T4/T1`, `T4/T2`, or `T4/T3` when runtime work is also present.

Escalate from T0 when the task changes an executable seam, public contract, safety or authority instruction, build artifact, or behavior.
Escalate from T1 when work crosses a subsystem boundary, changes player-facing behavior instead of restoring it, or lacks a sensitive local oracle.
Escalate from T2 when multiple systems must compose, a platform artifact changes, or separable parts can be present but inert.

## Conditional evidence

Add only evidence lines the risk actually needs.
Never add empty lines or `N/A` ceremony.

- `prove` names a focused command, reproduction, observation, or diff check when a distinct focused oracle is useful.
- `player` names ordinary entry, actions, and result for T2 and T3, or for a T1 defect that cannot be honestly reproduced below that path.
- `parts` names one causal signal per separable architecture-bearing part and appears only on T3.
- `platform` names the affected environment plus artifact or runner evidence only when a platform, native, packaging, or ABI seam changes.
- `correct` names the rejected claim and bounded current authority-bearing owners and active descendants to inspect, and appears only with T4.

One real execution or capture may satisfy multiple evidence purposes when it is genuinely the same oracle.
For example, a normal player-path capture may be the focused before-and-after proof and the player observation without a second run or duplicate evidence line.
A new or suspect oracle needs one deliberate negative control; an established sensitive regression does not need theatrical mutation on every task.

T0 uses the direct document, tool, configuration, or mechanical oracle.
T1 uses focused evidence and adds player, wider regression, platform evidence, or review depth only when its actual risk needs them.
T2 requires the affected ordinary player path and uses a full regression only for shared surfaces, meaningful regression radius, or project policy.
T3 requires the ordinary player path, causal evidence for every separable architecture-bearing part, and one full project regression after the final change.
T4 searches only current authority-bearing owners and active descendants, corrects live false canon, and permits clearly labeled historical evidence to remain.
T4 inherits the evidence depth of any attached runtime tier.

Delivery topology is independent from this evidence depth.
`direct-PR`, `local-only`, `validated-main`, and `no-mistakes` remain available at every tier.
Never switch modes merely because a task is behavior, architecture, or correction work.

## Role boundaries

Give an implementation worker only the two-field contract, applicable evidence lines, proportional tier instructions, authority boundary, and documentation rule.
Give the selected reviewer the exact tier, outcome, present evidence lines, final diff, and a short review duty.
Do not copy this full procedure or the historical failure taxonomy into either role prompt.

The selected reviewer checks the tier choice, exact outcome and source, executing control flow, actual evidence on the final diff, and whether the task was under-tiered.
A finding maps to that accepted target and may return to the same worker.
A reviewer may not invent a new product target or require another review role.

Do not compare a worker-authored or brief-authored SHA for semantic freshness.
Keep existing code-attribution and pipeline descendant-HEAD rules unchanged.
Do not add semantic completion fields to worker status or treat `done:` or delivery-field presence as proof that a player path, contribution, correction, or designer alignment occurred.

## Correction and documentation

For T4, search the bounded current instruction, active design or plan, current status or baton, production comments that assert design, tests whose descriptions assert design, and unlaunched active briefs that descend from the rejected claim.
Delete or relabel live false canon before later descendants dispatch.
Preserve designer sources and clearly labeled historical evidence.
Do not require a repository-wide zero-match result and do not build a descendant graph.

Do not create a maintained document for task chronology or handoff by default.
Update an existing owning document only when the change alters its present contract, operator workflow, or stable non-obvious invariant.
Delete or relabel a stale current claim.
Code comments explain current non-obvious behavior, never progress or unverified intent.
