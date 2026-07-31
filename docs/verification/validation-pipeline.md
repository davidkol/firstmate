# Validation pipeline verification

Audience: maintainer verification.

This record supports three current guarantees: that a no-mistakes ship task reports its PR at the pipeline's CI-ready return point, including on a repository whose PR registers no checks, that the `validated-main` delivery mode validates through the same pipeline without ever opening a PR, and that the pipeline reads repository `commands` and `agent` from the trusted default-branch config.
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

Observed end to end on a throwaway repository, complete step table from a real `--skip pr,ci` run:

```text
steps[9]{step,status,findings,duration_ms}:
  intent,completed,0,2
  rebase,completed,0,473
  review,completed,1,28729
  test,completed,1,72296
  document,completed,0,83941
  lint,completed,0,15
  push,completed,0,223
  pr,skipped,0,0
  ci,skipped,0,0
outcome: passed
pr_state: none
```

The review step ran for 28.7 seconds and parked at its gate with a real finding before anything else advanced, so skipping `pr` does not skip `review`.
Only `pr` and `ci` report `skipped`; the entire local review surface completed, and `pr_state: none` confirms no pull request was ever created.
Dropping the PR drops ceremony, not the reviewer; a change that reads "no PR" as "no pipeline" has removed the only thing between an unread change and the default branch.

The same run also pins why landing must read the published head rather than the local branch:

```text
submitted_head: edb06baa7750c369bfea570c7315097f4cab249b
current_head:   5cdf532bb69d64b4f49ca71d91e9e4be3c5631d8
pushed_head:    5cdf532bb69d64b4f49ca71d91e9e4be3c5631d8
relation: behind
next_action.code: sync
```

The pipeline committed its own fix rounds and published them while the local branch stayed at the submitted head.
Merging the local head would have landed the unfixed commit, which is why `bin/fm-merge-main.sh` takes `origin/<branch>` as the merge source and refuses when the local branch carries commits that head does not contain.

## Repository commands come from the trusted default-branch config

Verified on 2026-07-29 against `no-mistakes version v1.41.2 (867d64d) 2026-07-24T06:16:23Z`, by extracting literal strings from the installed binary.

`RepoConfig` carries the struct tag `yaml:"allow_repo_commands"`, consistent with the ten-field schema recorded above, and the binary carries these four strings:

```text
repo commands/agent loaded from default branch, not pushed branch
allow_repo_commands is enabled on the default branch: honoring commands/agent from pushed branch
trusted repo config: parse failed; commands/agent from pushed branch will be disabled
failed to fetch default branch into worktree; trusted config disabled (commands/agent from pushed branch will be dropped)
```

`commands` and `agent` are loaded from the trusted default-branch copy of `.no-mistakes.yaml`, not from the pushed branch, whenever `allow_repo_commands` is unset.
Firstmate does not set `allow_repo_commands`.
The consequence a maintainer will get wrong is that a branch editing `commands.test` still validates under the default branch's command, so a new or changed test command does not take effect for its own validation run and only becomes live once `.no-mistakes.yaml` reaches the default branch.
The two failure modes matter too: an unparseable trusted config, or a default branch that cannot be fetched into the worktree, drops the pushed branch's `commands` and `agent` rather than honoring them.

## The review step runs alone, and in its own agent process

Verified on 2026-07-30 against `no-mistakes version v1.41.2 (867d64d) 2026-07-24T06:16:23Z`.

This is the evidence the `direct-PR` and `local-only` review-only runs rest on.
It answers two separate questions: whether the pipeline can run review with every other step omitted, and whether the agent that performs that review is a different context from the worker that wrote the change.

`--skip` accepts every step except the one being kept, so a review-only run is expressible with the shipped flag and needs no new mechanism:

```console
$ no-mistakes axi run --intent "probe" --skip bogus-step-name
error: "unknown step \"bogus-step-name\""
help[1]: "Valid steps: intent, rebase, review, test, document, lint, push, pr, ci"
```

