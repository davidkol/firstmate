# Phase: VERIFY

Adversarial verification against SPECS. Not briefs, not tests, not claims. Specs are the source of truth. Code flows DOWN from specs.

## The Rule

**Verification checks code against SPEC.** Not against briefs (circular), not against tests (encode agent assumptions), not against what someone claims was implemented.

## Launch Verification Agent

The verification agent:
1. **Reads specs independently** — the architecture specs for each affected system
2. **Reads code independently** — the actual implementation files
3. **Compares** code behavior against spec requirements (REQs, DDs)
4. **Checks .tres files** for semantic correctness (enum integers match intended members)
5. **Runs the three-way cross-check** (Spec ↔ Code ↔ Docs) for any changed Definition classes
6. **Reports** PASS / FAIL / WARN with file:line and spec reference

## The Verification Agent Must NOT

- Read the brief and verify code matches the brief — that's circular
- Trust that tests passing means spec compliance — tests encode agent assumptions
- Skim files — read each file against its spec section fully
- Trust claims — verify independently

## Three-Way Cross-Check (for Definition Classes)

For every Definition class that was modified:

| In Spec | In Code | In Docs | Status |
|---------|---------|---------|--------|
| Yes | Yes | Yes | Correct |
| Yes | Yes | No | Doc gap |
| Yes | No | No | Code gap |
| No | Yes | No | **Potential invention** |
| No | Yes | Yes | **DANGEROUS — invention laundered into docs** |
| No | No | Yes | Phantom — remove |

**A field in code but not spec is a potential invention.** Do NOT document it. Flag it for investigation. Code may have been written by agents who invented it.

## What To Check Per Workstream

For each workstream, the verification agent should:

1. **Find the spec** — which system spec covers this feature?
2. **List all REQs** that should be satisfied
3. **For each REQ** — does the code implement it? Where? (file:line)
4. **For each code change** — does it have a REQ backing it? If not, is it an invention?
5. **Check traceability** — do the `§` and `⚙` refs in the code point to the right places?
6. **Check traceability** — do `⚙REQ-NN-XXX` and `§` refs in code point to the right spec sections?

## Wiring Verification (from retrospective — targets root causes of 305 review findings)

In addition to spec compliance, check these cross-system wiring patterns:

7. **EffectContext completeness** — For every EffectContext creation site: is `stat_container` populated? Was `create(source, target)` or `from_entity(entity)` used? If `new()` was used, flag it — `new()` is forbidden (leaves all fields unset). Both `create()` and `from_entity()` are correct per CLAUDE.md Rule 13.

8. **AoE allegiance consistency** — Any new AoE effect must use the canonical allegiance filter pattern from `deal_damage_effect.gd:22-24`. If it hardcodes `&"enemy"` without source check, flag it. If it uses `&""`, verify the rationale.

9. **No new set_meta expiry patterns** — If code writes `set_meta` with any key ending in `_expires`, `_revert_time`, or containing `duration`/`timeout`, verify that production code reads it. If no consumer exists, flag it as `[NO CONSUMER]`.

10. **Modifier type vs stat formula** — For any .tres or code that creates StatModifiers: verify REDUCTION-formula stats use modifier_type=3 (REDUCTION). INCREASED/MORE on REDUCTION stats is a silent no-op.

11. **Consumer existence** — For each new metadata key, signal emission, or data write: verify at least one consumer reads/processes it. "Writer without reader" is how dead code accumulates.

12. **Worker [CONCERN] review** — Read the Known Concerns section from the worker report. Each concern should be verified or dismissed with reasoning.

## Report Format

```markdown
### Workstream: [Name]

**SPEC COVERAGE:** [Does the spec fully describe what was implemented?]
**CODE COMPLIANCE:** [Does the code match spec requirements?]
**INVENTIONS:** [Any code without spec backing?]
**SPEC GAPS:** [Any spec requirements not implemented?]
**VERDICT:** PASS / FAIL / WARN

Findings:
- [file:line] — [finding] — [spec ref]
```

## After Verification

- **PASS:** Workstream is complete. Update BACKLOG if not already done.
- **FAIL:** Address findings. Re-verify after fixes.
- **WARN:** Document the warning. User decides if it needs fixing now or later.

## Phase Completion

- [ ] Verification agent launched and completed (NOT skipped)
- [ ] Agent read specs independently (NOT briefs)
- [ ] Three-way cross-check run for changed Definition classes
- [ ] All FAIL findings addressed
- [ ] WARN findings documented
- [ ] Final test suite run confirms no regressions

## FEATURE CHECK (Mandatory — Do Not Skip)

After verification passes, check the SCOPE definition from the start of the session:

1. **List all layers from the scope:** design, spec, data model, runtime wiring, UI, persistence, content
2. **For each layer:** is it DONE, PARTIAL, or NOT STARTED?
3. **If any layer is not DONE:**
   - Present the remaining layers to the user: "The [task] is verified, but the [feature] still needs: [remaining layers]."
   - Ask: "Continue to [next layer], or defer the rest?"
   - Do NOT present backlog options or declare "session complete"
4. **Only when all scoped layers are DONE** (or user explicitly defers remaining): update PROJECT_STATE.md and MEMORY.md.

**The anti-pattern:** A polished "Session Complete" summary with checkmarks after finishing a rename, while the feature doesn't work end-to-end. This gate prevents that. Task verification ≠ feature completeness.

**If no scope was defined** (bug fix, partial task, or scope was skipped): ask the user "Is there more to this feature, or are we done?" before declaring complete.
