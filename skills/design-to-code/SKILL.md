---
name: design-to-code
description: Use when taking a change from design intent through spec, brief, dispatch, review, and handoff, or when running a Socratic design pass over a design document, revising a design document after an audit, or handling a reported bug. Carries a working design-to-code playbook chain from a shipping game project so another project can adopt the same phase discipline.
user-invocable: true
---

<!-- maintainers: every file under playbooks/, plus consultant.md and specialist-protocol.md, is carried near-verbatim from another repository. Do not reword, reformat, or restyle their bodies. The repo one-sentence-per-line rule is waived for them by explicit captain instruction; it applies to this file. -->

# Design to code

This is a working process, not a designed-for-reuse framework.

Every file beside this one is carried near-verbatim from `Tombhammer`, a private Godot ARPG project, at pinned commit `99809956ffaa0a68d9681e6edff3d11e60347a57`, carried on 2026-08-23.
It was written over months of real use on that one project and it reads that way: the worked examples, the cited precedents, and the past-session war stories are all from that project and are all deliberately intact, because the concrete shape is the part that teaches.

Five general kinds of substitution were made in a carried file: the project name where it was the subject of a rule, the project's absolute path, the engine and language where a rule named them, the spec corpus path, and internal cross-references repointed at this directory's layout.
The captain also authorized a narrow standing removal rule on 2026-08-23 for carried lines that destroy uncommitted or unlanded work or write false provenance or attribution into an adopter's records.
The cleanup command in `playbooks/phases/review.md` applies the first class by omitting the original `--force` token.
The original cleanup line was the following.

```text
3. Clean up: `git worktree remove --force .wt/<name> && git branch -d <branch>`
```

The merge command in `playbooks/phases/review.md` applies the second class by omitting the original model co-author trailer.
The original trailer line was the following.

```text
Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

The captain separately authorized one pointer repoint on 2026-08-24 so `playbooks/phases/brief.md` proceeds to BRIEF-PRE-CHECK at `playbooks/phases/brief-audit.md` instead of skipping to HANDOFF.
This one-off authorization is not a standing-rule class or precedent, and another self-contradiction in carried text requires a new captain decision.
The original pointer line was the following.

```text
**Next:** Proceed to HANDOFF — update bookkeeping and summarize for the user.
```

No other carried prose was reworded, reordered, condensed, or generalized.

Firstmate does not load this shelf: `AGENTS.md` declares `skills/` installer-facing and not loaded by firstmate, and `.claude/skills` resolves to `../.agents/skills` rather than `skills/`.
The shelf is installable standalone through external skill-installer discovery like any other entry under `skills/`, as `README.md` documents for the skills.sh `npx skills add` installer.
This is T1 public-contract carriage because the installer-facing skill changes agent behavior even though no firstmate runtime, build artifact, or executable code changed.

## What a target project must supply

The carried text leaves two placeholders that a target project fills in for itself.

- `<the project's language>` - the implementation language rules are stated against.
- `<spec corpus root>` - the directory holding the per-system specifications, workflow specs, and reference material.
  In the source project this was `docs/architecture/`, with `systems/`, `workflows/`, and `reference/` beneath it.
  The carried text preserves that internal structure below the placeholder, because the distinctions between those three are load-bearing in the prose.

A third placeholder, `<the project>`, appears where a rule named the source project as its subject.
The target project also supplies its own `consultant` skill and its own per-system specialist configs under `.claude/specialists/`.
`specialist-protocol.md` is the carried shared protocol that `playbooks/phases/dispatch.md` names as `.claude/specialists/_protocol.md`.
The carried text assumes that the target project's default branch is literally named `main`.

## The chain

The implementation loop runs in this order, one file per phase under `playbooks/phases/`.

```
SCOPE -> RESEARCH -> DESIGN -> SPEC -> BRIEF -> BRIEF-PRE-CHECK -> DISPATCH -> REVIEW -> HANDOFF
```

`playbooks/implementation.md` is the entry point and owns that loop.
Three sibling playbooks cover the other arcs: `playbooks/design-pass.md` for a Socratic pass over a design document, `playbooks/md-revision.md` for revising that document after an audit, and `playbooks/bug-handling.md` for reported bugs.
`consultant.md` and `specialist-protocol.md` carry the two source-project role descriptions, but they do not register the target project's callable skill or specialist configs.

