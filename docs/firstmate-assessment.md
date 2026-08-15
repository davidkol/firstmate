# Firstmate process assessment

Firstmate's overall process is not yet assessed.
This living assessment records dated, evidence-based stage trials without turning task history into a transcript.
The current version can judge the Martyrdome target-design and target-publication trials plus one unattended-away boundary observation.

## Assessment boundary

- **Tested - Design:** One Martyrdome trial reached a durable, standalone whole-game target through discovery, question-and-answer work, drafting, and a bounded completeness audit.
- **Partly tested - Design mode and repeatability:** One-at-a-time dialogue was used extensively, while clean bulk discovery was tried only near the end on questions already shaped by earlier work.
- **Untested - Planning:** No implementation plan derived from the completed target has been assessed.
- **Untested - Implementation:** No implementation of the completed target has been assessed.
- **Partly tested - Review and validation:** Target publication received independent documentation review and bounded re-review, but implementation review, game-runtime validation, and player-outcome validation remain untested.
- **Tested once - Publication or integration:** The accepted target was published into Martyrdome with its private audit excluded, stale authority claims corrected, and PR 12 merged.
- **Partly tested - Supervision or recovery:** Foreground supervision continued in the active session, but the owned away-mode launcher refused to start, so the unattended-away boundary failed and recovery remains untested.

The successful delivery of one design target and one publication result is not evidence that Firstmate's untested later stages or cross-project repeatability work.

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
7. **2026-08-13 to 2026-08-15, Codex:** The extended target-design session performed the main question-and-answer work, created the private living target, ran completeness and bulk-question passes, incorporated answers, closed the top-level target, created the first assessment entry, attempted away mode, and supervised publication through merged Martyrdome PR 12.

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

## Later stage placeholders

### Planning

Planning is untested, so no verdict is recorded.

### Implementation

Implementation is untested, so no verdict is recorded.

### Review and validation

Publication-document review is tested once in P1.
Implementation review, runtime validation, and player-outcome validation remain untested, so no verdict is recorded for them.

### Publication or integration

P1 records one successful Martyrdome target-publication result.
General repeatability and implementation alignment remain untested.

### Supervision or recovery

S1 records a failed unattended-away boundary and successful foreground continuation in the same active turn.
Away-mode operation and recovery remain unproven.

## Current assessment conclusion

Firstmate has now produced one durable standalone game-design target and successfully published that accepted target into its game repository through bounded review and merge.
It still has not proved a concise, repeatable, end-to-end process, implementation alignment, game-runtime validity, or player outcomes.
The publication trial strengthened durable repository truth, proportional project-delivery rigor, routine autonomy, and foreground momentum while preserving the design trial's earlier failures as historical findings.
The supervision observation failed at the unattended-away boundary, and foreground continuation must not be credited as satisfying the captain's overnight request.
The next assessment entry must evaluate a later process stage on its own evidence rather than extending either successful result into an assumed overall verdict.
