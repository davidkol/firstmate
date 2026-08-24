# Design-Pass Playbook

> Read when running a deep-dive interrogation of in-progress design work — typically a draft of `Master-Design.md` or a brief — to validate the design before commit, surface framework-shaped questions, and decide what to commit, defer, or redo.
>
> **What's NOT here:** greenfield design (use `superpowers:brainstorming`); tactical implementation (use `playbooks/implementation.md`); spec authoring from a settled design (use `superpowers:writing-plans` / `verification-author`); orchestrator-driven multi-worker arcs (use `orchestrator` skill).

## What this playbook covers

A **design pass** is a Socratic session that examines an existing design draft (Master Design edit, brief, design proposal) before it lands. The session interrogates whether the draft serves the project's pillars, surfaces the framework-shaped questions, and decides what to commit, defer, or redo.

This playbook codifies the structural pattern that produced the most effective round in the enemy-coordination arc to date — round 4, 2026-05-02 (see `docs/briefs/enemy-coordination/design-r4.md`). The pattern is:

1. **Consultant-skill discipline** (Socratic, big-picture-first, no tactical drift).
2. **A specific structural sequence** (below).
3. **Shared discipline between agent and user** — both have responsibilities.

## When to use

- A non-trivial design draft exists (MD edits in working tree, brief, design proposal).
- Something feels off about the draft but it's not clear what.
- The design is about to be committed and warrants re-examination.
- Multiple prior design rounds didn't converge.
- The user has the sense of "I want to look at this again before we commit."

## When NOT to use

- **Greenfield design** — no draft to push against. Use brainstorming.
- **Tactical implementation work** — different mode entirely. Use orchestrator + worker dispatch.
- **Architecture spec writing from a settled design** — design is done; use writing-plans.
- **Quick clarifying questions about an existing design** — just answer.
- **Active arc coordination** — orchestrator owns that.

## Open with the consultant skill

Invoke the consultant skill explicitly. Default agents drift to tactics; the consultant frame holds the big picture.

**The session opens with one question: what does this deep-dive *produce*?** Pin a deliverable shape: pressure-test for commit / build user's mental model / surface spec-shaped questions / find the broken part. Different deliverables → different conversation shape.

Do NOT bulk-read context, summarize the draft, or list options before the deliverable is named.

## The trajectory

```
DELIVERABLE → TARGETED-READ → ARTICULATE-MODEL → NAME-MENU-IF-FUZZY →
STEP-UP-TO-PILLAR → NAME-PILLAR → CRITIQUE-AGAINST-PILLAR →
SURFACE-ALTERNATIVES → REFRAME → PIN-MODEL → SCOPE-COMMIT-VS-DEFER → CAPTURE
```

Phases ≠ messages. Some collapse into one exchange; others split across several. Order is load-bearing — skipping a step loses leverage downstream.

### 1. DELIVERABLE
"What does this deep-dive produce?" Pin the form before any reading or analysis.

**Pin mode at the same time: framework or content?** Framework-mode = building tools (roles, layers, composition rules; small bounded numbers; commits to MD). Content-mode = filling the roster (specific shapes, abilities, values; large authoring-mode lists).

The conversation shapes differ:
- **Framework-mode** is structural interrogation. Solo work with the agent is fine and is what most design passes should be.
- **Content-mode** is design brainstorming, and **solo brainstorm with the agent is brittle** — the user has stated this explicitly. Defer content-mode work until a designer-on-board is available; don't free-associate content with the agent as a substitute.

If a framework-mode pass starts drifting into content specifics, that's a signal to re-frame or defer — not to start authoring with the agent. Step 11 (SCOPE-COMMIT-VS-DEFER) is where this gets enforced; pinning it here at step 1 prevents the drift.

### 2. TARGETED-READ
Read the diff or the relevant section. **Not** the surrounding material. If the user added something to a doc, read what they added — `git diff <file>` is usually the right command, not `cat <file>`. Avoid reading 5 prior-round files "for context."

### 3. ARTICULATE-MODEL
Ask the user: "Walk me through how X works." If they articulate crisply, the model holds. **If they stall or hand-wave, that's the first finding** — the model isn't actually written down.

### 4. NAME-MENU-IF-FUZZY
If the model is missing or implicit, name the architectural menu the draft assumes. ("'Sensor-driven' is consistent with utility AI, behavior tree, FSM, or hybrid — the draft commits to none.") Forces the spec-shaped question into the open.

### 5. STEP-UP-TO-PILLAR
**The single most important step.** Before going "is this thing well-designed," ask "is this the right thing at all." If you skip this, you'll polish a thing that shouldn't exist. The user must catch this if the agent doesn't — both are responsible for the catch.

