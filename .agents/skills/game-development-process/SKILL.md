---
name: game-development-process
description: Use when a Firstmate session holds game-development work, before intake, planning, dispatch, review, or outcome closure.
user-invocable: false
metadata:
  internal: true
---

# One shared game-development process <!-- trace:D2/D10/D13/D14 -->

## Current owner and reconciliation

`companion-intake` owns intake transformation, project-source inspection, pertinent ambiguity, cold-readable task output, and routing accepted design to a captain-directed builder.
`delivery-doctrine` owns ship tier and outcome fields, task-local evidence depth outside the captain-directed path, reviewer boundaries, false-canon correction, and documentation procedure.
This skill owns the captain-in-the-loop implementation process, its uncertainty and evidence boundaries, the outcome ledger, the visible corrections and gaps, and both trace ledgers.

- **[P0 - EXPERIMENTAL - D13]** The captain directed Firstmate to test bringing him into the implementation loop to move an order of magnitude faster with less machine iteration and review.
- **[P1 - AUTHORITY - D2/D10]** One process and one learning destination serve every game so a lesson in one project improves the others.
- **[P2 - MIXED AUTHORITY AND GAP - D9/D10/D13]** Project design authority and runtime facts remain inputs to the shared process, D9 bars an active plan from outranking designer-owned sources, and D13 replaces only the hands-off implementation chain while leaving design intake unchanged.

## 1. Outcome ledger <!-- trace:D7/D8/D9/D12/D13/D15 -->

- **[O1 - FIRSTMATE IMPLEMENTATION - D13]** Keep one line per landed slice in `data/captain-in-the-loop-process/ledger.md` in the Firstmate home, not in a new subsystem, dashboard, schema, gate, or project file.
- **[O2 - INTAKE WRITE - D12/D13]** At intake, record the slice and its authoritative target in the active task record before work begins.
- **[O3 - LANDING WRITE - D12/D13]** At landing, Firstmate writes the completed ledger line rather than asking the builder to maintain a second record.
- **[O4 - ONE-LINE FORMAT - D13/D15]** Use `date | project | slice | production lines | all attributable AI usage (coverage, sources, units) | minutes launch to partial play availability | minutes launch to complete playable outcome | minutes to his "good enough" | minutes to landed | active captain attention minutes | defects he found and later escapes | read findings and disposition | one word on how it felt`.
- **[O5 - RECEIPT BOUNDARY - D12/D13]** The dated captain play note supplies the ordinary-route receipt, while executing code and observed runtime remain the authority for the present.
- **[O6 - REOPEN PATH - D12]** A later-discovered escape corrects the same slice record instead of leaving the earlier closure standing as the final truth.
- **[O7 - INTERPRETATION LIMIT - D12/D13]** The ledger stays descriptive and never claims that the process caused an outcome without a fair comparison.
- **[O8 - ORIGINAL TRIAL PREDICTION - D13; INTERPRETATION LIMITED BY D15]** The original three-slice prediction was launch to the captain's hands inside one hour, fresh tokens below 2.6 million per slice, and fewer than four agent sessions per slice, with two unmoved metrics falsifying the trial; retain that historical prediction without treating partial availability as complete delivery or fresh tokens as total cost.
- **[O9 - CLOCK AND ATTENTION BOUNDARY - D15]** All elapsed clocks start at launch; partial play names the available subset, while complete playable outcome means the whole accepted slice reaches its intended route in the captain's hands.
  Keep the accepted (his "good enough") and landed clocks even when a slice lands with explicitly accepted incompleteness, and mark a never-reached complete outcome as not reached rather than copying the partial clock.
  Active captain attention counts time spent directing, answering, playing, and deciding, separate from elapsed or passive waiting time.
