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

Only five kinds of substitution were made in a carried file: the project name where it was the subject of a rule, the project's absolute path, the engine and language where a rule named them, the spec corpus path, and internal cross-references repointed at this directory's layout.
Nothing else was reworded, reordered, condensed, or generalized.

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
Those references are left exactly as written rather than stubbed or deleted, so nothing about the original process is silently lost.
The ledger below records the 57 normalized target-provided dependencies from the mechanical sweep at `.no-mistakes/evidence/dependency-sweep.txt`.

### Method

The sweep enumerated the 16 carried Markdown files, then used `rg -ni` over each file to collect path-shaped references and nonstandard command, tool, and skill invocations.
It normalized descendants of `<spec corpus root>`, `.claude/specialists/`, and `.claude/skills/orchestrator/` to their owning dependency, split compound commands into executable and project resource, and retained every normalized file-and-line use site.
It subtracted the 16 carried destinations, including the `_protocol.md` mapping to `specialist-protocol.md`, and classified standard shell and Git utilities, generated worktree paths, format tokens, and illustrative example paths as non-dependencies.
A second fixed-string `rg -n -F` pass over each normalized dependency and its variants produced the recorded use-site sets.
Bucket B in that sweep is the source for this ledger.

### `.regime/` verifiers

Godot AST tooling from the source project.

