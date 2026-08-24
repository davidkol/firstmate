# Phase: SPEC

Flow design decisions into architecture specs. Create/update REQs, APs, and data models directly in the spec.

## Recording Decisions

Decisions are recorded **directly in the architecture spec** — there are no separate decision logs. For each decision:

1. **Add or update REQs** in the relevant spec section (`REQ-NN-XXX` numbering, sequential within the system)
2. **Add Anti-Patterns** (`AP-NN-XXX`) for rejected approaches — one line: "Don't do X → do Y instead, because Z"
3. **Update Known Traps** if the decision resolves or creates a trap
4. **Update "How It Works"** prose if the decision changes system behavior

**Prescriptive vs Descriptive.** Descriptive changes document what exists ("SKILL_RANK is ScalingVariable 26"). Prescriptive changes encode what SHOULD be used ("effect magnitudes MUST use ScalingRule(SKILL_RANK), not get_rank_value()"). Both are required for every decision. If you only wrote descriptive changes, you haven't finished this phase. Use the Decision → REQ/AP mapping from the DESIGN phase as your checklist — every row needs a REQ and an AP in the spec.

For cross-system decisions, update BOTH specs and use cross-system refs: `System NN REQ-NN-XXX` or `System NN AP-NN-XXX`.

**Every value must be cited.** Tag each value:
- `[MD §X.Y]` — from Master Design
- `[USER]` — user decided this
- `[REQ-NN-XXX]` — from prior spec requirement
- `[PRESERVED from file.gd]` — carried from existing code
- `[DEFAULT]` — language/engine default
- `[UNSPEC'd]` — not decided, needs user

## Invention Sweep (MANDATORY)

After recording decisions, **before proceeding**, audit your own work:

1. List every value and behavior you wrote
2. For each, cite the source (MD, user decision, existing REQ/AP)
3. **If you cannot cite a source, it's an invention.** Mark `[UNSPEC'd]` and present to user

**Red flags that signal invention:**
- "This is just a reasonable default" → If not in the brief, it's an invention
- "This prevents an edge case" → The designer may want that edge case
- "The brief implies this" → Implication ≠ statement. Flag it.
- "This is implementation detail" → If it changes game behavior, it's design

## Propagation

Identify which direction the change flows:

**Top-down** (design changed → code/content must follow):
1. Update architecture specs (REQs, data model sections)
2. Grep `§` refs to find affected code and content specs
3. Run consistency validation
4. Resolve conflicts (content spec entries, .tres files)
5. Update content pipeline docs (Check 5 — three-way cross-check)

**Bottom-up** (playtest tweak → design may need updating):
1. Content spec validation flags discrepancy
2. User confirms the new value
3. Content spec updated
4. If broader design rule changed → update MD

**Lateral** (code/spec change → content affected):
1. Data model validation flags affected entries
2. Add default rule to `defaults.md` or `?` lines to content specs
3. User resolves
4. Update content pipeline docs from spec (NOT from code)

## Stale Term Sweep

After ANY rename or term change:
```bash
grep -rn "OLD_TERM" docs/ resources/ tests/
```
Fix or flag EVERY hit. Stale refs in other spec files survive silently.

## Three-Way Cross-Check (Check 5)

When spec changes affect Definition class fields or enums:

| In Spec | In Code | In Docs | Status |
|---------|---------|---------|--------|
| Yes | Yes | Yes | Correct |
| Yes | Yes | No | Doc gap — add to docs |
| Yes | No | No | Code gap — implement |
| No | Yes | No | Potential invention — investigate |
| No | Yes | Yes | **DANGEROUS** — invention laundered |
| No | No | Yes | Phantom — remove from docs |

## Phase Completion

- [ ] Spec REQs/APs created or updated with source citations
- [ ] Invention sweep completed — every value traced to source
- [ ] Architecture spec REQs created/updated
- [ ] Spec data model sections updated
- [ ] Stale term sweep done (if renames)
- [ ] Content pipeline docs flagged for update
- [ ] Propagation direction identified and executed

**Next:** If code/content changes needed → read `playbooks/phases/implement.md`. If spec-only → read `playbooks/phases/verify.md`.
