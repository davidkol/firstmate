# Firstmate process assessment

Firstmate's overall process is not yet assessed.
This living assessment records dated, evidence-based stage trials without turning task history into a transcript.
The current version can judge the Martyrdome target-design, target-publication, and target-to-current gap trials plus one unattended-away boundary observation and one repository-surface delivery failure, and it carries a dated snapshot of the ongoing DANU new-project trial that reached a landed first implementation step.

## Assessment boundary

- **Tested - Design:** One Martyrdome trial reached a durable, standalone whole-game target through discovery, question-and-answer work, drafting, and a bounded completeness audit.
- **Partly tested - Design mode and repeatability:** One-at-a-time dialogue was used extensively, while clean bulk discovery was tried only near the end on questions already shaped by earlier work.
- **Tested once - Gap analysis:** One Martyrdome scout compared all 77 accepted target elements with current code, scenes, tests, and bounded runtime observations without writing an implementation plan.
- **Tested once - New-project onboarding:** One fresh peer home attached, reconciled, and began work on DANU, a repository with no prior Firstmate history, without project writes.
- **Tested once - Planning:** One DANU planning scout produced an eight-step architecture plan from the captain's verbatim rulings and it landed in the project; no Martyrdome plan has been assessed and plan quality in play is untested.
- **Tested once - Implementation:** DANU's first plan step and four smaller ships landed on the project's local default branch; no Martyrdome implementation has been assessed and no playable outcome has been observed.
- **Partly tested - Review and validation:** Target publication received independent documentation review and bounded re-review, and DANU's light-path implementation review caught real defects on every ship at the cost of long fix loops on parser work, but game-runtime validation and player-outcome validation remain untested.
- **Tested twice - Publication or integration:** The accepted standalone target was published in PR 12 and its split focused-document form was published in PR 13, but the second delivery exposed a repository-surface identity failure in the captain-facing handoff.
- **Failed once - Repository-surface identity:** Firstmate verified its managed clone, described that result as the local Martyrdome state, and linked the captain to that clone without identifying or verifying the captain's actual working repository.
- **Failed once - Canonical landing rollout:** The canonical-repository correction deadlocked DANU's guarded local landing for a pathless peer-home entry with a task in flight, and recovery found the captain's own checkout 36 commits behind Firstmate's home clone.
- **Failed once, then corrected - Designer-intent authority:** Firstmate repeated agent-authored DANU doctrine as designer intent in a captain-facing recommendation until the captain corrected it.
- **Partly tested - Supervision or recovery:** Foreground supervision continued in the active session, but the owned away-mode launcher refused to start, so the unattended-away boundary failed; one DANU context reset was a non-event, while unattended-away operation remains untested.

The successful remote publication results and the single DANU chain are not evidence that Firstmate's later stages, local delivery visibility, or cross-project repeatability work in general.

## Process changes under test

This is a lightweight history of corrections suggested by the trials.
Each entry records what Firstmate intends to change, what actually changed, and what a later trial taught us.
Those facts do not have to advance through a fixed workflow: a change may remain open, be revised, or be superseded when later evidence warrants it.

### D1-C1 - Default to clean bulk design questions

- **Planned:** Present one clean, deduplicated bulk questionnaire by default, while keeping one-at-a-time dialogue available when the captain requests it.
- **Made:** On 2026-08-15, Firstmate added a separate `--target-design-intake` route that defaults to a clean bulk questionnaire and keeps one-at-a-time dialogue as an explicit captain choice; deterministic contract tests pass, but no later target-design trial has exercised it.
- **Learned:** D1 found the late clean bulk sheet easier to read, but did not establish whether a bulk-first run would discover equally strong questions or produce equally useful dialogue.
  On 2026-08-16, N1 presented three DANU design questions as one sheet and eight research questions with defaults in one message, and the captain answered each sheet in one message; four later questions were answered only after he asked for the observed situation behind each, so sheet length should track situational need rather than a fixed budget.

### D1-C2 - Separate captain material from internal reconciliation

- **Planned:** Keep source reconciliation, candidate filtering, and audit mechanics out of the questionnaire the captain is expected to answer.
- **Made:** D1 recovered by producing a separate clean seven-question sheet, and on 2026-08-15 the shared target-design scout contract made an internal report plus a separate plain Markdown questionnaire the default output pair; real-session use remains untested.
- **Learned:** The clean sheet was readable, while the mixed internal report was not; repeatability remains untested.

### D1-C3 - Preserve answers before reconciliation

- **Planned:** Save each exact answer and its question context immediately, then reconcile prose and dependent artifacts in sensible batches instead of asking for repeated micro-approval.
- **Made:** D1 adopted a private living target and exact answer records after the captain identified the compaction risk, and on 2026-08-15 the shared target-design contract required one dated private record per answered question before batched target reconciliation without per-replacement booking prompts; real-session use remains untested.
- **Learned:** The durable records survived later compactions and supported clean worker handoffs, while 25 separate booking prompts added avoidable interaction cost.
  On 2026-08-16, N1 created its private trial record before the first ship, kept every DANU ruling in a dated decision file and context card, and resumed supervision after a context reset with no captain input.

### S1-C1 - Enter overnight work through the verified launcher

- **Planned:** Start the next unattended trial through the verified primary launcher so the owned away lifecycle can run and be observed.
- **Made:** No launcher or away-mode behavior was changed in S1; the unverified session refused away mode and foreground supervision continued instead.
- **Learned:** S1 proved the refusal boundary, not unattended operation or recovery.

### G1-C1 - Reuse existing unresolved decisions across investigation stages

- **Planned:** Before registering a captain decision found during an investigation, compare it with the home's existing unresolved decisions and reuse the existing identity when it is the same semantic choice.
- **Made:** No shared behavior has changed yet; G1 registered a new slide-control decision even though the target-design trial already held the same choice under `martyrdome-target-design-draft-decision-slide-control-mapping-and-handling`.
- **Learned:** Origin-scoped idempotency prevents duplicate registration within one report but does not prevent the same design question from reappearing when a later stage encounters it.

### P2-C1 - Distinguish every repository surface before reporting delivery

- **Planned:** Treat the remote repository, Firstmate-owned per-project storage, the captain's working repository, and each Treehouse worktree as different identified surfaces; never present the Firstmate-owned copy as the captain's local project, and report each relevant surface as verified, stale, or not identified.
- **Made:** The isolated implementation branch now gives primary and peer homes one explicit canonical repository path, anchors Treehouse work to it, records and re-verifies task repository identity, ignores retained clones during fleet refresh, and preserves non-conflicting untracked files during guarded synchronization and landing.
  Secondmate clones and Orca worktree ownership remain explicit exceptions.
  The change passed focused automated checks and a real Treehouse identity smoke, landed on Firstmate `main` as `e68553f`, was pushed to `origin/main`, and migrated the private Martyrdome registry to `~/projects/Godot/Martyrdome` under `validated-main`.
  The first guarded canonical sync advanced that real checkout from `47e4db4` to `a5a8eda` while preserving its untracked `notes.md`; the retained managed clone was left untouched and inactive.