- **[O10 - ACCOUNTING BOUNDARY - D15]** Account for all attributable AI work across builder, reviewer, Firstmate, and any contributing sub-agents or sessions, including work before launch or after first play when attributable to the slice.
  Use available records, identify sources and covered roles or sessions, and report partial or unavailable accounting with the missing coverage; do not pass a builder-only subtotal off as a slice total.
  Keep fresh input, cached input, and output tokens separately labeled with their reported units and provider semantics, avoid double-counting overlapping totals, and never convert token counts into money or quota without independent measured billing or quota evidence.
  Preserve unknown historical values as unknown, label estimates as estimates with their basis, and never invent missing measurements or backfill unknowns with zero.
  Firstmate uses the existing one-line record and available handoffs; this adds no service, dashboard, database, telemetry collector, or global quota change.

## 2. Roles <!-- trace:D9/D13 -->

- **[S30 - AUTHORITY - D13] Captain.** The captain dictates design before code, answers design questions, directs the builder in its own window, plays every build, names what is wrong, and says when to land without reviewing code.
- **[S31 - FIRSTMATE IMPLEMENTATION - D9/D13/D15] Builder.** One builder owns one slice in an isolated copy, stays warm across its sessions, builds from the target design, architecture, and captain direction under S36-S37, fixes concrete defects within that scope, integrates any genuinely independent sub-agent work itself, and never reads its own work as the reviewer.
- **[S32 - AUTHORITY AND FIRSTMATE IMPLEMENTATION - D13/D14/D15] Reader.** One fresh-context reviewer starts only when the captain says land, sees only the final diff, the slice outcome, and target-design and architecture pointers, never sees the build conversation, reports into the builder's window while the captain performs his last play, and remains advisory under the correction and decision boundaries in S39A-S39B.
- **[S33 - FIRSTMATE IMPLEMENTATION - D13] Firstmate.** Firstmate keeps design intake unchanged, checks seams before dispatch, launches the builder with design and architecture pointers, hands the captain its window, keeps it alive, lands on his word, writes the ledger line, and wakes only for a design question while the captain is away, a playable build while he is away, a failure, or a landing; every other routine builder status is a non-event.

## 3. Loop for one slice <!-- trace:D13/D14/D15 -->

- **[S34 - SLICE - D13]** The captain names the slice, or the builder proposes the next slice from the design in dependency order, and the slice is sized to reach his hands as one playable thing.
- **[S35 - SEAM CHECK - D13]** Before dispatch, Firstmate identifies every owner the slice touches and compares them with other live slices; disjoint work starts, a connecting joint is written first, and inseparable shared state stays under one builder.
- **[S36 - LAUNCH - D13]** Launch one builder in an isolated copy with the target design, architecture, slice, and standing rule that missing design intent or an architectural decision is a question, then hand the captain that builder's window.
- **[S37 - BUILD AND VERIFICATION - D13/D15]** Resolve routine concrete technical defects within accepted scope autonomously; design changes, material scope or architecture expansion, intentional acceptance of remaining known defects, and existing destructive or security decisions stay with the captain.
  Run the game and observe the changed route before calling it playable, run applicable existing checks, and add focused regression tests when they protect important changed behavior.
  Verification is proportionate to the actual change: no tests for trivial prose or tests that mirror implementation, no mandatory large suite per slice, and no blanket pipeline or new evidence schema.
  Captain play judges feel and intent and does not replace the builder's technical verification; report any verification limitation explicitly.
- **[S38 - PLAY - D13]** The captain plays the builder's running game or a play branch in his own copy, names what is wrong, and has the builder fix it in the same context; any in-window answer that fills a design gap is written by the builder into the project's design record, and a builder with no further direction after handing him a build or question declares `paused: waiting for the captain in the window on <what>` until he responds.
- **[S39 - LAND START - D13/D14]** When the captain says land, the builder commits the current head and spawns one fresh-context reviewer sub-agent with only the final diff, the slice outcome, and target-design and architecture pointers; asking itself does not satisfy the cold-read requirement, no build conversation reaches the reviewer, and no validation wrapper or pipeline step runs.
- **[S39A - ADVISORY HANDBACK - D13/D14/D15]** A successful read reports either no findings or one complete findings list into the builder's window within minutes; a failed, cancelled, or missing report stops landing, while the warm builder resolves routine concrete defects under S37 and sends only decisions reserved there to the captain.
  Show the complete findings and their dispositions to the captain; silence or an unselected finding never authorizes accepting a known defect.
