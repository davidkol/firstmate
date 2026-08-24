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

Nothing installs this shelf yet, and firstmate itself does not load it.
This remains T0 documentation carriage because the public shelf is inactive in this repository.
`AGENTS.md` declares `skills/` installer-facing and not loaded by firstmate, and `.claude/skills` resolves to `../.agents/skills` rather than `skills/`.
No installer for this shelf exists under `bin/`; `bin/fm-test-run.sh` recognizes generic `skills/*` changes only to select contract validation.
No executable seam, build artifact, or runtime behavior changed.

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

## Unresolved dependencies

The carried files reference material that was deliberately not carried.
Those references remain as written so the source process is visible, while this bounded ledger names the target-provided paths, commands, tools, and execution capabilities that the carried text instructs an agent to read, write, or execute.
The ledger does not cover illustrative mentions, prose references, or names that appear only inside a worked example.
Its 75 in-scope entries come from the 79-token annotated derivation in `.no-mistakes/evidence/dependency-sweep.txt`.
The full derivation also retains all four items judged out of scope and gives a one-clause reason for each judgment, so no candidate silently disappears from review.

### Method

The `METHOD` block in `.no-mistakes/evidence/dependency-sweep.txt` enumerates the 16 carried Markdown files and emits every uncarried path-shaped or command-shaped candidate found by its mechanical passes.
It strips trailing `:N` and `:N-M` line citations before extension matching, normalizes declared shared owners and aliases, and records every candidate on its own annotated `IN` or `OUT` line.
A fixed-string pass records each candidate's carried file-and-line use sites, while the annotation states the read, write, or execute verb and a one-clause boundary reason.
The sweep has no exclusion bucket.

### Agent and command capabilities

- **[EXECUTE]** Agent or subagent execution capability - `playbooks/phases/dispatch.md:82`, `playbooks/phases/dispatch.md:121`, `playbooks/phases/implement.md:126`, `playbooks/phases/implement.md:134`, `playbooks/phases/review.md:7`, `playbooks/phases/verify.md:9`, `playbooks/phases/verify.md:11`, `playbooks/phases/verify.md:43`, `playbooks/phases/verify.md:91`.
- **[EXECUTE]** Git command capability - `playbooks/design-pass.md:63`, `playbooks/md-revision.md:91`, `playbooks/implementation.md:23`, `playbooks/phases/brief.md:85`, `playbooks/phases/implement.md:142`, `playbooks/phases/review.md:26`, `playbooks/phases/review.md:27`, `playbooks/phases/review.md:34`, `playbooks/phases/review.md:41`, `playbooks/phases/review.md:42`, `specialist-protocol.md:103`.
- **[READ, EXECUTE]** Grep command or tool capability - `consultant.md:22`, `consultant.md:114`, `playbooks/bug-handling.md:60`, `playbooks/bug-handling.md:68`, `playbooks/bug-handling.md:90`, `playbooks/bug-handling.md:92`, `playbooks/bug-handling.md:139`, `playbooks/bug-handling.md:143`, `playbooks/bug-handling.md:154`, `playbooks/phases/brief-audit.md:21`, `playbooks/phases/brief-audit.md:25`, `playbooks/phases/brief-audit.md:29`, `playbooks/phases/brief-audit.md:62`, `playbooks/phases/brief-audit.md:105`, `playbooks/phases/brief.md:17`, `playbooks/phases/brief.md:19`, `playbooks/phases/brief.md:21`, `playbooks/phases/brief.md:29`, `playbooks/phases/brief.md:77`, `playbooks/phases/brief.md:83`, `playbooks/phases/brief.md:149`, `playbooks/phases/brief.md:159`, `playbooks/phases/brief.md:170`, `playbooks/phases/design.md:79`, `playbooks/phases/design.md:106`, `playbooks/phases/implement.md:60`, `playbooks/phases/implement.md:61`, `playbooks/phases/implement.md:84`, `playbooks/phases/research.md:77`, `playbooks/phases/research.md:78`, `playbooks/phases/research.md:79`, `playbooks/phases/research.md:90`, `playbooks/phases/research.md:101`, `playbooks/phases/research.md:102`, `playbooks/phases/review.md:70`, `playbooks/phases/review.md:108`, `playbooks/phases/spec.md:46`, `playbooks/phases/spec.md:67`, `specialist-protocol.md:12`, `specialist-protocol.md:91`, `specialist-protocol.md:109`, `specialist-protocol.md:121`, `specialist-protocol.md:221`, `specialist-protocol.md:227`.
- **[READ, EXECUTE]** Find command capability - `playbooks/bug-handling.md:155`.
- **[READ, EXECUTE]** `wc -l` command capability - `playbooks/phases/brief.md:15`, `playbooks/phases/brief.md:55`, `playbooks/phases/brief.md:191`.
- **[READ, EXECUTE]** `ls` command capability - `playbooks/phases/brief.md:17`.
- **[READ, EXECUTE]** `awk` command capability - `playbooks/phases/brief.md:151`.
- **[READ]** Agent `Read` tool capability - `consultant.md:22`, `specialist-protocol.md:12`.
- **[READ]** Agent `Glob` tool capability - `consultant.md:22`.
- **[EXECUTE]** Agent `Bash` tool capability - `consultant.md:22`.