- `.regime/venv/bin/python3` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- `.regime/verifiers/v_brief_precheck_v3.py` - `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.
- `.regime/verifiers/` - `playbooks/bug-handling.md:103`, `playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`.

### Test and runtime tools

- `./run_tests.sh` - `playbooks/bug-handling.md:100`, `playbooks/phases/brief.md:84`, `playbooks/phases/review.md:40`, `specialist-protocol.md:67`, `specialist-protocol.md:102`.
- MCP `game_eval` - `playbooks/bug-handling.md:100`, `playbooks/phases/review.md:79`, `playbooks/phases/review.md:83`, `playbooks/phases/review.md:101`, `playbooks/phases/review.md:182`.

### External skills and role configs

- `superpowers:brainstorming` - `playbooks/design-pass.md:5`, `playbooks/design-pass.md:204`, `playbooks/md-revision.md:5`.
- `superpowers:writing-plans` - `playbooks/design-pass.md:5`, `playbooks/md-revision.md:5`.
- `verification-author` - `playbooks/design-pass.md:5`.
- The target project's callable `consultant` skill - `playbooks/design-pass.md:5`, `playbooks/design-pass.md:13`, `playbooks/design-pass.md:33`, `playbooks/design-pass.md:35`, `playbooks/design-pass.md:205`.
- `.claude/skills/orchestrator/`, including its `SKILL.md` and `delegation-frame.md` - `consultant.md:88`, `playbooks/design-pass.md:5`, `playbooks/implementation.md:5`, `playbooks/implementation.md:31`, `playbooks/implementation.md:46`.
- `.claude/skills/dvs/SKILL.md` - `consultant.md:75`.
- `.claude/skills/pes/` - `consultant.md:83`.
- `.claude/specialists/`, including each `<system>.md` config - `playbooks/implementation.md:29`, `playbooks/implementation.md:47`, `playbooks/phases/dispatch.md:8`, `playbooks/phases/dispatch.md:59`, `playbooks/phases/dispatch.md:60`.

### `.agent/` guides

- `.agent/rules/gdscript-style.md` - `playbooks/implementation.md:51`.
- `.agent/task-guides.md` - `playbooks/implementation.md:52`.

### Uncarried sibling playbooks

- `docs/playbooks/verification.md` - `playbooks/implementation.md:5`, `playbooks/bug-handling.md:5`, `playbooks/bug-handling.md:38`, `playbooks/bug-handling.md:69`, `playbooks/bug-handling.md:72`, `playbooks/bug-handling.md:73`, `playbooks/bug-handling.md:90`, `playbooks/bug-handling.md:170`.
- `docs/playbooks/verifier-design.md` - `playbooks/design-pass.md:207`, `playbooks/implementation.md:22`.
- `docs/playbooks/auditing.md` - `playbooks/bug-handling.md:173`.
- `docs/playbooks/agent-coordination.md` - `playbooks/bug-handling.md:172`.

### PM and current-state corpus

- `docs/baton.md` - `consultant.md:86`, `playbooks/phases/handoff.md:7`.
- `docs/pm/queue.md` - `playbooks/bug-handling.md:41`, `playbooks/bug-handling.md:168`.
- `BACKLOG.md` - `consultant.md:87`, `playbooks/bug-handling.md:167`, `playbooks/phases/handoff.md:15`, `playbooks/phases/review.md:50`, `playbooks/phases/review.md:64`, `playbooks/phases/review.md:185`.
- `PROJECT_STATE.md` - `playbooks/phases/handoff.md:14`, `playbooks/phases/review.md:55`, `playbooks/phases/review.md:64`, `playbooks/phases/review.md:186`, `playbooks/phases/verify.md:108`.
- `MEMORY.md` - `consultant.md:63`, `playbooks/phases/verify.md:108`.
- `CLAUDE.md` - `consultant.md:62`, `consultant.md:119`, `playbooks/implementation.md:5`, `playbooks/md-revision.md:99`, `playbooks/phases/brief.md:103`, `playbooks/phases/brief.md:159`, `playbooks/phases/brief.md:171`, `playbooks/phases/implement.md:148`, `playbooks/phases/verify.md:56`, `specialist-protocol.md:260`.

No reference to `docs/arcs.md` or `pm-inbox/` survives in the carried set.

### Design, spec, content, audit, and inventory documents

- `docs/Master-Design.md` - `consultant.md:57`, `playbooks/bug-handling.md:161`, `playbooks/design-pass.md:174`, `playbooks/md-revision.md:3`, `playbooks/md-revision.md:138`, `playbooks/phases/brief.md:33`, `playbooks/phases/research.md:14`.
- `BigDesignReference.md` - `playbooks/bug-handling.md:163`.
- `docs/reference/_archive/` - `playbooks/bug-handling.md:163`.
- `docs/content/` - `consultant.md:92`, `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:163`, `playbooks/phases/brief.md:32`, `playbooks/phases/brief.md:74`, `playbooks/phases/brief.md:124`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- `docs/content/defaults.md` - `consultant.md:92`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`.
- `docs/briefs/` - `playbooks/phases/brief.md:202`, `playbooks/phases/dispatch.md:28`, `playbooks/phases/dispatch.md:131`, `playbooks/phases/research.md:79`.
- `docs/content-pipeline/README.md` - `consultant.md:91`.
- `docs/content-pipeline/templates/README.md` - `playbooks/phases/implement.md:166`.
- `docs/audits/2026-04-05-engine-perfection-audit.md` - `playbooks/phases/research.md:8`.
- `docs/inventory/refresh-1/SUMMARY.md` - `playbooks/bug-handling.md:156`, `playbooks/bug-handling.md:164`.
- `<spec corpus root>` and its referenced descendants - `consultant.md:58`, `consultant.md:59`, `consultant.md:60`, `consultant.md:61`, `playbooks/bug-handling.md:26`, `playbooks/bug-handling.md:153`, `playbooks/bug-handling.md:157`, `playbooks/bug-handling.md:162`, `playbooks/bug-handling.md:165`, `playbooks/bug-handling.md:166`, `playbooks/implementation.md:17`, `playbooks/implementation.md:20`, `playbooks/implementation.md:39`, `playbooks/implementation.md:48`, `playbooks/implementation.md:49`, `playbooks/implementation.md:50`, `playbooks/md-revision.md:19`, `playbooks/md-revision.md:139`, `playbooks/phases/brief.md:17`, `playbooks/phases/brief.md:19`, `playbooks/phases/brief.md:52`, `playbooks/phases/brief.md:59`, `playbooks/phases/brief.md:60`, `playbooks/phases/brief.md:98`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/design.md:58`, `playbooks/phases/implement.md:71`, `playbooks/phases/implement.md:112`, `playbooks/phases/implement.md:164`, `playbooks/phases/implement.md:165`, `playbooks/phases/research.md:9`, `playbooks/phases/research.md:15`, `playbooks/phases/research.md:16`, `playbooks/phases/research.md:52`, `playbooks/phases/research.md:78`, `playbooks/phases/research.md:107`, `specialist-protocol.md:152`, `specialist-protocol.md:154`.
- `event-types.md` - `specialist-protocol.md:230`.

### DVS, PES, and validation corpus

- `docs/briefs/dvs-flywheel-component-2-handoff.md` - `consultant.md:66`.
- `docs/briefs/dvs-flywheel-component-2-session-{1,2,3}-handoff.md` - `consultant.md:67`.
- `docs/briefs/dvs-flywheel-component-2-session-3-analysis.md` - `consultant.md:68`.
- `.flywheel/dvs/calibration-set.ndjson` - `consultant.md:69`.
- `.flywheel/dvs/calibration-set-unlabeled.ndjson` - `consultant.md:70`.
- `.flywheel/dvs/scope.yaml` - `consultant.md:71`.
- `scripts/flywheel/` - `consultant.md:72`.
- `docs/superpowers/specs/2026-04-08-design-verification-system.md` - `consultant.md:76`.
- `docs/superpowers/specs/2026-04-12-dvs-flywheel-adapter-design.md` - `consultant.md:77`.
- `docs/research/pes-v2-viability-review.md` - `consultant.md:80`.
- `docs/research/pes-v2-*.md` - `consultant.md:81`.
- `docs/validation/tdd-spec-rework.md` - `consultant.md:82`.
- `docs/superpowers/specs/2026-03-23-content-spec-system-design.md` - `consultant.md:93`.
- `docs/briefs/enemy-coordination/design-r4.md` - `playbooks/design-pass.md:11`.

### Memory pins

- `~/.claude/projects/-Users-davidkol-projects-Godot-Tombhammer/memory/` - `playbooks/md-revision.md:136`.
- `feedback_check_content_spec_layer.md` - `playbooks/phases/brief.md:36`.
- `feedback_hold_revisions_during_iteration.md` - `playbooks/md-revision.md:136`.
- `feedback_invented_quantities_in_design_drafts.md` - `playbooks/design-pass.md:155`.
- `feedback_md_design_voice_not_spec_voice.md` - `playbooks/md-revision.md:136`.
- `feedback_md_ground_truth_bar.md` - `playbooks/md-revision.md:136`.
