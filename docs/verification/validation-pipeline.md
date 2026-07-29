# Validation pipeline verification

Audience: maintainer verification.

This record supports the current guarantee that a no-mistakes ship task reports its PR at the pipeline's CI-ready return point, including on a repository whose PR registers no checks.
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
Both shapes set CI-readiness. Elapsed step duration is not evidence either way, because the step runs until the PR merges or closes in both cases, and a run parked on a real CI failure can stay open far longer without ever becoming ready.

`bin/fm-crew-state.sh` already maps this case correctly: its `nm_ci_checks_state` treats `no CI checks reported - still monitoring` as `green`, alongside `checks passed`.
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
