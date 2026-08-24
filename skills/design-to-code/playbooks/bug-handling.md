# Bug Handling — Playbook

> Read by orchestrator when the active arc is bug-finding or bug-fixing (a queue item, a BACKLOG row, an inventory finding, a user-reported defect). Routes bugs into the right mode and dispatches accordingly.
>
> **What's NOT here:** general feature implementation uses `implementation.md`. Verification-regime work uses `verification.md`. Design-call resolution uses `design-pass.md`. This playbook routes bugs INTO those playbooks; it doesn't replace them.

## The two-axis layer model

Bugs live on one or both of two axes. Each axis has three layers: designer-authored intent, agent-authored requirements, implementation.

```
MECHANIC AXIS                CONTENT AXIS
(how systems work)           (what's in the game)

MD         (designer) §      BDR          (designer)
  ↓                            ↓
Spec       (agent)    ⚙      Content Spec (agent)    ❖
  ↓                            ↓
Code (.gd)                   Content (.tres)
```

Mechanic axis covers rules, formulas, stat behavior, system contracts. Content axis covers what skills/items/effects/enemies/maps exist with what values. Cross-axis bugs (`L_cross`) live at boundaries — e.g., a `SK_*.tres` (content) referencing an effect class (mechanic) that doesn't exist; system A and system B disagreeing about a signal contract; a stat formula consuming a content-defined default.

## Authority chain

**Authority resolves by *concern* — the layer that owns the decision — not by naive layer-rank. The authoritative rule is the authority map in `<spec corpus root>/reference/intent-pyramid.md` §Authority resolution; this playbook does not keep its own copy.** The common case is the simple one and is all most fixes need: designer-authored intent (MD / BDR) is the oracle over agent-authored requirements (Spec / Content Spec), which are the oracle over implementation (Code / .tres). Consult the map when that isn't enough — e.g. a newer **CEO-ratified** decision conflicting with an older source (the newer ratified one is current; the older is stale). And carry the map's core rule into every fix: **a contradiction between layers is a defect to repair, not a fork to build past** — surface it, the CEO determines design calls, the stale layer gets updated to agree; build to the current decision only in the interim. Resolve by concern there rather than re-deriving authority here.

**Spec / Content Spec are agent-authored — trust by default, re-ground on signal.** Re-grounding triggers: (a) hit a contradiction between layers, (b) a bug suggests the agent-layer is wrong, (c) a better solution surfaces than what was specified. When in doubt: walk upstream to MD or BDR.

**Between axes: MD and BDR are peers.** MD covers mechanics; BDR covers content. They share boundaries but aren't nested. Conflicts at a boundary are design calls — both are designer-authoritative, only CEO can resolve.

## The 4 modes

A session runs in exactly one mode. Output type is the gate: a session producing none of these outputs is drifting and should STOP.

| Mode | Output | When to use | Handler |
|------|--------|-------------|---------|
| **A: AUDIT/SWEEP** | LIST → BACKLOG or queue | Find unknown bugs across a corpus; verify spec/code/content alignment; orphan-finding; cascade-shape enumeration | This playbook §Mode A operational + `verification.md` for oracle-test sweeps |
| **B: SINGLE-BUG FIX** | COMMIT against one BACKLOG row | Known bug, one layer, one axis, fix scoped | `implementation.md` |
| **C: CASCADE FIX** | COMMITS across N instances of one shape | Same bug shape at ≥3 sites | This playbook §Mode C operational |
| **D: DESIGN-CALL** | DESIGN DECISION → MD or BDR updated (handoff = `docs/pm/queue.md` entry; CEO ratifies inline via Author decision fields) | Designer layer silent, self-contradictory, OR being challenged (author tiebreak on a previously-settled design call); needs CEO ratify | `design-pass.md` |

Mode A outputs get `axis:` and `suggested-mode:` tags so downstream pickers (PM, orchestrators) route them without re-classifying.

## Triage routing — the forcing-question chain

Orchestrator runs this in research phase to pick mode + fix-layer. Same questions on both axes; run both if the bug touches both.

1. **Which axis(es) does this bug live on?**
   - Mechanic-only (rule, formula, stat behavior, system contract)
   - Content-only (missing skill, wrong default, stale field, orphan .tres)
   - Cross-axis (content references missing mechanic; mechanic depends on content not authored)
2. **For each affected axis, walk the chain:**
   - **Mechanic:** Does MD speak? → Does Spec match MD? → Does Code match Spec?
   - **Content:** Does BDR speak? → Does Content Spec match BDR? → Does .tres match Content Spec?
3. **First layer that doesn't satisfy upstream = the layer to fix:**
   - Designer-layer silent, self-contradictory, or being challenged (author tiebreak on a previously-settled design call) → **Mode D** (CEO ratifies)
   - Agent-layer doesn't match designer-layer → **Mode B targeting agent-layer** (align Spec or Content Spec to MD or BDR)
   - Implementation doesn't match agent-layer → **Mode B targeting implementation** (the default case)
4. **Cascade check (always last):** grep for the shape across the codebase. ≥3 instances → upgrade to **Mode C.**

