#!/usr/bin/env bash
# Supported entry point for a primary Firstmate session on Codex.
#
# Usage:
#   fm-codex-primary.sh [interactive options] [prompt]
#   fm-codex-primary.sh resume [resume options] [session-id] [prompt]
#   fm-codex-primary.sh --verify-only
#
# The launcher owns the primary's no-prompt/full-access posture.
# Before accepting work it asks Codex itself for the effective policy under the
# exact overrides passed to the interactive process, then fails closed unless
# bin/fm-codex-primary-policy-check.sh accepts that report.
# It anchors both the probe and the session to this tracked code root and refuses
# caller root or remote-server overrides whose hook/policy state it did not prove.
#
# It also bypasses project-hook trust for the tracked Firstmate hooks.
# This does not broaden Firstmate authority: AGENTS.md still requires explicit
# captain approval for destructive, irreversible, external, and
# security-sensitive actions.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
FM_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
POLICY_CHECK="$SCRIPT_DIR/fm-codex-primary-policy-check.sh"
POLICY_ARGS=(-c 'approval_policy="never"' -c 'sandbox_mode="danger-full-access"')
FEATURE_ARGS=(--enable hooks)
VERIFY_ONLY=0
RESUME_MODE=0

usage() {
  cat <<'EOF'
Usage: fm-codex-primary.sh [interactive options] [prompt]
       fm-codex-primary.sh resume [resume options] [session-id] [prompt]
       fm-codex-primary.sh --verify-only

Starts or resumes a primary Codex session only after Codex doctor proves the
effective approval policy is Never, the sandbox is unrestricted, and tracked
hook support is enabled.
Approval policy, sandbox policy, local code root, and server are launcher-owned.
Caller config, profile, and feature layers are refused; use Codex's ordinary
non-config flags such as --model for supported launch customization.
Non-interactive and service subcommands are not supported by this primary entry.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --verify-only)
    [ "$#" -eq 1 ] || { echo "error: --verify-only accepts no Codex arguments" >&2; exit 2; }
    VERIFY_ONLY=1
    ;;
esac

[ "${1:-}" = "resume" ] && RESUME_MODE=1

[ -f "$FM_ROOT/AGENTS.md" ] && [ -f "$FM_ROOT/.codex/hooks.json" ] \
  || { echo "error: primary Codex launcher is not inside a complete Firstmate code root: $FM_ROOT" >&2; exit 1; }
cd "$FM_ROOT"

# A later Codex CLI layer must not replace the policy and hook state that doctor
# verified. Codex accepts multiple TOML key spellings, so fail closed on every
# caller config/profile/feature layer instead of duplicating its parser.
for arg in "$@"; do
  case "$arg" in
    --)
      break
      ;;
    -a|-s|--ask-for-approval|--sandbox|--approve-for-me|--full-auto|--dangerously-bypass-approvals-and-sandbox)
      echo "error: primary policy is launcher-owned; remove the Codex policy flag: $arg" >&2
      exit 2
      ;;
    -a?*|-s?*|--ask-for-approval=*|--sandbox=*)
      echo "error: primary policy is launcher-owned; remove the Codex policy override: $arg" >&2
      exit 2
      ;;
    -C|--cd|--remote|--remote-auth-token-env)
      echo "error: primary entry is launcher-owned; remove the Codex root or remote override: $arg" >&2
      exit 2
      ;;
    -C?*|--cd=*|--remote=*|--remote-auth-token-env=*)
      echo "error: primary entry is launcher-owned; remove the Codex root or remote override: $arg" >&2
      exit 2
      ;;
    -c|--config|-c?*|--config=*|-p|--profile|-p?*|--profile=*|--enable|--disable|--enable=*|--disable=*)
      echo "error: primary policy is launcher-owned; caller config, profile, and feature layers are unsupported: $arg" >&2
      exit 2
      ;;
    exec|e|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|app|completion|update|doctor|sandbox|debug|apply|a|archive|delete|unarchive|fork|cloud|exec-server|features|help)
      [ "$RESUME_MODE" -eq 1 ] && continue
      echo "error: primary entry supports only fresh or resumed interactive sessions; unsupported Codex subcommand: $arg" >&2
      exit 2
      ;;
  esac
done

command -v codex >/dev/null 2>&1 || { echo "error: Codex is required for a primary Codex session" >&2; exit 1; }
[ -x "$POLICY_CHECK" ] || { echo "error: Codex policy checker is missing or not executable: $POLICY_CHECK" >&2; exit 1; }

# A launcher invoked from a restricted Codex tool process inherits these
# per-command markers. They describe the parent shell, not the new process whose
# explicit policy is verified below, so never let them falsely label the new
# primary's full-access commands as restricted.
unset CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED

if ! REPORT=$(codex doctor --json "${POLICY_ARGS[@]}" "${FEATURE_ARGS[@]}"); then
  echo "error: Codex doctor could not verify the primary policy" >&2
  exit 1
fi
if ! POLICY_SUMMARY=$(printf '%s' "$REPORT" | "$POLICY_CHECK"); then
  exit 1
fi
printf 'fm-codex-primary: effective policy verified: %s\n' "$POLICY_SUMMARY"

[ "$VERIFY_ONLY" -eq 1 ] && exit 0
exec codex --dangerously-bypass-hook-trust "${POLICY_ARGS[@]}" "${FEATURE_ARGS[@]}" "$@"
