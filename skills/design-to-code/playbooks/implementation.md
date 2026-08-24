# Implementation — Playbook

> Read by orchestrator when the active arc is implementation work (writing code, fixing bugs, adding features, refactoring). Falls back as the **default** when the active arc has no other playbook.
>
> **What's NOT here:** verification work uses `docs/playbooks/verification.md` instead. Universal rails (anti-invention, Rule 4 pre-execution review, two-session protocol, style/traceability) live in `CLAUDE.md` and `.claude/skills/orchestrator/SKILL.md`.

## The loop

```
SCOPE → RESEARCH → DESIGN → SPEC → BRIEF → BRIEF-PRE-CHECK → DISPATCH → REVIEW → HANDOFF
```

Each phase produces a structured artifact that feeds the next. Research Log → Decision Surface → Spec entries → Specialist Brief (or Direct Brief). Phases ≠ sessions — small fixes finish in one session; large features span several. The baton tracks resume-point.

## Phases

- **SCOPE** — Name the feature, not the task. List every layer end-to-end (design, spec, data, runtime, UI, persistence). If the task touches 2+ systems, read the relevant workflow spec at `<spec corpus root>/workflows/` first. Confirm scope with the user.
- **RESEARCH** — `playbooks/phases/research.md`. Output: Research Log.
- **DESIGN** — `playbooks/phases/design.md`. Output: Decision Surface (facts, unknowns for user, flagged assumptions).
- **SPEC** — `playbooks/phases/spec.md`. Output: REQ/AP updates in `<spec corpus root>/systems/NN-*.md`. Run invention sweep.
- **BRIEF** — `playbooks/phases/brief.md` AND `playbooks/phases/implement.md` (single bundle — implement.md carries Field Verification, Capability Check, Batch Limits, Worker Rules, GDScript Gotchas).
- **BRIEF-PRE-CHECK** — `playbooks/phases/brief-audit.md`. Grep-verify brief claims against disk before dispatch. Seven categories of load-bearing claim: (1) substring/text at `<file>:<line>`, (2) regex matches against cited examples, (3) file paths, (4) **directory paths**, (5) pre-skip filter assumptions, (6) cited test bodies (when a brief promises a specific oracle test will flip, verify the assertion shape against the prescribed fix), (7) **stale LIVE-bug claims** — for any brief citing "LIVE bug" / "EXPECTED-FAIL" / "still failing" / "currently broken", run `.regime/venv/bin/python3 .regime/verifiers/v_brief_precheck_v3.py <brief-path>` as a mandatory dispatch-gate (exit 1 = refuse dispatch; promoted 2026-05-17 via DEC-6 post wave-21 6-instance cascade). Full discipline: `docs/playbooks/verifier-design.md` §BRIEF-PRE-CHECK (canonical).
- **DISPATCH** — `playbooks/phases/dispatch.md`. Workers in worktrees (`git worktree add .wt/<name> -b <branch> main`). No `isolation: "worktree"` per Memory rule 11. Workers commit to worktree branch only.
- **REVIEW** — `playbooks/phases/review.md` + `playbooks/phases/verify.md`. Diff stat, test summary, Worker Deviation Review (invention / legit-catch / semantic-change). Reviewer FAIL → see orchestrator §Handling Reviewer FAIL.
- **HANDOFF** — `playbooks/phases/handoff.md`. Update baton, PROJECT_STATE, BACKLOG, MEMORY (if new architectural decision). Cleanup merged worktrees.

## Specialist dispatch vs direct brief

Use **specialist** when `.claude/specialists/<system>.md` exists for the target system AND its spec is rehabbed. Fall back to **direct brief** otherwise. Specialists carry per-system depth; the orchestrator's job is routing and cross-system coordination.

Every delegated agent prompt uses the four-field frame at `.claude/skills/orchestrator/delegation-frame.md` — Role / Standard / Required Inputs / Non-Goals. Composes with phase-file dispatch discipline; does not replace it.

## Branching logic

| Situation | Move |
|---|---|
| Worker hit an inventive moment ("I added a fallback for X") | REVIEW phase invention rollback. Don't accept. |
| Spec says X; code says Y; reviewer flagged it | Decision hierarchy: spec wins unless MD says otherwise. Back to SPEC. |
| Two systems disagree about a seam contract | Read workflow spec at `<spec corpus root>/workflows/`. If unresolved, kick to user (DESIGN unknown). |
| Migration leaves stale callers | All-or-nothing per Memory rule 5. Don't merge until ALL callers migrated. |
| BRIEF-PRE-CHECK finds path drift | STOP. Re-research. Don't dispatch with broken citations. |

## Reference artifacts

- **Phase files:** `playbooks/phases/{research,design,spec,brief,brief-audit,dispatch,review,handoff,implement,verify}.md`
- **Delegation frame:** `.claude/skills/orchestrator/delegation-frame.md`
- **Specialists:** `.claude/specialists/<system>.md`
- **Workflow specs (cross-system flows):** `<spec corpus root>/workflows/`
- **System specs:** `<spec corpus root>/systems/NN-*.md`
- **Wiring reference:** `<spec corpus root>/reference/wiring-reference.md`
- **Style guide:** `.agent/rules/gdscript-style.md`
- **Task guides:** `.agent/task-guides.md`