- **[S39B - WARM FIX - D13/D14/D15]** The same warm builder applies bounded fixes, repeats the applicable S37 verification on the changed result, hands the fixed build to the captain, and updates the dated play note with his final result, fixed findings, and any remaining defects he explicitly accepts.
  Report any issue remaining after that bounded fix and check to the captain instead of silently accepting it or restarting review; commit every post-read code and play-note change before publishing or declaring ready, and run no second machine read.
- **[S39C - SUPPORTED LANDING - D13/D14]** The captain-directed loop is offered on all four delivery modes because their guarded landing tools do not require a pipeline-published head: `no-mistakes` and `direct-PR` use the final branch and PR through `fm-pr-merge.sh`, `validated-main` uses the local final branch through `fm-merge-main.sh`, and `local-only` uses it through `fm-merge-local.sh`.
- **[S39D - LANDING GUARDS - D13/D14]** No landing guard is weakened: the PR tool records the final PR head, the validated-main tool accepts the local branch when no origin task branch exists, both main-landing tools still require a clean fast-forward, and a second parallel local-only slice rebases onto the current local default branch before its fresh read and final captain play.
- **[S40 - RECORD - D13]** Firstmate writes the ledger line at landing, keeps the builder alive when the next slice remains in the same area, and otherwise cleans up that task.

## 4. More than one slice <!-- trace:D9/D13 -->

- **[S41 - PARALLEL SLICES - D13]** Use two or more builders and windows only when their slices are disjoint or their connecting seam is written before either starts, so the captain can play one while another builds and answer each in its own window.
- **[S42 - SEAM RULE - D9/D13]** A written seam names what each side provides, what each consumes, and who owns shared state; it is captain-owned architecture written with Firstmate, and neither builder talks around it or invents the joint.
- **[S43 - COUPLED SLICES - D13]** Shared state that cannot be split stays with one builder, which may fan out genuinely independent parts to sub-agents and integrates them itself.
- **[S44 - SILENT SEAM - D13]** A builder that finds an unwritten seam stops and asks, and two such stops in one sitting mean the seam needs more writing.

## 5. Prototypes <!-- trace:D6/D11/D13 -->

- **[S45 - EXPERIMENTAL IDEA - D13]** Prototyping is an idea, not a rule; the captain may declare a slice throwaway before it starts, it receives no reader or landing, it lives on a play branch, its play learning goes into design, and any iterative loop after it remains deferred until far later.

## 6. Turned off for captain-directed slices <!-- trace:D3/D5/D7/D8/D9/D13/D14 -->

- **[S46 - TRIAL SWITCH - D13]** No reader runs during the build.
- **[S47 - TRIAL SWITCH - D13/D14/D15]** Every pipeline step remains off throughout a captain-directed slice; S37 owns direct technical verification and S39-S39B supply the one normal review and bounded warm fixes.
- **[S48 - TRIAL SWITCH - D13/D15]** Evidence captures and scripted play replays are not mandatory during the build; S37 still requires actual game execution and observation of the changed route.
- **[S49 - VERIFICATION BOUNDARY - D13/D15]** S37 supersedes the initial deferral of local and unit tests; checker-first ceremony remains off.
- **[S50 - TRIAL SWITCH - D13]** The carried phase chain and project-local orchestrator role are retired for implementation because the builder now owns orchestration inside the slice.
- **[S51 - TRIAL SWITCH - D13]** Firstmate does not react to routine builder status while the captain is in the window.
- **[S52 - TRIAL SWITCH - D13/D14]** No one requests another review round after the warm fix in S39B; the one normal landing read remains advisory.
- **[S53 - TRIAL SWITCH - D13]** A question the captain answers in the builder window does not become a decision hold; the builder writes the answer into the project's design record.

