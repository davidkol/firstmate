#!/usr/bin/env bash
# Verify the latest effective turn context in every authenticated Codex rollout
# passed by fm-codex-away-pretool-check.sh.
#
# Usage:
#   fm-codex-rollout-policy-check.sh <rollout.jsonl>...
#
# This script only judges rollout contents. Its caller owns process identity and
# must pass only files held open by the authenticated live Codex process.
set -u

[ -x /usr/bin/jq ] || { echo "error: Apple's protected jq is required to read Codex rollout policy" >&2; exit 1; }
[ "$#" -gt 0 ] || { echo "error: no authenticated Codex rollout was provided" >&2; exit 1; }

for rollout in "$@"; do
  [ -f "$rollout" ] || { echo "error: Codex rollout is unavailable: $rollout" >&2; exit 1; }
  values=$(/usr/bin/jq -r '
    select(.type == "turn_context")
    | [(.payload.approval_policy // ""), (.payload.sandbox_policy.type // "")]
    | @tsv
  ' "$rollout" 2>/dev/null | /usr/bin/tail -n 1) || {
    echo "error: could not read effective policy from Codex rollout: $rollout" >&2
    exit 1
  }
  if [ "$values" != $'never\tdanger-full-access' ]; then
    echo "error: Codex rollout is not no-prompt/full-access: $rollout" >&2
    exit 1
  fi
done
