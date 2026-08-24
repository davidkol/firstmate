# Phase: BRIEF_AUDIT

Between BRIEF and DISPATCH. Verify the brief's claims against code before a worker burns cycles executing a flawed brief.

## Core Insight

**The orchestrator has blind spots.** When you draft a brief naming 14 call sites, you've likely grepped narrowly (by directory, by convention). The worker will grep widely and find the 15th. Better to find it yourself before dispatch — either you widen the brief, or you surface the blind spot so the dispatch prompt calls it out.

This phase is NOT code review. It's **brief-vs-code correspondence checking**. Does the brief describe reality?

## Checks (mechanical, 5-15 minutes)

### 1. Line numbers exist and match
For every `file.gd:N` reference in the brief, Read the file at that line. Confirm the content matches what the brief claims is there.

Common failures:
- File was edited after brief drafting → line numbers shifted
- Orchestrator pattern-matched from memory, not from code

### 2. Widest-possible grep
For every "N callers" claim, grep more broadly than the brief did.

If the brief says "14 effect callers in `systems/effects/types/`", run:
```
Grep pattern="\.method_name\(" (no path filter, no glob)
```
Then classify results: in-brief / out-of-brief. Any out-of-brief caller is a blind spot — either add it to the brief or flag it explicitly in the dispatch prompt as "worker must check this too."

Rule: **never trust a narrowed grep in your own brief.** Your narrowing assumption is the blind spot.

### 3. Per-caller custom-logic sweep
For each caller the brief names, Read the full function body (not just the call line). Ask: does this caller have custom pre/post-call logic that the migration would break?

Common traps:
- Caller reads a return value the brief didn't mention
- Caller has flag-gated behavior (`if copy_metadata:`, `if voluntary:`) with post-call handling
- Caller does `instance.foo = value` immediately after the call — that post-call assignment may interact with the new signature

If a caller has custom logic, call it out in the brief with per-caller migration notes.

### 4. Referenced patterns are current
If the brief cites "canonical exemplar at `file.gd:N`", Read that line. Confirm the pattern is still there. Patterns drift — what was canonical two sessions ago may have been superseded.

### 5. Special-case coverage
Brief tables often have a "special cases" section. For each special case, verify it actually is special — Read the caller, confirm the edge. No invention.

### 7. Stale LIVE-bug claims (DEC-6 dispatch-gate)

For any brief citing "LIVE bug" / "EXPECTED-FAIL" / "still failing" / "currently broken", run the **Vbrief-precheck v3** dispatch-gate verifier BEFORE dispatching the worker:

```bash
.regime/venv/bin/python3 .regime/verifiers/v_brief_precheck_v3.py <brief-path>
```

Exit 0 = PASS; exit 1 = FAIL (refuse dispatch; verifier emits `DISPATCH_PRECHECK_BLOCKED` ledger line). The verifier extracts cited LIVE-bug citations (REQ IDs, file:line refs, oracle test method names) co-located with LIVE markers and checks each against HEAD via four signals: spec-touched-after-brief-date, spec-fix-marker-near-REQ, `⚙REQ` annotation in production code, fix-shape commit subject mentions REQ.

On FAIL: refresh the brief OR re-confirm each cited bug is still LIVE before re-dispatching. **Do NOT auto-retry** — one failed precheck surfaces stale citations to CEO; author makes the call.

Failure mode being prevented: wave-21 cascade (2026-05-17) — 6+ instances where overnight brief sat hours, autopilot fixed cited bugs, worker dispatched against stale brief and authored PASS regression-locks instead of EXPECTED-FAIL hunters (phantom coverage). Promoted via DEC-6.

### 6. Spec type ↔ code type resolution
When the brief cites a spec-authored type ("field X: Resource per DD-YY-ZZZ"), **do not trust the spec typing blindly**. Grep the actual class name and compare:

- Does the spec's type (`Resource`, `Node`, `Variant`, `Array`) reflect a deliberate choice, or is it design-doc voice shorthand for a specific class?
- What does the code currently use? If narrower (`ItemDefinition` vs spec's `Resource`), the code is often correct and the spec is sloppy.
- Read the DD's **justification column**, not just the type column. The WHY often contradicts the WHAT — e.g., "`Resource` ... content authors specify the form's **ItemDefinition**" names the real type inline.

When code ↔ spec types disagree, the stricter typed option usually wins (inspector filtering, edit-time errors, removes runtime guards). Recommend updating the spec, not widening the code.

Common drift patterns:
- `Resource` in spec, `SpecificClass` in code → spec was design-doc voice
- `Node` in spec, `Entity` in code → spec pre-dates Entity base class
- `Variant` in spec, typed field in code → spec was written before type was nailed down

Session 47 caught this on `SetFormWeaponEffect.form_weapon_definition`. Would've widened `ItemDefinition → Resource` for no benefit and lost inspector type-filtering.

## Outputs

One of:

- **PASS — dispatch as drafted.** All checks clean. Dispatch prompt can cite this audit.
- **PASS WITH ADDENDUM — dispatch with additional instructions.** Brief is mostly right; adds 1-3 items to worker's scope or a widened grep to run first.
- **REVISE — update brief before dispatch.** Blind spots material enough to warrant rewriting sections.

## When to skip this phase

- Brief is trivial (1-3 files, mechanical rename)
- Brief was authored by a specialist agent (specialists ran their own audit)
- Brief is a re-execution of a previously-merged pattern (confidence already earned)

For everything else, run it. The 5-15 minutes saved from worker re-work pays for itself.

## Anti-patterns

| Anti-pattern | Reality |
|--------------|---------|
| "I just wrote the brief, I don't need to audit my own work" | You wrote it from memory/pattern-matching. Check against code. |
| "Line numbers might have shifted, I'll trust the worker" | Worker wastes time figuring out stale numbers. You have context; verify. |
| "14 callers is exhaustive because the brief says so" | Your grep was narrow. Widen it. |
| "Worker will catch deviations" | Worker catches SOME deviations. Catching them here is cheaper. |

## Phase Completion

- [ ] Every `file:line` reference verified
- [ ] Widest-possible grep run for every "N callers" claim
- [ ] Each caller's full function body read for custom logic
- [ ] Referenced patterns still canonical
- [ ] Special cases verified, not assumed
- [ ] Spec types resolved against code types (design-doc voice ≠ typing intent)
- [ ] If brief cites "LIVE bug" / "EXPECTED-FAIL" / "still failing" / "currently broken": Vbrief-precheck v3 PASS (exit 0)
- [ ] Output: PASS / PASS WITH ADDENDUM / REVISE
- [ ] If PASS WITH ADDENDUM: dispatch prompt includes the addenda

**Next:** DISPATCH (with audit outcome carried into dispatch prompt).