In the round-4 enemy session, this step was *the user's*: "we didn't ask if the classes are a good fit for this game." The agent had drifted into class internals. The session pivoted there.

### 6. NAME-PILLAR
Force the pillar to be named **concretely** in the user's words. ("What does combat in Tombhammer want to feel like?") Without a named pillar, every critique floats. The agent should not assume the pillar; the user articulates.

**Concreteness test.** A concrete pillar fills three slots:

1. **Player verb** — what is the player actually doing? ("Reading the board, answering with build + coordination.")
2. **Differentiator** — what's the obvious nearby genre, and what makes this *not* that? ("Between ARPG and MMO pace; questions instead of just density.")
3. **Failure mode** — what happens if the pillar isn't served? ("Otherwise just another boring ARPG.")

If a candidate pillar can't fill all three, it's not concrete enough yet — push back. "Make it interesting," "MMO-shaped," "co-op feel" all fail the test. Coined-on-the-spot phrasing is fine if the slots fill.

In the round-4 session: "co-op puzzle board at ARPG pace, encounters pose questions, party reads the board and answers with build + coordination, otherwise just another boring ARPG."

**Even good pillars compress.** "ARPG pace" was later refined to "between ARPG and MMO pace" — the original phrasing under-specified the differentiator slot. The concreteness test catches this kind of compression; if a slot looks unusually clean, push on it once more before moving on.

### 7. CRITIQUE-AGAINST-PILLAR
Each item in the draft gets a verdict against the pillar, with **specific failure modes and cited precedents.** Not vibes.

**Precedent is required, not optional.** Every verdict names at least one precedent — a game / mechanic / system that tried something close, with what worked or failed and why. ("Conductor — healers in ARPGs are universally feel-bad. PoE Soulrenders, D2 Fanatics. Extends kill-time without adding visceral threat.") If you can't find a precedent, flag the critique as speculative and weight it lower; without precedent, criticism is taste smuggled as authority.

Concrete > abstract. Cited > asserted.

### 8. SURFACE-ALTERNATIVES
Most drafts converge on one approach without examining the menu. Naming alternatives ("no behavior classes; 3 broad classes; classes as Director-only primitives; emergent from skill kit; threat-shapes") un-locks the conversation. The user can't pick a different path if they don't see one.

### 9. REFRAME
Only after the pillar lands. A reframe before the pillar is just another draft. The reframe should fall out of the pillar, not be invented in parallel.

### 10. PIN-MODEL
Before listing content, pin the structural model with a diagram. (`shapes → questions → encounters` before specific shapes.) If you list content first, the model becomes "that list" and you can't iterate on the structure.

**Name cardinality.** Once the model is pinned, name explicit rough numbers per layer (round 4: ~6–8 threat shapes, ~12–20 questions, many authored enemies). Cardinality is what makes a framework feel bounded vs. open-ended. It also forces a useful sort: small bounded numbers (~tens) belong in framework-mode and can commit; large open-ended lists belong in content-mode and defer to authoring with a designer. If you can't name a rough number for a layer, the model probably isn't pinned tightly enough yet.

### 11. SCOPE-COMMIT-VS-DEFER
What does the durable artifact (MD edit, brief) commit to? What does it defer? Framework is committable; specifics usually aren't.

The framework-vs-content distinction was named at DELIVERABLE (step 1); this step is where it gets enforced. What specifics are deferred to content-mode (with a designer-on-board)? Where do they live in the meantime? Many sessions try to backfill specific shapes / abilities / values into a framework-mode pass and end up committing content-shaped material the agent improvised. Resist — if the work that surfaced is content-mode, capture it as deferred (in the brief's "open / deferred to content phase" section) rather than half-authoring it now.

### 12. CAPTURE
Ask the user where the artifacts live and in what form. Don't default to writing. "Nothing" is sometimes right; usually it's a brief + (if the methodology was novel) a playbook update.

## Disciplines

### For the agent

- **Targeted reads only.** No bulk-loading. No "let me read 5 files first."
- **Ask the user to articulate before you explain.** Their stall is the finding.
- **Name the architectural menu when the draft is implicit.** Don't reverse-engineer it silently.
- **Hold the pillar as first-class.** Every concrete proposal: "does this serve the pillar?"
- **Cite precedents or flag as speculative.** Without a precedent, criticism is taste smuggled as authority.
- **Surface alternatives before reframing.** Otherwise the reframe is a new draft.
- **Don't generate lists before pinning the framework.** Lists lock the model.
- **Don't write artifacts before asking where they live.** Form is a real choice.
- **When interrogating a list of candidate items (shapes, archetypes, mechanics), use a kit-pull diagnostic.** Ask: "what player kit-surface does each candidate pull on?" (defensive answer / interrupt / positioning / target-selection / etc.) Two candidates that pull on the same surface are parametric variants of one item, not two — that's the cleanest fold/keep test. Surfaced in r5 of the enemy-coordination arc; reusable across any framework with a named candidate list.
- **After 3+ consecutive verdicts of the same shape (e.g., three "not a shape, fold to X" in a row), explicitly sanity-check the next verdict against the framework principle, not against the prior verdicts.** Pattern-matching produces false confidence. Each candidate gets an independent re-check. Surface the discipline in your prose so the user can see it being applied — silent re-checking reads as silent agreement.
- **Once a diagnostic frame is stable, batch-process remaining candidates.** Don't re-derive the frame per candidate. Watchlist fast-pass at arc end resolves the long-tail in <1 session if the frame holds — see r5's 9-of-9 watchlist resolution after the kit-pull frame stabilized.
- **Expect framework refactor across rounds, not just framework population.** Round-N often surfaces an authoring surface that round-N-1 didn't have (r5 added properties / status-effect-categories / composition-patterns alongside r4's "shapes only"). Treat the framework's own surface inventory as iterable, not fixed. Avoid committing the round-N framework as final-form until at least one subsequent round has verified no new surfaces emerge.

