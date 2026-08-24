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

The captain authorized two further carried-text corrections on 2026-08-24, both because the original line was unusable or unsafe for an adopter.
`playbooks/md-revision.md` now names a neutral memory directory instead of the source author's machine, username, and private project path.
The original line named that path directly.

```text
- **Memory pins (source material):** `feedback_md_ground_truth_bar.md`, `feedback_md_design_voice_not_spec_voice.md`, `feedback_hold_revisions_during_iteration.md` (all retained in `~/.claude/projects/-Users-davidkol-projects-Godot-Tombhammer/memory/` as backups for this playbook).
```

`playbooks/phases/handoff.md` now archives resolved backlog entries before removing them, which also removes a disagreement with `playbooks/phases/review.md:51`.
The original line deleted them outright.

```text
   - `BACKLOG.md` — resolved items removed, new items added
```

No other carried prose was reworded, reordered, condensed, or generalized.

The repository this was carried into does not itself load this shelf; its own agent-loaded skills live in a separate directory.
This directory is published for standalone installation and is discoverable by external skill installers, so an adopting project installs it like any other public skill.
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

The implementation loop runs in this order, with the phase files under `playbooks/phases/`.
Most phases have one file, but two are bundles: BRIEF is `brief.md` together with `implement.md`, and REVIEW is `review.md` together with `verify.md`, as `playbooks/implementation.md:21` and `playbooks/implementation.md:24` define them.

```
SCOPE -> RESEARCH -> DESIGN -> SPEC -> BRIEF -> BRIEF-PRE-CHECK -> DISPATCH -> REVIEW -> HANDOFF
```

`playbooks/implementation.md` is the entry point and owns that loop.
Three sibling playbooks cover the other arcs: `playbooks/design-pass.md` for a Socratic pass over a design document, `playbooks/md-revision.md` for revising that document after an audit, and `playbooks/bug-handling.md` for reported bugs.
`consultant.md` and `specialist-protocol.md` carry the two source-project role descriptions, but they do not register the target project's callable skill or specialist configs.

## Authority: intent always wins

The carried files disagree about which layer settles a conflict.
`specialist-protocol.md:242` makes code the ground truth on a spec-code mismatch, `playbooks/phases/verify.md:3-7` makes the specification the source of truth, and `playbooks/bug-handling.md:26-28` places designer-authored intent above both.

The captain resolved this on 2026-08-24: **intent always wins**.
Where designer intent, the specification, and the executing code disagree about authority, intent is authoritative and the lower layers are corrected to match it.

This resolution is authored here and is deliberately bounded.
It settles the authority-layer question and nothing else.
The procedural disagreements below are not covered by it, and no carried line was edited to apply it.

## Known ambiguities in the carried process

The carried text contains unresolved procedural disagreements with itself - about whether the verifier may read the brief, what proof an enum change needs, which phase a task starts at, and which phase owns cleanup among others.
None of them stops the chain running: an adopter hits one and chooses.
No carried line was edited to resolve them.

## What a target project must provide

This is a setup checklist, not an index of every path the carried text mentions.
It answers one question: what must be in place before this chain can run here.
Work through it and you are done; an entry you cannot provide is a gap you decide about, not a defect in the carriage.