## Known ambiguity

Reading A treats the chain in `playbooks/implementation.md:10` as strictly sequential.
Under that reading, `playbooks/phases/implement.md` launches workers and proceeds directly to REVIEW, while `playbooks/phases/dispatch.md` can fall back to BRIEF, so either route can bypass BRIEF-PRE-CHECK.
Reading B treats specialist DISPATCH and direct BRIEF as alternatives because `playbooks/phases/dispatch.md:8-14` explicitly presents them that way.
Under that reading, the linear arrow diagram in `playbooks/implementation.md:10` is a compression rather than a strict order, and the carried text is coherent.
The carried text does not settle which reading is correct.
Adopters should decide which reading applies to their project.
No carried line was changed to resolve this ambiguity.

## Unresolved dependencies

The carried files reference material that was deliberately not carried.
Those references remain as written so the source process is visible, while this self-contained ledger names the 82 target-provided paths, commands, tools, skills, and execution capabilities that the carried text instructs an agent to read, write, or execute.
The derivation records every found candidate before assigning an `IN` or `OUT` boundary judgment, preserves raw aliases and their use sites, and strips trailing `:N` or `:N-M` citations only after the cited token is retained.
Items judged out of scope remain annotated with reasons in the pipeline evidence rather than disappearing before review.

### Agent, verifier, and runtime capabilities

- **[EXECUTE]** `./run_tests.sh` - `playbooks/bug-handling.md:100`, `playbooks/phases/brief.md:84`, `playbooks/phases/review.md:40`, `specialist-protocol.md:67`, `specialist-protocol.md:102`.
- **[EXECUTE]** `.regime/venv/bin/python3` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- **[WRITE]** `.regime/verifiers/` - `playbooks/bug-handling.md:103`.
- **[EXECUTE]** `.regime/verifiers/v_brief_precheck_v3.py` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- **[EXECUTE]** MCP `game_eval` - `playbooks/bug-handling.md:100`, `playbooks/phases/review.md:79`, `playbooks/phases/review.md:83`, `playbooks/phases/review.md:101`, `playbooks/phases/review.md:182`.
- **[EXECUTE]** Subagent or parallel-worker execution capability - `playbooks/phases/dispatch.md:82`, `playbooks/phases/dispatch.md:121`, `playbooks/phases/implement.md:126`, `playbooks/phases/implement.md:134`, `playbooks/phases/review.md:7`, `playbooks/phases/verify.md:9`, `playbooks/phases/verify.md:11`, `playbooks/phases/verify.md:43`, `playbooks/phases/verify.md:91`.
- **[EXECUTE]** `superpowers:brainstorming` - `playbooks/design-pass.md:5`, `playbooks/design-pass.md:204`, `playbooks/md-revision.md:5`.
- **[EXECUTE]** `superpowers:writing-plans` - `playbooks/design-pass.md:5`, `playbooks/md-revision.md:5`.

### Agent rules, skills, and role configs

- **[READ]** `.agent/rules/gdscript-style.md` - `playbooks/implementation.md:51`.
- **[READ]** `.agent/task-guides.md` - `playbooks/implementation.md:52`.
- **[READ]** `.claude/skills/dvs/SKILL.md` - `consultant.md:75`.
- **[READ, EXECUTE]** `.claude/skills/orchestrator/` - `consultant.md:88`.
- **[READ, EXECUTE]** `.claude/skills/orchestrator/SKILL.md` - `playbooks/implementation.md:5`.
- **[READ]** `.claude/skills/orchestrator/delegation-frame.md` - `playbooks/implementation.md:31`, `playbooks/implementation.md:46`.
- **[READ]** `.claude/skills/pes/` - `consultant.md:83`.
- **[READ]** `.claude/specialists/` - `playbooks/implementation.md:29`, `playbooks/implementation.md:47`, `playbooks/phases/dispatch.md:8`, `playbooks/phases/dispatch.md:59`, `playbooks/phases/dispatch.md:60`.
- **[READ]** `.claude/specialists/_protocol.md` - `playbooks/phases/dispatch.md:59`.

### Source-project context registry

