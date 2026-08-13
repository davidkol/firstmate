#!/usr/bin/env bash
# Verify the effective policy reported by Codex 0.147.0 for a primary
# Firstmate session.
#
# Usage:
#   codex doctor --json <policy overrides> | fm-codex-primary-policy-check.sh
#
# This is an effective-policy oracle, not a config-file parser.
# It accepts only the no-prompt/full-access combination that the supported
# primary launcher owns and reports every value it judged.
set -u

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required to verify Codex's effective policy" >&2
  exit 1
}

REPORT=$(cat 2>/dev/null || true)
if ! VALUES=$(printf '%s' "$REPORT" | jq -er '
  .checks["sandbox.helpers"].details as $details
  | (.checks["config.load"].details["enabled feature flags"] // "") as $features
  | [
      $details["approval policy"],
      $details["filesystem sandbox"],
      $details["network sandbox"],
      (if ($features | split(",") | map(gsub("^\\s+|\\s+$"; "")) | index("hooks")) != null then "enabled" else "disabled" end)
    ]
  | if any(.[]; type != "string" or length == 0) then error("missing policy value") else @tsv end
' 2>/dev/null); then
  echo "error: could not read Codex's effective sandbox policy from doctor --json" >&2
  exit 1
fi

TAB=$(printf '\t')
APPROVAL=${VALUES%%"$TAB"*}
REST=${VALUES#*"$TAB"}
FILESYSTEM=${REST%%"$TAB"*}
REST=${REST#*"$TAB"}
NETWORK=${REST%%"$TAB"*}
HOOKS=${REST#*"$TAB"}
SUMMARY="approval=$APPROVAL filesystem=$FILESYSTEM network=$NETWORK hooks=$HOOKS"

if [ "$APPROVAL" != "Never" ] || [ "$FILESYSTEM" != "unrestricted" ] \
  || [ "$NETWORK" != "enabled" ] || [ "$HOOKS" != "enabled" ]; then
  echo "error: Codex effective policy mismatch: $SUMMARY" >&2
  exit 1
fi

printf '%s\n' "$SUMMARY"