## 7. What stays <!-- trace:D2/D5/D9/D10/D13/D14 -->

- **[S54 - AUTHORITY - D9/D13]** Design intake and its clean bulk questionnaire remain before code, and missing design intent or an architectural decision means ask rather than invent; routine technical corrections follow S37.
- **[S55 - SAFETY - D13]** Every builder works in an isolated copy, and direct captain intervention in that builder's window is authoritative.
- **[S56 - DELIVERY - D13/D14]** Firstmate treats GitHub as hosting only and lands captain-directed work through the supported ordinary landing tools in S39C after the captain's word.
- **[S57 - REVIEW AND RECORD - D13/D14]** One fresh-context normal read at landing and one ledger line per landed slice remain.
- **[S58 - SCOPE - D13]** Build no new machinery for this process unless a direct path exposes a concrete repeated need.

## Superseded implementation switches <!-- trace:D1/D3/D4/D5/D6/D7/D8/D9/D11/D12/D13 -->

The 2026-09-04 thin adjustments (D15) supersede only the earlier captain-picked-every-finding rule, testing deferral, and incomplete measurement line; their earlier decision records remain historical trace.
The standalone optional-Firstmate route remains deferred.

The 2026-09-03 captain-in-the-loop direction supersedes the hands-off implementation settings below without deleting their trace or the evidence boundaries that qualified them.

- **[S0-S5 - SUPERSEDED BY D13]** Per-job switch recording, one strong hands-off owner, cold-readable handoffs, independent challenges during work, and the future planner-builder retest no longer govern captain-directed implementation.
- **[S6-S9 - SUPERSEDED BY D13]** The conditional exact-contract switch no longer adds an implementation phase; only a connecting seam is written before parallel slices, while designer sources still outrank every plan.
- **[S10-S15 - SUPERSEDED BY D13]** Pre-build claim routing, checker assignment, and four-field closure plans are replaced by the captain playing each slice and the builder checking that it reaches its route.
- **[S16-S20 - SUPERSEDED BY D13]** Pre-build reproduction, semantic freeze, challenge-repair rounds, and per-check value tracking are replaced by one advisory cold read at the captain's landing word.
- **[S21-S24 - SUPERSEDED BY D13]** The guarded disposable-discovery-build procedure is replaced by the lighter prototype idea in S45.
- **[S25-S27 - RETAINED THROUGH P1/P2]** One shared process and learning destination remain, while project-specific design authority, runtime facts, and workflow continue to outrank generic process text.
- **[S28-S29 - SUPERSEDED BY D13]** The carried Tombhammer-chain trial no longer governs the next Martyrdome implementation slice.

## Corrections that remain visible <!-- trace:D4/D9/D10/D12 -->

- **[K1 - CORRECTION - D9]** Firstmate's claim that one owner was the only shape with no seam for intent was false because delegation, reports, compaction, and handoff are all seams, so one owner now means accountable continuity with explicit handoffs.
- **[K2 - CORRECTION - D10]** Firstmate's claim that one central process dissolved substitution because substitution required two competing processes was false because a central process can still overwrite project-local authority, runtime facts, or workflow.
- **[K3 - CORRECTION - D12]** Firstmate's claimed ten-case priming finding was fabricated from a report that explicitly disclaimed making a finding, so it supplies no evidence here.
- **[K4 - CORRECTION - D4]** Firstmate earlier hardened the captain's uncertainty about a Martyrdome specification layer into a ruling against one, and the conditional-contract decision replaced that incorrect record before D13 retired the hands-off implementation chain.

## Open gaps <!-- trace:GAP/D13 -->

