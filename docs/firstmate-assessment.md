# Firstmate process assessment

Firstmate's overall process is not yet assessed.
This living assessment records dated, evidence-based stage trials without turning task history into a transcript.
The current version can judge only the Martyrdome target-design trial.

## Assessment boundary

- **Tested - Design:** One Martyrdome trial reached a durable, standalone whole-game target through discovery, question-and-answer work, drafting, and a bounded completeness audit.
- **Partly tested - Design mode and repeatability:** One-at-a-time dialogue was used extensively, while clean bulk discovery was tried only near the end on questions already shaped by earlier work.
- **Untested - Planning:** No implementation plan derived from the completed target has been assessed.
- **Untested - Implementation:** No implementation of the completed target has been assessed.
- **Untested - Review and validation:** The target received textual reconciliation and completeness checking, but no implementation review, game validation, or player-outcome validation has been assessed.
- **Untested - Publication or integration:** The completed private target had not been published into Martyrdome when this assessment was made.
- **Untested - Supervision or recovery:** Worker dispatch and context compaction occurred during design, but no bounded supervision or recovery trial has been assessed.

The successful delivery of a design target is not evidence that Firstmate's later process stages work.

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

## Reproducible session inventory

### Method

The inventory searched the canonical Codex session store and the established Claude project transcript store for case-insensitive Martyrdome references.
A session was included only when its metadata identified the primary Firstmate checkout and its canonical conversation or recorded actions materially inspected, reconstructed, designed, or managed Martyrdome-specific knowledge.
Codex counts used top-level `response_item` messages and ignored duplicate `event_msg` mirrors and every copied `compacted.payload.replacement_history`.
Claude counts used top-level human and assistant conversation records and excluded tool-result turns, hook notifications, and injected context.
Exact or imported cross-store message sequences were compared before counting a conversation as distinct.
The existing internal design-process review supplied candidate findings and counts, but every material claim used here was checked against the complete inventory and the human-owned sources above.
The final target report was used only to establish the delivered result and its deliberately open matters.
The inventory records session date and contribution rather than private transcript paths or session identifiers.

### Included primary sessions

1. **2026-07-27, Claude:** The first cross-project workflow survey inspected Martyrdome's repository and session-memory setup while strategizing a shared game-development workflow.
2. **2026-07-28 to 2026-07-29, Claude:** Catalog process scouting commissioned Martyrdome-specific scouting and handoff passes, synthesized their findings with the other games, and exposed that apparent process cleanliness could mean invisible evidence rather than an actually complete process.
3. **2026-07-30 to 2026-07-31, Claude:** Process-rollout analysis found that substantial Martyrdome notes lived outside the repository and had not been available to dispatched workers, which directly established the later durability and source-discovery risk.
4. **2026-08-08, Claude:** The process diagnosis checked why earlier project scouts missed game-development knowledge, used Martyrdome as part of that diagnosis, and captured the captain's intent-to-design-to-architecture-to-implementation goal that governs this assessment.
5. **2026-08-13, Codex:** The captain dictated a large combat-system expansion, Firstmate converted it into design prose, published a standalone design addition, and then preserved the next sequence of runtime reconstruction, question audit, and human review.
6. **2026-08-13, Codex:** Firstmate commissioned the runtime and transcript reconstruction plus the design-question audit, returned their reports, and began the first design question.
7. **2026-08-13 to 2026-08-15, Codex:** The extended target-design session performed the main question-and-answer work, created the private living target, ran completeness and bulk-question passes, incorporated answers, and closed the top-level target.

### Exclusions and unavailable evidence

- A Codex record containing the exact 2026-08-08 Claude conversation was an imported or mirrored history and was counted only as the canonical Claude session.
- Codex event mirrors and compaction replacement histories were excluded because they repeat messages from the same conversation.
- Martyrdome project-local sessions, disposable worker worktrees, and validation worktrees were excluded because this inventory is limited to primary Firstmate sessions.
- Startup digests, backlog listings, status-only carryover, tool output, and a speech-transcription test that merely said "Martyrdome" were excluded as false matches.
- General Firstmate sessions that only listed Martyrdome among registered projects and performed no Martyrdome-specific work were excluded.
- No additional harness store was included because no other local store could be identified reliably as a canonical primary Firstmate transcript rather than guessed from incidental files.
- The inventory establishes every identifiable session in the two canonical stores available on this machine, but it cannot prove that an unavailable, deleted, or unrecognized external transcript never existed.

## Design trial D1 - Martyrdome whole-game target

### Scope and observed outcome

The trial began with cross-session recovery of Martyrdome knowledge and ended with a private standalone target that was judged complete enough to pause at the reusable whole-game-system level.
The result deliberately left slide handling for comparative playtesting, boss-specific answer structures for boss design, Broken-Muscle-Armor presentation for authored and feel-tested treatment, and exact values or content-specific effects for their named later activities.
The result did not authorize gap analysis, implementation planning, content authoring, or publication.

The design outcome was successful, but the process that produced it was not efficient or consistently aligned with the captain's operating needs.
The design-stage verdict is therefore **a useful target produced through a process mismatch**.

### Measured evidence

- The complete inventory contains seven distinct primary sessions across two canonical harness stores.
- The extended target-design session contained 160 captain messages after injected and hook records were excluded.
- A reproducible lower-bound count found 100 design-question prompts in that session, consisting of 99 option menus and the initial open-ended design question.
- The same session contained 25 explicit "Book ...?" prompts and nine compaction records.
- Seven worker passes were associated with the extended target-design work, including one aborted premature project ship and six completed report passes.
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

Implementation review, runtime validation, and player-outcome validation are untested, so no verdict is recorded.

### Publication or integration

Publication of the completed target and its integration into Martyrdome are untested, so no verdict is recorded.

### Supervision or recovery

Dedicated supervision and recovery behavior is untested, so no verdict is recorded.

## Current assessment conclusion

Firstmate proved that it can help produce a durable, standalone game-design target, but it did not yet prove a concise, repeatable, end-to-end process for doing so.
The strongest result was the design artifact and the useful direct dialogue that shaped it.
The dominant failures were late durability, primary-session overreach, excessive approval cadence, premature delivery ceremony, mixed audiences, and unwanted presentation tooling.
The next assessment entry must evaluate a later process stage on its own evidence rather than extending the design result into an assumed overall verdict.
