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

## What a target project must supply

The carried text leaves two placeholders that a target project fills in for itself.

- `<the project's language>` - the implementation language rules are stated against.
- `<spec corpus root>` - the directory holding the per-system specifications, workflow specs, and reference material.
  In the source project this was `docs/architecture/`, with `systems/`, `workflows/`, and `reference/` beneath it.
  The carried text preserves that internal structure below the placeholder, because the distinctions between those three are load-bearing in the prose.

A third placeholder, `<the project>`, appears where a rule named the source project as its subject.

## The chain

The implementation loop runs in this order, one file per phase under `playbooks/phases/`.

```
SCOPE -> RESEARCH -> DESIGN -> SPEC -> BRIEF -> BRIEF-PRE-CHECK -> DISPATCH -> REVIEW -> HANDOFF
```

`playbooks/implementation.md` is the entry point and owns that loop.
Three sibling playbooks cover the other arcs: `playbooks/design-pass.md` for a Socratic pass over a design document, `playbooks/md-revision.md` for revising that document after an audit, and `playbooks/bug-handling.md` for reported bugs.
`consultant.md` and `specialist-protocol.md` are the two agent roles the chain dispatches into.

## Unresolved dependencies

The carried files reference material that was deliberately not carried.
Those references are left exactly as written rather than stubbed or deleted, so nothing about the original process is silently lost.
Every one of them is a gap a target project closes for itself, or does not.

### `.regime/` verifiers

Godot AST tooling from the source project.

- `playbooks/implementation.md:22` - `.regime/venv/bin/python3 .regime/verifiers/v_brief_precheck_v3.py`, cited as a mandatory dispatch gate.
- `playbooks/phases/brief-audit.md:52` - the same verifier, invoked directly.
- `playbooks/bug-handling.md:103` - `.regime/verifiers/`, where promoted cascade shapes get a mechanical verifier.

### PM corpus

- `playbooks/phases/handoff.md:7` - `docs/baton.md`.
- `consultant.md:86` - `docs/baton.md`.
- `playbooks/bug-handling.md:41` - `docs/pm/queue.md`.
- `playbooks/bug-handling.md:168` - `docs/pm/queue.md`.

No reference to `docs/arcs.md` or `pm-inbox/` survives in the carried set.

### `superpowers` skills

- `playbooks/design-pass.md:5` - `superpowers:brainstorming` and `superpowers:writing-plans`.
- `playbooks/design-pass.md:204` - `superpowers:brainstorming`.
- `playbooks/md-revision.md:5` - `superpowers:brainstorming`.

### Per-system specialist configs

The source project wrote 27 of these for itself; only the shared protocol is carried.

- `playbooks/implementation.md:29` - `.claude/specialists/<system>.md`.
- `playbooks/implementation.md:47` - `.claude/specialists/<system>.md`.
- `playbooks/phases/dispatch.md:8` - `.claude/specialists/`.
- `playbooks/phases/dispatch.md:60` - `.claude/specialists/<system>.md`.

`playbooks/phases/dispatch.md:59` points at `.claude/specialists/_protocol.md`, which is carried here as `specialist-protocol.md`.

### Uncarried sibling playbooks

Four playbooks in the source chain were too coupled to the source project's verification regime to carry.

- `playbooks/implementation.md:5` and `playbooks/bug-handling.md:170` - `docs/playbooks/verification.md`.
- `playbooks/design-pass.md:207` and `playbooks/implementation.md:22` - `docs/playbooks/verifier-design.md`.
- `playbooks/bug-handling.md:173` - `docs/playbooks/auditing.md`.
- `playbooks/bug-handling.md:172` - `docs/playbooks/agent-coordination.md`.

### Source-project artifacts assumed by name

The carried text names the source project's own working files directly, and no substitution rule covered them.
A target project either creates files under these names or reads them as role descriptions.

- `docs/Master-Design.md`, the design document treated as ground truth - `playbooks/md-revision.md:3`, `playbooks/md-revision.md:138`, `playbooks/bug-handling.md:161`, `playbooks/phases/research.md:14`, `playbooks/phases/brief.md:33`, `playbooks/design-pass.md:174`.
- `BACKLOG.md` and `PROJECT_STATE.md` - `playbooks/phases/handoff.md:14`, `playbooks/phases/handoff.md:15`, `playbooks/phases/review.md:50`, `playbooks/phases/review.md:55`, `playbooks/phases/review.md:64`, `playbooks/phases/review.md:185`, `playbooks/phases/review.md:186`, `playbooks/bug-handling.md:167`, `consultant.md:87`.
- `docs/content/`, the content specifications - `playbooks/bug-handling.md:163`, `playbooks/phases/brief.md:32`, `playbooks/phases/brief.md:74`, `playbooks/phases/brief.md:124`, `playbooks/phases/brief.md:128`, `playbooks/phases/brief.md:145`, `playbooks/phases/brief.md:197`, `consultant.md:92`.
- `docs/briefs/`, where approved briefs are saved - `playbooks/phases/dispatch.md:28`, `playbooks/phases/dispatch.md:131`, `playbooks/phases/brief.md:202`, `playbooks/phases/research.md:79`.
- `.agent/rules/gdscript-style.md`, the style guide - `playbooks/implementation.md:51`.
- `.claude/skills/orchestrator/` and its delegation frame - `playbooks/implementation.md:5`, `playbooks/implementation.md:31`, `playbooks/implementation.md:46`, `consultant.md:88`.
- `consultant.md:56-93` is a context registry listing the source project's own documents, including its design verification system and process research corpus.
  It is the one carried section that is largely an inventory of another project rather than a rule, and it is carried whole rather than trimmed.
