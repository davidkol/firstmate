# Phase: BRIEF

Write mechanical execution briefs for separate sessions. You do NOT execute them.

> **Anti-invention reminder (SKILL.md rule 1):** You WILL invent. Mark it `[UNSPEC'd]`. Do not resolve silently. Every unspecified choice goes in the Assumptions Made section below and is surfaced to the user before dispatch.

## Core Insight

**You are a planner, not an executor.** Your briefs are the spec-to-code translation layer. A separate session (fresh context, no decay) picks up each brief and executes it. The brief must be correct to spec — if the brief contradicts the spec, the resulting code contradicts the spec.

## Context Loading (MANDATORY — paste output, do not summarize)

Before writing each brief, perform and paste the output of each step into a scratch block at the top of the brief. This is not a self-graded checkpoint — an empty or omitted scratch block means the brief is not complete.

0. **Re-read `playbooks/phases/implement.md` in full.** Paste `wc -l playbooks/phases/implement.md` as proof-of-load. This file holds Field Verification, Capability Check / NOT WIRED list, Batch Limits, .tres enum handling, Worker Rules (destructive-git + `git add -A` + rm bans), Worktree Management, and GDScript Gotchas. brief.md references these by pointer — do not attempt to write a brief without them loaded.

1. For each Definition class the brief modifies: `ls <spec corpus root>/reference/recipes/ | grep -i <class>` — paste result. Use the matching recipe if found.

2. If no recipe matches: `grep -A 20 '<class>' <spec corpus root>/reference/content-authoring.md` — paste result.

3. For each effect type, component, or class the brief references by name: `grep '@export var' <file>.gd` — paste result into the brief's Field Verification appendix (per implement.md §"Field Verification").

4. If neither recipes nor content-authoring.md cover a behavior you need: read the architecture spec for the relevant system, read the actual `.gd` file for the effect/class, and add a new recipe or update content-authoring.md BEFORE writing the brief.

**No [RESEARCH NEEDED] in briefs — but no silent resolution either.** If you can't answer a question from docs, read the code. If it's a genuine design question, resolve it with the user first. If under decay pressure you are tempted to pick a value to move on: STOP. That choice goes in the Assumptions Made section tagged `[UNSPEC'd]` and must be surfaced to the user before dispatch. Deferral tags (`[RESEARCH NEEDED]`) are banned; invention tags (`[UNSPEC'd]`) are mandatory. Removing one without the other creates invention pressure.

## Pre-claim verification (MANDATORY)

**Before claiming `dead` / `unshipped` / `unused` / migration semantics on any code path, grep all four layers:**

- `tests/` — is the path under test?
- `docs/content/` — is the path referenced by a content spec?
- `docs/Master-Design.md` — does the MD reference the path or describe a behavior that requires it?
- `.tres` files — is the path referenced by content data?

Skipping any of these layers means the "dead" claim is unverified. (See pin `feedback_check_content_spec_layer.md`.)

## Brief Structure