- **Learned:** Repository identity must be executable state shared by intake, spawn, synchronization, landing, teardown, and reporting rather than a path inferred independently at each boundary.
  A real Martyrdome Treehouse lease produced a distinct worktree root with the same Git common directory while leaving `notes.md` untouched, so the required isolation does not require a duplicate primary clone.
  The first independent implementation review found six rollout defects, including cross-project migration blocking and absent remote-identity proof; the correction review found two more fail-open reporting paths before the final review returned `SHIP` with no findings.
  The useful review boundary was therefore not ceremonial: it prevented a locally green implementation from making incremental migration unsafe or invisible at startup.
  On 2026-08-17, the rollout deadlocked in the DANU peer home: the guarded local landing refused a pathless entry with `PROJECT_IDENTITY_MISSING` while migration refused with a task in flight, so recovery needed one captain question, one authorized direct fast-forward landing, migration onto the captain's own checkout, and a rebuild of the isolated pool.
  The current compatibility rule is owned by [Canonical project repositories](configuration.md#canonical-project-repositories).

### N1-C1 - Bound review rounds on heuristic-parser work

- **Planned:** Put a review-round bound in the brief from the start for heuristic-parser and similar edge-case-rich work, limiting later rounds to errors and regressions while deferring warnings into a known-limitations catalogue.
- **Made:** No brief scaffold or pipeline behavior has changed; on 2026-08-16 and 2026-08-17 Firstmate imposed the bound mid-run by steer at round 6 of the DANU vocabulary fold and round 9 of Step 1.
- **Learned:** Both loops converged after the bound, in four and six further rounds, and the fold's tenth round still caught a real parse-time regression, so the bound reduced cost without silencing the reviewer.

### N1-C2 - Review light-path work against the local default branch

- **Planned:** Have the validation wrapper pass the project's local default branch as the review base for `local-only` work so an unpushed home does not diff against a stale `origin/main`.
- **Made:** No shared behavior has changed; N1 answered the resulting scope re-ask by approving the local base on each affected run.
- **Learned:** The re-ask recurred on both review runs of DANU exploration batch 1 and produced one data-versus-base mismatch, so it costs at least one decision round per task in a `local-only` home until fixed.

### N1-C3 - Append steer receipts at steer time

- **Planned:** When a mid-task steer adds owner words that a worker will land as project authority, append the verbatim receipt to the brief's captain-decided section at steer time.
- **Made:** No scaffold or steer behavior has changed; on 2026-08-16 Firstmate appended the receipt only after an independent review objected that a DANU decision-record row quoting the captain's ruling had no receipt in the brief.
- **Learned:** The receipts check then passed and the row stood, so the objection was legitimate and the fix was mechanical.

### N1-C4 - Placeholder under standing autonomy, then answer by exception

- **Planned:** No change is proposed yet; the loop is recorded so a later trial can judge whether a wrong placeholder ever lands before the captain reads it.
- **Made:** On 2026-08-17 Firstmate chose the smallest reversible placeholders for two DANU Step 1 gate questions that brushed game behavior, reported them in one line each, and the captain overruled both in one message; both rulings were recorded verbatim, relayed after the active run's terminal outcome, applied, and re-reviewed.
- **Learned:** The loop cost the captain one message and no waiting in this instance, and its risk of a wrong placeholder landing before he reads it did not materialize here.

## Human-owned evaluation standard

The captain's stated goals and expectations are the evaluation standard.
Firstmate's tracked contracts are secondary evidence of what the system claims it should do, not authority for grading whether the process served the captain.
The tracked role split is therefore cited only to identify claimed mechanisms in [AGENTS.md](../AGENTS.md) and the [Companion intake skill](../.agents/skills/companion-intake/SKILL.md).

The trial is judged against these captain-owned criteria.

- **Facilitate the complete game-development chain:** The captain described intent, design, architecture, and implementation as a connected chain and asked for a companion agent that asks the right questions, creates a missing design artifact, collaborates on architecture, and then dispatches implementation work (captain, 2026-08-08, canonical primary transcript).
- **Make the process quick and easy for him:** The captain said the companion should facilitate the chain, make it quick and easy, and work the way he thinks about building a game with other agents (captain, 2026-08-08, canonical primary transcript).
- **Use his attention only where it matters:** The captain said, "only bring up to me what i need to decide," and separately said that the captain cannot review every change while the crew does the work (captain, 2026-07-28, dated autonomy and GitHub rulings).
- **Keep captain-facing material readable:** The captain said that he cannot read most long agent output and that its volume causes quick misalignment (captain, 2026-08-08, canonical primary transcript).
- **Ask direct design questions:** The captain said that open-ended questions make him ramble and asked to be led with more direct questions (captain, 2026-08-13, canonical primary transcript).
- **Preserve accepted design outside chat:** After a compaction, the captain asked whether accepted work existed in documents and required a verbatim read of prior approved versions rather than whatever survived context (captain, 2026-08-13, canonical primary transcript).
- **Avoid ceremony that does not serve the work:** When a private draft triggered a project branch workflow, the captain asked, "Why do we need a feature branch and all this stuff to write a single draft document?" (captain, 2026-08-13, canonical primary transcript).
- **Optimize for his process rather than a hypothetical user:** The captain said, "I just want the best possible process," and rejected the former goal of making Firstmate transferable to someone else (captain, 2026-08-08, canonical primary transcript).
- **Default to clean bulk design questions:** The captain said, "i think the default should be the clean bulk and i have the option to go one at a time" (captain, 2026-08-15, canonical primary transcript).
- **Maintain momentum while he is away:** The captain said, "great, im going to bed, do as much as you can overnight," making continued progress during his absence a specific criterion for this continuation (captain, 2026-08-15, canonical primary transcript).
- **Keep actual work on the intended repository surface:** After Firstmate confused its managed clone with the real working repository, the captain said that a Firstmate-owned per-project folder was acceptable for Firstmate material but "for actual work it should just use the treehouse stuff" (captain, 2026-08-16, canonical primary transcript).
- **Operate well on a brand-new repository and concept:** The captain framed the DANU work as "a test run of how firstmate operates on a brand new repo and game concept" and asked "how well does it steer the project in the direction i want per the firstmate principles of intent -> design -> implementation -> playable game" (captain, 2026-08-16, danurepo peer-home session).
- **Build systems and architecture, not design or balance:** The captain said, "You let me handle game balancing. All you need to do is build the systems and architecture" (captain, 2026-08-16, danurepo peer-home session).

## Reproducible session inventory

### Method

The inventory searched the canonical Codex session store and the established Claude project transcript store for case-insensitive Martyrdome references.
A session was included only when its metadata identified the primary Firstmate checkout and its canonical conversation or recorded actions materially inspected, reconstructed, designed, or managed Martyrdome-specific knowledge.
Codex counts used top-level `response_item` messages and ignored duplicate `event_msg` mirrors and every copied `compacted.payload.replacement_history`.
Claude counts used top-level human and assistant conversation records and excluded tool-result turns, hook notifications, and injected context.
Exact or imported cross-store message sequences were compared before counting a conversation as distinct.
The existing internal design-process review supplied candidate findings and counts, but every material claim used here was checked against the complete inventory and the human-owned sources above.
The final target report was used only to establish the accepted target and its deliberately open matters.
The merged Martyrdome repository and PR 12 established the publication result, while the active primary session established the review decision, foreground continuation, and failed away-mode attempt.
The inventory records session date and contribution rather than private transcript paths or session identifiers.

### Included primary sessions

1. **2026-07-27, Claude:** The first cross-project workflow survey inspected Martyrdome's repository and session-memory setup while strategizing a shared game-development workflow.
2. **2026-07-28 to 2026-07-29, Claude:** Catalog process scouting commissioned Martyrdome-specific scouting and handoff passes, synthesized their findings with the other games, and exposed that apparent process cleanliness could mean invisible evidence rather than an actually complete process.
3. **2026-07-30 to 2026-07-31, Claude:** Process-rollout analysis found that substantial Martyrdome notes lived outside the repository and had not been available to dispatched workers, which directly established the later durability and source-discovery risk.
4. **2026-08-08, Claude:** The process diagnosis checked why earlier project scouts missed game-development knowledge, used Martyrdome as part of that diagnosis, and captured the captain's intent-to-design-to-architecture-to-implementation goal that governs this assessment.
5. **2026-08-13, Codex:** The captain dictated a large combat-system expansion, Firstmate converted it into design prose, published a standalone design addition, and then preserved the next sequence of runtime reconstruction, question audit, and human review.
6. **2026-08-13, Codex:** Firstmate commissioned the runtime and transcript reconstruction plus the design-question audit, returned their reports, and began the first design question.
7. **2026-08-13 to 2026-08-15, Codex:** The extended target-design session performed the main question-and-answer work, created the private living target, ran completeness and bulk-question passes, incorporated answers, closed the top-level target, created the first assessment entry, attempted away mode, supervised publication through merged Martyrdome PR 12, merged the resulting Firstmate intake correction, and commissioned and reviewed the target-to-current gap assessment.
8. **2026-08-16, Codex:** The resumed Martyrdome target-design session completed the focused target modules, globally reconciled and published the split target through PR 13, then exposed that Firstmate had verified and linked only its managed clone rather than the captain's working repository.

### Exclusions and unavailable evidence

- A Codex record containing the exact 2026-08-08 Claude conversation was an imported or mirrored history and was counted only as the canonical Claude session.
- Codex event mirrors and compaction replacement histories were excluded because they repeat messages from the same conversation.
- Martyrdome project-local sessions, disposable worker worktrees, and validation worktrees were excluded because this inventory is limited to primary Firstmate sessions.
- Startup digests, backlog listings, status-only carryover, tool output, and a speech-transcription test that merely said "Martyrdome" were excluded as false matches.
- General Firstmate sessions that only listed Martyrdome among registered projects and performed no Martyrdome-specific work were excluded.
- No additional harness store was included because no other local store could be identified reliably as a canonical primary Firstmate transcript rather than guessed from incidental files.
- The inventory establishes every identifiable session in the two canonical stores available on this machine, but it cannot prove that an unavailable, deleted, or unrecognized external transcript never existed.

## Design trial D1 - Martyrdome whole-game target (2026-08-13 to 2026-08-15)

### Scope and observed outcome

The trial began with cross-session recovery of Martyrdome knowledge and ended with a private standalone target that was judged complete enough to pause at the reusable whole-game-system level.
The result deliberately left slide handling for comparative playtesting, boss-specific answer structures for boss design, Broken-Muscle-Armor presentation for authored and feel-tested treatment, and exact values or content-specific effects for their named later activities.
The design trial stopped before gap analysis, implementation planning, content authoring, or publication.
The captain separately authorized publishing the completed target into Martyrdome after this assessment (captain, 2026-08-15, canonical primary transcript).

The design outcome was successful, but the process that produced it was not efficient or consistently aligned with the captain's operating needs.
The design-stage verdict is therefore **a useful target produced through a process mismatch**.

### Measured evidence

- The complete inventory contains seven distinct primary sessions across two canonical harness stores.
- The extended target-design work contained 160 captain messages before the target closed, after injected and hook records were excluded.
- A reproducible lower-bound count found 100 design-question prompts in that session, consisting of 99 option menus and the initial open-ended design question.
- The target-design work contained 25 explicit "Book ...?" prompts and crossed nine compactions before the target closed.
- Nine worker passes were associated with the extended target-design work, including one aborted premature project ship and eight completed report passes.
- The late bulk intake classified 29 candidates, shortlisted 12 questions, and then required a separate clean seven-question captain-facing sheet after the internal report proved unreadable as an answer surface.
- The final target preserved three deliberately open design areas and stopped rather than converting them into invented answers.

These counts describe process volume and routing, not design quality by themselves.

### Verdict against the captain's goals

- **Facilitate the full chain - Partly met:** Firstmate recovered intent, separated target design from current-state gaps and implementation planning, and delivered the missing target artifact, but this trial assessed no later link in the chain.
- **Make the process quick and easy - Not met:** One hundred design prompts, 25 booking prompts, nine compactions, and repeated full-document reconciliation imposed substantial interaction and coordination cost.
- **Use captain attention only for real design choices - Partly met:** The captain made the actual design decisions, but he also had to correct durability, branch ceremony, target language, approval cadence, report audience, punctuation, formatting, and presentation mode.
- **Keep captain-facing material readable - Not met consistently:** Direct option questions became readable, but one internal audit was presented as the answer sheet and the clean replacement was opened in an unwanted visual presentation.
- **Ask direct design questions - Met after correction:** Options and recommendations helped the captain answer crisply, while still allowing him to reject the menu, refine the premise, or invent a sharper answer.
- **Preserve accepted design outside chat - Failed, then recovered:** The first accepted sections existed only in conversation through a compaction, after which a private living draft and exact answer records made later work durable.
- **Avoid unnecessary ceremony - Failed, then recovered:** Firstmate briefly treated private draft capture as a project ship with branch ceremony before the captain corrected the destination.
- **Coordinate work through other agents - Not met consistently:** Primary Firstmate improvised most discovery and drafted repeated replacement prose itself before later scouts took over source filtering, document writing, and completeness checking.
- **Optimize for this captain - Not met consistently:** The process eventually adapted to direct questions and plain Markdown, but the mixed-audience report and unwanted Lavish presentation repeated presentation patterns the captain had already said did not work for him.

### Strengths to preserve

- Direct options with recommendations gave the captain a useful starting point without constraining him to the offered menu.
- One-at-a-time dialogue helped the captain refine ideas and sometimes discover answers sharper than any presented option.
- The final target cleanly separated intended design from current implementation, gaps, and plans.
- Exact option-and-answer capture preserved compact answers such as "A" without losing their meaning.
- The private living target survived later compactions and gave clean workers a durable source.
- The completeness pass separated reusable systems from content, tuning, implementation detail, and intentionally open matters, then stopped.

### Failures to preserve as findings

- Accepted design began as chat-only state and was made durable only after the captain challenged the risk.
- Primary Firstmate performed most question discovery and repeated drafting itself instead of coordinating bounded discovery and writing passes.
- Twenty-five explicit booking prompts turned answer capture into micro-approval of replacement prose.
- Private draft capture briefly triggered unnecessary project-branch ceremony.
- Internal source reconciliation and captain-facing questions were mixed in the same report.
- A clean Markdown questionnaire was opened as an unwanted Lavish presentation.

### Accepted operating correction

The observed evidence, the captain's preference, and the recommendation are distinct.

**Observed evidence:** One-at-a-time dialogue produced useful refinements and novel answers, while the late clean bulk sheet was easier for the captain to read than the internal audit it replaced.

**Captain's stated preference:** Clean, deduplicated bulk design questions are the default, and one-at-a-time dialogue remains an available mode (captain, 2026-08-15, canonical primary transcript).

**Assessment recommendation:** Use a clean, deduplicated bulk questionnaire by default, keep source reconciliation and internal mechanics in a separate internal report, and offer one-at-a-time dialogue without presenting it as the preferred default.

This correction supersedes the earlier internal review's recommendation to default to one-at-a-time questioning.
It is an accepted operating direction, not evidence that bulk discovery is empirically superior.

### Remaining uncertainty

This trial does not establish whether clean bulk discovery would have reached the same questions without the preceding extended dialogue.
This trial also does not establish whether bulk answers would produce dialogue as useful as the one-at-a-time discussion.
The bulk experiment occurred late, after prior dialogue had already shaped the target, source set, vocabulary, and candidate question pool.
The trial covers one game, one captain, and one target-design exercise, so it does not establish cross-project repeatability.
The target's textual completeness does not prove its design quality in play.

## Publication trial P1 - Martyrdome target publication (2026-08-15)

### Trial and boundary

This continuation begins after the dated D1 snapshot above and does not rewrite its finding that publication was then untested.
The trial covers publishing the accepted private target into the tracked Martyrdome repository, reconciling current design-authority claims, independently reviewing the documentation change, and merging PR 12.
It excludes game code, architecture, implementation planning, runtime behavior, design quality in play, and any claim of repeatability.

### Captain-owned criteria

The captain asked for a living artifact that would continue expanding as subsequent process parts were tested, then directed Firstmate to proceed into writing the drafted target into Martyrdome (captain, 2026-08-15, canonical primary transcript).
The existing criteria for durable repository truth, the intent-to-design-to-architecture-to-implementation chain, proportional ceremony, routine autonomy, readable communication, and momentum therefore apply to this trial.
The captain's 2026-08-13 branch-ceremony objection applied to making a private draft compaction-safe, while this trial was an actual tracked project publication.

### Status and observed outcome

**Tested once - Publication or integration:** The complete accepted target was published as Martyrdome's current target-design authority, its private audit appendix was excluded, older contradictory authority claims were relabeled, project memory points to the target, one additional stale handoff claim was corrected after independent review, and PR 12 was merged.
The publication result was successful.
This one result does not establish repeatability, architecture alignment, implementation alignment, or runtime validity.

### Measured evidence

- A heading-bounded byte comparison found the published target body identical to the accepted source body from `## Target design` through the end of `## Intentionally open target questions`.
- Both bodies contain 19 third-level target sections and three intentionally open question bullets, while the published file contains no `## Final top-level completeness audit appendix`.
- Merge commit `1c13546` added `docs/target-design.md`, added project memory naming it as current authority, and relabeled older design sources and current-build briefs without changing game code.
- The first independent review produced one ask-user finding: `docs/handoff-combat-director.md` still presented a settled legacy enemy lens without scoping it as historical implementation guidance or pointing to the new target.
- Firstmate classified that finding as a bounded mechanical correction required by the accepted source-of-truth contract, authorized the fix under the project's standing `yolo` posture, and did not wake the captain or add a game-design rule.
- The corrected handoff passed independent re-review, and GitHub records PR 12 merged on 2026-08-15 as commit `1c13546`.

### Verdict against the captain's goals

- **Preserve durable repository truth - Met for this trial:** The accepted target now lives in the game repository, private audit material stayed private, and project memory plus active design documents point to one current target authority.
- **Advance the full chain - Partly met:** Firstmate moved from accepted target design into tracked publication, but architecture, planning, implementation, and runtime alignment remain untested.
- **Use proportional rigor - Met for this trial:** A project branch and independent review were appropriate for an authority-bearing Martyrdome publication, unlike the earlier mistaken branch ceremony for a private compaction-safety draft.
- **Use captain attention only for real choices - Met for this trial:** The only ask-user review finding required a mechanical source-of-truth correction already inside the accepted contract, so Firstmate resolved it under standing authority without inventing design or interrupting the captain.
- **Keep captain-facing communication concise - Met at this boundary:** The captain was not asked to inspect the publication mechanics or decide the bounded correction, and the active session relayed the PR-ready and merge outcome in short status messages.
- **Maintain momentum - Met for the foreground publication stage:** Firstmate proceeded directly from the assessment into publication, carried the review correction through re-review, and merged the authorized PR in the same active session.
- **Supervise reliably while the captain is away - Not established by this result:** The publication completed under foreground continuation, not a proven unattended supervision lifecycle.

### Strengths and failures

The trial preserved accepted prose, kept private process evidence out of the game repository, reconciled current authority without deleting historical sources, and used review to catch one stale descendant that the initial pass missed.
Firstmate's authority handling was appropriately autonomous because the correction restored the already accepted publication boundary rather than changing the game.
The initial reconciliation nevertheless missed `docs/handoff-combat-director.md`, so the first pass was incomplete even though review caught and corrected it before merge.

### Correction and uncertainty

**Observed evidence:** One Martyrdome publication completed with a bounded review correction, re-review, and merge.

**Captain's stated preference:** Continue expanding this assessment as later process parts are tested, and proceed from the completed assessment into publishing the drafted target (captain, 2026-08-15, canonical primary transcript).

**Assessment recommendation:** Keep tracked branch and independent review ceremony for real project publications that change current authority, while keeping private draft durability outside that project-delivery ceremony.

This trial does not show that publication will repeat successfully on another project or that Martyrdome's implementation matches the published target.

## Publication observation P2 - Martyrdome repository-surface identity (2026-08-16)

### Trial and boundary

This observation begins after the focused Martyrdome target modules were reconciled, independently reviewed, and merged through PR 13.
It covers remote publication, synchronization of Firstmate's managed project clone, the captain-facing completion report, and the captain's attempt to find the delivered files in his actual working folder.
It does not decide the replacement project-storage architecture or claim that the captain's unidentified working repository was safe to update automatically.

### Captain-owned criteria

The existing criteria for durable repository truth, readable communication, proportional ceremony, and preserving the captain's work apply.
After observing the failure, the captain said, "it immediately caused an issue where you didnt realize you are dealing with the clone and not the real repo" (captain, 2026-08-16, canonical primary transcript).
The captain then clarified that a Firstmate-owned per-project folder may exist for Firstmate material, but "for actual work it should just use the treehouse stuff" (captain, 2026-08-16, canonical primary transcript).

### Status and observed outcome

**Failed once - Repository-surface identity:** The focused target documents reached GitHub and Firstmate's managed clone successfully, but Firstmate did not identify or verify the captain's actual Martyrdome working repository before reporting local availability.
The remote publication succeeded while the captain-facing local-delivery handoff failed.

### Measured evidence

- GitHub records Martyrdome PR 13 merged as commit `a5a8eda`, publishing one top-level target document and eleven focused target documents.
- Firstmate verified commit `a5a8eda` only in `~/fm-homes/martyrdome/projects/Martyrdome`, which is its managed clone.
- The completion report said "Local Martyrdome `main` is clean and synchronized with `origin/main`" without qualifying that repository as Firstmate's managed clone.
- When the captain could see only `target-design.md`, Firstmate linked `~/fm-homes/martyrdome/projects/Martyrdome/docs/target-design` as though it were the captain's working folder.
- Firstmate had neither identified nor inspected the captain's actual Martyrdome checkout, so its local synchronization state was unknown.

### Verdict against the captain's goals

- **Preserve durable repository truth - Partly met:** The remote repository contains the accepted documents, but the handoff did not preserve a truthful distinction between remote state, Firstmate-owned local state, and the captain's local state.
- **Keep captain-facing communication readable and accurate - Failed:** A concise completion message concealed the repository identity needed to interpret "local," and the later file link reinforced the wrong surface.
- **Use proportional isolation - Not established:** The managed clone prevented direct interference with the captain's checkout, but this observation does not prove that duplicating the project repository was necessary once Treehouse worktree isolation was available.
- **Maintain momentum - Failed at handoff:** Publication finished, but the captain could not immediately find the delivered files in the folder he actually uses.

### Strengths and failures

The remote merge and independent document validation remained valid.
The failure was not missing content but incorrect repository identity in the operator model and completion report.
Firstmate treated the only local repository it knew as if it were the captain's real project, even though its own architecture deliberately made that repository a managed clone.
The isolation boundary therefore created an immediate visibility and truthfulness cost at delivery.

### Correction and uncertainty

**Observed evidence:** Firstmate can complete project work through Treehouse and GitHub while still misreporting where the landed work is visible locally.

**Captain's stated preference:** Firstmate may retain per-project storage for its own material, but actual project work should use Treehouse rather than a duplicate working repository.

**Assessment recommendation:** Design one explicit repository-surface model that identifies the captain's repository, keeps Firstmate-private material separate, makes Treehouse the project-work surface, and requires delivery reports to state which surfaces were actually verified.

The exact role of the current managed clone, how an existing repository is registered safely, how Treehouse anchors to it, and whether local synchronization is offered or automated remain design questions.

## Gap-analysis trial G1 - Martyrdome target versus current implementation (2026-08-15)

### Trial and boundary

This trial began after the accepted target was published and compared that target with Martyrdome commit `1c13546`.
It covers source routing, static implementation inspection, bounded runtime observation, classification of every accepted target element, and preservation of intentionally open questions.
It excludes target revision, implementation planning, architecture selection, code changes, and player-cohort validation.

### Captain-owned criteria

The captain defined the sequence as "current target drafts of all the designs, the gap, and then the implementation plan" and later said to merge the Firstmate process change and resume the process (captain, 2026-08-13 and 2026-08-15, canonical primary transcript).
The standing criteria for durable evidence, readable captain-facing communication, proportional ceremony, routine autonomy, and using his attention only for genuine choices also apply.

### Status and observed outcome

**Tested once - Gap analysis:** A read-only scout produced a standalone 77-row target coverage matrix with present-state evidence and one of five explicit classifications for every row.
The result found 6 target elements met, 29 partial, 19 missing, 12 contradicted, and 11 unknown.
The report remained evidence-only and did not become an implementation plan or alter Martyrdome.

### Measured evidence

- The report accounts for all 19 target-design sections, every grappling subsection, and all four intentionally open target-question rows.
- The 77 classifications mechanically recount to 6 `met`, 29 `partial`, 19 `missing`, 12 `contradicted`, and 11 `unknown`.
- Static evidence used current code, scenes, assets, and focused absence searches, while observed and controlled runtime evidence were labeled separately.
- Runtime evidence reached the menu and world, observed dash and health behavior, demonstrated a full-health Hando entering `HELD`, and exercised encounter retreat cleanup.
- No project-defined automated check was found; both executable smoke paths exited zero while emitting engine errors, so the report explicitly marked project test health `needs-human` instead of claiming green.
- A clean-checkout Godot import rewrote 69 tracked generated-resource files, the scout restored them, and teardown verified a clean disposable worktree before removing it.
- The required decision lifecycle registered three open questions with non-blocking defaults, but one slide-control record duplicated the same semantic question already registered by the target-design trial.

### Verdict against the captain's goals

- **Advance the full chain - Met for this boundary:** Firstmate moved from accepted target into a distinct evidence phase and stopped before implementation planning as requested.
- **Preserve target versus present authority - Met:** The accepted target defined intent, executing code and runtime defined the present, and historical documents were used only as search leads.
- **Use proportional rigor - Met overall:** One disposable scout, bounded runtime probes, focused absence searches, and a traceable report were appropriate for a whole-game gap assessment without project writes.
- **Use captain attention only for real choices - Partly met:** The scout required no new immediate answer and gave every open question a non-blocking default, but the lifecycle duplicated one already-known slide-control choice and therefore added avoidable Captain's Call clutter.
- **Keep captain-facing material readable - Partly met:** The internal 277-line report is appropriately comprehensive as planning evidence, but it still requires a separate concise captain reading rather than serving as the chat handoff itself.
- **Report outcomes faithfully - Met:** The scout did not convert exit-zero smoke runs into a green project check and separated observed, static, missing, contradicted, and unknown claims.
- **Avoid invented design - Met:** Intentionally open target questions remained open and the report recommended only evidence that could resolve unknown classifications.

### Strengths and failures

The trial produced a complete and traceable bridge between target design and later planning.
Its strongest behavior was evidentiary discipline: current code and observed runtime outranked old prose, unknown qualitative claims stayed unknown, and contradictory current behavior was distinguished from mere absence.
The report also exposed cross-cutting seams without prescribing architecture, which keeps the next planning phase informed without silently deciding it.

The process failure was decision deduplication across stages.
The lifecycle correctly preserved unresolved choices and kept them non-blocking, but origin-scoped identities allowed the existing slide-control question to be registered again.
The project also lacks an automated health check, so this trial could not establish a green baseline and had to rely on bounded smoke observations that emitted engine errors.

### Correction and uncertainty

**Observed evidence:** One complete gap matrix was produced without changing the game or spilling into implementation planning, while one unresolved design question was duplicated across stage-specific records.

**Captain's stated preference:** Complete the target first, then the gap, then the implementation plan, while recording planned changes, changes made, and what each phase teaches Firstmate (captain, 2026-08-13 and 2026-08-15, canonical primary transcript).

**Assessment recommendation:** Preserve the evidence-only gap phase and its concise captain summary, but add semantic reuse of existing unresolved decisions before a later investigation registers new ones.

This trial does not establish implementation-plan quality, implementation alignment, representative player feel, final difficulty, or the target's design quality in play.
The 11 unknown classifications remain evidence limits rather than planning blockers unless a later plan depends on choosing their exact values.

## Supervision observation S1 - Unattended-away boundary (2026-08-15)

### Trial and boundary

The captain said he was going to bed and asked Firstmate to do as much as possible overnight in the same primary Codex session that performed P1.
This observation covers the attempt to enter Firstmate's owned away-mode lifecycle and the work that continued in the foreground after that attempt failed.
It does not cover recovery from a dead worker, restart recovery, or a successfully running unattended watcher.

### Captain-owned criteria

The direct criterion is the captain's request to maintain momentum during his absence (captain, 2026-08-15, canonical primary transcript).
Routine autonomy, concise reporting, proportional safety, and reliable supervision when he walks away also bear on whether that request was actually served.

### Status and observed outcome

**Partly tested - Supervision or recovery:** Firstmate attempted to start the owned away-mode lifecycle, but the launcher refused because the primary Codex session lacked the verified wrapper boundary.
Foreground supervision kept the same active turn moving through the Martyrdome publication.
The unattended-away boundary failed, so foreground continuation alone does not establish that the overnight request was satisfied.

### Measured evidence

- The captain's exact request was, "great, im going to bed, do as much as you can overnight" (captain, 2026-08-15, canonical primary transcript).
- `bin/fm-afk-launch.sh start` returned `[codex-away-permission] away mode cannot begin in an unverified or restricted Codex session that may escalate interactively; relaunch with bin/fm-codex-primary.sh`.
- The same active turn continued foreground supervision and later observed the review correction, re-review, PR readiness, and merge.
- No successful away-mode start or unattended supervision result was observed in this trial.

### Verdict against the captain's goals

- **Supervise reliably while the captain is away - Not met:** The owned unattended lifecycle did not start, so this trial provides direct failure evidence at the away boundary.
- **Maintain momentum - Partly met:** Foreground work continued and completed P1, but that continuation depended on the active turn and cannot be counted as successful unattended overnight operation.
- **Use proportional rigor - Mixed:** The launcher failed closed at an unverified permission boundary, but the required verified launch context was not in place when the captain walked away.
- **Use routine autonomy - Not established at the away boundary:** Publication mechanics were handled autonomously in the foreground, but no unattended authority or recovery behavior ran.
- **Keep captain-facing communication concise - Met for the failure report:** Firstmate stated the refusal and its consequence directly, without claiming away mode had started.
- **Advance the full chain and preserve durable game truth - No new evidence:** This supervision observation changes neither the D1 design verdict nor P1's publication verdict.

### Strengths and failures

The refusal was explicit, bounded, and did not get misreported as successful away mode.
The active turn preserved short-term momentum by continuing foreground supervision.
The core failure is that the owned unattended lifecycle was unavailable at the moment the captain delegated overnight work.

### Correction and uncertainty

**Observed evidence:** The away launcher refused, while foreground work continued in the same active turn.

**Captain's stated preference:** Do as much as possible overnight while he was away (captain, 2026-08-15, canonical primary transcript).

**Assessment recommendation:** Do not treat foreground continuation as proof of unattended supervision, and leave the stage partly tested until a later trial observes the owned away lifecycle actually running across the captain's absence.

This observation does not establish whether away mode would work from the verified wrapper, whether recovery works, or how much work an unattended cycle can complete.

## New-project trial N1 - DANU intake and first implementation (2026-08-16 to 2026-08-17, ongoing)

### Trial and boundary

This entry is a dated snapshot of a trial that was still running on 2026-08-17; it does not close the trial, and later facts belong in dated annotations rather than rewrites.
The trial covers Firstmate operating on a brand-new repository and game concept, DANU, a private TypeScript project with two commits at trial start, from a fresh peer home registered `local-only` with routine autonomy on 2026-08-16 by captain instruction.
It includes peer-home bring-up, project add and reconcile, Firstmate's read of the repository's own handoff, the next-step recommendation, the first ship task, captain and agent playtests, design-intake and research scouts, an eight-step architecture plan, its first implementation step, local landing, and one context reset.
It excludes design-target work in the Martyrdome sense, the Director, UI, the C# port, unattended-away supervision, and cross-project repeatability, none of which was observed.
Unlike D1, P1, G1, and S1, this trial tested an existing process on a project that had no prior Firstmate history.

### Captain-owned criteria

- The captain framed the trial as "a test run of how firstmate operates on a brand new repo and game concept" and asked "how well does it steer the project in the direction i want per the firstmate principles of intent -> design -> implementation -> playable game" (captain, 2026-08-16, danurepo peer-home session).
- Inside DANU the captain had set "Project goal for now is to find out whether the idea works, not to ship" (DANU `docs/DECISIONS.md`, 2026-08-16), and the repository's own `AGENTS.md` demands ask-don't-guess, layperson language, owner-supplied plan goals, and strict status hygiene.
- Mid-trial the captain drew the role line explicitly: "You let me handle game balancing. All you need to do is build the systems and architecture" (captain, 2026-08-16, danurepo peer-home session).
- The captain set the design goal as the most robust interpretation system and asked Firstmate to choose options by that criterion, and later stated the whole-game target as Pax Historia without LLMs at play time (captain, 2026-08-16, closely attributed from voice).
- The standing criteria for the full chain, quick and easy operation, attention only where it matters, readable material, direct questions, accepted work durable outside chat, proportional ceremony, clean bulk questions, and optimizing for this captain apply as dated above.

### Status and outcome

**Tested once - New-project onboarding:** A fresh peer home attached, cloned, gate-initialized, and reconciled DANU with no project commits, and Firstmate relayed the repository's own honest handoff instead of dispatching discovery.
**Tested once - Planning:** A planning scout produced an eight-step architecture plan in the repository's own plan shape with the captain's verbatim goals, and it landed as `docs/plans/world-memory.md` on local `main`.
Plan quality in play is untested.
**Tested once - Implementation:** The first plan step, world memory, landed on local `main` after two review runs; the vocabulary fold, ladder fixes, exploration batch, and input-logging ships also landed.
Whether the idea works remains the captain's open project question and is not answered by this trial.
**Partly tested - Review and validation:** The light path's single reviewer caught real defects on every ship, but heuristic-parser work needed ten to fifteen fix rounds until Firstmate imposed a round bound.
**Partly tested - Publication or integration:** Local landing worked repeatedly, then the canonical-repository rollout deadlocked the guarded landing for a peer home with a task in flight.
**Partly tested - Supervision or recovery:** A context reset was a non-event, but stale-worker alarms fired falsely while pipelines applied fixes, and unattended-away supervision was not observed.
The observable result on 2026-08-17 was that the trial durably recorded the captain's rulings and design reports, landed an architecture plan and its first implementation step within one day on a fresh repository, and remained incomplete before a playable outcome, with the false-canon and landing failures recorded below.

### Measured evidence

- Onboarding: the reconcile report found the entry-point `AGENTS.md`, handoff `STATUS.md`, decision record `docs/DECISIONS.md`, check `npm test`, and setup `npm ci` with no collision, disagreement, or gap, and `no-mistakes init` plus `doctor` created no commits.
- Firstmate-side ceremony at bring-up was three tool-blocked shell attempts, none captain-facing.
- The first ship's contract validation refused once because the outcome pointer was prose instead of a receipted `captain decision <id>`; the receipt validators then passed first time on the next two briefs, and one honest mis-tier was caught on a later scorer brief.
- A bare `tasks-axi add` in the peer home wrote its item into the main home's backlog until corrected with an explicit backlog file.
- The captain's first playtest was 24 commands, saved verbatim with a labeled provisional tally of 7 patterns.
- The design-intake scout replayed those 24 lines at HEAD with the same seed and reproduced the transcript word for word, then classified 10 candidate rows as 3 shortlisted, 1 premature, 3 implementation-only, 1 answered by the decision record, and 2 duplicates of routed work.
- The output-persistence scout ran 5 novel orders across seeds 1 to 8 and two rulesets and found that nothing a player says persists in world state; it classified 12 rows as 3 shortlisted, 1 answered, 1 stale, 2 premature, 4 implementation-only, and 1 duplicate.
- The Pax Historia research scout observed the live game, dumped twelve production prompts and a serialized world state, verified every prior-art quote at source finding one misattribution and one paraphrase-as-quote, produced a 16-item functional checklist, and registered 8 owner questions.
- The bear test in Pax on Normal difficulty absorbed the order into 11 of 16 events and then rescinded it within the first month, with no rule deciding which outcome occurs.
- Exploration batch 1 landed 399 authored inputs as `b5087cc` after two review runs and five decision rounds; its headline was 145 of 333 orders read wrongly plus 21 non-orders read as orders, explore tier 67.3 percent top-1 versus 72.5 percent overall.
- The vocabulary fold landed as `223a492` with the captain's own player tier at 17 of 17 from 14, explore 224 to 286 of 333, hard 8 to 12 of 18, varied 143 to 168 of 176, plain unchanged, and 53 tests, after ten review rounds and about 2 hours 20 minutes on a 28-file parser change; round 10 still caught a parse-time regression from 0.66 to 6 to 8 milliseconds.
- Step 1 landed after a first run of 15 fix rounds, of which 8 keyed decisions were answered by Firstmate under standing autonomy and 2 were escalated as design questions, and a second run of 3 rounds, with 21 commits and 103 tests; Firstmate imposed a round bound at round 9 and the loop converged in 6 more rounds.
- Two ask-user review findings on the first ship were decided fast: the first by Firstmate under standing autonomy within minutes of the finding and without waking the captain, and the second by the captain typing directly into the worker's window before Firstmate's identical decision was sent.
- Captain question sheets: three design questions presented as one sheet were answered in one message, eight research questions with defaults were answered in one message, and four later questions were answered in one line only after the captain asked for observed context on each; the number of open captain questions peaked at 10 and reached zero on 2026-08-16.
- Firstmate asked no clarifying question back in any recorded segment; the captain's decisions arrived through the bulk sheets above plus one two-part landing-fork question answered "1A 2 yes".
- About 12 false worker-gone-quiet alarms fired across two tasks while pipelines applied fixes, each costing one wake turn.
- The wake drain printed an empty open-decisions section while two keyed decisions were open in one status log.
- The guarded local landing refused after the canonical-repository update with `PROJECT_IDENTITY_MISSING` while migration refused with a task in flight; recovery fast-forwarded 36 commits onto the captain's own checkout that he had never pulled and rebuilt the isolated pool by removing five clean scratch worktrees.
- After the context reset, the re-emitted digest, backlog, and status logs were enough to resume supervision with no captain input.
- One worker showed a mid-task model switch banner not caused by Firstmate and still finished; recorded because it affects repeatability claims.

### Verdict against the captain's goals

- **Test Firstmate on a brand-new repository and concept - Tested once, succeeded at onboarding:** The peer home attached and reconciled the repository without writes, and the first ship, playtest, and fold loop ran; repeatability on another fresh repository is unavailable evidence.
- **Steer the project intent -> design -> implementation -> playable game - Partly met:** The trial durably recorded the captain's rulings and design reports, landed an architecture plan and its first implementation step within one day, and applied the rulings to the plan; the captain-owned chain remains incomplete before playability, and the project's own "does the idea work" question stays open.
- **Build systems and architecture, leave design and balancing to the captain - Failed once, then corrected:** Firstmate repeated agent-authored "rhetoric is not an input" doctrine as the project's thesis in a captain-facing recommendation, the captain corrected it, and it was routed as a false-canon correction with the ruling recorded verbatim.
- **Facilitate the complete chain - Met for this boundary:** Firstmate captured rulings verbatim in a context card and decision records, escalated real design forks to evidence scouts instead of building on its own read, and dispatched the plan and Step 1 without adding approval ceremony the captain had not asked for.
- **Make the process quick and easy - Partly met:** Bulk-by-exception answers and zero-question segments kept his cost low, but the review loops on parser work, the recurring local-only base re-ask, and the landing deadlock added hours of pipeline time and one avoidable question.
- **Use his attention only where it matters - Met, with one open measure:** Most ask-user findings were decided under standing autonomy without waking him, and his two overrules of Firstmate's placeholders cost one message; the record leaves "decisions requested versus genuinely needed" as an open observation.
- **Keep captain-facing material readable - Met, with a learned nuance:** Short one-sentence-with-default sheets were enough for eight questions, but four questions needed observed situational context before he could answer, so length should track situational need rather than a fixed budget.
- **Ask direct design questions - Met:** Each question carried options and a default, and the captain answered by criterion and delegation, by letter, or by one-line correction.
- **Preserve accepted work outside chat - Met:** The private trial record existed before the first ship, every ruling has a dated decision file, and the context reset test passed on the first wake after it.
- **Avoid ceremony that does not serve the work - Partly met:** Guards refused real defects with one retry each, but the local-only review base, the mid-task steer receipt objection, and the peer-home backlog mis-write were Firstmate-side costs of Firstmate's own machinery.
- **Default to clean bulk design questions - Met:** Three sheets were presented in bulk with defaults and answered in one message each.
- **Keep actual work on the intended repository surface - Partly met:** Work landed on Firstmate's home clone for a day while the captain's own checkout was 36 commits behind, and the canonical migration deadlocked before it recovered onto his checkout.
- **Maintain momentum while he is away - Unavailable evidence:** Unattended-away supervision was excluded from this trial.

### Strengths and failures

Firstmate relayed the repository's own honest handoff instead of rediscovering it, sequenced one small enabling ship in front of the captain's playtest, and kept the in-flight worker unsteered when the playtest arrived early.
Evidence scouts corrected Firstmate's own inference twice before the captain was asked a wrong question: the vocabulary-mismatch finding replaced Firstmate's proposed missing-content fork, and the persistence scout verified the bear case empirically.
The light-path review earned its keep, catching an EOF confirmation defect, Firstmate's own narrowing of the logged parse, and a late parse-time regression.
Direct captain intervention in a worker window was tolerated cleanly because the decision key closed and Firstmate's duplicate steer was refused.
The rulings-to-context-card-to-decision-file path is the durable slot for intent-to-design knowledge that earlier trials lacked.

The reusable failures are these.
Firstmate reproduced agent-authored canon as designer intent in a captain-facing recommendation, the exact failure earlier findings warned about.
The light path's single reviewer keeps finding edge cases on heuristic-parser work until a round bound is imposed, so the bound belongs in the brief from the start.
A mid-task steer that adds owner words needs its receipt appended to the brief at steer time, or review objects later.
Local-only landing without a pushed origin makes the review base re-ask recur on every task in the home.
Peer-home defaults resolved against the primary home for the backlog writer, and the canonical-repository rollout did not cover a pathless peer-home entry with a task in flight.
False stale-worker alarms during pipeline fix rounds and an empty open-decisions section on a log with two open keys cost wake turns without captain impact.

### Correction and uncertainty

**Observed evidence:** One fresh repository went from onboarding to a landed first architecture step in one day, with all captain-facing questions batched by exception, one false-canon recommendation corrected by the captain, and several Firstmate-side mechanics defects surfaced by supervision.

**Captain's stated preference:** Firstmate builds the systems and architecture while he owns design and balancing, question length should carry the situational context each question needs, and the trial's own criteria are how Firstmate operates on a brand-new repository and how well it steers toward a playable game (captain, 2026-08-16, danurepo peer-home session).

**Assessment recommendation:** Keep the ruling capture, evidence-scout, and bulk-by-exception loop; put a review-round bound in heuristic-parser briefs from the start; append steer receipts at steer time; fix the local-only review base and the peer-home defaults in Firstmate rather than paying the extra round per task; and cover the pathless peer-home case in the canonical migration.

**Process-change evidence:** N1 updates the Learned facts for D1-C1, D1-C3, and P2-C1 and records the Planned, Made, and Learned facts for N1-C1 through N1-C4 above.

**Open empirical questions:** Whether the plan and Step 1 make the idea work in play, whether decisions requested matched decisions genuinely needed, whether the captain experienced the scout-first routing of design forks as momentum or delay, whether the delegated design choice read to him as served or invented, whether the local-only landing plus captain playtest loop is quick and easy in practice, and whether onboarding repeats on another fresh repository all remain unanswered by this record.

## Future stage entries

Later trials should extend this document with one bounded entry under the applicable stage rather than rewriting the design-stage history.
Each entry should use the following shape.

1. **Trial and boundary:** Name the stage, project, dates, included evidence, and explicit exclusions.
2. **Captain-owned criteria:** Quote or closely attribute each human-owned goal with its date before consulting Firstmate's internal contract.
3. **Status and outcome:** Label the stage tested, partly tested, or untested and name the observable result.
4. **Measured evidence:** Record only reproducible counts, checks, captures, or player observations that bear on the verdict.
5. **Verdict:** Judge each captain-owned criterion and distinguish success, partial success, failure, and unavailable evidence.
6. **Strengths and failures:** Preserve only reusable findings rather than chronology or transcript detail.
7. **Correction and uncertainty:** Separate observed evidence, captain preference, recommendation, and unanswered empirical questions.
8. **History rule:** Preserve prior dated entries, and annotate factual corrections with their date instead of silently rewriting earlier evidence.
9. **Process-change evidence:** Reference any affected change ids above and update only the concrete `Made` or `Learned` facts supported by the trial.

## Later stage placeholders

### Gap analysis

G1 records one successful evidence-only Martyrdome target-to-current comparison with one decision-deduplication failure.
Repeatability and player-cohort evidence remain untested.

### Planning

N1 records one DANU architecture plan produced from the captain's verbatim rulings and landed in the project.
Martyrdome planning and plan quality in play remain untested.

### Implementation

N1 records DANU's first architecture step and four smaller ships landed on the project's local default branch.
Martyrdome implementation, implementation alignment with a published target, and any playable outcome remain untested.

### Review and validation

Publication-document review is tested once in P1.
N1 records light-path implementation review that caught real defects on every DANU ship, with long fix loops on parser work until a round bound was imposed.
Runtime validation and player-outcome validation remain untested, so no verdict is recorded for them.

### Publication or integration

P1 records one successful Martyrdome target-publication result.
P2 records a second successful remote publication whose captain-facing local handoff failed because Firstmate confused its managed clone with the captain's working repository.
N1 records repeated successful local landing on a fresh peer home and one landing deadlock caused by the canonical-repository rollout, recovered onto the captain's own checkout.
General repeatability and implementation alignment remain untested.

### Supervision or recovery

S1 records a failed unattended-away boundary and successful foreground continuation in the same active turn.
N1 records one context reset resumed with no captain input, false stale-worker alarms during pipeline fix rounds, and one wake drain that missed two open decisions.
Away-mode operation remains unproven.

## Current assessment conclusion

Firstmate has now produced one durable standalone game-design target, published both its standalone and split focused-document forms into Martyrdome through bounded review and merge, and completed one evidence-only target-to-current gap assessment.
It still has not proved a concise, repeatable, end-to-end process, implementation-plan quality, implementation alignment, game-runtime validity, or player outcomes.
The gap trial strengthened source-authority discipline, honest runtime evidence, and separation between investigation and planning while exposing cross-stage decision duplication as a new process failure.
The publication trials strengthened remote repository truth, proportional project-delivery rigor, routine autonomy, and foreground momentum while preserving the design trial's earlier failures as historical findings.
The second publication also exposed that Firstmate can land correct work remotely while misleading the captain about which local repository was verified and where the result is available.
The supervision observation failed at the unattended-away boundary, and foreground continuation must not be credited as satisfying the captain's overnight request.
The DANU trial then carried a fresh repository from onboarding through a captain-ruled plan to a landed first implementation step in one day with questions batched by exception, while reproducing the agent-authored-canon failure once and exposing local-only review base, peer-home default, stale-alarm, and canonical-landing defects in Firstmate's own machinery.
That single chain does not show that the idea works in play or that onboarding repeats elsewhere.
The next assessment entry must evaluate a later process stage on its own evidence rather than extending any successful result into an assumed overall verdict.