**Cross-axis Mode D special case:** when a bug's symptom is on one axis but the blocking design call lives on the OTHER axis (e.g., content references a mechanic-axis behavior class that doesn't exist yet), Mode D targets the axis where the design needs to land, not where the symptom appears. "Layer required but not yet authored" is also Mode D — same trigger as silent, distinct framing.

## Mode A operational

Two peer sweep mechanisms depending on detection method:

- **Grep-based sweep (this playbook).** Use when the bug shape is structurally detectable via pattern matching — silent no-ops, stale refs, enum-shift in .tres, cascade shape across N sites, orphan files. Dispatch AUDIT-only workers in worktrees. Brief specifies: axis + corpus scope, pattern to match, classification criteria, output format. Output: BACKLOG entries with `axis:` and `suggested-mode:` tags. No fix work in same session.
- **Oracle-test sweep (`verification.md`).** Use when detection requires running code against a spec assertion — invariant violation, behavioral drift, contract mismatch. Use the verification regime's existing flow (slice → triage → briefs → workers → findings). Findings tagged `structural-bug` become BACKLOG entries routed back through this playbook for fix-mode dispatch.

**Cross-feeds:**
- Verification cascade findings (≥3 same-shape) → either promote to mechanical verifier (`verification.md` §verifier-substrate work) OR route to Mode C cascade fix.
- Grep sweep can't determine "broken or working as intended" → route to verification.md to author an oracle test that decides.

**Sweep worker brief MUST include:** AUDIT-only stop condition (no edits to code/.tres), file:line citation for every classified entry, classification criteria (true cascade instance vs. coincidence), output format (BACKLOG entry template — see below).

**BACKLOG row template for Mode A output:**

```
- [ ] {bug-shape name} — {one-line surface}
  axis: mechanic|content|cross
  suggested-mode: B|C|D
  evidence: file.gd:42, file.gd:78  (grep-verified)
  blocks: {other BACKLOG row, if applicable}
  notes: {1-line context}
```

**Adjacent findings during sweep:** if a sweep surfaces bugs outside the scope card (orphan-in-the-other-direction, secondary cascades, unrelated drift), file them as separate BACKLOG rows with their own `axis:` + `suggested-mode:` tags. Do NOT widen the scope card. Original sweep scope is preserved; new findings tracked separately.

**Cascade detection during sweep:** name the shape as a one-line pattern, grep across the appropriate corpus, count instances. ≥3 → BACKLOG entry tagged Mode C. Recurring shapes across waves → promote to mechanical verifier per `verification.md`.

**Default cascade-grep corpus:** mechanic-axis bugs grep across `systems/` + `entities/`; content-axis bugs grep across `resources/`; cross-axis grep both. A within-system 2-instance pattern is below the global ≥3 threshold but worth filing as a system-scoped cascade for tracking — note `scope: system-NN` in the BACKLOG row.

## Mode C operational

For cascade fixes (≥3 sites of one shape):

- **Brief shape:** one worker brief lists all N sites with file:line citations + cascade shape name + spec/MD anchors + the fix pattern (what changes per site).
- **Worker discipline:** fix all N sites in one session; run full-suite after each site or batched; verify each fix passes oracle test if one exists.
- **Verification:** `./run_tests.sh --summary` after fix; for behavioral cascades, `game_eval` confirms behavior changed at one representative site.
- **Don't partial-fix.** If one site is harder than expected, STOP and file remaining sites as new BACKLOG entries with the same cascade tag — don't merge a partial cascade fix.

Promoted cascade shapes (recurring across waves) get a mechanical verifier in `.regime/verifiers/` so future occurrences are caught at sweep time.

## Output discipline

Every bug-handling session ends with one of:
- **LIST** — BACKLOG rows added, queue items routed, dispositions filed
- **COMMIT** — N commits against M BACKLOG rows (typically M=1 for Mode B, M=N for Mode C)
- **DESIGN DECISION** — MD or BDR section edited, CEO ratified, downstream Mode B/C work queued

No LIST, no COMMIT, no DECISION → the session is drifting. STOP and report what shape the work actually had so the next session can route correctly.

## Mid-session mode shifts — STOP

The dominant failure mode in prior sessions: user pulls orchestrator from Mode B (fix a bug) into Mode D (design exploration). Orchestrator stays in B-shape doing D-work. Both axes contaminated.

Discipline:
- **Mode B → Mode D:** file the design question in the BACKLOG row, STOP, hand off to PM. A new session in Mode D resolves it.
- **Mode A → Mode B:** file the fix-ready BACKLOG row, STOP. A new Mode B session executes.
- **Mode B → Mode C:** if cascade detected mid-session, STOP, re-scope brief to all N sites. Don't try to fix one and "come back for the others."
- **Open Mode D blocks dependent Mode B/C.** When triage surfaces both a Mode D design call AND dependent Mode B/C work (e.g., spec is `[UNSPEC'd]`; the fix needs defaults the design call sets; a cascade is at 3/3 but blocked by an open MD question), file the dependent rows tagged `blocks: <Mode-D-row-id>` so they surface automatically post-resolve, but do NOT dispatch them until Mode D resolves. Dispatching concurrently re-creates mode-mixing.