- **[READ]** `docs/briefs/dvs-flywheel-component-2-handoff.md` - `consultant.md:66`.
- **[READ]** `docs/briefs/dvs-flywheel-component-2-session-{1,2,3}-handoff.md` - `consultant.md:67`.
- **[READ]** `docs/briefs/dvs-flywheel-component-2-session-3-analysis.md` - `consultant.md:68`.
- **[READ]** `.flywheel/dvs/calibration-set.ndjson` - `consultant.md:69`.
- **[READ]** `.flywheel/dvs/calibration-set-unlabeled.ndjson` - `consultant.md:70`.
- **[READ]** `.flywheel/dvs/scope.yaml` - `consultant.md:71`.
- **[READ]** `scripts/flywheel/` - `consultant.md:72`.
- **[READ]** `docs/superpowers/specs/2026-04-08-design-verification-system.md` - `consultant.md:76`.
- **[READ]** `docs/superpowers/specs/2026-04-12-dvs-flywheel-adapter-design.md` - `consultant.md:77`.
- **[READ]** `docs/research/pes-v2-viability-review.md` - `consultant.md:80`.
- **[READ]** `docs/research/pes-v2-*.md` - `consultant.md:81`.
- **[READ]** `docs/validation/tdd-spec-rework.md` - `consultant.md:82`.
- **[READ]** `docs/superpowers/specs/2026-03-23-content-spec-system-design.md` - `consultant.md:93`.
- **[READ]** `docs/briefs/enemy-coordination/design-r4.md` - `playbooks/design-pass.md:11`.
- **[READ]** `docs/content-pipeline/README.md` - `consultant.md:91`.

### Target-project guides and sibling playbooks

- **[READ]** `design-pass.md` - `playbooks/bug-handling.md:5`, `playbooks/bug-handling.md:41`.
- **[READ]** `implementation.md` - `playbooks/bug-handling.md:5`, `playbooks/bug-handling.md:39`.
- **[READ, EXECUTE]** `verification.md` - `playbooks/bug-handling.md:5`, `playbooks/bug-handling.md:38`, `playbooks/bug-handling.md:69`, `playbooks/bug-handling.md:72`, `playbooks/bug-handling.md:73`, `playbooks/bug-handling.md:90`.
- **[READ, EXECUTE]** `docs/playbooks/verification.md` - `playbooks/implementation.md:5`, `playbooks/bug-handling.md:170`.
- **[READ]** `docs/playbooks/verifier-design.md` - `playbooks/design-pass.md:207`, `playbooks/implementation.md:22`.
- **[READ]** `docs/playbooks/auditing.md` - `playbooks/bug-handling.md:173`.
- **[READ]** `docs/playbooks/agent-coordination.md` - `playbooks/bug-handling.md:172`.

### PM and current-state corpus

- **[READ, WRITE]** `docs/baton.md` - `consultant.md:86`, `playbooks/phases/handoff.md:7`.
- **[READ, WRITE]** `docs/pm/queue.md` - `playbooks/bug-handling.md:41`, `playbooks/bug-handling.md:168`.
- **[READ, WRITE]** `BACKLOG.md` - `consultant.md:87`, `playbooks/bug-handling.md:167`, `playbooks/phases/handoff.md:15`, `playbooks/phases/review.md:50`, `playbooks/phases/review.md:64`, `playbooks/phases/review.md:185`.
- **[READ, WRITE]** `PROJECT_STATE.md` - `playbooks/phases/handoff.md:14`, `playbooks/phases/review.md:55`, `playbooks/phases/review.md:64`, `playbooks/phases/review.md:186`, `playbooks/phases/verify.md:108`.
- **[READ, WRITE]** `MEMORY.md` - `consultant.md:63`, `playbooks/phases/verify.md:108`.
- **[READ]** `CLAUDE.md` - `consultant.md:62`, `consultant.md:119`, `playbooks/implementation.md:5`, `playbooks/md-revision.md:99`, `playbooks/phases/brief.md:103`, `playbooks/phases/brief.md:159`, `playbooks/phases/brief.md:171`, `playbooks/phases/implement.md:148`, `playbooks/phases/verify.md:56`, `specialist-protocol.md:260`.

### Design, spec, content, and inventory documents

