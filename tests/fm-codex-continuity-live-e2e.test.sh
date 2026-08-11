#!/usr/bin/env bash
# Opt-in credentialed Codex regression proving an idle home starts no checkpoint
# and a live home delivers and drains one real foreground-checkpoint wake.
set -u

if [ "${FM_CODEX_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_CODEX_LIVE_E2E=1 to run the Codex continuity regression"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v codex >/dev/null 2>&1 || fail "codex not found"

LAB="$ROOT/.codex-live-e2e.$$"
PROJECT="$LAB/project"
HOME_DIR="$LAB/fmhome"
IDLE_TRANSCRIPT="$LAB/codex-idle.jsonl"
LIVE_TRANSCRIPT="$LAB/codex-live.jsonl"
CODEX_VERSION=$(codex --version)
producer_pid=

cleanup() {
  if [ -n "$producer_pid" ]; then
    kill "$producer_pid" 2>/dev/null || true
    wait "$producer_pid" 2>/dev/null || true
  fi
  rm -rf "$LAB"
}
trap cleanup EXIT

mkdir -p "$LAB"
git clone -q "$ROOT" "$PROJECT"
# A local clone contains only committed objects, so apply this candidate diff to
# the isolated clone before asking Codex to exercise the behavior under review.
git -C "$ROOT" diff --binary HEAD | git -C "$PROJECT" apply - \
  || fail "could not project the candidate diff into the isolated Codex clone"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"
IDLE_PROMPT='This isolated Firstmate home has no task metadata and no X-mode relay poll. Follow docs/supervision-protocols/codex.md for this home, then reply briefly with whether supervision was needed.'

(
  cd "$PROJECT" || exit 1
  printf '%s\n' "$$" > "$HOME_DIR/state/.lock"
  FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$PROJECT" codex exec \
    --dangerously-bypass-hook-trust \
    --dangerously-bypass-approvals-and-sandbox \
    --skip-git-repo-check \
    -c 'model_reasoning_effort="low"' \
    --json \
    "$IDLE_PROMPT"
) > "$IDLE_TRANSCRIPT" 2>&1 || fail "Codex credentialed idle turn failed: $(tail -20 "$IDLE_TRANSCRIPT")"

if grep -E '"type":"command_execution","command":"[^"]*fm-watch-checkpoint\.sh' "$IDLE_TRANSCRIPT" >/dev/null; then
  fail "Codex started a foreground checkpoint for an idle home"
fi

printf 'window=fm:fm-live\nworktree=%s\nkind=ship\nharness=codex\n' "$PROJECT" > "$HOME_DIR/state/live.meta"
# shellcheck disable=SC2016 # Backticks are literal prompt markup.
LIVE_PROMPT='This isolated Firstmate home has live work. Run exactly `FM_POLL=1 FM_SIGNAL_GRACE=1 bin/fm-watch-checkpoint.sh --seconds 8` as one foreground shell call. When it returns a real wake reason, run exactly `bin/fm-wake-drain.sh` once, then remove only `$FM_HOME/state/live.meta` so this isolated test home no longer needs supervision, and report the delivered result briefly. Do not use a background task or fm-watch-arm.sh.'

(
  sleep 2
  printf 'done: live Codex supervision delivered the result\n' > "$HOME_DIR/state/live.status"
) &
producer_pid=$!
(
  cd "$PROJECT" || exit 1
  FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$PROJECT" codex exec \
    --dangerously-bypass-hook-trust \
    --dangerously-bypass-approvals-and-sandbox \
    --skip-git-repo-check \
    -c 'model_reasoning_effort="low"' \
    --json \
    "$LIVE_PROMPT"
) > "$LIVE_TRANSCRIPT" 2>&1 || fail "Codex credentialed live wake turn failed: $(tail -20 "$LIVE_TRANSCRIPT")"
wait "$producer_pid" || fail "live wake producer failed"
producer_pid=

grep -F 'signal:' "$LIVE_TRANSCRIPT" >/dev/null \
  || fail "Codex transcript omitted the real foreground checkpoint wake"
grep -F 'live Codex supervision delivered the result' "$LIVE_TRANSCRIPT" >/dev/null \
  || fail "Codex transcript omitted the drained actionable result"
if grep -F 'checkpoint: no actionable wake' "$LIVE_TRANSCRIPT" >/dev/null; then
  fail "Codex rendered a routine quiet-checkpoint result on the actionable path"
fi
if grep -E '"type":"command_execution","command":"[^"]*fm-watch-arm\.sh' "$LIVE_TRANSCRIPT" >/dev/null; then
  fail "Codex switched to the background arm path"
fi
[ ! -s "$HOME_DIR/state/.wake-queue" ] || fail "Codex left the delivered actionable wake queued"

printf 'ok - %s live E2E skipped idle supervision and delivered one actionable foreground wake\n' "$CODEX_VERSION"