### Verifiers, tests, and runtime tools

- **[EXECUTE]** `.regime/venv/bin/python3` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- **[EXECUTE]** `.regime/verifiers/v_brief_precheck_v3.py` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- **[WRITE]** `.regime/verifiers/` - `playbooks/bug-handling.md:103`.
- **[EXECUTE]** `./run_tests.sh` - `playbooks/bug-handling.md:100`, `playbooks/phases/brief.md:84`, `playbooks/phases/review.md:40`, `specialist-protocol.md:67`, `specialist-protocol.md:102`.
- **[EXECUTE]** MCP `game_eval` - `playbooks/bug-handling.md:100`, `playbooks/phases/review.md:79`, `playbooks/phases/review.md:83`, `playbooks/phases/review.md:101`, `playbooks/phases/review.md:182`.

### External skills and role configs

- **[EXECUTE]** `superpowers:brainstorming` - `playbooks/design-pass.md:5`, `playbooks/design-pass.md:204`, `playbooks/md-revision.md:5`.
- **[EXECUTE]** `superpowers:writing-plans` - `playbooks/design-pass.md:5`, `playbooks/md-revision.md:5`.
- **[EXECUTE]** `verification-author` - `playbooks/design-pass.md:5`.
- **[EXECUTE]** The target project's callable `consultant` skill - `playbooks/design-pass.md:5`, `playbooks/design-pass.md:13`, `playbooks/design-pass.md:33`, `playbooks/design-pass.md:35`, `playbooks/design-pass.md:205`.
- **[READ, EXECUTE]** `.claude/skills/orchestrator/`, including its `SKILL.md` and `delegation-frame.md` - `consultant.md:88`, `playbooks/design-pass.md:5`, `playbooks/implementation.md:5`, `playbooks/implementation.md:31`, `playbooks/implementation.md:46`.
- **[READ]** `.claude/specialists/`, including each `<system>.md` config - `playbooks/implementation.md:29`, `playbooks/implementation.md:47`, `playbooks/phases/dispatch.md:8`, `playbooks/phases/dispatch.md:59`, `playbooks/phases/dispatch.md:60`.

### Source-project context registry

- **[READ]** `.claude/skills/dvs/SKILL.md` - `consultant.md:75`.
- **[READ]** `.claude/skills/pes/` - `consultant.md:83`.
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

- **[READ]** `.agent/rules/gdscript-style.md` - `playbooks/implementation.md:51`.
- **[READ]** `.agent/task-guides.md` - `playbooks/implementation.md:52`.
- **[READ, EXECUTE]** `docs/playbooks/verification.md` - `playbooks/implementation.md:5`, `playbooks/bug-handling.md:5`, `playbooks/bug-handling.md:38`, `playbooks/bug-handling.md:69`, `playbooks/bug-handling.md:72`, `playbooks/bug-handling.md:73`, `playbooks/bug-handling.md:90`, `playbooks/bug-handling.md:170`.
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

