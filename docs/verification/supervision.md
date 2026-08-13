# Supervision integration verification

Audience: maintainer verification.

This record supports current session-start, turn-end, watcher-continuity, and wedge-alarm guarantees.
Operator behavior and active limits remain in the linked current guides.
Task-specific chronology, temporary paths, run identifiers, and delivery transcripts remain in private reports or PR evidence.

## Native session-start delivery

The cross-harness transport pass ran on 2026-07-17 with Codex 0.144.4, Grok 0.2.103, OpenCode 1.17.18, Pi 0.80.10, and the tracked Claude hook wiring.
It predates the run tier, so it covers the nudge payload's transport only; the Claude run-tier evidence is the separate dated subsection below.

Codex command shape:

```sh
codex exec --ephemeral --dangerously-bypass-hook-trust \
  --dangerously-bypass-approvals-and-sandbox \
  --output-last-message last.txt \
  'Follow any SessionStart hook context before this prompt.'
```

Observed result: the `SessionStart` hook completed and its stdout reached model context.

That result and the later Codex probe recorded under [Semantic busy state](#semantic-busy-state) disagree, and the conditions that distinguish them are only partly recorded.
This one ran on codex-cli 0.144.4 and does not record its checkout shape, so it cannot be read as covering the primary checkout or a linked worktree specifically.
The later one ran on codex-cli 0.145.0, explicitly in a linked worktree, and found that Firstmate-written project hooks under `<worktree>/.codex/hooks.json` fired for neither an interactive pane nor `codex exec`, while global `~/.codex/hooks.json` `SessionStart` hooks fired in the same runs.
Both are real observations; they differ in codex-cli version and in checkout shape, and only the newer one says where it ran.

Neither observation settles the installed build, so what session-open tier follows from them is not decided here: [`../sessionstart-nudge.md`](../sessionstart-nudge.md) owns tier assignment and the tracked re-verification card.

Grok command shape:

```sh
grok --trust -p 'Follow any SessionStart hook context before this prompt.' \
  --permission-mode bypassPermissions --output-format plain
```

Observed result: the project hook ran, but its stdout did not reach model context.
This is the current Grok fail-open limit.

OpenCode was checked in both headless and interactive modes.
`client.session.promptAsync` accepted the nudge in both cases; the persistent TUI completed the generated turn, while `opencode run` exited before another turn.
This is the current headless fail-open limit.

Pi command shape:

```sh
pi -p -e .pi/extensions/fm-primary-turnend-guard.ts \
  --no-context-files --no-session \
  'After obeying any earlier session-start instruction, reply with exactly PI_SMOKE_DONE.'
```

Observed result: `PI_SMOKE_DONE`, with one session-start execution.
The earlier `sendUserMessage` counterfactual raced the positional prompt; the current non-triggering `pi.sendMessage` custom message did not.
The installed pi-signed 0.82.0 wrapper repeated the Pi primary extension and session-start path on 2026-07-27.
[`runtime-backends.md`](runtime-backends.md#tmux) owns the shared-ancestry evidence and authoritative selection-marker boundary.

### Claude run-tier hook delivery and its inline size limit

Measured 2026-08-07 on Claude Code 2.1.224, against a throwaway project whose only `SessionStart` hook printed a generated payload of a controlled size.
This is the harness-supplied fact the run tier depends on, and no portable test can see it.
Ground truth is the session transcript record rather than the model's own report: `attachment.stdout` is what the hook printed, and `attachment.content` is what reached model context.

| Hook stdout | Reached context | Shape |
| --- | --- | --- |
| 8,433 B | 8,432 B | delivered whole |
| 10,113 B | 2,298 B | `<persisted-output>` notice plus head preview |
| 30,107 B | 2,299 B | `<persisted-output>` notice plus head preview |
| 132,036 B | 2,299 B | `<persisted-output>` notice plus head preview |

The end-to-end path was confirmed the same day against a real session opened in a Firstmate-shaped throwaway home carrying only the tracked `SessionStart` hook.
The hook ran `bin/fm-sessionstart-run.sh`, which routed to the full digest; `bin/fm-lock.sh` resolved the harness through the hook process's own ancestry and recorded `lock acquired: harness pid 27963`; bootstrap's locked sweeps ran; and `state/.session-start-complete` was published with that same pid, so a later `clear` or `compact` re-emits rather than repeating startup.
That home's digest was 7,776 bytes and reached model context whole at 7,774 bytes, with `LOCK`, `BOOTSTRAP`, `WAKE QUEUE`, `READ-ONCE CONTRACT`, `FLEET STATE`, `CONTEXT`, and `NEXT STEP` all present in the new order.

The inline limit therefore sits between 8,433 and 10,113 bytes.
Above it, context receives `<persisted-output>` wrapping `Output too large (NN KB). Full output saved to: <path>`, roughly two kilobytes of the payload's HEAD, and an ellipsis; the full text is written to that file and nothing else reaches the model.
Truncation is head-preserving, confirmed by a 132 KB payload whose first line survived and whose last line did not.

Two consequences for the session-start digest:

- The persisted file is the digest whenever the digest is large, so AGENTS.md section 3's instruction to read that file before acting is what keeps a session from starting blind. This is not a corner case: the main home's digest measured 123,926 bytes on 2026-08-07.
- `bin/fm-session-start.sh`'s fleet-state-before-context ordering only pays off once the digest fits inline, because a two-kilobyte head preview never reaches any bulk section. It is correct and cheap insurance, not the fix. Measured on that same 2026-08-07 main-home digest, `CONTEXT` was 89,867 bytes of the 123,926 and `data/learnings.md` alone was 77,504; bounding curated startup memory is what would bring the digest under the inline limit.

Same-day comparison of the composition change alone, run against a copy of the main home's `data/` and `state/`: 128,856 bytes before, 123,926 after, entirely from `FLEET STATE` falling from 32,260 to 26,356 as done rows, the queued bound, and the per-line status cap took effect.

This composition change is one part of the session-start cost problem and does not by itself bring the digest under the inline limit, which the main home's digest still exceeds by an order of magnitude.

Current deterministic and live entry points:

```sh
tests/fm-sessionstart-nudge.test.sh
tests/fm-session-start.test.sh
tests/fm-captain-translation-contract.test.sh
FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh
FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh
```

The Ahoy first-message boundary was reverified on 2026-07-22 with Pi 0.81.1 and OpenCode 1.17.18.
Marked current operational input and the two exact legacy compatibility shapes selected Bearings, while genuine near-miss captain messages remained real boundaries.
The detailed reconciliation and task chronology stay in the private audit report and PR evidence.

## Semantic busy state

The per-adapter semantic sources behind [`bin/fm-busy-lib.sh`](../../bin/fm-busy-lib.sh) were live-verified on 2026-07-28 against firstmate-launched workers wired exactly as `fm-spawn` writes them.
Each pass polled `state/<id>.busy-state` while a real turn ran.

| Harness | Version verified | Semantic source | Observed result |
| --- | --- | --- | --- |
| Pi | 0.82.0 | Extension `agent_start` / `agent_settled` with `ctx.isIdle()` | The spawn seed `busy source=fm-spawn`, then `busy source=pi-ext event=agent-start`, then `idle source=pi-ext event=agent-settled`; the turn-end marker was still touched. |
| OpenCode | 1.17.18 | Plugin `session.status` | In a real TUI pane: seed, then `busy source=opencode-plugin event=session-busy`, then `idle source=opencode-plugin event=session-status-idle`. |
| Claude | 2.1.220 (Claude Code) | Hooks `UserPromptSubmit`, `Stop`, `StopFailure`, `SessionEnd` | `UserPromptSubmit` fired for the argv launch prompt and each steer, and `Stop` closed every completed turn. A mid-stream Escape interrupt fired no closing hook, which is why the firstmate-controlled clear exists. `StopFailure` and `SessionEnd` are wired from the four hook names present in the installed binary; only the abnormal paths they cover were not reproduced live. |
| Codex | codex-cli 0.145.0 | None usable | See below; classifies `unknown codex-unverified`. |
| Kimi (standalone) | not installed | None usable | No binary on `PATH`, so the gate stays closed and it classifies `unknown kimi-unverified`. |
| Grok | 0.2.112 | Isolated rendered-tail fallback | Retained unconverted; the approved audit could not credit a live structured-lifecycle run. |

Codex was probed two ways, both refused:

```sh
codex app-server daemon start
codex exec --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust 'Reply with exactly PROBE2.'
```

The daemon refused with `managed standalone Codex install not found`, and an interactive TUI worker neither starts nor attaches to the app-server control socket, so no client can observe its turns.
Firstmate-written project hooks under `<worktree>/.codex/hooks.json` fired for neither an interactive pane whose directory trust was granted nor `codex exec`, in both cases with `--dangerously-bypass-hook-trust`, while global `~/.codex/hooks.json` `SessionStart` hooks fired in the same runs.
Codex also exposes no `StopFailure` hook, so an API-error turn end would need separate coverage even after hook discovery works.
The app-server protocol schema does define the required lifecycle (`turn/started`, plus a `turn/completed` status of `completed`, `interrupted`, `failed`, or `inProgress`), so the gate is a reachability problem rather than a protocol gap.

Deterministic entry points:

```sh
tests/fm-busy-state.test.sh
tests/fm-busy-adapter-wiring.test.sh
tests/fm-crew-state.test.sh
```

## Codex primary permission policy

The supported primary Codex entry and its away-mode escalation guard were verified on 2026-08-12 with codex-cli 0.147.0 on macOS.

The historical rollout separated the failure's three layers: the initiating trigger was a primary turn whose effective policy was `on-request`/`workspace-write`; the masking condition was that routine operations stayed inside that restricted workspace until away startup needed sandbox-sensitive supervision mechanics; and the visible symptom was the resulting `require_escalated` retry remaining unresolved for 17,657.9 seconds after the captain left.
The unrestricted primary probe avoided that trigger with `never`/`danger-full-access`, while the separate worker dispatch test showed that `fm-spawn.sh` already retained its established `--dangerously-bypass-approvals-and-sandbox` path.

The effective-policy oracle was exercised against both separable configurations:

```sh
codex doctor --json \
  -c 'approval_policy="never"' \
  -c 'sandbox_mode="danger-full-access"' --enable hooks \
  | bin/fm-codex-primary-policy-check.sh

codex doctor --json \
  -c 'approval_policy="on-request"' \
  -c 'sandbox_mode="workspace-write"' --enable hooks \
  | bin/fm-codex-primary-policy-check.sh
```

Observed output and statuses:

```text
approval=Never filesystem=unrestricted network=enabled hooks=enabled
exit=0
error: Codex effective policy mismatch: approval=OnRequest filesystem=restricted network=restricted hooks=enabled
exit=1
```

A third doctor fixture preserved the good sandbox values but omitted `hooks` from `config.load.details["enabled feature flags"]`; the same oracle reported `hooks=disabled` and exited 1.
The launcher passes `--enable hooks` to both doctor and the TUI, so a persisted `features.hooks=false` cannot silently remove SessionStart, PreToolUse, or Stop after the check.

A last-value-precedence probe showed Codex accepts `-c=approval_policy="on-request"` and `-c=sandbox_mode="workspace-write"` after canonical unrestricted overrides and then reports `OnRequest`/`restricted`.
The launcher consequently refuses every caller config, profile, or feature layer before doctor or TUI launch, including that `-c=` form and `--disable hooks`; both refusals exited 2.
It also refused `exec`, `review`, `delete`, `mcp-server`, and `fork` before doctor so its acceptance banner applies only to the verified fresh/resume interactive lifecycle.

The ordinary player path used an isolated peer home and `bin/fm-open.sh <home> codex --no-alt-screen <acceptance-prompt>`.
Before the TUI accepted the prompt, the launcher printed `fm-codex-primary: effective policy verified: approval=Never filesystem=unrestricted network=enabled hooks=enabled`; the TUI displayed `permissions: YOLO mode`; the rollout's first `turn_context` recorded `approval_policy:"never"` and `sandbox_policy:{"type":"danger-full-access"}`; and one shell call printed `PRIMARY_POLICY_LIVE_OK`.
The same restricted session was then resumed through `bin/fm-open.sh <home> codex resume --no-alt-screen <session-id> <acceptance-prompt>`.
Its next `turn_context` changed from the saved session's `on-request`/`workspace-write` posture to `never`/`danger-full-access`, the resumed TUI again displayed YOLO mode, and its shell call printed `RESUMED_POLICY_OK`.

The negative player path launched raw Codex with `-a on-request -s workspace-write` in a separate isolated home and asked it to run `bash -x bin/fm-afk-launch.sh start`.
The rollout recorded the restricted policy, the command environment carried `CODEX_SANDBOX=seatbelt`, and the lifecycle entry returned 2 with `[codex-away-permission]` before its process-identity lock.
The pane contained `BOUNDED_AWAY_REFUSAL`, no `Would you like to run` approval prompt appeared, and the isolated state directory remained empty.
A second raw negative used `-a on-request -s danger-full-access`, where Codex sets no seatbelt marker.
The lifecycle still returned `[codex-away-permission]` because the live Codex process's open rollout reported `on-request`/`danger-full-access`, no approval prompt appeared, and the isolated state directory remained empty.
Focused process fixtures also demonstrated that blank or fabricated `CODEX_THREAD_ID`/`CODEX_HOME` values and a spoofed legacy verification marker cannot override that restricted live rollout, a Codex-named unsigned process holding fabricated rollouts is rejected, and a missing authenticated live rollout fails closed.
The genuine OpenAI-signed primary passed the gate with its live `never`/`danger-full-access` rollout; when that authenticated process held multiple internal rollouts, the guard required every latest effective context to have that safe posture instead of trusting the caller's thread id to choose one.
The live-argv oracle separately read NUL-delimited process arguments from macOS `KERN_PROCARGS2`, accepted the launcher's exact `--dangerously-bypass-hook-trust -c approval_policy="never" -c sandbox_mode="danger-full-access" --enable hooks` prefix, rejected both raw restricted argv and a later policy override, and accepted prompt arguments containing `-c` or `-sandbox` as text, so neither writable rollout bytes nor flattened prompt text can change the guard's decision.

Codex 0.147.0 code-mode calls use the dynamic `exec` tool and emitted neither the project's Bash PreToolUse hook nor its PermissionRequest hook in the negative probes.
Disabling `features.code_mode_host` made code mode fail closed instead of exposing a normal hookable shell path, so that is not the shipped correction.
The authoritative away-declaration seatbelt therefore runs inside both lifecycle entry points, while the tracked PreToolUse hook remains defense for native Bash calls.
Code mode cannot provide a universal hook for an unsupported raw process opened after another session already entered away mode; the executable boundary is instead that raw Codex cannot create an away session, and every supported active-away primary starts and remains under the launcher's proved `Never` policy.

The primary change did not modify the worker template in `bin/fm-spawn.sh`.
`tests/fm-spawn-dispatch-profile.test.sh` separately observed the existing `--dangerously-bypass-approvals-and-sandbox` Codex worker launch.

Deterministic coverage:

```sh
tests/fm-codex-primary.test.sh
tests/fm-spawn-dispatch-profile.test.sh
```

## Turn-end guard

The direct and passive mechanisms were validated across all five harnesses on 2026-07-08 through 2026-07-12, with Claude's replacement Stop-owned path revalidated on 2026-07-24 and Codex's replacement native typed continuation validated on 2026-08-09.

| Harness | Version verified | Mechanism | Observed result |
| --- | --- | --- | --- |
| Claude | 2.1.219 | Cooperative blocking `Stop` guard plus `asyncRewake` auto-arm | A fresh unsupervised session ran session start first, reclaimed a stale dead-owner lock, completed two tokenless rewake cycles with no model arm command or guard continuation, and left a competing live owner unchanged. |
| Codex | 0.147.0 | Native typed `Stop` continuation | In a throwaway trusted repository, a Stop hook returned `decision:"block"` with a concise reason after the first turn emitted `INITIAL_OK`; Codex displayed that feedback, continued automatically without human input, emitted `CONTINUATION_OK`, then stopped normally. |
| Codex | 0.142.1 | Exit-2 blocking `Stop` hook, now the typed path's fallback | Hook process root stayed anchored to the trusted checkout and one continuation ran. |
| OpenCode | 1.17.6 | Passive `session.idle` callback | Throwing could not block, while `promptAsync` scheduled one TUI follow-up; headless remained fail-open. |
| Pi | 0.80.5 | Passive `agent_settled` callback | Exactly one guard follow-up ran for an unhealthy cycle, with no recursion across tool turns. |
| Grok | 0.2.112 native and 0.2.73 pre-native | Running-payload adaptive `Stop` | Native false-to-true continuation stayed in one process with two model turns and zero resume launches; the field-absent pre-native process launched exactly one guarded resume. |

The Grok adaptive matrix ran on 2026-07-28 with separate scratch repositories and homes, dedicated tmux sockets, one target plus one control window, ambient tmux variables removed, and a socket-bound wrapper first in `PATH`.

```sh
FM_GROK_STOP_LIVE_E2E=1 \
  FM_GROK_NATIVE_BIN="$native_grok_0_2_112" \
  FM_GROK_LEGACY_BIN="$official_pre_native_grok_0_2_73" \
  tests/fm-grok-stop-live-e2e.test.sh
```

Observed bounded output:

```text
ok - grok 0.2.112 (9bbd559437aa) [stable] native Stop kept one session across false->true, two model turns, and zero resume processes
ok - grok 0.2.73 (9ff14c43bbe5) [stable] legacy Stop omitted capability, resumed exactly once, and stopped normally
ok - Grok adaptive Stop real-process matrix passed with exact target cleanup and control-window survival
```

The same run proved the Claude-compatible Stop entries stay inert under `GROK_AGENT`, the legacy resume carries `GROK_TURNEND_GUARD_ACTIVE=1`, and every replacement root is removed after exact target cleanup while its control window survives.

The secondmate-home scope and manual-repair wake path were measured with Claude Code 2.1.207 on 2026-07-12, when a native background completion re-invoked the idle model with no human input.
The current Stop-owned main/secondmate inclusion and child-worktree exclusion are covered deterministically by `tests/fm-claude-stop-autoarm.test.sh`.
Session-lock ownership in `bin/fm-session-lock-lib.sh` is decided against a session's whole contiguous harness ancestry rather than one chosen pid, so the Stop auto-arm reaches its lock owner wherever that owner sits: the outermost pid of Claude Code's multi-level `bg-spare` hook worker chain, or an inner pid when a harness-named daemon parents the session.
Harness identity is read from the executable path and `argv[0]` as well as the command basename, because Claude Code's native installer names the per-session executable by its version (`.../share/claude/versions/2.1.220`): `ps -o comm=` reports that path on macOS and the bare version string on Linux, and neither basename names a harness.
`tests/fm-session-lock-ancestry.test.sh` pins both platforms' reporting semantics behind a deterministic process table and runs the real Stop auto-arm in version-named, daemon-parented, and combined real process trees.
`tests/fm-watch-arm.test.sh` runs a real watcher and attached arm to verify that a delivered reason survives queue draining, while an unrelated queue append cannot make a watcher cycle that delivered nothing look successful.

The Claude product live path ran with Claude Code 2.1.219 on 2026-07-24:

```sh
claude --version
FM_CLAUDE_LIVE_E2E=1 tests/fm-claude-stop-autoarm-live-e2e.test.sh
```

Observed output:

```text
2.1.219 (Claude Code)
ok - Claude 2.1.219 (Claude Code) live E2E reclaimed a stale session lock through session start, completed two tokenless Stop-owned rewake cycles, and preserved the competing-live-owner boundary
```

Current entry points:

```sh
tests/fm-turnend-guard.test.sh
tests/fm-supervision-instructions.test.sh
FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh
FM_GROK_STOP_LIVE_E2E=1 FM_GROK_NATIVE_BIN="$native_grok" FM_GROK_LEGACY_BIN="$pre_native_grok" tests/fm-grok-stop-live-e2e.test.sh
```

The Claude auto-arm false-failure, guard-predicate, and monotonic bounded fail-open correction was first verified upstream on 2026-08-02 and reverified in this repository on 2026-08-07 with the installed ShellCheck 0.11.0 and isolated behavior suites.

```sh
bin/fm-lint.sh
bin/fm-doc-audience-check.sh
bin/fm-test-run.sh tests/fm-claude-stop-autoarm.test.sh tests/fm-guard-stale-banner.test.sh tests/fm-turnend-guard.test.sh tests/fm-supervision-instructions.test.sh
```

Observed output:

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=57 local_links=177
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=116878
```

The model-aware pull-guard predicate correction (`bin/fm-guard.sh` no longer reports a false watcher-down mid-turn under the Claude Stop auto-arm model, where the watcher runs only between turns) was first verified upstream on 2026-08-04 and reverified in this repository on 2026-08-07 as a separate run of the same isolated behavior suites with the installed ShellCheck 0.11.0.

```sh
bin/fm-lint.sh
bin/fm-doc-audience-check.sh
bin/fm-test-run.sh tests/fm-claude-stop-autoarm.test.sh tests/fm-guard-stale-banner.test.sh tests/fm-turnend-guard.test.sh tests/fm-supervision-instructions.test.sh
```

Observed output:

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=57 local_links=177
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=117611
```

The captain-visible Codex supervision-noise correction was deterministically verified in this repository on 2026-08-10.
The quiet checkpoint returned status 124 with no output, a preexisting durable queue returned an immediate `queue:` reason, and a real signal still passed through with its queue record intact for the drain.
Routine drains suppressed an unchanged buried decision while boundedly reading only new status bytes, surfaced an identically worded decision after resolution made it newly actionable again, and `--open-decisions all` restored the complete durable set for session recovery.
A session-start Codex preflight suppressed only the impossible pre-first-checkpoint watcher-down banner, while the next ordinary guard call still emitted the full liveness alarm.
A surfaced signal absorbed its one following bare stale duplicate into the stuck timer, changed pipeline step-log evidence reset that timer, and unchanged pipeline evidence still wedge-escalated.
Declared pauses and captain-held dead endpoints recorded their bounded internal rechecks without queueing another captain wake, while a live external-decision gate still surfaced once.
An explicit `branch_sync.state: pipeline_owned` fixture kept a divergent live fix round attributable, while the historical same-branch rewritten-head negative control still fell back from run-step state.

```sh
tests/fm-watch-checkpoint.test.sh
tests/fm-wake-drain-open-decisions-cursor.test.sh
tests/fm-crew-state.test.sh
tests/fm-session-start.test.sh
tests/fm-watch-triage.test.sh
```

All five commands exited zero.
The opt-in `FM_CODEX_LIVE_E2E=1 tests/fm-codex-continuity-live-e2e.test.sh` passed with codex-cli 0.147.0, starting no checkpoint for the idle home and delivering plus draining the live home's real actionable wake.

The Codex foreground-checkpoint correction and concise fleet-status projection were deterministically verified in this repository on 2026-08-09.
The pull guard accepted a fresh checkpoint beacon without a live watcher only mid-turn, while the Codex Stop hook still emitted a typed block that required the next foreground checkpoint, and that block deferred to the away-mode instruction instead of contradicting it.
A secondmate launch pinned the supervision model of its OWN harness from the single mapping owner, so a spawned Codex secondmate stayed quiet mid-turn while a persistent-watcher secondmate still alarmed.
The default fleet view counted only run-step or semantic-busy work as active, marked every other working report unverified, listed terminal work with its PR or report pointer, and left only records with no live, terminal, or blocked state for reconciliation.
Every registered primary guard integration remained covered by the shared guard suite, and the runtime backends remained outside this change because the view renders only the backend-agnostic fleet snapshot contract.
This pass covers the guard's own decisions; the codex-cli 0.147.0 row in the table above is the live record that Codex honors the typed continuation, and the 0.142.1 row covers the exit-2 banner that remains its fallback.

```sh
bin/fm-lint.sh
bin/fm-doc-audience-check.sh
bin/fm-test-run.sh tests/fm-guard-stale-banner.test.sh tests/fm-turnend-guard.test.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-secondmate-harness.test.sh tests/fm-supervision-instructions.test.sh tests/fm-documentation-audiences.test.sh
```

All commands exited zero.

The broader relevant regression pass was first run upstream on 2026-08-02 and rerun in this repository on 2026-08-07, in both cases without live-home or daemon mutation.

```sh
bin/fm-test-run.sh tests/fm-watch-triage.test.sh tests/fm-watcher-lock.test.sh tests/fm-afk-inject-e2e.test.sh tests/fm-afk-return.test.sh tests/fm-x-mode.test.sh tests/fm-backend.test.sh tests/fm-backend-tmux-smoke.test.sh tests/fm-secondmate-safety.test.sh
```

Observed output:

```text
FM_TEST_SUMMARY total=8 failed=0 skipped_gate=0 duration_ms=499176
```

The actionable-close ordering correction was first reverified upstream on 2026-08-02 against an identity-matched live successor, and the same check was rerun in this repository on 2026-08-07.

```sh
tests/fm-claude-stop-autoarm.test.sh >/dev/null && echo "fm-claude-stop-autoarm: ok"
```

Observed output:

```text
fm-claude-stop-autoarm: ok
```

## Watcher continuity

The cross-harness evidence combines the 2026-07-17 live pass with Claude's replacement Stop-owned path revalidated on 2026-07-24, all against isolated project and home state.
No credential material was copied into a fixture.

```text
Claude Code 2.1.219
codex-cli 0.144.4
OpenCode 1.17.18
Pi 0.80.10
grok 0.2.103 (89c3d36fb6f1) [stable]
```

| Harness | Exact opt-in command | Observed guarantee |
| --- | --- | --- |
| Claude | `FM_CLAUDE_LIVE_E2E=1 tests/fm-claude-stop-autoarm-live-e2e.test.sh` | Session start reclaimed a stale owner before two Stop-owned cycles, and a competing live owner prevented arm, rewake, epoch write, or lock replacement. |
| Codex | `FM_CODEX_LIVE_E2E=1 tests/fm-codex-continuity-live-e2e.test.sh` | The one-second foreground checkpoint returned without switching to the arm wrapper. |
| OpenCode | `FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh` | A verified successor existed before prompt handling, with no model re-arm or turn-end fallback. |
| Pi | `FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` | One initial tool call led to extension-owned successors and clean child retirement on exit. |
| Grok | `FM_GROK_LIVE_E2E=1 tests/fm-grok-continuity-live-e2e.test.sh` | Native task completion surfaced the actionable close and the cycle ledger recorded `reason=actionable-signal`. |

Pi 0.81.1 repeated the continuity and clean-exit lifecycle on 2026-07-23 after the Calm presentation changes.

Pi same-process session-transition ownership was verified on 2026-07-27 against the tracked extension with a faithful in-process factory rebind (module cache retained, real arm children):

```sh
pi --version
tests/fm-pi-watch-extension.test.sh
tests/fm-pi-primary-types.test.sh
```

Observed guarantee: after ordinary `session_shutdown` for `/new`, `/resume`, and `/fork`, plus same-instance shutdown-plus-start, the replacement generation armed again without a Pi restart and without the `watcher: not armed - Pi session is shutting down` refusal.
Stale prior-generation tool callbacks could not mutate the active child, repeated transitions kept exactly one live arm cycle, and terminal `quit` still refused late rearm.
Plain Pi and pi-signed share the same tracked `.pi/extensions/fm-primary-pi-watch.ts` path, so both inherit the generation owner; other primary harnesses are not applicable because they do not use this Pi extension lifecycle.

Deterministic entry points:

```sh
tests/fm-pi-watch-extension.test.sh
tests/fm-pi-primary-types.test.sh
tests/fm-watcher-lock.test.sh
tests/fm-subagent-pretool-check.test.sh
tests/fm-claude-stop-autoarm.test.sh
tests/fm-turnend-guard.test.sh
```

## Wedge-alarm channels

The two real notification channels were bounded manually on 2026-07-10 on macOS 26.5.2 with Herdr 0.7.3.
Automated suites never execute these real notification commands.

Argv-safe Notification Center command:

```sh
/usr/bin/osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "FIRSTMATE TEST - IGNORE" sound name "Basso"' \
  -e 'end run' \
  'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)'
```

Observed output: no stdout, exit 0, and one banner with the supplied body.

Herdr command:

```sh
herdr notification show 'FIRSTMATE TEST - IGNORE' \
  --body 'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)' \
  --sound request
```

Observed output:

```json
{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}
```

The safe command-channel contract is covered without a notification by `tests/fm-daemon.test.sh`: the summary reaches both `$1` and stdin, every channel is process-group bounded, and a failed channel falls through.