### For the user

- **Push back when the agent asks the wrong question.** "Tick-level isn't useful, I don't know the model" is the right move when the agent presupposes a model that doesn't exist.
- **Step up when conversation drifts to tactics.** "We didn't ask if the classes are a good fit" was the most leveraged user move in the round-4 session.
- **Name the pillar concretely.** Don't leave "MMO-shaped" or "interesting" or "fun" vague — those float.
- **Distinguish tool-building from content-authoring scope.** Some sessions are about the framework; the specific roster is for later. The agent can confuse these silently.
- **Recognize when a session pattern is working — and capture it.** This playbook only exists because the user named the pattern after one good session.
- **Solo design-pass arcs are slow.** Without a designer present, design-space judgment has to be reconstructed via Socratic interrogation rather than spoken from designer experience. The enemy-coordination arc took ~5 rounds across roughly a week of sessions. Acceptable for stress-testing the methodology and producing a framework; not standard practice. When a designer is on board, expect arc length to compress dramatically — much of what the agent surfaces by interrogation, the designer can name directly. Plan accordingly: solo arcs should be reserved for stress-tests and framework-bootstrap; routine design work waits for designer availability.
- **When codifying a rule from an anti-pattern observation, expect the rule's resting place to be soft, not hard.** First-draft formulations of design rules tend to be categorical ("never X"); the user's revision tends to add a soft form ("X permitted but reserved for Y context"). The hard form catches the anti-pattern; the soft form admits the legitimate exceptions. Don't fight the softening — it's the rule reaching its true shape. r5 example: "threat-increasing-only buffs" softened to "threat-reducing buffs reserved for major-threat carriers" (heals/shields permitted but rare, on Elite/Boss with prominent presentation).

## Anti-patterns

- **Validating internals before validating fit.** Polishing a thing that shouldn't exist.
- **"Let me read everything first."** Tactical disguised as thoroughness.
- **Reframing before the pillar is named.** New draft, not deep dive.
- **Generating lists before the framework is pinned.** Locks model to list.
- **Committing to MD before the framework is solid.** The diff has to be unwound.
- **Treating "deep-dive" as license for research mode.** Different mode.
- **Defending an existing draft because it's already written.** Sunk-cost.
- **Hand-waving the pillar.** "Make it interesting" / "MMO-shaped" — concretize or you can't critique.
- **Free-associating content with the user.** The user said it explicitly: "It's harder for me to free-associate when it's just me talking to an AI." Solo brainstorm is brittle. If the work needs designer brainstorm, defer it; if it needs frame-setting, do that.
- **Treating quantitative claims in the draft as ground truth.** Agents fabricate magnitude (kill-time tiers, density limits, window durations, percentages) with confidence; numbers calcify across rounds and end up driving fit-filter work. Verify provenance before using a tier number as filter — ungrounded magnitudes are `[UNSPEC'd]`, not constraints. Pacing especially is content-dependent and shouldn't be framework-pinned at all. Memory pin: `feedback_invented_quantities_in_design_drafts.md`.
- **Treating round-N's framework structure as the final framework.** The framework's own surface inventory iterates round-by-round, not just its content. r4 had "shapes only"; r5 surfaced 3 more first-class authoring surfaces (properties, status-effect categories, composition patterns). If round-N+1 surfaces a new surface, the round-N framework was incomplete, not wrong. Build in headroom — defer "framework is final" judgment until a subsequent round has confirmed no new surfaces emerge.
- **Categorical-rule fundamentalism.** Codifying an anti-pattern observation as a hard "never X" rule when the user's intent is "X usually fine, in this specific context anti-pattern." Expect the user to soften categorical rules to admit context-specific exceptions; don't treat the soft form as weakness or compromise — it's the rule reaching the right shape. Match user intent: hard rules where they want hard rules, soft rules where the anti-pattern is context-dependent.

