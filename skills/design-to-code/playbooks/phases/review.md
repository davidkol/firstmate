# Phase: REVIEW

After workers complete. Merge, verify, update bookkeeping.

## Content Batch Size Limit

**Max ~10 skills per audit/authoring agent.** Session 83 TDD testing proved that cold agents get every skill right when given focused attention, but miss bugs at 67 files per batch. The docs are sufficient — the failure mode is attention degradation at volume. When dispatching content work:
- Audit batches: max 10 SK_*.tres per agent
- Authoring batches: max 5 new .tres per agent
- Brief writing: max 5 skills per brief

## BDR Clause Diff (MANDATORY for .tres work)

Before declaring any .tres skill PASS or complete, split its BDR entry into numbered clauses. Every clause must map to at least one effect or field in the .tres. Example:

```
BDR: "Occult Sacrifice: Cost - 1 Black. [1] Sacrifice your weakest minion [2] to generate 2 Black Marks."
  [1] → SlayEntityEffect + WeakestSelector(MINION)  ✓
  [2] → GenerateResourceEffect(black, 2)             ✓
```

If a clause has no mapping: mark the skill `[PARTIAL]` and add the missing clause to BACKLOG. **Do NOT silently drop clauses.** Session 83 found ~12 skills where secondary BDR clauses were silently omitted during rewiring.

## Before Merging ANY Branch

1. **`git diff --stat main..<branch>`** — count files. If scope looks wrong, STOP.
2. **Spot-check 2-3 key files** with `git show <branch>:<file>` — verify changes match the brief
3. **No extra files, no reverted changes** — if diff shows unexpected files, investigate

## Merge Protocol

