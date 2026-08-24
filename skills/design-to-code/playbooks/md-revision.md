# MD Revision — Playbook

> Read when revising `docs/Master-Design.md` after a cold-read audit, design-pass review, or any other revision pass. Codifies the three disciplines that govern MD revision: what bar to apply (ground-truth), how prose should sound (design-voice not spec-voice), and when to commit vs hold in working tree.
>
> **What's NOT here:** greenfield MD authoring (no prior draft to revise — use `superpowers:brainstorming` then `design-pass`); spec authoring from a settled MD section (use `superpowers:writing-plans`); cold-read audit phase itself (use `design-pass` Socratic interrogation pattern).

## When to use

- Cold-read audit found drift / ambiguity / wrong-refs in an MD section and a revision pass is queued.
- Design-pass session converged on a draft and revisions need to land in MD.
- An MD section has accumulated multiple revision passes within one session and the commit-cadence question has arisen.
- Author cold-reading their own MD and iterating on prose.

## When NOT to use

- Single typo fix (just commit normally).
- Worker-merge bookkeeping (commits are how merges land).
- Distinct logical units that warrant separate commits per concern.
- Spec edits (`<spec corpus root>/**`) — different bar, different voice. Specs carry `[INFER'd]` / `[UNSPEC'd]` tags; MD does not.

## The three disciplines

A complete MD revision pass applies three disciplines in sequence:

1. **Ground-truth bar** — what to fix in this pass (and what to defer)
2. **Design-voice prose** — how the fixed prose should sound (not spec-shaped)
3. **Commit cadence** — when to commit vs hold revisions in working tree

Skipping any one of the three breaks the pattern.

---

## 1. Ground-truth bar: no contamination in source-of-truth

The bar for MD revisions is **"no contamination accumulating in ground-truth"** — NOT "ready for the next worker / arc / Move to consume." Fix every drift, ambiguity, wrong cross-ref, and undefined term in the same revision pass before commit. Defer only pure stylistic items.

### Why

MD is the decision-hierarchy root. Citations from specs, briefs, code, content, and tests all reference back. **Fixing too late is a nightmare** because by then N downstream artifacts cite the bad MD prose, and unwinding requires touching everything that touched the source. The cheapest moment to fix any MD issue is before the first downstream artifact references it; cost-to-fix grows roughly with the number of downstream consumers.

### How to apply: triage findings into two buckets

| Bucket | What goes in it | Action |
|---|---|---|
| **Drift / ambiguity / wrong-ref** | Terminology drift between sections; undefined terms used as if formal; cross-refs pointing at wrong targets; asserted-but-not-defined levers; presuppositions a cold reader can't recover; prose drift between MD and the brief that authored it | Fix in the same revision pass before commit |
| **Pure style** | Sub-numbering for addressability; cross-ref placement/voice; redundant-but-consistent statements (same fact stated twice without contradiction); prose flow polish | Defer to a dedicated MD style sweep |

The agent's failure mode is framing a revision pass as "what's ready for the next consumer" — which biases toward shipping the contaminating items because they'd be caught downstream. **Wrong frame:** downstream catch is *expensive cleanup*, not *successful verification*.

This bar applies specifically to **MD-as-ground-truth**. Looser bars apply elsewhere:
- Test code: "good enough if tests pass."
- Briefs: agent-facing, can carry `[INFER'd]` markers and stylistic looseness.
- Specs with `[INFER'd]` / `[UNSPEC'd]` tags: explicit ambiguity is sometimes the correct state.

**Provenance:** s71 director-design r1 revision pass 2 (2026-05-04). After cold-read audit on MD §5.2 director framework surfaced 2 CRITICAL + 7 MEDIUM + 15 LOW findings, agent fixed only 2 CRITICAL + 4 MEDIUM in first revision pass and framed the rest as "defer to user's MD sweep." User correction: *"MD is supposed to be ground truth so we shouldnt let anything in there that can cause any issues now or in the future, because fixing it too late is a nightmare."* 12 of remaining 19 items got fixed in pass 2; 4 deferred as pure-style. Pass 2 commit `1fc5914c`.

---

## 2. Design-voice prose: MD is intent + cross-refs, not inline mechanism

When revising MD, agent default-mode generates **spec-shaped prose**: inline disambiguations between similarly-named axes, parenthetical structure-payload definitions, formula explainers, and "call this X / call this Y" pipeline-stage labels. These look ugly in a design document and migrate detail that belongs one layer down.

### Why

MD is design-voice — intent, constraints, cross-refs to the layers below. Spec is where mechanism lives (formulas, named variables, pipeline stages, payload structure, axis disambiguation). When MD has to carry precision because spec hasn't been written yet, agent prose drifts into spec-territory. The drift is invisible to the agent (it reads as "being precise") but ugly to a designer reading prose-flow.

### Concrete drift examples (s71 director-design r1)