- **[G1 - GAP - D10]** The test for purely game-specific material is deliberately deferred until two projects sit under one Firstmate banner.
- **[G2 - RESOLVED 2026-08-31; ORIGINAL GAP]** The permanent home and owner of this document were unsettled until `data/captain-decision-2026-08-31-process-home.md` placed the shared process in Firstmate as this agent-only skill.
- **[G3 - SUPERSEDED 2026-09-03; ORIGINAL GAP - D4/D13]** The exact-contract boundary is no longer an active implementation question for captain-directed slices beyond the seam rule.
- **[G4 - SUPERSEDED 2026-09-03; ORIGINAL GAP - D3/D5/D6/D7/D8/D9/D11/D13]** Fair comparisons never settled the hands-off role, coherent-slice, disposable-build, closure-field, handoff, or challenge switches before D13 replaced their implementation process.
- **[G5 - RESOLVED 2026-09-04 - D13/D15]** Routine technical corrections are builder-owned under S37; design and scope decisions remain captain-owned.
- **[G6 - RESOLVED 2026-09-04 - D13/D15]** S37 replaces the deferred testing question with proportionate technical verification.
- **[G7 - GAP - D13]** No captain-directed slice has yet tested the one-hour, token, and session-count prediction in O8.

## Evidence boundaries <!-- trace:D2/D3/D4/D5/D6/D7/D8/D9/D10/D11/D13 -->

- **[E1 - SURVIVED ATTACK - D5/D7]** Target-relevant falsification survived the red team as a high-confidence local heuristic, not a universal cross-game result.
- **[E2 - SURVIVED ATTACK - D9]** Captain authority over intent survived the red team because no other source can settle his intent.
- **[E3 - SURVIVED ATTACK - D3/D4/D6/D7/D9]** Explicit uncertainty labels and changeable switches survived only when their sample limits remain attached.
- **[E4 - SURVIVED ATTACK - D2/D10]** One shared learning destination survived as the captain's compounding goal, while one generic execution shape did not.
- **[E5 - NOT BROKEN, NOT VALIDATED - D5]** Coherent playable slices were not broken by the red team, but no comparative result validated their threshold.
- **[E6 - STEERING BOUNDARY - D2/D3/D4/D5/D6]** Firstmate materially steered all four original switch questions, especially role shape and specification, while the captain still rejected one location recommendation and independently changed the cadence and discovery triggers.
- **[E7 - LOW - D3/D8]** Model version, context size, reviewer count, and phase compliance have low support as explanations of outcomes and do not raise confidence in any switch.
- **[E8 - TRANSLATION BOUNDARY - D13/D14/D15]** The detailed loop is Firstmate's translation of the captain's dated rulings, so those decision records win wherever the loop conflicts with them.
- **[E9 - TRIAL BOUNDARY - D13]** The captain authorized testing this direction rather than declaring that it already works.
- **[E10 - MEASUREMENT BOUNDARY - D13]** Baseline timings, tokens, and session counts are bounded observations from four prior chunks, not a universal performance law.

## Decision trace ledger <!-- trace:D1/D2/D3/D4/D5/D6/D7/D8/D9/D10/D11/D12/D13/D14 -->

