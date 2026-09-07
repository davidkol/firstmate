# Primary turn-end supervision guard

This is the authoritative current contract for the "no turn ends blind" primary backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`.
Primary scope lives in `bin/fm-primary-scope-lib.sh`, shared with the native session-start adapters in [`sessionstart-nudge.md`](sessionstart-nudge.md).
Harness hook files adapt each enabled primary harness integration's turn-end mechanism to that shared predicate.

Related PreToolUse guards deny unsafe commands before execution rather than detecting a blind turn end afterward.
Their separate owners are [`arm-pretool-check.md`](arm-pretool-check.md), [`cd-guard.md`](cd-guard.md), and [`subagent-guard.md`](subagent-guard.md).
Do not infer this guard's scope, loop safety, or compatibility tradeoffs for those guards.

## Current invariant

`bin/fm-guard.sh` is a pull-based warning that runs only when another supervision command invokes it.
The turn-end guard closes the remaining gap at the primary's own turn boundary.
When work or X-mode relay polling needs supervision at that boundary and no identity-matched watcher has a fresh beacon, the harness integration must either block the turn end or force one bounded follow-up that uses the recovery instruction from the emitted session-start protocol.
The mid-turn pull warning uses the model-aware supervision verdict described below, while the turn-end guard keeps the PID-strict watcher predicate.
The guard remains a backstop; [`watcher-continuity.md`](watcher-continuity.md) owns normal continuity.

## Guard predicates

The guard first calls the shared primary scope.
A secondmate home runs its own primary Firstmate session, so a genuine `.fm-secondmate-home` marker includes it whether the home is a linked worktree or plain clone.
The marker must be a regular non-symlink file whose whitespace-stripped first line is a non-empty identifier containing only letters, digits, dots, underscores, and dashes.
An unmarked checkout or invalid marker falls through to the git-dir check.
That check keeps crewmate and scout linked worktrees inert because their git dir differs from their git common dir.
It also requires `AGENTS.md`, `bin/`, and the effective state directory.

For an in-scope primary, the guard counts in-flight work from `state/*.meta`.
The default cross-harness mode exits silently with no supervision need.
Every mode treats `state/x-watch.check.sh` as supervision need, so X-mode relay polling remains guarded without an in-flight task.
Otherwise it calls `fm_watcher_healthy <state-dir> <watch-path> [grace-seconds] [home]` from `bin/fm-wake-lib.sh`, the same PID-strict identity-matched lock and fresh-beacon check used by `bin/fm-watch-arm.sh`: a stale beacon blocks even when a watcher pid is live, and a fresh leftover beacon blocks when the lock is missing, dead, or identity-mismatched.
The turn-end guard needs that strict check because it fires at the turn boundary, where the auto-arm is bringing a fresh watcher up for the upcoming idle period, and it cooperates with that arm rather than trusting a beacon left by the cycle that just ended.
`bin/fm-guard.sh`, the pull warning, instead uses the model-aware `fm_watcher_supervision_verdict` from the same library, because it fires mid-turn when the Claude and Codex Stop auto-arm model has no live watcher at that instant.
Under either model a beacon fresh within grace is healthy even with no live watcher process, and only a beacon stale beyond grace (or absent) alarms.
The strict turn-end predicate remains unchanged for both models, so a Codex primary must own a live armed cycle before it can finish a turn.
Under every persistent-watcher harness a live identity-matched watcher with a fresh beacon is still required, so the pull guard keeps the same strict semantics there.
Its banner names the true failing condition, either a missing live watcher process or a genuinely stale beacon with its real age, and keys the once-per-episode dedup on that condition rather than the beacon mtime.

`FM_STATE_OVERRIDE` wins over `FM_HOME/state`, and `FM_HOME` wins over repository-root `state/`.
`FM_GUARD_GRACE` controls beacon freshness and defaults to 300 seconds.
If `jq` is missing or hook stdin is empty, the guard exits 0 because it cannot safely read loop-guard fields.

## Harness integrations

- Claude registers two `Stop` hooks in `.claude/settings.json`, both anchored through `CLAUDE_PROJECT_DIR`: `bin/fm-turnend-guard.sh --claude`, and `bin/fm-claude-stop-autoarm.sh` with `asyncRewake: true` and `timeout: 28800`.
- Codex registers two `Stop` hooks in `.codex/hooks.json`, each anchored to the hook process working directory and each verifying a Firstmate-shaped hook-bearing root before it runs: `bin/fm-codex-stop-autoarm.sh` first, then the shared guard with `--codex`. Both receive the original payload.
- OpenCode listens for `session.idle` in `.opencode/plugins/fm-primary-turnend-guard.js`, lets the watcher coordinator act first, and calls `client.session.promptAsync` once when the guard returns 2.
- Pi listens for `agent_settled` in `.pi/extensions/fm-primary-turnend-guard.ts`, runs once per logical agent run, and calls `pi.sendUserMessage(..., { deliverAs: "followUp" })` once when the guard returns 2.
- Grok registers a `Stop` hook in `.grok/hooks/fm-primary-turnend-guard.json` and delegates capability selection to `bin/fm-turnend-guard-grok.sh`.
  The tracked Claude Stop entries are inert when `GROK_AGENT` is present, so Grok's Claude-compatible settings loading cannot create a second continuation path.

Claude blocks a Stop directly with exit status 2 and stderr.
Codex uses its native JSON `decision:"block"` continuation output, so it receives one typed instruction without rendering the full operator banner as chat, carrying it with the same canonical `turn-end-guard` operational-input marking as the passive follow-ups below.
That instruction is the harness repair line itself, sent verbatim because every branch of that line is already a complete imperative, and a continuation that cannot be emitted falls through to the exit-2 banner rather than allowing a blind stop.
Either mode flag comes from that harness's own registered Stop hook, so it pins the repair line's harness instead of letting `bin/fm-harness.sh` detect one: detection checks environment markers before process ancestry, and a foreign marker left in a stored multiplexer environment would otherwise hand a markerless harness another harness's instruction.
Both payloads carry `stop_hook_active`, and `--codex` keeps the shared non-`--claude` loop guard, so a true value lets the second stop finish after one forced continuation.

The Codex delivery proofs are asked only of the session that owns the home.
Supervision belongs to whoever holds `state/.lock`, the Stop-owned wake applies exactly that gate before it arms, and a session it declines to arm for must not then be told to repair the owner's supervision.
So a Codex session with a live foreign lock owner keeps the shared harness behavior, never writes or clears this home's episode state, and receives the read-only instruction rather than the owner's repair line when it does have to block.
Only a live foreign owner counts: a missing, malformed or dead recorded owner is not another session, so the owning-session rules still apply and a genuine diagnostic still reaches the conversation.

For the owning session, a healthy watcher is not on its own a Codex stop proof.
The watcher observes the home; the supervisor is what turns an observed event into a message in a conversation, so a home whose watcher is healthy while its only supervisor is bound to a replaced conversation leaves the current one with no delivery route at all.
That session therefore does not take the shared healthy-watcher fast path and falls through to its own conversation-bound proofs instead, with one exception: under away mode the daemon owns triage and delivery, so a healthy watcher allows the stop as it does for every other harness.

The Codex mode waits up to `FM_CODEX_AUTOARM_SYNC_WAIT_MS` (default 1500 milliseconds) for the Stop-owned background wake to prove it owns recovery for this conversation, and allows the stop on either proof.
The first is a live supervisor recorded in `state/.codex-autoarm-session` whose pid is alive and still matches its recorded process identity, and only while the home carries no unresolved arm-failure episode.
That proof is optimistic: a supervisor records `arming` within milliseconds of detaching, seconds before its arm wrapper reports, so `state/.codex-autoarm-failure-episode` withdraws it whenever the last completed cycle failed to bring a watcher up.
Without that withdrawal every turn end after an episode's single notice would pass silently and blind; with it the stop falls through to the typed continuation, still bounded to one per turn by the shared `stop_hook_active` loop guard.
The auto-arm opens that episode on every failed cycle and closes it only on an actionable wake or a verified healthy watcher, never because a new supervisor started.
The second is that record carrying `outcome=wake` no older than `FM_CODEX_AUTOARM_OUTCOME_FRESH` (default 15 seconds), because a supervisor whose whole cycle fits inside the wait window publishes its wake and exits, and process liveness alone would then send the session to repair a hook registration that just worked.
The supervisor writes that outcome only after its publication call returns success, so the record proves a published wake and never a delivery receipt; a publication that fails records `wake-unpublished` instead, and the durable `state/.wake-queue` record remains the recovery path for a wake no live conversation consumed.
Both proofs require the record's `session` to equal this Stop payload's `session_id`, so a supervisor bound to a closed conversation never buys this one a blind stop.
No other outcome is recovery evidence: `arming` from a dead process, `wake-unpublished`, `superseded`, `failed`, `afk`, `clean`, an unparsable or future-dated timestamp, and any aged record all still block.
The separate `state/.codex-autoarm-failure-notified` marker decides only whether the auto-arm publishes another failure message, and it is written after the publication succeeds, so a notice that never reached the conversation neither silences the episode nor suppresses the next attempt.

That bound is a freshness window, not a cycle identity: it establishes that a wake was published recently, not that it belongs to this Stop's own cycle.
A wake published mid-turn can still be fresh at the next turn end; the auto-arm hook runs first on that same event and arms the following cycle, and the shared loop guard bounds the exposure either way.

Both proofs read the binding as one snapshot: a single open and a single pass, so an atomic replacement of that record cannot mix the session of one version with the pid of another.
The episode has one owner and every transition has a home.
The auto-arm opens it on a failed arm cycle, on a retirement that timed out and therefore left this conversation with no route, and on a wake whose publication failed after its bounded retries.
It closes the episode on a wake it actually published.
This guard closes it at the two boundaries no supervisor survives to reach: a home with no supervision need left, and a home whose watcher is verifiably healthy again AND whose delivery route for this conversation is intact.
Both halves are required, because an episode opened by a routing or publication failure is about the route to this conversation and the stuck supervisor's own watcher is usually still beating; a healthy watcher alone would close it while the failure it records is still true.

The typed continuation reports what was actually refused, and so does the operator banner behind it.
The repair line names the hook registration and the watcher startup, and those are not what failed in every Codex refusal, so the continuation leads with the observed condition and then carries that instruction unaltered.
A missing binding, a binding for another conversation, an open arm-failure episode and an unpublished wake each state themselves; away mode and the read-only case send their own instruction with no added condition.
In the banner a running supervisor is named with its pid, its bound conversation and its recorded outcome, rather than being described as an auto-arm that never claimed the home.

Claude runs the guard with `--claude`, which ignores `stop_hook_active` and cooperates with the Stop-owned auto-arm.
Claude Code sets `stop_hook_active=true` on every stop after any stop-hook continuation, including `asyncRewake` rewakes, which re-opened the 2026-07-21 blind window under the default one-shot behavior.
The Claude mode waits up to `FM_CLAUDE_AUTOARM_SYNC_WAIT_MS` (default 800 milliseconds) and allows the stop when the watcher is healthy, `state/.claude-autoarm.lock` has a live `autoarm` role owner whose eventual failure must exit 2, or `state/.claude-autoarm-epoch` contains a fresh actionable rewake owned by this event epoch.
Fresh `failed` and `failed-suppressed` outcomes enter or advance the failure progression instead of acting as unconditional recovery proof.
The auto-arm itself rechecks the healthy watcher predicate and retries a bounded number of times before reporting a genuine failure.
The first fresh exhausted-failure epoch preserves its handoff without consuming a blocked-stop count, while later fresh failed epochs advance the same monotonic progression instead of resetting it.
When none of those proofs appears, it re-blocks up to `FM_CLAUDE_TURNEND_BLOCK_BUDGET` times (default 3, below Claude's 8-block override).
In Claude mode, positive watcher recovery clears the block budget, failure notice, and attended alarm together under the existing budget lock before either hook reports ordinary recovery.
The one loud attended fail-open is available only when the auto-arm has recorded an exhausted failure, its one notice is already consumed, the block budget is exhausted, and a final check finds neither a healthy watcher nor an automatic continuation.
Each epoch identity is accounted at most once under the budget lock.
Whenever both coordination locks are needed, positive auto-arm recovery and the terminal check acquire the auto-arm owner lock before the budget lock.
After that alarm, the Stop auto-arm suppresses further exit-2 continuations until positive watcher recovery, so the final fail-open remains reachable.
The alarm cannot repeat during that failure episode, and a later unhealthy stop blocks again.
A positively verified healthy watcher clears the failure notice, alarm, and block budget for a future independent episode.
A Claude failure notice describes the automatic mechanism as broken and does not direct a routine manual background arm.

OpenCode, Pi, and pi-signed expose passive callbacks for this purpose.
Their adapters fail open at the hook boundary to protect the user session but schedule one bounded follow-up when the predicate blocks.
The generated prompts use the canonical `turn-end-guard` kind after the U+2063 `FIRSTMATE_OP: ` prefix, so Ahoy does not treat them as captain messages.
Each passive adapter owns a loop latch.
Pi keeps the latch across internal tool turns and clears it only when the generated follow-up settles or delivery fails.
OpenCode's forced follow-up is supported for persistent TUI sessions and remains fail-open in headless `opencode run`.

Grok makes exactly one typed capability decision from each running Stop payload.
A boolean `stopHookActive` selects native blocking, including both false on the initial stop and true on the bounded continuation.
The camel-case field has precedence when both spellings appear; when it is absent, a boolean `stop_hook_active` selects the same native path for compatibility.
The native path returns the shared guard's status and stderr to the same Grok process and never starts `grok --resume`.
When both capability spellings are absent, the adapter preserves one pre-native `grok --resume` fallback guarded by `GROK_TURNEND_GUARD_ACTIVE` and intentionally omits `--permission-mode`.
Malformed JSON, a selected field with a non-boolean type, missing `jq`, missing hook prerequisites, or an already-active legacy guard allows the stop without starting either continuation path.
Grok's project hook requires the checkout to be trusted with `/hooks-trust` or launch-time `--trust`; genuine pre-native builds can run the same tracked hook from an isolated global hook directory.

If a passive adapter cannot invoke its SDK, or the Grok legacy fallback cannot find `grok` or a session id, the next pull-based `fm-guard.sh` call reports the problem.
That warning uses `bin/fm-supervision-instructions.sh --repair-line`, so it always points to the active harness protocol rather than embedding another repair command.

## Compatibility limits

- Child crewmate and scout worktrees are outside scope.
- A valid secondmate home is in scope; an idle secondmate endpoint with no X-mode relay poll remains healthy because it has no supervision need.
- The direct-blocking and bounded passive-follow-up split is limited to the primary integrations listed above.
- OpenCode headless mode and untrusted Grok project hooks remain fail-open at the host boundary.
- Kimi Code CLI 0.29.1 exposes only global `[[hooks]]` configuration in `~/.kimi-code/config.toml`, including a `Stop` event with snake_case payload fields `hook_event_name`, `session_id`, `cwd`, and `stop_hook_active`.
- Kimi has no project-level hook configuration and remains outside the primary guard integrations above.
- Captain-approved Kimi crew wake support uses `bin/fm-kimi-turnend-hook.sh` to edit only one marker-delimited Firstmate region in that global config and install a silent always-zero hook.
- The hook remains inert unless the payload `cwd` contains a per-task token pointer that resolves through Firstmate's private registry to one `state/<id>.turn-ended` marker.
- Installation refuses before writing unless `python3` with `tomllib` and `jq` are available.
- If `jq` is removed after installation, the hook remains silent and exits 0, turn-end wakes stop, and Kimi crews fall back to idle detection.
- Unreadable hook input remains fail-open.
- No harness adapter uses a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers the predicate, main and secondmate primary scope, child-worktree exclusion, `FM_HOME` and `FM_STATE_OVERRIDE` precedence, the live-lock and fresh-beacon guard predicate, the `--codex` typed continuation with its deference to a redirected repair line and its own-harness repair pin, the `--codex` registration order, its cooperative allow for a live supervisor and for a fresh published wake with the stale, non-wake, dead-supervisor, and other-conversation refusals, the read-only session staying quiet beside a healthy watcher and receiving the lock-holder instruction when it blocks, the continuation naming a missing or mismatched delivery binding, the cooperative `--claude` claim wait, monotonic failed-epoch progression, bounded attended fail-open, post-alarm continuation suppression, positive recovery reset, Pi logical-run latching, missing-`jq` behavior, all five primary registrations, Grok native and legacy selection, typed field precedence, malformed input, and exactly-one-path safety.
`tests/fm-guard-stale-banner.test.sh` covers the pull-guard predicate, including the persistent-model fresh-leftover-beacon negative control, the Claude and Codex Stop auto-arm model's healthy fresh-beacon-without-a-watcher case and stale-beacon alarm, the true-reason banner wording, and the reason-keyed episode dedup surviving a beacon mtime change.
`tests/fm-codex-stop-autoarm.test.sh` covers the Codex Stop-owned background wake's inert gates, immediate hook return with detached delivery, quiet idle, same-conversation reuse, stale-supervisor retirement and rebinding, a retirement that times out and the episode the guard then keeps open beside the old healthy watcher, a detached supervisor whose authorizing primary was replaced, a transient publication failure that the bounded retry recovers, a supersession during that retry recorded as supersession rather than failure, mid-cycle away mode, one-notice failure episodes that stay loud at the guard on later cycles, an unpublishable notice that does not silence the episode, recovery closing the episode, arm-output cleanup on retirement, the published and both unpublished wake records read back by the real guard, and second-home isolation.
`tests/fm-kimi-harness.test.sh` covers the separate Kimi crew hook's format preservation, idempotence, refusal cases, token guard, spawn registration, and teardown cleanup.
`tests/fm-supervision-instructions.test.sh` covers recovery-line ownership and pi-signed's identity-preserving reuse of Pi's protocol.
`FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` is the opt-in isolated Pi path.
[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the active cross-harness empirical evidence, including the 2026-07-24 Claude `asyncRewake` revalidation.