Observed end to end on a throwaway repository, driving `bin/fm-validate.sh` against a task whose `state/<id>.meta` records `mode=direct-PR`, over a 17-line documentation-only change.
The worker typed no `--skip`; the eight omissions were derived from the recorded mode.
Complete step table at the terminal outcome:

```text
steps[9]{step,status,findings,duration_ms}:
  intent,skipped,0,0
  rebase,skipped,0,0
  review,completed,2,64399
  test,skipped,0,0
  document,skipped,0,0
  lint,skipped,0,0
  push,skipped,0,0
  pr,skipped,0,0
  ci,skipped,0,0
outcome: passed
```

The review step is the only one that executed, and the run still reaches a normal terminal `outcome: passed`.

The reviewing agent is a separate operating-system process the daemon starts, not the session that produced the change.
`no-mistakes axi logs --step review` records the spawn and exit of that process by pid:

```text
  reviewing changes...
  claude started pid=25665
  ...
  claude exited pid=25665 status=success
```

`no-mistakes axi run --help` states the same boundary from the other side: "The calling agent drives AXI approval gates but does not become the pipeline agent."
That is what makes the step a fresh-context review rather than an author re-reading their own work.

The review is a real verdict, not a formality.
On the 17-line documentation change it returned two findings, the first being that every command the new guide instructs a contributor to run (`./configure`, `make`, `make test`) exists nowhere in the repository, which it established by listing the tracked files.
On a separate 6-line shell helper it returned three findings including a confirmed command-injection defect, which it demonstrated by executing the committed script rather than reasoning about it:

```text
| `./divide.sh 'HOME[$(cmd)]+1' 1` | **`cmd` executes** - arbitrary command execution |
```

### The local-only review publishes nothing

`local-only` forbids reaching any remote, so its review is only safe because `push` is one of the eight skipped steps.
Verified on 2026-07-30 against the same binary, on a repository shaped like the registry's `local-only` project: an `origin` pointing at a local filesystem path rather than a forge.

`bin/fm-validate.sh` announced the derived set, and the review ran:

```text
fm-validate: task lo-review is mode=local-only; skipping pipeline steps: intent,rebase,test,document,lint,push,pr,ci
    review,awaiting_approval,4,96475
```

`git ls-remote --heads origin` returned the identical single `refs/heads/main` line immediately before and immediately after the run.
The task branch was never published, and no other ref appeared.

### A repository with no remote at all cannot run this review

Verified on 2026-07-30 against the same binary.
This is a real limit, not a configuration mistake, and it is the one case where a delivery mode cannot carry the reviewer.

`no-mistakes axi run` refuses without an initialized gate:

```console
$ no-mistakes axi run --intent "add b" --skip intent,rebase,test,document,lint,push,pr,ci
error: repo not initialized (run 'no-mistakes init' first)
```

and `no-mistakes init` refuses without an `origin` remote:

```console
$ no-mistakes init
init: no 'origin' remote in <path>

no-mistakes pushes your branch and opens a pull request, so it needs a remote to push to.
```

An `origin` on a local filesystem path satisfies it, which is what a clone of a local repository already has, so the fleet's registered `local-only` project can run the review.
A project with genuinely no remote cannot, and that must be recorded as a named gap on the project rather than described as a safeguard that is running.

### Measured cost

| Change | Review-only run | Full pipeline, same class of change |
|---|---|---|
| 17-line documentation change | 64.4s step, 66s wall clock | about 26 minutes |
| 6-line shell helper | 107.6s step, 109s wall clock | not measured |
| 7-line shell helper, local-only | 96.5s step, 99s wall clock | not measured |

Answering the review gate and publishing the branch add about a second between them, so the light path's end-to-end cost is the review step plus the worker's own PR call.
The 26-minute figure is the captain's own reference case from 2026-07-29 and is what moved the fleet default to `direct-PR`; the review-only run is roughly a twenty-fourth of it, and inside the captain's stated 5-minute end-to-end target for this path with a wide margin.

Cost scales with the change under review, not with repository size, so a large change will cost more than these figures.
The numbers above are two data points, not a bound.
