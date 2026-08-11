Mode: Codex foreground checkpoint.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
2. Source `__FM_X_MODE_ENV__` first when X mode is active.
3. If no task metadata and no X-mode relay poll need supervision, do not start a checkpoint.
4. When supervision is needed, run one foreground watcher checkpoint with `bin/fm-watch-checkpoint.sh --seconds "${FM_CODEX_WATCH_CHECKPOINT:-180}"`.
5. Ordinary wake: if the command prints `signal:`, `stale:`, `check:`, `heartbeat`, or `queue:`, drain queued wakes, handle that wake, then start the next checkpoint when supervision is still needed.
6. Quiet expiry: if the command exits 124 with no output, process any queued user message now visible to Codex and immediately start the next checkpoint when supervision is still needed, without a routine wake drain.
7. Never use shell `&` or Codex background tasks for firstmate watcher supervision.
8. Do not run `bin/fm-watch-arm.sh` as Codex's normal supervision command.
   If it is ever shelled anyway, a backgrounded, piped, or bundled anti-pattern is denied automatically by the PreToolUse seatbelt (`bin/fm-arm-pretool-check.sh`) registered in `.codex/hooks.json`.
9. The strict Stop hook uses Codex's typed continuation to require the next foreground checkpoint without rendering the full operator banner as chat.
10. Failure or missing cycle only: drain queued wakes, inspect the failure, then start a fresh foreground checkpoint.

Codex cannot reason while a foreground tool call is running.
The bounded checkpoint returns control regularly so user messages and queued wakes can be handled without relying on background-task wake semantics.
Codex renders every foreground checkpoint invocation as a tool card, so one bounded card per live supervision interval remains unavoidable without a supported runtime wake primitive.
