#!/usr/bin/env bash
# Codex-only away-mode permission-prompt seatbelt.
#
# Usage:
#   <Codex PreToolUse JSON on stdin> | fm-codex-away-pretool-check.sh
#   fm-codex-away-pretool-check.sh --entry
#
# Codex 0.147.0 reports the effective shell posture as permission_mode in the
# hook payload: bypassPermissions for the supported full-access primary and
# default for an on-request/workspace primary.
#
# The hook denies a restricted primary's attempt to enter away mode, and while
# the durable .afk flag is present it denies every new restricted Bash call.
# That prevents a sandbox denial from becoming an unattended interactive
# approval wait. An already-authorized bypassPermissions path remains allowed.
# Codex's macOS sandbox sets CODEX_SANDBOX=seatbelt inside restricted commands
# and leaves it absent in a danger-full-access command.
# A raw on-request/danger-full-access session also leaves it absent, so the
# direct entry walks to the live Codex ancestor, verifies that process is an
# OpenAI-signed Codex executable, resolves a rollout file that process itself
# holds open, and reads its latest effective turn context.
# It does not trust caller-controlled CODEX_HOME, CODEX_THREAD_ID, markers, or
# PATH replacements for the process tools. If the authenticated process holds
# multiple internal-thread rollouts, every one must have the safe posture.
# The --entry mode is called by both away lifecycle entry points before their
# first process-identity check, so it remains effective when Codex routes shell
# work through code mode instead of emitting a hookable native Bash tool.
# Malformed or unrelated hook payloads fail open because startup's
# effective-policy gate and the entry-point check own the primary invariant.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
ARGV_CHECK="$SCRIPT_DIR/fm-codex-primary-argv-check.sh"
ROLLOUT_CHECK="$SCRIPT_DIR/fm-codex-rollout-policy-check.sh"

codex_thread_is_unrestricted() {
  local pid=$PPID parent comm lsof_bin="" executable signature rollouts rollout
  local rollout_paths=()

  # Non-Codex callers remain outside this harness-specific guard. For a Codex
  # call, derive identity from ancestry the child cannot rewrite.
  while [ "$pid" -gt 1 ]; do
    comm=$(/bin/ps -o comm= -p "$pid" 2>/dev/null) || return 1
    case "${comm##*/}" in
      codex) break ;;
    esac
    parent=$(/bin/ps -o ppid= -p "$pid" 2>/dev/null) || return 1
    parent=${parent//[[:space:]]/}
    [ -n "$parent" ] && [ "$parent" != "$pid" ] || return 1
    pid=$parent
  done
  [ "$pid" -gt 1 ] || return 0

  for candidate in /usr/sbin/lsof /usr/bin/lsof; do
    if [ -x "$candidate" ]; then
      lsof_bin=$candidate
      break
    fi
  done
  [ -n "$lsof_bin" ] || return 1
  [ -x /usr/bin/codesign ] || return 1

  executable=$("$lsof_bin" -a -p "$pid" -d txt -Fn 2>/dev/null \
    | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -n 1) || return 1
  [ -n "$executable" ] || return 1
  /usr/bin/codesign --verify --strict "$executable" >/dev/null 2>&1 || return 1
  signature=$(/usr/bin/codesign -dv --verbose=4 "$executable" 2>&1) || return 1
  printf '%s\n' "$signature" | /usr/bin/grep -Fx 'Identifier=codex' >/dev/null || return 1
  printf '%s\n' "$signature" | /usr/bin/grep -Fx 'Authority=Developer ID Application: OpenAI OpCo, LLC (2DC432GLL2)' >/dev/null || return 1
  printf '%s\n' "$signature" | /usr/bin/grep -Fx 'TeamIdentifier=2DC432GLL2' >/dev/null || return 1

  [ -x "$ARGV_CHECK" ] || return 1
  "$ARGV_CHECK" "$pid" >/dev/null 2>&1 || return 1

  rollouts=$("$lsof_bin" -p "$pid" -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' \
    | /usr/bin/awk 'index($0, "/sessions/") && /\/rollout-.*\.jsonl$/ { if (!seen[$0]++) print }') || return 1
  [ -n "$rollouts" ] || return 1
  while IFS= read -r rollout; do
    rollout_paths+=("$rollout")
  done <<< "$rollouts"
  [ -x "$ROLLOUT_CHECK" ] || return 1
  "$ROLLOUT_CHECK" "${rollout_paths[@]}" >/dev/null 2>&1
}

if [ "${1:-}" = "--entry" ]; then
  [ "$#" -eq 1 ] || { echo "usage: fm-codex-away-pretool-check.sh --entry" >&2; exit 2; }
  if [ -n "${CODEX_SANDBOX:-}" ] || ! codex_thread_is_unrestricted; then
    echo "[codex-away-permission] away mode cannot begin in an unverified or restricted Codex session that may escalate interactively; relaunch with bin/fm-codex-primary.sh" >&2
    exit 2
  fi
  exit 0
fi
[ "$#" -eq 0 ] || { echo "usage: fm-codex-away-pretool-check.sh [--entry]" >&2; exit 2; }

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

VALUES=$(printf '%s' "$PAYLOAD" | jq -er '
  [(.permission_mode // ""), (.tool_name // ""), (.tool_input.command // .toolInput.command // "")]
  | @tsv
' 2>/dev/null) || exit 0
TAB=$(printf '\t')
PERMISSION_MODE=${VALUES%%"$TAB"*}
REST=${VALUES#*"$TAB"}
TOOL_NAME=${REST%%"$TAB"*}
COMMAND=${REST#*"$TAB"}

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ "$PERMISSION_MODE" = "bypassPermissions" ] && exit 0

ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 0
ACTIVE_HOME=${FM_HOME:-$ROOT}
STATE=${FM_STATE_OVERRIDE:-$ACTIVE_HOME/state}
REASON=""

if [ -f "$STATE/.afk" ]; then
  REASON="away mode is active, so a restricted Codex shell call cannot start an interactive approval; return attended and relaunch with bin/fm-codex-primary.sh"
else
  # The /afk skill's only supported declaration paths are the launch helper's
  # start modes and its shared foreground entry. Match a shell word boundary
  # on both sides so reading or searching those scripts remains allowed.
  COMMAND_EDGE='(^|[;|&()][[:space:]]*)'
  ASSIGNMENTS='([A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&()]+[[:space:]]+)*'
  INTERPRETER='((exec[[:space:]]+)?(bash|sh)([[:space:]]+-[^[:space:];|&()]+)*[[:space:]]+)?'
  SCRIPT_PATH='([^[:space:];|&()]*/)?'
  WORD_END='($|[[:space:];|&()])'
  LAUNCH_RE="$COMMAND_EDGE$ASSIGNMENTS$INTERPRETER${SCRIPT_PATH}fm-afk-launch\\.sh[[:space:]]+(start|start-native)$WORD_END"
  START_RE="$COMMAND_EDGE$ASSIGNMENTS$INTERPRETER${SCRIPT_PATH}fm-afk-start\\.sh$WORD_END"
  if [[ "$COMMAND" =~ $LAUNCH_RE ]] || [[ "$COMMAND" =~ $START_RE ]]; then
    REASON="away mode cannot begin from a restricted Codex policy that may ask interactively; relaunch with bin/fm-codex-primary.sh"
  fi
fi

[ -n "$REASON" ] || exit 0
ESCAPED=$(printf '%s' "[codex-away-permission] $REASON" | jq -Rs '.')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":%s}\n' "$ESCAPED" >&2
exit 2