- **[READ, WRITE]** `docs/Master-Design.md` - `consultant.md:57`, `playbooks/bug-handling.md:161`, `playbooks/md-revision.md:3`, `playbooks/md-revision.md:138`, `playbooks/phases/brief.md:33`, `playbooks/phases/research.md:14`.
- **[READ, WRITE]** `docs/content/` - `consultant.md:92`, `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:163`, `playbooks/phases/brief.md:32`, `playbooks/phases/brief.md:74`, `playbooks/phases/brief.md:124`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- **[READ]** `docs/content/defaults.md` - `consultant.md:92`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- **[WRITE]** `defaults.md` - `playbooks/phases/spec.md:59`.
- **[READ, WRITE]** `docs/briefs/` - `playbooks/phases/brief.md:202`, `playbooks/phases/dispatch.md:28`, `playbooks/phases/dispatch.md:131`, `playbooks/phases/research.md:79`.
- **[READ]** `docs/inventory/refresh-1/SUMMARY.md` - `playbooks/bug-handling.md:156`, `playbooks/bug-handling.md:164`.
- **[READ]** `docs/audits/2026-04-05-engine-perfection-audit.md` - `playbooks/phases/research.md:8`.
- **[WRITE]** `docs/content-pipeline/templates/README.md` - `playbooks/phases/implement.md:166`.
- **[READ, WRITE]** `<spec corpus root>` and its instructed descendants - `consultant.md:58`, `consultant.md:59`, `consultant.md:60`, `consultant.md:61`, `playbooks/bug-handling.md:26`, `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:157`, `playbooks/bug-handling.md:162`, `playbooks/bug-handling.md:165`, `playbooks/bug-handling.md:166`, `playbooks/implementation.md:17`, `playbooks/implementation.md:20`, `playbooks/implementation.md:39`, `playbooks/implementation.md:48`, `playbooks/implementation.md:49`, `playbooks/implementation.md:50`, `playbooks/md-revision.md:19`, `playbooks/md-revision.md:139`, `playbooks/phases/brief.md:17`, `playbooks/phases/brief.md:19`, `playbooks/phases/brief.md:52`, `playbooks/phases/brief.md:59`, `playbooks/phases/brief.md:60`, `playbooks/phases/brief.md:98`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/design.md:58`, `playbooks/phases/implement.md:71`, `playbooks/phases/implement.md:112`, `playbooks/phases/implement.md:164`, `playbooks/phases/implement.md:165`, `playbooks/phases/research.md:9`, `playbooks/phases/research.md:15`, `playbooks/phases/research.md:16`, `playbooks/phases/research.md:52`, `playbooks/phases/research.md:78`, `playbooks/phases/research.md:107`, `specialist-protocol.md:152`, `specialist-protocol.md:154`.
- **[READ]** `event-types.md` - `specialist-protocol.md:230`.

### Memory pins

- **[READ]** `~/.claude/projects/-Users-davidkol-projects-Godot-Tombhammer/memory/` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_check_content_spec_layer.md` - `playbooks/phases/brief.md:36`.
- **[READ]** `feedback_hold_revisions_during_iteration.md` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_invented_quantities_in_design_drafts.md` - `playbooks/design-pass.md:155`.
- **[READ]** `feedback_md_design_voice_not_spec_voice.md` - `playbooks/md-revision.md:136`.
- **[READ]** `feedback_md_ground_truth_bar.md` - `playbooks/md-revision.md:136`.

### Target-project code and content roots

- **[READ]** `docs/` - `playbooks/phases/design.md:79`, `playbooks/phases/spec.md:67`.
- **[READ]** `systems/` - `playbooks/bug-handling.md:92`, `playbooks/phases/design.md:79`, `playbooks/phases/research.md:77`.
- **[READ]** `entities/` - `playbooks/bug-handling.md:92`, `playbooks/phases/research.md:77`.
- **[READ]** `resources/` - `playbooks/bug-handling.md:92`, `playbooks/phases/spec.md:67`.
- **[READ]** `tests/` - `playbooks/phases/brief.md:31`, `playbooks/phases/spec.md:67`.
- **[READ, EXECUTE]** `systems/stats/scaling_rule.gd` - `playbooks/phases/brief.md:151`, `playbooks/phases/implement.md:62`.
- **[READ, EXECUTE]** `systems/stats/stat_names.gd` - `playbooks/phases/brief.md:170`.
- **[READ]** `deal_damage_effect.gd` - `playbooks/phases/verify.md:58`.
- **[READ, EXECUTE]** `systems/effects/types/` - `playbooks/phases/brief-audit.md:23`.
