# Phase: DESIGN

For tasks that require decisions — game mechanics, architectural splits, new abstractions. This is where research becomes decisions.

## Decision Surface (MANDATORY — build this from Research Log)

The Decision Surface is the structured output of this phase. It separates what you KNOW from what you DON'T KNOW. The user decides the unknowns, not you.

```markdown
## Decision Surface: [Topic]

### Known (cite Research Log entry for each)
1. [fact] — RL entry [N], source: [file:line]
2. [fact] — RL entry [N], source: [file:line]

### Unknown (present to user as decision points)
- [ ] [question] — A: [option + rationale], B: [option + rationale]
  Recommendation: [X] because [research-grounded reason]
- [ ] [question] — A: ..., B: ..., C: ...

### Assumptions Made (flagged, not silent)
- [assumption] — [UNSPEC'd]: why assumed, what alternatives exist

### Read-Side Verification
For each new data write this design introduces:
- Write: [what, where] → Reader: [who consumes it, file:line]
- Write: [what, where] → Reader: [NOT YET BUILT — noted as dependency]
```

**Why this works:** 10 sessions filled gaps with plausible values instead of flagging them as decisions. The "Unknown" section makes gaps visible. The "Assumptions Made" section catches the most dangerous pattern: choices the agent makes without realizing they're choices.

**Rule:** Every "Unknown" item must have at least 2 options with rationale. If you can only think of one option, you haven't researched enough — check PoE/D4/LE or think of the do-nothing/composition alternative.

## The Design Process

1. **Build Decision Surface** from Research Log (Known section)
2. **Enumerate ALL sub-questions** the topic opens — these go in Unknown
3. **For each Unknown**, present 2-3 options with:
   - What shipping games do
   - What the MD currently says (if anything)
   - Recommendation with rationale
4. **User decides** — move items from Unknown to Known
5. **Check Assumptions** — present the flagged section, get user confirmation
6. **Update the Master Design** with decisions
7. **Adjacent Path Check** (see below)

## Adjacent Path Check

When the design changes a code path, verify ALL parallel paths:

```
Primary path: [what the design targets]
Parallel paths (check each — affected? should it be?):
- [ ] [parallel path 1] — affected: yes/no, handled: yes/no
- [ ] [parallel path 2] — ...
```

Common parallels to check (workflow specs in `<spec corpus root>/workflows/` map these):
- Zone tick vs projectile _on_hit (Skill Execution Pipeline)
- PHASED vs default cost resolution (Skill Execution Pipeline)
- Player vs enemy vs minion entity setup
- Apply path vs cleanup/revert path (Progression Pipeline: equip/unequip, allocate/deallocate)
- Offensive vs defensive pipeline stages (Combat Loop)
- Local execution vs network replication path (each workflow has a Replication section)

**Why:** The PHASED cost bug (B3) happened because default branch got features that PHASED didn't. Pierce was implemented in projectile path but not zone. Every design that changes one path should explicitly consider all parallel paths.

## Entity Disambiguation

When the topic specifies properties for one entity, check if related entities need separate decisions. Items and skills are different objects with different semantics.

**Rule:** If the topic specifies a property and multiple related entities exist, explicitly verify WHICH entity it applies to. Don't infer one from the other.

## Updating the Master Design

1. Find the right MD section — verify § numbering (it shifts when sections are added)
2. Write in the designer's voice — MD is prose, not spec language
3. Mark dependencies — `see §X.Y` cross-references
4. `grep -rn "§X.Y" docs/ systems/` — find anything affected by the change
5. Flag downstream impact — specs, code, content specs, pipeline docs

## Validate With Example Values

Every numeric decision: include a worked example with realistic values. "At 10 stacks, this means X." This catches flat-vs-percentage errors, formula mismatches, and scale problems before implementation.

## Spec Questions [SPEC?]

If you encounter a spec ambiguity or contradiction during design:
1. **Do not defer to the worker.** Resolve it now or flag it for the user.
2. **Do not assume the spec is wrong.** Read the MD section first — the spec may correctly reflect a design intent you're not seeing.
3. Tag the question as `[SPEC?]` with the specific ambiguity and which sources conflict.
4. Present options to the user. The user decides; you encode the decision as a REQ and/or AP in the relevant spec.

**Do not write a brief that depends on an unresolved spec question.** The worker will either invent an answer or ship wrong code.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Skip external research | Always verify against shipping games |
| Fill gaps silently | Everything not in MD or user-decided goes in "Assumptions Made" |
| Single-option decisions | Minimum 2 options per Unknown, no exceptions |
| Skip worked examples | Include "at N stacks, this means X" for every numeric value |
| Design only the write side | Read-Side Verification: name the consumer for every new data write |
| Verify primary path only | Adjacent Path Check: list all parallel paths |
| Update MD without checking § refs | Grep all § refs — numbers shift |

## Decision → REQ/AP Mapping (MANDATORY before leaving this phase)

For each decision the user made in the "Unknown" section, write down the target REQ or AP:

```markdown
| Decision | Type | Target Spec | REQ/AP ID | Content |
|----------|------|-------------|-----------|---------|
| D1: ... | REQ | 09-effects | REQ-09-021 | "MUST use ScalingRule(SKILL_RANK) for..." |
| D1: ... | AP | 09-effects | AP-09-012 | "Don't call get_rank_value() for..." |
```

**Why this exists:** Session 64 made 3 design decisions but the brief only encoded *descriptive* spec changes (table rows, TRAP status). The *prescriptive* changes (REQs saying "use this mechanism, not that one") were missed entirely. Descriptive updates document what exists; prescriptive updates encode what SHOULD be used. Both are required.

**Rule:** Every design decision that chooses A over B needs TWO spec entries: a REQ for A and an AP against B. If you can only think of the REQ, ask: "what's the wrong way to do this?" — that's the AP. Carry this mapping into the SPEC phase (or into the brief if spec changes are folded in).

## Phase Completion — Ready for Spec/Brief?

- [ ] Decision Surface has no unchecked items in "Unknown" — user decided everything
- [ ] "Assumptions Made" reviewed with user — no silent inventions
- [ ] **Decision → REQ/AP mapping complete** — each decision has a target REQ AND AP identified
- [ ] Read-Side Verification complete — every write has a named reader (or explicit [NOT YET BUILT])
- [ ] Adjacent Path Check complete — all parallel paths accounted for
- [ ] Master Design updated (if game design changes)
- [ ] Impact analysis done — downstream blast radius identified

**Next:** Run `playbooks/phases/spec.md` to encode the Decision → REQ/AP mapping. Then `playbooks/phases/brief.md` for implementation. Do NOT skip the SPEC phase even if spec changes seem "small" — prescriptive encoding is the step that gets dropped.