- **[T1 - PROJECT-SCOPED AUTHORITY - D1]** `data/captain-decision-2026-08-30-tombhammer-trial-continuation.md` is retained as the superseded S28-S29 trial authority.
- **[T2 - AUTHORITY - D2]** `data/captain-decision-2026-08-31-one-process-one-place.md` is carried by P1, S25-S27, and E4 as one shared process and learning destination.
- **[T3 - PROVISIONAL, MODERATE - D3]** `data/captain-decision-2026-08-31-switch-role-shape.md` is retained through superseded S0-S5 with its retest and causal limit intact.
- **[T4 - MODERATE - D4]** `data/captain-decision-2026-08-31-switch-spec-layer.md` is retained through superseded S6-S9, G3, and K4 without turning a conditional contract into a standing specification layer.
- **[T5 - AUTHORITY; LOW-TO-MODERATE CADENCE - D5/D7]** `data/captain-decision-2026-08-31-switch-checkability-routing.md` is retained through superseded S10-S15 with the unvalidated cadence distinguished.
- **[T6 - EXPERIMENTAL, PROVISIONAL; WEAK, SINGLE INSTANCE - D6/D11]** `data/captain-decision-2026-08-31-switch-discovery-build.md` is retained through superseded S21-S24 with its tentative example distinguished.
- **[T7 - PROVISIONAL AUTHORITY AND FIRSTMATE IMPLEMENTATION - D7]** `data/captain-decision-2026-08-31-closure-contract.md` is retained through superseded S10-S15 without promoting Firstmate's overhead mechanisms to captain authority.
- **[T8 - ADOPTED AUTHORITY; ONE-JOB EVIDENCE BOUNDARY - D8]** `data/captain-decision-2026-08-31-review-freshness.md` is retained through superseded S16-S20 without claiming that every check is valuable.
- **[T9 - PROVISIONAL - D9]** `data/captain-decision-2026-08-31-architecture-owner.md` is carried by P2, S31, S42, S54, E2, and K1 with the false no-seam claim corrected.
- **[T10 - MIXED AUTHORITY AND GAP; DEFERRED TEST - D10]** `data/captain-decision-2026-08-31-central-local.md` is carried by P1, P2, S25-S27, G1, and K2 with project authority preserved.
- **[T11 - EXPERIMENTAL, WEAK - D11]** `data/captain-decision-2026-08-31-discovery-safety.md` is retained through superseded S21-S24 and the lighter S45 prototype idea.
- **[T12 - AUTHORITY; COST ACCEPTED - D12]** `data/captain-decision-2026-08-31-outcome-record.md` is carried by O1-O7 with its write moments, evidence boundary, reopen path, and causal limit intact.
- **[D13 - AUTHORITY AND EXPERIMENTAL DIRECTION]** `data/captain-decision-2026-09-03-captain-in-the-loop.md` is carried by P0, O1-O5, O8, S30-S58, G5-G7, and E8-E10 as the ruling that parks the hands-off implementation goal and tests the captain in the builder's window.
- **[D14 - AUTHORITY AND CORRECTION]** `data/captain-decision-2026-09-03-landing-read-is-a-normal-review.md` is carried by S32, S39-S39D, S47, S52, S56-S57, and E8 as the ruling that keeps one advisory fresh-context review while removing the no-mistakes pipeline from captain-directed slices.

- **[D15 - AUTHORITY AND BOUNDED CORRECTION]** On 2026-09-04 the captain said "do it" to the three-item proposal in `data/captain-decision-2026-09-04-thin-process-adjustments.md`; O4/O8-O10, S31-S32, S37, S39A-S39B, S47-S49, G5-G6, and E8 carry the approved technical-fix, verification, and accounting adjustments without changing the ordinary non-game delivery policy.

## Report trace ledger <!-- trace:D1/D2/D3/D4/D5/D6/D7/D8/D9/D10/D11/D12/D13 -->

- **[R1 - BOUNDED EMPIRICAL SOURCE - D3/D5/D6/D8/D9]** `data/tombhammer-blind-what-drove-outcomes/report.md` supplies the bounded confidence labels used in E7 and the superseded switches.
- **[R2 - ADVERSARIAL SOURCE - D2/D3/D4/D5/D6/D7/D8/D9/D10/D11/D12]** `data/process-plan-redteam/report.md` supplies the survived-versus-not-validated distinction, the steering boundary, and the corrections carried in E1-E6 and K1-K3.
- **[R3 - SOURCE STUDY - D2/D3/D4/D5/D6]** `data/process-synthesis-candidate/report.md` supplies the original Hookgame comparison and the single-instance discovery-build limit retained with S21-S24.
- **[R4 - ONE-JOB COST SOURCE - D8]** `data/martyrdome-wrestling-cost-forensics/report.md` supplies the one-job review-cost boundary retained with S16-S20.
- **[R5 - BOUNDED SYNTHESIS - D13]** `data/process-synthesis-2026-09-03/synthesis.md` supplies the four-chunk baseline behind O8 and the cost observations behind S46-S53 without turning them into captain authority.
