# Startup-memory budget verification

Maintainer-verification record for `config/startup-memory-budget`, `bin/fm-startup-memory-budget.sh`, and `bin/fm-startup-memory-budget-lib.sh`.
[`docs/configuration.md`](../configuration.md) owns the setting's contract; this file records the empirical facts behind the guarantees that matter operationally.

## The guarantee this file exists to hold

Being over budget reports a curation outcome and nothing else.
It never blocks, fails, or slows a session start.
That property is what makes the budget safe to land on a home that is already far over it, so it is recorded here with the evidence rather than asserted.

## Evidence, 2026-08-07

macOS 24.6.0, bash 3.2, ShellCheck 0.11.0.
`FM_CONFIG_OVERRIDE` points at a scratch config directory and `FM_DATA_OVERRIDE` at this home's real `data/`, so the accounting run reads real files and writes nothing.

An absent setting is a concrete error rather than an inferred default:

```
$ FM_CONFIG_OVERRIDE=$S/config FM_DATA_OVERRIDE=$S/data bin/fm-startup-memory-budget.sh read
startup-memory-budget: invalid config/startup-memory-budget - file is absent
exit=1
```

The locked bootstrap path publishes the visible default, exactly one value and one newline:

```
$ od -c $S/config/startup-memory-budget
0000000    7   5   0   0  \n
0000005
$ bin/fm-startup-memory-budget.sh read
7500
exit=0
```

An over-budget total is reported and **exits 0**:

```
$ FM_CONFIG_OVERRIDE=$S/config FM_DATA_OVERRIDE=/path/to/home/data bin/fm-startup-memory-budget.sh report
estimator=ceil(UTF-8 bytes / 3) conservative-local-estimate
role=primary
effective_budget_tokens=7500
file=data/captain.md bytes=6160 estimated_tokens=2054 status=present
file=data/captain-shared.md bytes=0 estimated_tokens=0 status=absent
file=data/learnings.md bytes=79282 estimated_tokens=26428 status=present
total_estimated_tokens=28482
budget_status=over-budget
exit=0
```

This home measured 28,482 estimated tokens against the 7,500 default on the day the budget landed, roughly 3.8x over, and that is a reporting result with no effect on startup.
Bootstrap calls only the materialization step; it never runs `report`, never reads the memory files, and emits `STARTUP_MEMORY_BUDGET:` only when the setting itself is malformed or unsafe.
The estimate rounds per file rather than over the summed bytes, so a whole-surface byte count divided by three can differ by a token or two from `total_estimated_tokens`.

## Regression pointers

`tests/fm-startup-memory-budget.test.sh` pins the parser's accepted and rejected forms, default materialization, the accounting output, and primary-to-secondmate propagation.
Run it with `bin/fm-test-run.sh --family secondmate` or directly.