- **Inline axis disambiguation:** `"difficulty tier (Easy / Medium / Hard per §3.4.7 — distinct from the Normal / Elite / Boss enemy tier axis in §3.6)"` — the `(distinct from...)` parenthetical belongs in §3.4.7 and §3.6 directly, not inline at every cross-reference.
- **Parenthetical formula breakdowns:** `"(per_spend_budget = base_per_spend × spend_multiplier; spend_multiplier per §5.3.1.2; base_per_spend [UNSPEC'd])"` — three semicolon-separated variable scopings inside a sentence parenthetical. Belongs in spec.
- **"Call this X" stage labeling:** `"For parametric templates, cost is computed after the Director's parameter roll (call this **instantiation**), not at the selection step (call this **draw**)"` — pipeline-stage naming inline. Belongs in spec.
- **Structure-payload specs:** `"(per-template entries with timestamp + the template's constituent-shape composition)"` — data structure description in a design doc. Belongs in spec.

### How to apply

- **Prefer high-level intent prose.** Use cross-refs to anchor precision: `(§5.3.1.2)` for the formula, `(§3.4.7)` for the difficulty axis, etc.
- **Avoid inline mechanism**: parenthetical formula breakdowns, "call this X" labeling, structure-payload specs in MD prose.
- When precision is genuinely required and no spec exists yet to migrate it to, **keep it but flag for post-spec reword sweep.**
- Watch for the agent's "let me be precise" instinct — that's the signal that spec-shape is creeping in.

**Provenance:** s71 director-design r1 (2026-05-04). User flagged the pattern explicitly twice during the same session: round 1 — *"im noticing a bit of a trend in these MD edits that agents make that look basically like spec, that might be ok but we should consider this for rewording after we write spec"*; round 2 — *"theres a lot of these additions that are like explainers or tags within parens or w/e ... they might be worth keeping but look ugly as hell for this design document."* User's mode: keep precision now (no spec to migrate it to), reword in design-voice after spec lands.

---

## 3. Commit cadence: hold revisions in working tree during multi-pass iteration

When a session does multiple revision passes against a freshly-landed MD section (cold-read audit → revise → re-audit → revise loop), **don't auto-commit each pass**. Hold revisions in working tree until the user signals they want to advance state.

### Why

Each commit creates a boundary the user has to span when reading "what changed since the framework landed." Three commits in one session means `git diff <baseline>..HEAD` is the only way to read the cumulative state — per-commit diffs are noisy with author intermediate states. Holding uncommitted lets `git diff` show exactly the pending changes for a single clean read pass.

### How to apply

- **First commit:** when the substantive design unit lands (e.g., the framework pin from a design-pass session). Commit normally.
- **Revision passes after that:** hold in working tree by default. Tell the user "fixes uncommitted, here's the diff to read."
- **Commit when user signals:** `"commit"`, `"squash and commit"`, `"looks good"`, `"push"`, or after they've explicitly read and approved.
- **If the user doesn't comment for several rounds**, ask whether to commit or keep holding — don't default to either.
- **Squash-on-request:** if user wants the per-pass commits collapsed into a single revision-pass commit, propose interactive rebase or amend-stack (destructive operation, ask first per CLAUDE.md rule).

### Counter-pattern: committed too eagerly

s71 director-design r1, 2026-05-04. After three revision-pass commits accumulated in a single session (`daf61212` pass 1, `1fc5914c` pass 2, `1ee321d2` pass 3), user noted *"annoying that it got committed because now i cant see just the diff easily."* For passes 4+5, agent held all revisions uncommitted; user read working tree directly and signaled closure with *"i think its good enough now."*

### Where this applies vs does not apply

| Applies | Does NOT apply |
|---|---|
| Multi-pass revision cycles on freshly-landed MD / specs / briefs | Single-edit fixes (commit normally) |
| Cold-read audit + revision loops | Worker-merge bookkeeping (commits are how merges land) |
| Author cold-reading + iterating on prose | Distinct logical units (separate commits per concern is correct) |

---

## Putting it together: a complete MD revision pass

```
1. AUDIT INPUT → list of findings (drift / ambiguity / style)
2. TRIAGE      → split into "fix now" vs "defer to style sweep" per Discipline 1
3. REVISE      → fix every "fix now" item in design-voice per Discipline 2
4. HOLD        → keep revisions in working tree per Discipline 3 (unless single-edit)
5. PRESENT     → "fixes uncommitted, here's the diff to read"
6. COMMIT      → on user signal ("commit", "looks good", "push")
```

If a revision pass skips the triage (jumps straight to revise), the deferred-style items contaminate the same commit as the load-bearing fixes — the user reads a diff that mixes substance with style and loses signal.

If a revision pass skips design-voice (writes spec-shaped prose), the MD section accumulates parenthetical mechanism that will need cleanup after the corresponding spec lands.

If a revision pass auto-commits each iteration, the cumulative diff becomes harder to read and the user spans more commit boundaries than necessary.

---

## Reference artifacts

- **Memory pins (source material):** `feedback_md_ground_truth_bar.md`, `feedback_md_design_voice_not_spec_voice.md`, `feedback_hold_revisions_during_iteration.md` (all retained in `~/.claude/projects/-Users-davidkol-projects-Godot-Tombhammer/memory/` as backups for this playbook).
- **Design-pass playbook (sister discipline):** `playbooks/design-pass.md` — the Socratic interrogation pattern that produces the audit findings this playbook consumes.
- **Master Design:** `docs/Master-Design.md` — the artifact this playbook governs revisions to.
- **Decision hierarchy:** `<spec corpus root>/reference/decision-hierarchy-workflow.md` — Design → Spec → Code, and why MD-as-ground-truth matters.
