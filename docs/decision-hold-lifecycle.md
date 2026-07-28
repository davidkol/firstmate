# Decision hold lifecycle mechanism

The normative policy is owned by `.agents/skills/decision-hold-lifecycle/SKILL.md` and is not restated here.
This document records the deterministic mechanism, structured surfaces, and privacy-safe regression evidence.

## Mechanism

`bin/fm-decision-hold.sh` is the only lifecycle command for an investigation or visual review's unresolved captain decisions.
The command runs tasks-axi in the active `FM_HOME`, so the existing backlog remains the only durable work database and a secondmate-owned decision stays in the secondmate home.
It never reads report bodies, review artifacts, terminal output, or chat.

The `hold` subcommand maps an originating work id and stable decision key to `<origin-id>-decision-<decision-key>`.
It creates a kind `captain` backlog item when absent and invokes `tasks-axi hold <id> --reason <reason> --kind captain` on every retry.
It rejects an identity collision, a changed title, and attempts to reopen an already resolved identity.

`hold` requires a stated default and accepts a `desk` or `play` answerable axis that defaults to `desk`.
Both are composed into the tasks-axi hold reason as `<reason> | default if unanswered: <default> | answerable: <desk|play>`, and the script rejects a reason or default that contains either marker.
`tasks-axi hold` already rejects parentheses in a reason, so the script applies the same rejection to the default before any backlog identity exists.
The default additionally rejects commas, because the shared backlog metadata parser in `bin/fm-fleet-snapshot.sh` stops the composed `(hold: ...)` field at the first comma.
The same first-comma truncation applies to a comma in the reason, so on the jq-derived surfaces such a reason reads back cut at the comma and loses the trailing default and answerable markers, while the backlog markdown and the tasks-axi session-start digest still render the whole field.
Commas in reasons are pre-existing and common on the live board, so the reason keeps accepting them and widening that shared parser was deliberately excluded from this change.
The hold reason is the only store because it is the one hold field every existing read surface already renders, and because `tasks-axi done` preserves it verbatim while `resolve` rewrites only the body, so both facts survive `complete` and `resolve` without a second copy to drift against.
A hold created before this contract has no marker; every read path resolves it as a desk question with no recorded default, and no read path and no repeated `hold` rewrites an existing body.

The `list` subcommand prints one tab-separated `<answerable> <id> <default> <title>` row per waiting captain question in the active home, play rows first, and filters to one axis with `--answerable`.
It omits a hold whose hold kind is not `captain` and a hold tasks-axi still reports as blocked, so an item held for another reason and a question whose prerequisite work is unfinished are never relayed.
It reads titles, hold kinds, blocker readiness, and reasons through `tasks-axi show` rather than parsing the quoted list projection.
That readiness agrees with the fleet snapshot and Bearings for an open blocker and for a Done blocker still present in `data/backlog.md`, and it deliberately diverges in one routinely reachable case.
Once `tasks-axi prune` archives a Done blocker out of that file, tasks-axi reports the hold as unblocked and `list` shows the question, while the fleet snapshot still counts that blocker id unresolved and Bearings withholds it.
The divergence is intentional and errs toward showing a waiting captain question rather than hiding one, and closing it was deliberately excluded because it would require a second backlog parser inside this script.

The `complete` subcommand unions the reviewed keys into `decision_keys=` and appends `decisions_reviewed=1` while originating task metadata is live.
A post-teardown visual review can complete against the surviving report and durable holds without recreating volatile task metadata.
It accepts `--none` as an explicit semantic inventory result, not as inferred absence.
It verifies every listed identity against tasks-axi before recording completion.
For an open keyed status decision, it appends a `captain-held [key=<key>]: ...` transfer event only after the matching backlog hold is durable.
`bin/fm-classify-lib.sh` recognizes that transfer as closing the live status copy without claiming that the captain has answered it.

Scout teardown calls the script's read-only `verify` subcommand after checking for the report and before removing any source state.
The `--force` path remains the explicit captain-approved discard escape hatch.

The `resolve` subcommand requires a decision file and at least one existing dependent task whose structured `blocked-by` edge points to the hold.
It records the decision digest and routed task identities as a retry identity in the hold body, clears each dependency edge through tasks-axi, and marks the hold Done only after those writes succeed.
An exact retry can finish a partial routing operation, while a changed decision or routed-task set is rejected.
A failed intermediate step leaves the hold open.

## Structured read surfaces

`bin/fm-fleet-snapshot.sh` parses canonical tasks-axi `(hold: ...)` and `(hold-kind: captain)` metadata alongside existing backlog fields.
It resolves every repeated `blocked-by:` edge against structured Done records, keeps missing blockers unresolved, and classifies only an unblocked captain hold as actionable.
Its secondmate-home summary classifies an actionable captain hold as `captain_decision` and preserves blocked captain holds as queued work in the owning home.

`bin/fm-bearings-snapshot.sh` projects actionable captain holds into `decisions_open` and leaves blocked captain holds in ordinary queued gates.
It excludes completed kind `captain` records from Recently Landed.
The projection remains read-only and does not inspect historical prose.

