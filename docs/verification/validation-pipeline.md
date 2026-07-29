# Validation pipeline verification

Audience: maintainer verification.

This record supports two current guarantees: that a no-mistakes ship task reports its PR at the pipeline's CI-ready return point, including on a repository whose PR registers no checks, and that the `validated-main` delivery mode validates through the same pipeline without ever opening a PR.
`AGENTS.md` section 7 owns the operating contract and `bin/fm-crew-state.sh` owns the state mapping.
Task-specific chronology, temporary paths, run identifiers, and delivery transcripts remain in private reports or PR evidence.

## No registered checks is a CI-ready result

Verified on 2026-07-28 against `no-mistakes version v1.41.2 (867d64d) 2026-07-24T06:16:23Z`.

`internal/pipeline/steps/ci.go` applies a registration grace period before it trusts an empty check list:

- `defaultChecksGracePeriod = 60 * time.Second`
- while `len(checks) == 0 && elapsed < gracePeriod()`, the step logs `no CI checks reported yet, waiting for checks to register...` and keeps polling
- once the grace elapses with `len(checks) == 0`, the step logs `no CI checks reported - still monitoring until merged or closed`
- that message sets run CI-readiness true, because readiness is `message == ciChecksPassedMsg || message == ciNoChecksPassedMsg`

CI readiness is one of the three points `no-mistakes axi run` returns at, so the worker is released roughly a minute after the PR opens.
The step itself keeps polling afterwards only to observe the merge or close, which is why the worker must not wait for the step to finish.

Observed end to end on this repository, whose fork registers no checks, complete step log:

```text
monitoring CI for PR #1 (timeout: 168h0m0s)...
no CI checks reported yet, waiting for checks to register...
no CI checks reported yet, waiting for checks to register...
no CI checks reported - still monitoring until merged or closed
base branch advanced (b6e351d34117..44bd65bb8b95), re-arming CI monitor timeout
PR has been merged!
```

Two grace-period polls, then CI-ready.
The run recorded a CI-ready timestamp and the step ended at the merge rather than at the 168-hour `ci_timeout`.
A second checkless run on this repository reached CI-ready the same way and then logged `no CI checks reported - still monitoring` again across two further base advances, which is the background monitoring the worker must not wait on.

The comparison that matters is against runs on a repository that does register checks: those log `CI checks running, waiting for results...` and then `all CI checks passed`.
Both shapes set CI-readiness.
Elapsed step duration is not evidence either way, because the step runs until the PR merges or closes in both cases, and a run parked on a real CI failure can stay open far longer without ever becoming ready.

`bin/fm-crew-state.sh` maps the steady-state checkless marker correctly: its `nm_ci_checks_state` scans the step log for the LAST recognized marker (`tail -1`) and treats `no CI checks reported - still monitoring` as `green`, alongside `checks passed`.
A trailing `base branch advanced ... re-arming CI monitor timeout` marker instead reads `not-ready`, deliberately and pinned by `tests/fm-crew-state.test.sh`.
That is the last marker the scan recognizes in the PR #1 log quoted above, because its closing `PR has been merged!` line is not one of the recognized markers.
That window is pre-existing and self-clears on the next poll, and it does not hold the worker: the pipeline releases the worker at its own CI-ready return point, and the resulting `done: PR ... checks green` line is recognized independently by `log_reports_ci_ready`.
The prose instructions were the only surface that still described a green check result as the sole ready signal.

## No repository-level way to declare an absent CI step

Verified on 2026-07-28 against the same binary version.

`internal/config/config.go` defines `RepoConfig`, the type `.no-mistakes.yaml` decodes into, with exactly ten YAML fields: `agent`, `commands`, `ignore_patterns`, `allow_repo_commands`, `auto_fix`, `commit`, `intent`, `test`, `document`, and `disable_project_settings`.
Its `UnmarshalYAML` decodes into a raw struct carrying the same ten fields, so no undocumented key is honored.
None of them disables a pipeline step or declares one absent.

The `ci` key that exists in the schema is `auto_fix.ci`, an auto-fix attempt count, with `auto_fix.babysit` as its documented legacy alias.
`ci_timeout` is a global-only field and a timeout rather than a declaration.

The only shipped mechanism for omitting the step is the per-invocation `--skip ci` flag on `no-mistakes axi run`, which no repository configuration can make sticky.
Nothing in firstmate should be built on the assumption that a repository can declare itself checkless to the pipeline; the grace-period behavior above is what makes checkless repositories work.

## The pipeline cannot land on the default branch, but it can validate without a PR

Verified on 2026-07-28 against the same binary version.

This is the evidence the `validated-main` delivery mode rests on, and it settles a question that is easy to get wrong in the opposite direction.

The pipeline refuses to run on the default branch at all, so no flag combination makes it push the default branch itself.
The shipped skill at `~/.claude/skills/no-mistakes/SKILL.md` states it under "Before you start":

```text
- You must be on a **feature branch**, not the repository's default branch.
```

and the binary carries the matching refusal and remedy strings:

```text
refusing to validate %q: it is the default branch
Put your changes on a feature branch: `git switch -c <branch>`, then re-run
```

The pipeline's `push` step therefore publishes the task branch, never the default branch, and every terminal outcome the skill documents is PR-shaped (`checks-passed` leaves the PR open, `passed` means it merged or closed).
Landing on the default branch is firstmate's action, not the pipeline's, which is why `bin/fm-merge-main.sh` exists.

What the pipeline does support is validating with no PR.
`--skip` is validated against a fixed step list, client-side, before any run starts:

```console
$ no-mistakes axi run --intent "probe" --skip bogusstep
error: "unknown step \"bogusstep\""
help[1]: "Valid steps: intent, rebase, review, test, document, lint, push, pr, ci"
```

`pr` and `ci` are both accepted members of that list, and the binary carries dedicated paths for each omission:

```text
skipping PR creation: %s
no PR URL found, skipping CI
```

So `--skip pr,ci` leaves `intent`, `rebase`, `review`, `test`, `document`, `lint`, and `push` running, which is the entire local review surface.
Dropping the PR drops ceremony, not the reviewer; a change that reads "no PR" as "no pipeline" has removed the only thing between an unread change and the default branch.

Scope of this verification: the refusal strings, the step list, and the skip-validation output above were read from the installed binary and its shipped skill, and the invalid-step probe was run.
A full `--skip pr,ci` run was not executed as part of recording this.