Mode shift = STOP regardless of who initiated it (user-pull or agent-realization). The agent has STOP triggers when challenged but not when followed — this rule covers the followed case.

## Roles

- **CEO** ratifies Mode D outputs (MD or BDR edits). Only CEO signs off on designer-layer changes.
- **PM** routes findings into BACKLOG / queue with general scope (axis + suspected mode); dispatches orchestrators; surfaces Mode D items. PM does not micro-tag modes — orchestrator's research phase does that.
- **Orchestrator** drives one mode end-to-end. Research phase classifies (axis, layer, mode, cascade). Dispatch + review per mode. Bounces a session if the mode shifts.
- **Worker** executes one row of one mode. Single-bug scope by default; Mode C briefs are wider but still one shape.

## Anti-patterns

Codified failure modes from prior sessions and cross-session evidence:

- **Mode-mixing.** One orchestrator session doing triage + fix + design exploration. The `mvp-bug-triage` session spent its full window on Q1 mixing all three; Q2-Q4 never touched.
- **Find-and-fix composite.** "I'll find the bug AND fix it in one session." Cross-session evidence: list-producing sessions ship reliably; fix-producing sessions on contested specs drift or STOP. Decouple find from fix.
- **Treating cascade as singleton.** A bug that looks like a one-off often has N siblings. Always grep-check the shape before scoping the fix.
- **Pre-digesting narrow single-bug briefs.** Narrow fix briefs are HARDER to author correctly than wide sweep briefs — orchestrator must author MD/spec citations correctly, which is the same skill that produced the original bug. Wider briefs that classify-then-route ship more reliably than per-bug case files.
- **Auto-trusting agent-layer.** Spec / Content Spec are agent-authored. When implementation and agent-layer disagree, default is "implementation wrong" — but verify agent-layer is upstream-aligned before treating it as oracle.
- **Drift while followed.** Agent has STOP triggers when challenged but not when user follows agent's escalation. Mode-shift discipline catches this: when mode changes, session ends regardless of who's leading.
- **Fabrication under load.** Recent example: cited "5 .tres files reference both X and Y" via grep-disjunction (`X\|Y`) read as conjunction. Every file:line citation gets a grep verify before it lands in a brief.
- **Multi-session bug-walk contamination.** Session N reads session N-1's research file, inherits its framing/errors, propagates. Mitigation: each session starts cold from BACKLOG row + MD/BDR + Spec/Content Spec; doesn't inherit prior-session research artifacts.

## Read order for cold-start

When attaching with a bug to handle:

1. This playbook (axis model, modes, triage chain).
2. The BACKLOG row or queue item — what's the surface symptom and any tags? **Treat queue/BACKLOG framing as a starting point, not authority.** Descriptions compress and paraphrase (e.g., "BDR names X explicitly" may mean BDR names the *behavior*, not the exact string the .tres uses); always re-read the cited MD/BDR/spec section before accepting the framing.
3. The owning MD section (mechanic axis) and/or BDR entry (content axis).
4. The owning Spec (`<spec corpus root>/systems/NN-*.md`) and/or Content Spec (`docs/content/*.md`).
5. The code surface via `grep` for the named function/class.
6. The content surface via `find` for the named .tres files.
7. `docs/inventory/refresh-1/SUMMARY.md` — skim if the bug appears in top buckets (silent-no-op family, save/load gaps, content corpus gaps). Skip if the bug is fully anchored by queue + spec + code.
8. *(conditional)* `<spec corpus root>/reference/wiring-reference.md` — only if the bug looks like a cross-system / wiring shape.

## Reference artifacts

- **Master Design:** `docs/Master-Design.md`
- **Architecture Specs:** `<spec corpus root>/systems/NN-*.md`
- **Content Specs:** `docs/content/` (basic-skills, character-definitions, contracts, counters, defaults, gem-definitions, map-definitions, minion-definitions, objectives, pickup-definitions, skills-hybrid-classes, skills-pure-classes, skills-specializations, unique-affixes, wave-configurations) — canonical content reference; superseded `BigDesignReference.md` (archived at `docs/reference/_archive/`) per Phase 4 archive 2026-05-18
- **Inventory findings:** `docs/inventory/refresh-1/SUMMARY.md`
- **Wiring reference:** `<spec corpus root>/reference/wiring-reference.md`
- **Decision hierarchy:** `<spec corpus root>/reference/decision-hierarchy-workflow.md`
- **BACKLOG:** `BACKLOG.md`
- **Decision queue:** `docs/pm/queue.md`
- **Implementation playbook:** `playbooks/implementation.md`
- **Verification playbook:** `docs/playbooks/verification.md`
- **Design-pass playbook:** `playbooks/design-pass.md`
- **Agent coordination:** `docs/playbooks/agent-coordination.md`
- **Auditing playbook:** `docs/playbooks/auditing.md` — upstream source of Mode A AUDIT/SWEEP findings + `axis:` + `suggested-mode:` BACKLOG row tags. Bug-handling consumes audits' typed verdicts; audits do not fix.