## Verification record

Verification date: 2026-07-14.
Additional quoted `blocked_by` regression verification date: 2026-07-17.
Plural blocker-readiness and mixed-home projection verification date: 2026-07-22.
Stated-default and desk-or-play verification date: 2026-07-28.

The focused end-to-end regression uses only synthetic `sample` identities and decision text.
It begins with a completed investigation and visual review whose genuine unresolved choice exists only in the report.
The initial Bearings snapshot correctly has no open decision, and the new teardown gate refuses to erase the source.
A later regression covers tasks-axi's quoted multi-entry `blocked_by` output so `resolve` matches the first, middle, and last ids and rejects a genuinely absent id.
The stated-default regression asserts that a question with no default is refused before any backlog identity exists, that an unstated axis falls back to `desk`, that `list` separates the two axes, that the teardown gate still refuses an uninventoried investigation, and that `resolve` returns the hold reason byte-identical.
A companion regression builds a hold the way the pre-default script did and asserts that listing, completion, verification, teardown, and resolution all still work, that its body is unchanged throughout, and that re-holding it adds the missing default without rewriting that body.
A third regression puts an item held for another reason and a question blocked by unfinished work on the same board and asserts that `list` omits both, including under `--answerable play`, and that the blocked question returns to the list once its blocker is done.
It then prunes that finished blocker out of the backlog and asserts that the stale `blocked-by:` edge remains while `list` keeps showing the question, pinning the intentional divergence from the fleet snapshot in the direction that shows a waiting captain question rather than hiding one.
The stated-default regression also asserts that a default containing a comma is refused before any backlog identity exists.

The final verification commands and their exact summarized outputs follow.

```text
$ bash tests/fm-decision-hold-lifecycle.test.sh
ok - report-only unresolved decision is reproduced and completion refuses before loss
ok - non-forced scout teardown always requires durable inventory verification
ok - captain holds are idempotent, distinct, teardown-safe, Bearings-visible, and durably routed before close
ok - completion and verification validate origins before constructing paths
ok - ended visual review follows the same decision-hold completion owner
ok - resolved findings and decision-like prose do not create false holds
ok - terminal single-owner stale status decisions do not block empty inventory
ok - main-home and secondmate-home captain holds remain correctly routed
ok - resolve matches first/middle/last in quoted blocked_by and rejects a genuinely absent id

$ bash tests/fm-fleet-snapshot-view.test.sh
ok - backlog normalization preserves strict roles and resolves every blocker compatibly
ok - durable captain-held transfer closes the duplicate live status decision
ok - snapshot parses tasks-axi rows and respects operational overrides

$ bash tests/fm-bearings-snapshot.test.sh
ok - a completed scout with decision-like report prose is a pointer, not pending
ok - action-free items (working/done/queued/landed) do not leak into Captain's Call
ok - mixed secondmate roles, partial state, and captain readiness project independently
ok - main and secondmate captain actionability use the same blocker readiness

$ bash tests/fm-brief.test.sh
ok - fm-brief.sh: investigation and visual-review completions load the shared decision policy

$ bash tests/fm-teardown.test.sh
all teardown safety cases passed

$ bin/fm-lint.sh
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)

$ git diff --check
(no output)

$ for test_script in tests/*.test.sh; do bash "$test_script"; done
ALL 71 TEST SCRIPTS PASSED
```

The 2026-07-28 stated-default and desk-or-play verification re-ran the directly affected suites.
`tests/fm-fleet-snapshot-view.test.sh`, `tests/fm-brief.test.sh`, `tests/fm-teardown.test.sh`, and `tests/fm-session-start.test.sh` each exited 0 with their existing assertions unchanged.
`tests/fm-bearings-snapshot.test.sh` is flaky on the verifying machine: it exited 0 on its first standalone run and failed on repeat runs.
That suite fails identically against a pristine pre-change copy of the repository, so the failure is not caused by this change, and no full-suite pass is claimed for that machine.
The lifecycle suite's own output follows.

```text
$ bash tests/fm-decision-hold-lifecycle.test.sh
ok - report-only unresolved decision is reproduced and completion refuses before loss
ok - non-forced scout teardown always requires durable inventory verification
ok - captain holds are idempotent, distinct, teardown-safe, Bearings-visible, and durably routed before close
ok - completion and verification validate origins before constructing paths
ok - ended visual review follows the same decision-hold completion owner
ok - resolved findings and decision-like prose do not create false holds
ok - terminal single-owner stale status decisions do not block empty inventory
ok - main-home and secondmate-home captain holds remain correctly routed
ok - resolve matches first/middle/last in quoted blocked_by and rejects a genuinely absent id
ok - every captain question carries a stated default and a desk or play axis through resolution
ok - captain questions created before stated defaults keep working and keep their bodies
ok - list shows captain-held questions once tasks-axi reports their blockers cleared
```

ShellCheck is not installed on the verifying machine, so `bin/fm-lint.sh` could not run there for the 2026-07-28 verification and CI remains the enforcing lint gate.
