# Phase: IMPLEMENT

Translate spec decisions into code via mechanical worker briefs.

## Core Insight

**Agents rationalize.** They read warnings, understand them, and decide they don't apply. More warnings don't fix this. The fix is removing judgment entirely. Briefs must be mechanical.

## The Brief Chain

```
Spec (truth) → Orchestrator reads spec → Brief (mechanical, zero-judgment) → Worker executes
```

The brief is the **spec-to-code translation layer**. The orchestrator reads the spec, makes all decisions, and writes a mechanical brief that workers follow to the letter. Workers should NOT need to interpret spec — the brief already did that work. The worker is a typist, not a thinker.

**The brief must be correct to spec.** If the brief contradicts the spec, the resulting code contradicts the spec. The orchestrator owns this correctness — not the worker. Workers CAN read specs for context, but the brief is their instruction set.

## Dependency Ordering

Implementation items have dependencies. Foundation items first:
1. **Events** (new event types) — many triggers depend on these
2. **Stats** (new stat names, ScalingVariables) — counters, pipeline, effects depend on these
3. **Query** (conditions, selectors) — skills depend on these
4. **Pipeline changes** (formula updates, new PipelineModifier fields) — effects depend on these
5. **Counter behaviors** — skills that use counters depend on these
6. **Skill system changes** (new fields on SkillDefinition) — content wiring depends on these
7. **Entity lifecycle** (minion fields, form system) — content depends on these

Build the foundation before the features that sit on it.

## Brief Structure

```markdown
# Worker Brief: [Name]

## Worker Rules
- Follow steps in order. Do not skip steps.
- Paste command output where requested. Do not summarize.
- If a step's output surprises you, STOP and report.
- Do not make decisions. All decisions are pre-made.
- Every change must trace to a spec line. No spec = no implementation.
- Do NOT use git stash/clean/checkout --/restore/reset --hard.
- Do NOT use rm/mv/rmdir in Bash.
- Commit with specific file paths. NEVER git add -A or git add .

## Before You Start
[Specs to read — listed explicitly]

## Delta N: [Name]
### Decisions (do not revisit)
| Question | Decision | Spec Reference |
[Pre-made, every row cites spec]

### Steps
[Exact OLD → NEW mappings. Paste-output checkpoints. STOP conditions.]

## Verify Before Commit
For each .tres file changed:
- [ ] grep the changed field and confirm the value matches the brief
- [ ] if an enum integer was used, grep the enum source file to confirm the mapping
  (e.g., `grep EMPOWER_RATIO systems/stats/scaling_rule.gd` to confirm index = 23)
- [ ] if tags were changed, list them and cross-check against the content spec → line

## Test & Commit
[Specific file paths, grep validation commands]
```

## Context Loading (MANDATORY before writing the brief)
For each Definition class the brief modifies:
1. Check `<spec corpus root>/reference/recipes/README.md` for a matching recipe — use it if found
2. If no recipe matches, re-read content-authoring.md field table for that class
3. **Re-read wiring-reference.md** for component access, EffectContext, error handling patterns
4. List what you read and what you found — this is a checkpoint

If the composition guide doesn't cover a behavior you need:
1. Read the architecture spec for the relevant system
2. Find the answer
3. Add it to the composition guide before writing the brief

## Field Verification (MANDATORY before writing code blocks in briefs)

For every effect type, component, or class the brief references by name:
1. `grep '@export var' <file>.gd` — get the EXACT field names, types, and defaults
2. Paste the field list into the brief's appendix — no paraphrasing, no guessing from enum names
3. If the brief writes code that creates EffectContext, verify which fields `from_entity()` auto-populates vs which the caller must set (see wiring-reference.md)

**Why:** Retrospective found agents guessing field names from enum names (DispelCategory → "dispel_category" — wrong). Agents also created minimal EffectContexts because briefs didn't specify required fields. Both are prevented by the orchestrator reading source files and including exact field lists.

## Capability Check (MANDATORY before briefing cross-system wiring)

Before briefing any behavior that requires a runtime system or cross-system connection:
1. **Does the consuming system exist?** Verify the consuming code is wired, not just the writing code.
2. **If it doesn't exist:** Mark `[NOT WIRED]` in the brief or scope the system creation as a prerequisite.

**Known NOT WIRED systems:**
- Duration-based effect expiry via set_meta (no consumer — 10 effect files, see wiring-reference.md)
- Objective failure detection (infrastructure exists, 0 of 12 conditions trigger it — see S11)
- 8 of 12 objective condition lifecycle methods (conditions exist, ObjectiveController never calls them)
- Vendor persistence path (`GameData._get_vendor()` always returns null — B111)
- Network death/respawn subsystem (`on_player_died` never called — B28)
- Unwired EventTypes: ON_DASH, ON_ENTITY_CONTACT, ON_AREA_ENTER, ON_AREA_EXIT, ON_IMMUNE, ON_RESIST

