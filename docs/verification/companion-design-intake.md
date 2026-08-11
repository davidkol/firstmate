# Separate Companion design-intake verification

This maintained record owns the genuinely cold Delivery acceptance for the separate design-intake scout.
The generated brief from `bin/fm-brief.sh --design-intake` owns the normative discovery and report contract.
Static tests prove format and routing only.
Static fixtures did not prove model generation.

## Deterministic implementation evidence

The implementation writer prepared the branch on 2026-08-11 from Companion commit `6077d702e1d50a8e364dc77b0eb8a64f018545c2` plus supervision-noise commit `825cc65d25542b429d0975bd206866bcf4c7bb5f`.
The pre-feature combined tree was verified as `9e651111db26042a9c771d25f07c47cde9bbf9a7`.
The two supervision open-decision baseline suites passed before feature edits.
The complete deterministic gate is:

```sh
/bin/bash -n bin/fm-brief.sh
bin/fm-test-run.sh tests/fm-brief.test.sh
bin/fm-test-run.sh tests/fm-companion-intake.test.sh
bin/fm-test-run.sh tests/fm-decision-hold-lifecycle.test.sh
bin/fm-test-run.sh tests/fm-send-resolve-key.test.sh
bin/fm-test-run.sh tests/fm-wake-drain-open-decisions.test.sh
bin/fm-test-run.sh tests/fm-wake-drain-open-decisions-cursor.test.sh
bin/fm-doc-audience-check.sh
bin/fm-lint.sh
bin/fm-test-run.sh --changed --require-nonempty
bin/fm-test-run.sh --all
git diff --check
```

Record the final implementation commit and bounded summaries from every command above after the writer lane commits the change.

## Observed cold-acceptance failure and focused rerun

The 2026-08-11 cold Delivery acceptance exposed a terminal status-write violation after the authorized second steer.
The scout used an editor on a stale status snapshot, temporarily placed `done: design-intake report reconciled` above the existing `resolved [key=report-ready]:` line, and then rewrote the append-only status log to repair the order.
That run does not satisfy required observation 16 and is retained as failing model-behavior evidence.
The generated contract now requires a fresh status-file read after the second steer, verification that `report-ready` is already resolved, a literal terminal line appended at EOF, and no edit, reorder, replacement, or other rewrite of existing status lines.
On 2026-08-11, `/bin/bash -n bin/fm-brief.sh` exited 0 after the contract fix.
On 2026-08-11, `bin/fm-test-run.sh tests/fm-brief.test.sh` reported `total=1 failed=0 skipped_gate=0` after focused assertions covered all four terminal-write constraints.
This focused rerun proves the generated normative contract only and does not replace a genuinely cold Delivery rerun from the final fix commit.

## Cold Delivery boundary

The genuinely cold Delivery acceptance must not be run in the implementation writer lane.
Run it later from the final committed implementation in a fresh peer Firstmate checkout, an empty peer `FM_HOME`, and a separate isolated Delivery worktree.
Launch the generated scout through the unchanged `fm-spawn.sh` path with the existing scout kind and the Codex harness.
Retain metadata and transcript evidence that this is a newly started bare Codex process with no prior transcript or summary and with an endpoint distinct from Firstmate and Delivery's primary checkout.
Do not expose an authored expected-question fixture or authored expected report to the cold process.

The cold process must follow Delivery's `AGENTS.md` router and inspect `SPACEGAME.md`, pertinent sections of `docs/execution.md` and `docs/findings.md`, `docs/reviews/z5-playtest-kit.md`, current implementation and tests, and current git history.
It must treat `data/delivery-game-status-report/report.md` as a lead rather than final authority.
It must inspect `data/delivery-game-status-report/decision-fl5c-helm-view.md`, the current `delivery-ship-viewport` task, current tasks-axi records, and the full current decision-hold records for every possible semantic match.

## Required observations

1. The report names the exact Delivery commit and stays within 12 candidate dispositions and three new shortlist items.
2. The process discovers at least one grounded non-fixture design question from project-owned sources and cites evidence that a reviewer can independently inspect.
3. Reconciliation independently compares semantic question, answerability axis, default, evidence, and affected work with every possible current hold or decision match.
4. The FL5c helm or viewport candidate is classified as answered from the verbatim decision and current viewport task rather than from stale project prose.
5. The viewport candidate creates no new hold and does not enter the new shortlist.
6. At least one genuinely play-dependent question remains classified as play despite code, tests, or an agent recommendation.
7. Zero new holds is a valid result when every grounded candidate is answered, duplicate, stale, premature, or implementation-only.
8. A zero-new result uses `complete --none` only to attest that this intake origin created no distinct unresolved question.
9. At least one grounded candidate independently matches a current open hold, and repeated reconciliation creates at most one hold per semantic question.
10. Regular Companion presents exactly one pertinent question and reads the default from the real hold list when reusing an existing question.
11. A new surviving shortlist item is presented first only in the immediate handoff, while a later desk or play retrieval promises pertinence rather than persisted intake rank.
12. No affected task is blocked while a question waits, and answer routing adds its dependency only immediately before the existing resolve command clears it.
13. Delivery's before and after commit, tracked diff, and untracked-file observations are identical, and the scout creates no implementation task or game change.
14. The first steer resolves `report-ready` while explicitly withholding terminal completion.
15. The existing completion gate succeeds only after the first steer, and the second ordinary steer arrives only after completion succeeds.
16. The scout appends terminal done only after the second ordinary steer and then passes ordinary teardown verification.

## Evidence to retain

- Record the acceptance date, final Firstmate implementation commit, and exact Delivery commit.
- Record the fresh peer-home, Firstmate checkout, Delivery primary checkout, and isolated scout-worktree paths.
- Retain the exact generation and spawn commands, generated brief path, report path, metadata, and cold-process transcript evidence.
- Retain every matched or newly created hold id and the independent semantic-match check for each one.
- Retain each immediately or later presented Companion question, its desk or play context, and its default, with exactly one question per context.
- Retain the first steer, completion result, second ordinary steer, terminal status order, and teardown result.
- Retain clean Delivery before and after observations.
- State explicitly in the completed acceptance record that static fixtures did not prove model generation.

## Current status

The first cold Delivery acceptance exposed the append-only terminal status violation recorded above.
A genuinely cold Delivery rerun is pending from the final committed fix head.