## Signs you're drifting

- "Let me give you a comprehensive list of options" — you stopped pushing back.
- "Here's how we'd implement X" — you're in tactics, not design.
- "The draft says Y; let me just refine it" — you stopped asking about fit.
- The user is taking notes from your output — they're consuming, not thinking.
- You're reading more than 1–2 files between user messages.
- You haven't asked a hard question in 3+ exchanges.
- The session has produced more text than decisions.

## Worked example — enemy-coordination round 4 (2026-05-02)

| Phase | What happened |
|---|---|
| DELIVERABLE | User picked: build mental model + surface spec-shaped questions |
| TARGETED-READ | Agent read `git diff docs/Master-Design.md` only (~400 lines of diff, not the whole file) |
| ARTICULATE-MODEL | Agent asked for tick-level walkthrough of an Aggressor; user replied "I don't even know the model" — surfaced the architectural gap in one exchange |
| NAME-MENU-IF-FUZZY | Agent named utility AI / behavior tree / FSM / hybrid as the implicit menu |
| STEP-UP-TO-PILLAR | **User caught it**: "we didn't ask if the classes are good fit." Single most leveraged move of the session. |
| CRITIQUE-AGAINST-PILLAR | Per-class verdicts with cited precedents (PoE Soulrenders, D2 Fanatics, mana-drain hate, 2D-stealth limits) |
| SURFACE-ALTERNATIVES | No classes; 3 broad classes; Director-only tags; emergent from skill kit; threat-shapes |
| NAME-PILLAR | User articulated: "co-op puzzle board, MMO-shaped questions, otherwise boring ARPG" |
| REFRAME | Roles → threat shapes (one possible reframe, accepted; the Summoner pattern was the in-draft template) |
| PIN-MODEL | Three layers: shapes → questions → encounters. Multi-shape questions committed. |
| SCOPE-COMMIT-VS-DEFER | Framework committed; specific shape/question lists deferred to content phase ("we're not at content phase yet, we're building tools") |
| CAPTURE | Two artifacts — design-r4 brief + this playbook |

**Outcome:** 7-class draft in MD working tree superseded; brief written; methodology captured. User's assessment: "the most effective [pass] since the first one. Very well refined compared to the other ones which kinda narrowly focused and led us here."

### Subsequent rounds (r5, 2026-05-02 → 2026-05-03)

The arc continued for one more round (r5) which used the same trajectory but contributed three new disciplines now codified in the agent-disciplines section:

- **Kit-pull diagnostic** as a named tool for shape-vs-parameter judgment — surfaced during Striker resolution when 5 prior-art clusters disagreed on the fix; reframing as "what player kit-surface does it pull on" produced clean resolution.
- **Streak-guard** — when 3+ consecutive verdicts resolve the same way, sanity-check next verdict against framework not prior verdicts. Surfaced after three "not a shape, fold to X" verdicts in a row (Targeted, Soaker, Tether).
- **Framework refactor across rounds** — r5 surfaced 3 first-class authoring surfaces (properties, status-effect categories, composition patterns) that r4's "shapes only" framing missed. The framework's surface inventory iterated, not just its content.

Plus the watchlist fast-pass pattern (9-of-9 single-cluster candidates resolved in one continuation pass once the kit-pull frame stabilized — 8 folded to existing structures, 1 cut as anti-pattern).

After the framework landed in MD, the user softened one categorical rule ("threat-increasing-only buffs" → "threat-reducing buffs reserved for major-threat carriers") — codified in agent-discipline #softening-rules-resting-place. The hard form caught the anti-pattern; the soft form admitted the legitimate exceptions.

**Arc cost:** ~5 rounds across roughly a week of solo design-pass sessions. User's verdict: acceptable for stress-testing the methodology and producing a stable framework, but not a shape that should repeat — future arcs should have a designer present.

## Cross-references

- `superpowers:brainstorming` — for greenfield design (use first if no draft exists)
- `consultant` skill — the Socratic discipline this playbook composes with
- `playbooks/implementation.md` — for tactical implementation after a design pass settles
- `docs/playbooks/verifier-design.md` — sibling playbook style; reference for format