**Blocker dependency chains** (do not brief downstream items until prerequisites are done):
```
[Private field access web (16 sites)] → [NetworkManager decomp (S6)] → [Host migration]
[Objective failure infra (S11)]       → [PROTECT_VIP, TOWER_DEFENSE, timed Harvest]
[GameData persistence fixes]          → [Character roster]
[StatusTracker decomp (S8)]           → [Buff aura scanning]
```

Check `<spec corpus root>/reference/wiring-reference.md` "NOT SUPPORTED" sections before briefing.

## Key Patterns

1. **Decisions table per delta** — all judgment pre-made with spec citations
2. **Paste-output checkpoints** — agent can't silently skip verification
3. **STOP conditions** — "if X surprises you, STOP and report"
4. **Every numeric value sourced** — `[MD §X.Y]`, `[USER]`, `[REQ-NN-XXX]`, `[AP-NN-XXX]`, `[PRESERVED]`, `[DEFAULT]`, `[UNSPEC'd]`
5. **Read full test files** before modifying — assertions on line 34 can break from changes on line 22

## Sizing Workers

| Scope | Method |
|-------|--------|
| 1-2 items, ~15 min | Subagent (background) |
| 3-9 items, ~1 hour | Separate session with brief |
| 10+ items | Split into smaller workstreams |

## Batch Limits (Anti-Decay)

**Context decays in long sessions.** Quality visibly drops after ~3 worker dispatches or ~30 files of changes. The fix:

1. **Max 3 worker dispatches before forced context reload.** After dispatching 3 workers and merging their results: STOP. Re-read this phase file. Re-read relevant recipes or content-authoring.md. Re-read the spec sections for remaining work. Then continue.
2. **Max 30 .tres files per session.** If the task involves more than 30 content files, write a handoff brief for the remaining work and let a fresh session continue. A fresh session with full context beats a decayed session pushing through.
3. **Handoff briefs must be self-contained.** Include: what's done, what remains (per-file), decisions already made (with REQ/AP cites), and the "Before starting" context loading list. No [RESEARCH NEEDED] for things answerable from existing docs — resolve them before writing the brief.
4. **No [RESEARCH NEEDED] in briefs.** If you're writing a brief and don't know the answer to something, read the .gd file NOW. If you notice yourself deferring questions you could answer, you've hit context decay — reload.

## Worktree Management

```bash
git worktree add .wt/<name> -b <branch-name> main
```

- **One worktree per worker.** Never share worktrees between workers.
- **Never use `isolation: "worktree"`.** Create worktrees manually.
- **Never edit main while worktrees active.** Causes merge conflicts.
- **Full brief in prompt.** Workers don't inherit CLAUDE.md.

## .tres Files — Special Handling

After ANY enum change:
```
OLD enum: [list values with integers]
NEW enum: [list values with integers]

For each .tres file:
  [filename]: field = [N] meant [OLD]. Action: [KEEP/CHANGE/DELETE]
```

## Content Pipeline Doc Updates

If the spec changes touched Definition class fields or enums, the brief MUST include a delta for updating:
- `<spec corpus root>/reference/recipes/` (update affected recipe or create new one if pattern is novel)
- `<spec corpus root>/reference/content-authoring.md` (field tables)
- `docs/content-pipeline/templates/README.md`
- Affected template `.tres` files
- Affected guide `.md` files

Updates flow from SPEC, not from the code being written. Include spec citations.

## GDScript Gotchas (include in worker briefs)

1. Return types required: `func foo() -> int:`
2. Typed arrays: `Array[StringName]`, not `Array`
3. StringName literals: `&"name"`
4. `var x := method()` fails if method returns Variant — use explicit types
5. Autoloads must NOT have `class_name`
6. Dict access returns Variant — use explicit `float()` cast

## Phase Completion

- [ ] Worktrees created from current main (one per worker)
- [ ] Briefs are mechanical — zero judgment, all decisions pre-made
- [ ] Every numeric value has a source tag
- [ ] Test files read in full before including in brief
- [ ] Content pipeline doc update delta included if applicable
- [ ] Matching recipe or content-authoring.md re-read for all Definition classes in brief
- [ ] New recipe created or existing recipe updated if novel pattern discovered
- [ ] Workers dispatched

**Next:** Read `phases/review.md` when workers report completion.
