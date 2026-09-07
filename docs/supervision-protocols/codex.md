Mode: Codex Stop-hook-owned background wake.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
2. Routine watcher arm and re-arm are owned by the Stop hook (`bin/fm-codex-stop-autoarm.sh`), never by you.
   Every turn end while supervision is needed launches or attaches one home-scoped watcher cycle with no model command and no model tokens, and the hook returns immediately so this conversation stays interactive for the captain while it waits.
3. An actionable close wakes you as a new marked operational message in this conversation, published with `codex queue` against this conversation's own id.
   On such a wake, run `bin/fm-wake-drain.sh` first and handle it.
   Do not run `bin/fm-watch-checkpoint.sh` or `bin/fm-watch-arm.sh` after an ordinary wake; the next turn end re-arms automatically when supervision is still needed.
   Do not invent a wake from an attach-status line alone; drain and act only on real wake records, the drain's `OPEN DECISIONS` entries, or a real watcher reason line.
4. On the one `FIRSTMATE WATCHER FAILURE` notice, drain, inspect the automatic mechanism failure, and do not turn the notice into a repeating manual-checkpoint loop.
5. If the Stop hook does not claim this conversation, the turn-end guard blocks the stop with a repair instruction.
   Inspect its registration in `.codex/hooks.json` and the watcher startup path before ending blind, and keep the Stop-owned automatic mechanism as the only Codex arm owner.
   `bin/fm-watch-checkpoint.sh` remains available as a short manual recovery probe during that inspection only, never as the routine cycle.
6. Read `watcher: started ...` and `watcher: attached ...` inside the wake text as the reason that cycle closed, not as proof a cycle is running now: the cycle that printed the line ended when it published the wake. The next turn end arms the following one.
7. The durable wake queue preserves actionable events between a wake and the next Stop-launched arm, while the bounded turn-end guard prevents a blind Stop when recovery did not start.
   `codex queue` reports success even for a conversation that has already exited, so a published wake is never delivery proof; a wake published into a closed conversation is drained by the next session start instead.
8. Never use shell `&` or Codex background tasks for firstmate watcher supervision.
   If `bin/fm-watch-arm.sh` is ever shelled during recovery, a backgrounded, piped, or bundled anti-pattern is denied automatically by the PreToolUse seatbelt (`bin/fm-arm-pretool-check.sh`) registered in `.codex/hooks.json`.
9. Waiting on the hook-owned cycle is silent: do not send idle progress while the watcher is parked.

The watcher itself remains `bin/fm-watch.sh`, and `bin/fm-watch-arm.sh` remains the verified arm wrapper that the detached supervisor foregrounds.
Codex has no asynchronous hook mode, so the Stop hook detaches that supervisor through `bin/fm-codex-detach.sh` and exits at once rather than holding the stop open.
The supervisor binds to the conversation id carried in the Stop payload and is retired by the next Stop from a different conversation, so a restart or replacement session always owns its own wake target.
See [`watcher-continuity.md`](../watcher-continuity.md) for the arm-layer successor and clean-close failure contract.