- **[READ]** `Master-Design.md` - `playbooks/design-pass.md:3`.
- **[READ, WRITE]** `docs/Master-Design.md` - `consultant.md:57`, `playbooks/bug-handling.md:161`, `playbooks/md-revision.md:3`, `playbooks/md-revision.md:138`, `playbooks/phases/brief.md:33`, `playbooks/phases/research.md:14`.
- **[READ]** `BigDesignReference.md` - `playbooks/bug-handling.md:163`.
- **[READ]** `docs/reference/_archive/` - `playbooks/bug-handling.md:163`.
- **[READ, WRITE]** `docs/content/` - `consultant.md:92`, `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:163`, `playbooks/phases/brief.md:32`, `playbooks/phases/brief.md:74`, `playbooks/phases/brief.md:124`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- **[READ]** `docs/content/*.md` - `playbooks/bug-handling.md:153`.
- **[READ]** `docs/content/defaults.md` - `consultant.md:92`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- **[WRITE]** `defaults.md` - `playbooks/phases/spec.md:59`.
- **[READ]** `content-authoring.md` - `playbooks/phases/brief.md:136`, `playbooks/phases/brief.md:137`, `playbooks/phases/brief.md:138`, `playbooks/phases/implement.md:134`, `playbooks/phases/implement.md:188`, `playbooks/phases/research.md:56`.
- **[READ]** `recipes/README.md` - `playbooks/phases/research.md:56`.
- **[READ]** `wiring-reference.md` - `playbooks/phases/brief.md:171`, `playbooks/phases/research.md:57`.
- **[READ, WRITE]** `docs/briefs/` - `playbooks/phases/brief.md:202`, `playbooks/phases/dispatch.md:28`, `playbooks/phases/dispatch.md:131`, `playbooks/phases/research.md:79`.
- **[READ]** `docs/inventory/refresh-1/SUMMARY.md` - `playbooks/bug-handling.md:156`, `playbooks/bug-handling.md:164`.
- **[READ]** `docs/audits/2026-04-05-engine-perfection-audit.md` - `playbooks/phases/research.md:8`.
- **[WRITE]** `docs/content-pipeline/templates/README.md` - `playbooks/phases/implement.md:166`.
- **[READ]** `event-types.md` - `specialist-protocol.md:230`.

### Memory pins

- **[READ]** `.claude/projects/-Users-davidkol-projects-Godot-Tombhammer/memory/` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_check_content_spec_layer.md` - `playbooks/phases/brief.md:36`.
- **[READ]** `feedback_hold_revisions_during_iteration.md` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_invented_quantities_in_design_drafts.md` - `playbooks/design-pass.md:155`.
- **[READ]** `feedback_md_design_voice_not_spec_voice.md` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_md_ground_truth_bar.md` - `playbooks/md-revision.md:136`.

### Target-project code and content roots

- **[READ]** `docs/` - `playbooks/phases/design.md:79`, `playbooks/phases/spec.md:67`.
- **[READ]** `systems/` - `playbooks/bug-handling.md:92`, `playbooks/phases/design.md:79`, `playbooks/phases/research.md:77`.
- **[READ]** `systems/*.md` - `consultant.md:59`.
- **[READ]** `systems/08-status-system.md` - `specialist-protocol.md:154`.
- **[READ, WRITE]** `systems/NN-*.md` - `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:162`, `playbooks/implementation.md:20`, `playbooks/implementation.md:49`, `playbooks/phases/research.md:16`.
- **[READ]** `entities/` - `playbooks/bug-handling.md:92`, `playbooks/phases/research.md:77`.
- **[READ]** `resources/` - `playbooks/bug-handling.md:92`, `playbooks/phases/spec.md:67`.
- **[READ]** `tests/` - `playbooks/phases/brief.md:31`, `playbooks/phases/spec.md:67`.
- **[READ, WRITE]** `SK_*.tres` - `playbooks/bug-handling.md:22`, `playbooks/phases/review.md:8`.
- **[READ, WRITE]** `XX_*.tres` - `specialist-protocol.md:221`.
- **[READ, EXECUTE]** `scaling_rule.gd` - `playbooks/phases/brief.md:149`.
- **[READ, EXECUTE]** `systems/stats/scaling_rule.gd` - `playbooks/phases/brief.md:151`, `playbooks/phases/implement.md:62`.
- **[READ, EXECUTE]** `systems/stats/stat_names.gd` - `playbooks/phases/brief.md:170`.
- **[READ]** `deal_damage_effect.gd` - `playbooks/phases/verify.md:58`.
- **[READ, EXECUTE]** `systems/effects/types/` - `playbooks/phases/brief-audit.md:23`.