```markdown
# Execution Brief: [Name]

> **Context:** [1-2 sentences on what this brief accomplishes and why]
> **Prerequisites:** [Any briefs that must be executed first]
> **Estimated scope:** [N files, complexity level]

## Worker Rules
[Use the canonical Worker Rules list from `playbooks/phases/implement.md` §"Brief Structure". The canonical list includes: follow steps in order, paste command output (do not summarize), STOP on surprise, do not make decisions, every change traces to a spec line, do NOT use git stash/clean/checkout --/restore/reset --hard, do NOT use rm/mv/rmdir in Bash, commit with specific file paths — NEVER `git add -A` or `git add .`. Single source of truth — if the canonical list changes, it updates for every brief automatically.]

Brief-phase additions (not in implement.md):
- You will be running inside a git worktree under `.wt/<name>`. Do not touch main, do not merge, do not cherry-pick. When done, say "ready to merge" and stop.
- Read the matching recipe from <spec corpus root>/reference/recipes/ before starting. Fall back to content-authoring.md if no recipe matches.

## Specs to Read
[Explicit list of spec files. For each, paste the output of `wc -l <file>` AND a one-line quote of a section heading or REQ/AP ID that is load-bearing for this brief. The quote is proof-of-read — it is not proof-of-existence.]

Example:
```
- <spec corpus root>/systems/02-stat-pipeline.md — 847 lines — "REQ-02-014: REDUCTION stats reject non-REDUCTION modifiers (silent no-op)"
- <spec corpus root>/systems/10-skill-system.md — 612 lines — "AP-10-003: SkillDefinition.cost is paid before effect application"
```

## Assumptions Made
List every choice made while writing this brief that was NOT explicitly specified by the cited sources. Tag each:
- `[UNSPEC'd]` — no spec line, no user decision, picked a value to unblock the brief. **MUST be surfaced to user before dispatch.**
- `[INFER'd]` — extrapolated from an adjacent rule in the same spec. Cite the rule.
- `[PROVISIONAL]` — user said "probably X but we'll confirm later."

If this section is empty, justify why (most non-trivial briefs have at least one). An unjustified empty section is a red flag for silent invention.

## Changes

### File: [exact/path/to/file.tres]
**Content spec says:** [exact quote from `docs/content/<file>.md` — name the file and row]
**Current state:** [what's in the file now]
**Change:** [exact edit — OLD → NEW with field names and values]
**Verify:** [grep command to confirm the change took effect]

### File: [next file...]
[Same structure]

## Post-Execution Checklist
- [ ] All grep verification commands pass
- [ ] `./run_tests.sh --summary` — no new failures
- [ ] `git diff --stat` — only expected files changed
- [ ] Commit with specific file paths (never git add -A)

## Known Concerns (worker fills this out)
If you notice something that seems wrong but the brief says to proceed, note it here.
This is NOT "STOP and report" (which is for surprising output). This is for design concerns
that don't block execution but should be reviewed at merge time.

Format: `[CONCERN] file:line — description of concern — why I think it might be wrong`
```

## Connection Protocol (MANDATORY for every brief)

Every brief that crosses system boundaries must include a Connection Protocol section. This is what prevents "briefs specify WHAT but not HOW to connect." Read the relevant workflow spec (`<spec corpus root>/workflows/`) for seam contracts and cross-system traps, then `<spec corpus root>/reference/wiring-reference.md` for canonical patterns.

```markdown
## Connection Protocol
- **Component access:** [which pattern for each component — cite wiring-reference.md]
- **EffectContext creation:** Use `create(source, target)` when both are known (status ticks, zone ticks, pickups). Use `from_entity(entity)` when target isn't known yet (triggers, talents). NEVER use `new()` — it leaves source/target/position/stat_container unset. See CLAUDE.md Rule 13.
  Required fields: stat_container, tag_context, skill_ref, rank
  Canonical exemplar: _build_context() at skill_manager.gd:339
- **Error handling:** Required data → push_warning + return. Optional data → silent return.
  [List which data is required vs optional for this brief's changes]
- **Duration/timer pattern:** [StatusTracker duration | SceneTreeTimer | NOT WIRED]
  NEVER use set_meta for expiry timestamps.
- **Consumer trace:** [For each new data write, name the consumer]
  - `metadata[&"key"]` → consumed by [file:line] for [purpose]
  - StatModifier on [stat] → consumed by [pipeline stage] at [file:line]
  - If no consumer exists yet: note "[NO CONSUMER — stored for future .tres composition]"
- **Do NOT copy from:** [List known-broken exemplars if any]
```

Omit lines that don't apply (e.g., no consumer trace if the brief only edits .tres values). But every brief that writes code MUST have component access + EffectContext + error handling specified.

## Brief Quality Rules

1. **Every chosen value has a source tag** — numeric (damage, cooldown, radius), enum member (TargetingMode, ScalingVariable, DamageType), StringName literal (`Tags.FIRE`, `EventTypes.ON_HIT`), condition/selector predicate, tag filter, modifier_type, formula. An untagged choice is an invented choice.

   Valid tags:
   - `[content-spec <file>:<line>]` — cite row in `docs/content/<file>.md` (e.g., `[content-spec unique-affixes.md:235]`)
   - `[REQ-NN-XXX]` / `[AP-NN-XXX]` — cite architecture spec REQ/AP ID (verifiable by grep)
   - `[MD §X.Y]` — cite Master Design section (verifiable by grep)
   - `[USER: <date>, <decision summary>]` — **date REQUIRED. Must correspond to a decision-log entry, baton update, or pasted session quote with date. Bare `[USER]` or `[USER: <scope blurb>]` is banned — it is indistinguishable from invention.**
   - `[DEFAULT: <path>:<line>]` — path must be `docs/content/defaults.md`, `<spec corpus root>/reference/recipes/README.md`, or `<spec corpus root>/reference/content-authoring.md` (all authoritative default sources). **Bare `[DEFAULT]` is banned. If no entry in any of these exists, this is `[UNSPEC'd]`, not `[DEFAULT]`.**
   - `[UNSPEC'd]` — inline use requires a matching Assumptions Made entry naming the gap.
   - `[INFER'd: <adjacent rule cite>]` — high-confidence extrapolation from an adjacent rule in a spec you cited. Inline use requires a matching Assumptions Made entry with rationale.
   - `[PROVISIONAL: <rationale>]` — values that need later review. Inline use requires a matching Assumptions Made entry.
   - `[PRESERVED: <file:line of current value>]` — for fields unchanged by the brief. Does not require an Assumptions Made entry (nothing is being chosen).

   **Format flexibility for annotated tags:** The tags `[INFER'd]`, `[PROVISIONAL]`, `[PRESERVED]`, `[USER]`, `[DEFAULT]` all require an annotation (cite / rationale / date / path:line / file:line). The canonical form is `[TAG: annotation]` with a colon separator — use this form by default. Alternate separators are also accepted: ` from `, ` — `, ` at `. The test is substantive, not syntactic: *is there text after the tag name that names the required annotation?*

   - **PASS** canonical: `[INFER'd: content-authoring.md:2494]`
   - **PASS** alternate: `[INFER'd from content-authoring.md:2494]`
   - **PASS** alternate: `[INFER'd — content-authoring.md:2494]`
   - **FAIL** bare tag with no annotation: `[INFER'd]`
   - **FAIL** annotation present but not the required kind: `[USER: roughly Q2]` (no specific date)

   Substantive requirements (unchanged regardless of separator):
   - `[INFER'd ...]` requires the annotation to name an adjacent rule in a spec actually read by the orchestrator
   - `[USER ...]` requires an explicit date (session-only decisions paste the quote + date)
   - `[DEFAULT ...]` requires the path to be one of: `docs/content/defaults.md`, `<spec corpus root>/reference/recipes/README.md`, or `<spec corpus root>/reference/content-authoring.md`
   - `[AP]` without a REQ/AP ID still FAILs — that is a missing ID, not a separator issue
   - Every non-`[PRESERVED]` annotated tag still requires a matching Assumptions Made entry where the whitelist says so

2. **Every enum integer is resolved by grep output, not by assertion.** For each enum integer written to a `.tres` file, the brief must include in its Field Verification appendix the result of a grep that enumerates the enum members in source-file order and confirms the INDEX of the chosen member. Example for `scaling_rule.gd`'s ScalingVariable enum:
   ```
   $ awk '/enum ScalingVariable/,/}/' systems/stats/scaling_rule.gd
   enum ScalingVariable {
       DAMAGE,          # 0
       SPELL_DAMAGE,    # 1
       ...
       EMPOWER_RATIO,   # 23
   }
   ```
   The brief may not cite an enum integer without pasting the full enum block and counting from 0. "grep confirmed the name exists" is not sufficient — numeric coincidence is not correctness (CLAUDE.md agent-discipline rule 8).

3. **Exact file paths** — not "the skill file" but `resources/skills/SK_fireball.tres`
4. **Exact OLD → NEW** — not "update the damage" but `amount = 100.0 → amount = 0.0` + add ScalingRule
5. **No judgment calls for the worker** — every decision is pre-made by you (the orchestrator)
6. **No "consider" or "if appropriate" language** — mechanical instructions only
7. **Connection Protocol included** — for every brief that writes code (see above)
8. **Every non-cited decision has an Assumption Ledger entry.** If you made a choice the spec doesn't cover and you did not tag it, you invented silently. Re-read the brief and tag every such choice `[UNSPEC'd]`. The Assumptions Made section is where `[UNSPEC'd]` choices live.
9. **No un-cited capability claims.** Any statement about what a system can or cannot do, whether a consumer exists, whether a field is wired, whether an effect is supported — requires an inline citation to the spec line, wiring-reference.md section, or source `file:line` that proves it. "I looked and didn't find it" is not a citation. If you cannot cite, STOP and read. SKILL.md rule 2: "No citation = no claim."
10. **StatModifier briefs must verify formula compatibility.** For every brief that creates or modifies a `StatModifier`:
    1. Identify the target stat name.
    2. Paste the output of `grep -A 2 '<stat_name>' systems/stats/stat_names.gd` showing the stat's `formula` field.
    3. If the formula is `REDUCTION`, the `modifier_type` MUST be `REDUCTION`. Using `INCREASED` / `MORE` / `BASE_ADD` on a REDUCTION-formula stat is a complete silent no-op (`wiring-reference.md` §REDUCTION traps, CLAUDE.md agent-discipline rule 16).
    4. Paste the formula verification line into the brief's Field Verification appendix, adjacent to the modifier_type choice.

## Sizing Briefs

| Scope | Brief size |
|-------|-----------|
| 1-5 files, same pattern | Single brief |
| 6-15 files, mixed patterns | Split into 2-3 briefs by pattern |
| 15+ files | You're writing too many. Stop at 3 briefs, handoff the rest. |

## Dependency Ordering

If briefs have dependencies (e.g., code change before .tres wiring), number them and note prerequisites:
- Brief 1: Code changes (new fields, effect fixes)
- Brief 2: .tres wiring (depends on Brief 1)
- Brief 3: More .tres wiring (depends on Brief 1, parallel with Brief 2)

## Phase Completion

- [ ] `playbooks/phases/implement.md` re-read this session (paste `wc -l` output in each brief's Context Loading scratch block)
- [ ] Matching recipe or content-authoring.md re-read for all Definition classes in briefs
- [ ] All briefs are mechanical — zero judgment, all decisions pre-made
- [ ] Every chosen value (numeric, enum, StringName, predicate, tag filter) has a source tag per Quality Rule 1
- [ ] Every enum integer has a pasted enum block with index counts per Quality Rule 2
- [ ] Every `[USER]` tag cites a decision-log line or pasted conversation quote (bare `[USER]` is banned)
- [ ] Every `[DEFAULT]` tag cites a `docs/content/defaults.md:<line>` (bare `[DEFAULT]` is banned)
- [ ] Every capability claim in the brief is followed by an inline citation per Quality Rule 9
- [ ] Every StatModifier change cites the target stat's formula field and `modifier_type` matches per Quality Rule 10
- [ ] Assumptions Made section reviewed — every `[UNSPEC'd]` surfaced to the user before dispatch
- [ ] No `[RESEARCH NEEDED]` tags — deferred questions routed to `[UNSPEC'd]` in Assumptions Made
- [ ] Briefs saved to `docs/briefs/`
- [ ] Max 3 briefs this session (if more work remains, write a handoff)

**Next:** Proceed to BRIEF-PRE-CHECK (`playbooks/phases/brief-audit.md`) — verify the brief before dispatch.