- **A test runner.** The chain invokes `./run_tests.sh --summary` after every fix and merge, at `playbooks/bug-handling.md:100`, `playbooks/phases/brief.md:84`, `playbooks/phases/review.md:40`, `specialist-protocol.md:67` and `specialist-protocol.md:102`. Provide a runner at that path or decide what replaces it.
- **Per-system specialist configs.** `playbooks/phases/dispatch.md:59-60` reads `.claude/specialists/_protocol.md` then `.claude/specialists/<system>.md`, and `playbooks/implementation.md:29` routes to a specialist only when that config exists. The shared protocol is carried here as `specialist-protocol.md`; the per-system configs are yours to write, one per system you want specialist dispatch for.
- **Bookkeeping files the chain reads and writes.** `BACKLOG.md` and `PROJECT_STATE.md` (`playbooks/phases/handoff.md:14-15`, `playbooks/phases/review.md:50-64`), a session baton at `docs/baton.md` (`playbooks/phases/handoff.md:7`), a decision queue at `docs/pm/queue.md` (`playbooks/bug-handling.md:41`, `:168`), a brief directory at `docs/briefs/` (`playbooks/phases/dispatch.md:131`), and a project memory file (`playbooks/implementation.md:25`).
- **A spec corpus root, with the internal structure the prose depends on.** The carried text expects `systems/` for per-system specs, `workflows/` for cross-system flows, and `reference/` holding `wiring-reference.md`, `content-authoring.md` and a `recipes/` directory. Those distinctions are load-bearing: `playbooks/phases/brief.md:128` names three of them as separate authoritative sources for a default value.
- **A design document treated as ground truth.** `docs/Master-Design.md` in the source project, read first for design intent at `playbooks/phases/research.md:14` and used as the authority layer throughout `playbooks/bug-handling.md`.
- **Content specifications.** `docs/content/`, read when a brief touches authored content (`playbooks/phases/brief.md:32`, `:74`, `:124`).
- **External skills the chain calls.** `superpowers:brainstorming` and `superpowers:writing-plans` (`playbooks/design-pass.md:5`, `:204`, `playbooks/md-revision.md:5`), a `verification-author` skill (`playbooks/design-pass.md:5`), a `consultant` skill and an `orchestrator` skill (`playbooks/implementation.md:31`, `:46`). None are carried here.
- **The implementation language.** Substituted as `<the project's language>` where a carried rule named one. The worked examples remain in the source project's language on purpose.
- **The default branch name.** The carried text hardcodes `main`. Three sites are operational and break on a different default branch: `playbooks/implementation.md:23` and `playbooks/phases/implement.md:142` create worktrees from it, and `playbooks/phases/review.md:26` diffs against it. Six further sites are prose.
- **An agent runtime that can dispatch subagents.** `playbooks/phases/dispatch.md` and `playbooks/phases/verify.md` assume parallel workers in worktrees, and `consultant.md:22` assumes a `Read`, `Grep`, `Glob`, `Bash` tool surface.
- **Optional, if you want the source project's checks.** A runtime evaluation tool the text calls MCP `game_eval` (`playbooks/phases/review.md:79`, `:101`, `:182`) and the `.regime/` verifier substrate (`playbooks/implementation.md:22`, `playbooks/phases/brief-audit.md:52`). Neither is carried, and the captain ruled the verification regime out of scope.

## Stale source citations

Every `file:line` citation in the carried text points into the source project's code as it stood at one moment, and several were already wrong at the pinned commit.
These three are verified against `99809956`:

- `playbooks/phases/brief.md:105` names `_build_context()` at `skill_manager.gd:339` as the canonical exemplar. At the pinned commit that function is at line 576, and line 339 is `_process_repeat_delivery_queue()`, an unrelated queue processor.
- `playbooks/phases/verify.md:58` names `deal_damage_effect.gd:22-24` as the canonical AoE allegiance filter pattern. Those lines are a runtime backstop for the no-damage-type case, not an allegiance filter.
- `consultant.md:59` counts 27 per-system specs. The pinned tree holds 28, so a reader following the count silently drops `28-director.md`.

Correcting these numbers would not help, because the files they point into do not exist in an adopting project.
Treat every such citation as a source-project artifact and substitute your own exemplar.

## Source-project assumptions you must replace

The carried text states the source project's architecture as unconditional rule in several places.
The lines are left exactly as written; what follows is what an adopter must decide or supply instead.

- `specialist-protocol.md:260-263` states `EffectContext` construction, component access through `PipelineUtils` and `StatusTracker`, REDUCTION-stat modifier behavior, and a ban on `set_meta` for duration expiry as unconditional rules. Replace each with the equivalent convention in your own architecture, or drop the rule if you have no equivalent.
- `playbooks/phases/implement.md:96` presents a "Known NOT WIRED systems" list as current fact. It describes the source project at one moment; substitute your own list of known-unwired systems, or remove the check.
- `playbooks/phases/brief.md:5` cites "SKILL.md rule 1" for the anti-invention reminder, and `playbooks/implementation.md:23` and `:40` cite "Memory rule 11" and "Memory rule 5". Those numbers resolve to the source project's own rule files, not to anything here, and this file has no numbered rules to find. Supply your own, or read them as prose.

## How this list was built

The checklist above was derived from the carried text and is meant to be finishable, not exhaustive.
An exhaustive index of every referenced path was attempted and abandoned: three independent scans each produced a different set of omissions, which is evidence that the goal is not reachable rather than evidence of carelessness.
The full annotated derivation of every candidate token is kept as validation evidence for this repository and is deliberately not shipped with the skill.
