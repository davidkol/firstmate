# Phase: RESEARCH

Always first. Every task starts here regardless of scope.

## Reading Order (by task type)

**Fix execution** (codebase review findings):
1. `docs/audits/2026-04-05-engine-perfection-audit.md` — the current audit (for audit-driven fixes)
2. `<spec corpus root>/reference/wiring-reference.md` — canonical patterns
3. Affected `.gd` files — current implementation
4. Relevant architecture specs — intended behavior

**New design** (features, mechanics):
1. `docs/Master-Design.md` — design intent (anchors your mental model)
2. Workflow specs — `<spec corpus root>/workflows/` if the feature touches 2+ systems (maps flows, seam contracts, cross-system traps)
3. Architecture specs — `<spec corpus root>/systems/NN-*.md` for ALL affected systems (decisions are folded into REQs, APs, and Known Traps)
4. Code — implementation (least authoritative)
5. External research — shipping games (PoE, D4, Last Epoch)

**Spec gap audit** (comparing MD to spec to code):
1. Master Design — source of truth
2. Spec — what's claimed (includes all decisions as REQs/APs)
3. Code — what's implemented

**Why the first reading matters:** The first file you read anchors your mental model. Everything after is interpreted through that lens. Anchor to the most authoritative source for your task type.

## Research Log (MANDATORY — build this as you read)

Write findings AS you read, not from memory later. This is your working document for the Design phase. If a fact isn't in the log, it doesn't exist for decision-making.

```markdown
## Research Log: [Topic]

### Reading 1: [file:line range]
- **Found:** [key facts, exact values/names]
- **Cross-refs needed:** [what to check next]
- **Relates to:** [earlier reading N] — consistent / CONTRADICTS

### Reading 2: ...

### Checkpoint (write one every 3-5 readings)
- What I know: [2-3 bullets]
- Contradictions: [list or "none"]
- Open questions: [list]
- Still on scope? [yes/no]
```

**Why this works:** 6 sessions read conflicting sources and didn't notice. The Research Log catches contradictions at read-time because you write "Relates to: Reading 1 — CONTRADICTS" the moment you see the conflict, not when you try to synthesize from memory later.

## Tier 1: Read Design Docs Directly (DO NOT DELEGATE)

1. **Workflow specs** — `<spec corpus root>/workflows/` for any multi-system task. Read the relevant workflow FIRST — it maps the flow, seam contracts, and cross-system traps. Use the "Common Brief Patterns" table to focus your reading.
2. **Architecture specs** for ALL potentially affected systems — not just the obvious one. Decisions are folded into REQs, APs, and Known Traps within each spec.
3. **Master Design** relevant sections
4. **Wiring + content references** — the workflow spec's "Read First" column tells you which subsections matter
5. **Content authoring** — `recipes/README.md` for .tres tasks (find matching recipe first). Fall back to `content-authoring.md` for full field tables when no recipe matches.
6. **Wiring reference** — `wiring-reference.md` for any cross-system code

Log each reading. If the composition guide or wiring reference doesn't cover a behavior you need, read the .gd file and update the reference BEFORE writing the brief.

## Tier 1.5: Trace the Feature Runtime Path (DO NOT SKIP)

After reading design docs, trace the full runtime path:
1. **Who creates/provides this?** (talent, equipment, gems, crafting)
2. **Who manages it at runtime?** (which Manager/Autoload owns state)
3. **Who consumes it?** (UI, other systems, effects)
4. **How is it persisted?** (PlayerData fields, save/load hooks)
5. **Can the player interact with it?** (which UI screen, what flow)

This catches missing layers that blast-radius analysis misses.

## Existence Check (MANDATORY before proposing new infrastructure)

Before proposing ANY new mechanism, API, or infrastructure:

```bash
grep -rn "concept_name" systems/ entities/
grep -rn "concept_name" <spec corpus root>/systems/
grep -rn "concept_name" docs/briefs/
```

Log the result: `EXISTS at [file:line]` or `CONFIRMED NOT FOUND (grepped N files)`.

**Why:** 4 sessions proposed building infrastructure that already existed (RollingWindowTracker, dispel_by_category, cost_options, empowerment scaling). 30 seconds of grep prevents an hour of wasted design.

## Inherited Claim Verification

When reading a baton, handoff brief, or prior session's output:
- **Numeric values** (enum indices, line numbers, counts): verify against code
- **"X doesn't exist"**: grep to confirm
- **"X is the correct approach"**: check if newer REQs or APs supersede

Tag each claim: `[VERIFIED]` or `[UNVERIFIED]`. Do not build on unverified claims.

**Why:** MASTERY_POINTS=23 (wrong, was 24) survived two sessions. MarkCost = actual spending (wrong) survived three sessions. Handoff authority is not code authority.

## Tier 2: Delegate Code-Level Scoping (PARALLEL)

| Agent | Reads | Purpose |
|-------|-------|---------|
| Code reader | Affected `.gd` files + grep for consumers | What code actually does |
| .tres scanner | `grep --include="*.tres"` for affected enums/fields | What content references |
| Blast radius | All files referencing affected classes/functions | Scope of changes |

## External Research

Search shipping games for the same problem: PoE 1&2, D4, Last Epoch, Grim Dawn, Hades. Look for GDC talks, dev blogs, wiki docs. Save findings to `<spec corpus root>/research/arpg-*.md`.

## Phase Completion — Ready for Design?

- [ ] Research Log has entries for all affected systems
- [ ] Contradictions logged and noted for user review (or "none found")
- [ ] Existence Check done for any proposed new infrastructure
- [ ] No `[UNVERIFIED]` inherited claims remain
- [ ] Runtime path traced (Tier 1.5)
- [ ] Code-level agents returned with findings

**Next:** If design/MD changes needed → `playbooks/phases/design.md`. If spec-only → `playbooks/phases/spec.md`. If implementation-only → `playbooks/phases/implement.md`.