One workstream at a time:
```bash
git merge <branch> --no-ff -m "merge: [summary]

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

After EACH merge:
1. `./run_tests.sh --summary` — verify no new failures
2. `git diff --stat HEAD~1` — verify the merge looks right
3. Clean up: `git worktree remove --force .wt/<name> && git branch -d <branch>`

## Merge Conflicts

Expected when parallel workers branch from the same base. Resolve by keeping both sides — changes shouldn't overlap if research identified file boundaries correctly. If they DO overlap, investigate before resolving.

## Bookkeeping (AFTER EVERY MERGE, not at session end)

**BACKLOG.md:**
- Mark resolved items with `~~RESOLVED~~`
- Add any new items discovered during implementation
- Update "Last updated" date

**PROJECT_STATE.md:**
- Update system status if it changed
- Update key metrics (test count, .tres count, etc.)
- Update "Last updated" date

**These get forgotten if deferred.** The rule is: update after EVERY merge, immediately.

**Timing distinction:**
- **Single worker:** Update bookkeeping immediately after merge.
- **Parallel workers:** Do NOT update PROJECT_STATE.md or BACKLOG.md until ALL worktrees are merged. Editing shared bookkeeping files while worktrees are outstanding risks merge conflicts and stale data.

## Consumer Trace Verification (MANDATORY for code changes)

For every merge that includes code changes (not just .tres edits), verify at least ONE data flow end-to-end:

1. **For each new metadata key written** (`context.metadata[&"key"] = value`): grep for the consumer. If no consumer exists, the worker should have noted `[NO CONSUMER YET]` in their Concerns section.
2. **For each new EffectContext creation site**: verify `stat_container` and `tag_context` are populated (or explain why not).
3. **For each .tres with stat modifiers**: verify modifier_type matches the stat's formula (REDUCTION stats need type 3).
4. **For each new `set_meta()` call**: verify a corresponding `get_meta()` exists in production code.

This catches the class of bugs where "the writer side works but nobody reads the data" — responsible for 10+ permanently broken timed effects and the EffectContext scaling bug across 42 reactive skills.

## Runtime Testing (MANDATORY for .tres-heavy merges — NO EXCEPTIONS)

After merging .tres-heavy workstreams, use MCP `game_eval` to verify at least 2-3 representative changes actually work at runtime. The test suite does NOT test .tres content correctness — "3236 tests pass" means the build is clean, not that content is correct.

Pick: one skill from each pattern type changed (reactive, zone, projectile). Load it. Fire it. Verify behavior matches the brief.

**Session 83 finding: ALL 34 content bugs found in the BDR quality audit would have been caught by casting each skill once.** Zero sessions across sessions 77-82 used game_eval despite this phase requiring it. This is not optional. If the editor is not available for game_eval, note `.tres runtime confidence: UNVERIFIED` in the baton and flag it for the next session.

**Minimum runtime checks per .tres merge:**
- Does the skill fire? (not silently no-op)
- Does it target the right entity? (enemies, not self)
- Does the damage/heal amount look reasonable? (not 0, not flat when should scale)

## Review Common Mistakes

| Mistake | Fix |
|---------|-----|
| Skip diff stat check | Every merge, `git diff --stat`, every time |
| Trust worker's "tests pass" claim | Run tests yourself on main after merge |
| Defer bookkeeping to session end | Items get forgotten. Update immediately. |
| Merge without spot-checking files | Read 2-3 key files. Workers miss things. |
| Merge all workstreams then test | Merge one, test, merge next. Isolates failures. |
| Trust "tests pass" as correctness | Tests verify BUILD, not CONTENT. .tres errors pass all tests. |
| Skip consumer trace | Every new data write needs a verified reader. |
| Skip runtime testing for .tres | MCP game_eval on 2-3 representative changes. |

## Decision Encoding Verification (MANDATORY for design sessions)

If this session made design decisions (had a Decision Surface with user-decided items), verify each decision is encoded as a prescriptive REQ/AP in the relevant spec — not just descriptive updates.

For each decision from the Decision Surface:
1. Grep the target spec for the REQ/AP ID from the Decision → REQ/AP mapping
2. Read the REQ/AP text — does it **prescribe** the chosen approach AND **prohibit** the rejected alternative?
3. If only descriptive changes landed (table rows, field additions) but no prescriptive REQs/APs → add them before closing the session

**Why:** Session 64 merged code + descriptive spec changes but missed all prescriptive REQs/APs. The decisions were implemented in code but not encoded in specs. A future author could legally use the rejected approach. Caught only by post-merge audit.

## Worker Concern Review

Before proceeding to verification, review any `[CONCERN]` tags in worker reports. These are design-level observations workers made during execution. For each concern:
- Is it a real issue? → Add to verification scope or fix now
- Is it a known tradeoff? → Note it in the merge commit or handoff
- Is it wrong? → Dismiss with a brief explanation

Do NOT ignore concerns. Workers flagged them because something felt wrong — that instinct is usually correct. The retrospective found multiple cases where workers self-censored issues that later became bugs.

## Worker Deviation Review

Workers that deviate from the brief report it in their completion summary. Every deviation must be categorized before merge — deviations are data about brief quality AND signal about latent issues.

### Three buckets

**Invention** — worker made a decision the brief didn't give them.
- Action: REJECT. Revert the invented change. Either add the decision to the brief (and re-dispatch) or resolve it with the user. Never merge silent inventions.
- Example: brief says "14 callers", worker finds 15th and migrates it WITHOUT flagging — that's invention, not catch.

**Legit catch** — worker found something the brief missed, surfaced it, used an unambiguous mechanical pattern.
- Action: ACCEPT and learn. Note what the brief-audit phase missed. Worker caught a blind spot.
- Example: 15th caller found via wider grep, worker applies canonical pattern + flags it in completion report. Merge as-is.

**Semantic change** — the brief's mechanical instruction caused a behavior change the brief didn't anticipate.
- Action: ACCEPT + carry to baton. Semantic changes are usually latent bug fixes or tradeoffs that deserve future attention. Tests passing is necessary but not sufficient — the change may affect untested paths.
- Example: metadata merge-vs-overwrite change that preserves pre-populated knockback fields. Behavior is more correct, tests green, but the delta matters for future work. Record in baton.

### Categorization protocol

For each deviation in the worker's completion report:

1. **Ask**: did the worker have a decision to make, or was there one right answer?
   - Decision → Invention. Reject.
   - One right answer → Legit catch or Semantic change.
2. **Ask**: did the behavior change, or did only the code structure change?
   - Code-only → Legit catch. Merge.
   - Behavior-changed → Semantic change. Merge + baton entry.
3. **Record** semantic changes in baton with: what changed, why worker made the call, what future work might surface.

### Anti-patterns

| Anti-pattern | Reality |
|--------------|---------|
| "Tests pass, deviation is fine" | Tests cover known paths. Semantic change needs explicit categorization. |
| "Worker is experienced, trust the judgment" | Workers follow briefs mechanically. Any judgment applied = invention unless explicit. |
| "I'll remember this for later" | Semantic changes decay from memory. Write to baton immediately. |
| "All three deviations are improvements, merge as-is" | Maybe — but only after categorizing each one explicitly. |

## Verification Confidence Self-Assessment

Before proceeding to verify.md, rate your confidence (1-5) on these dimensions:

| Dimension | Confidence | Notes |
|-----------|-----------|-------|
| Code compiles and tests pass | ? | |
| Logic correct for happy path | ? | |
| Null/missing data handled correctly | ? | |
| Cross-system data flow complete (writer → consumer) | ? | |
| .tres content will work at runtime | ? | |
| No existing patterns broken | ? | |

**If any dimension is ≤ 2:** that dimension needs targeted verification in the verify phase. Don't proceed hoping the verification agent catches it — direct the agent to check that specific dimension.

## Phase Completion

- [ ] Every merge: diff stat checked, 2-3 files spot-checked
- [ ] Consumer trace done for code changes (at least one flow per workstream)
- [ ] Worker [CONCERN] tags reviewed and addressed
- [ ] Runtime testing done for .tres-heavy merges (MCP game_eval, 2-3 changes)
- [ ] Tests pass on main after all merges (same or fewer failures than baseline)
- [ ] All worktrees cleaned up
- [ ] BACKLOG.md updated — resolved items marked
- [ ] PROJECT_STATE.md updated if meaningful changes
- [ ] No uncommitted changes on main
- [ ] Recipe created/updated if implementation introduced a novel .tres pattern
- [ ] content-authoring.md updated if implementation added new fields
- [ ] Confidence self-assessment completed — low dimensions noted for verify phase

**MANDATORY NEXT STEP:** Read `playbooks/phases/verify.md` and launch adversarial verification. Do NOT skip this. Do NOT claim work is complete without verification.
