#!/usr/bin/env bash
# Open a peer firstmate home: a session the captain talks to directly.
#
# A peer home is an ordinary directory holding only data/, state/, config/, and
# projects/, provisioned by "fm-home-seed.sh <id> <home> --peer". It carries NO
# copy of this repo: this script exports FM_HOME and runs <command> from THIS
# tracked code root, so the home always runs the current bin/, AGENTS.md, and
# .agents/skills/, and /updatefirstmate reaches every peer home by updating this
# one repo. docs/configuration.md "FM_HOME" owns the peer/secondmate
# distinction.
#
# Usage: fm-open.sh <home> <command> [args...]
#   <command> is the primary agent harness to launch, and is required: firstmate
#   does not pick a primary harness on the captain's behalf, and README's
#   requirements own the supported set.
#
# Examples:
#   fm-open.sh ~/fm-homes/hookgame claude
#   fm-open.sh ~/fm-homes/delivery grok --trust
#
# Supervision ownership is unchanged: the opened session acquires that home's
# own state/.lock at session start, so a second session opened against the same
# home starts read-only exactly as it would in any other home.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PEER_HOME_MARKER=".fm-peer-home"

usage() {
  echo "usage: fm-open.sh <home> <command> [args...]" >&2
}

case "${1:-}" in
  -h|--help|'')
    usage
    exit 0
    ;;
esac
[ $# -ge 2 ] || { usage; exit 1; }

REQUESTED=$1
shift

[ -d "$REQUESTED" ] || { echo "error: peer home does not exist or is not a directory: $REQUESTED" >&2; exit 1; }
HOME_ABS=$(cd "$REQUESTED" && pwd -P)

# The marker is the difference between an existing home and a mistyped path that
# would otherwise open silently against an empty board.
if [ -L "$HOME_ABS/$PEER_HOME_MARKER" ] || [ ! -f "$HOME_ABS/$PEER_HOME_MARKER" ]; then
  echo "error: $HOME_ABS is not a peer firstmate home (no $PEER_HOME_MARKER)" >&2
  echo "       seed one with: bin/fm-home-seed.sh <id> $REQUESTED --peer {<project>...|--no-projects}" >&2
  exit 1
fi
# Read the marker exactly as fm_backend_hometag_marker_id and
# fm_backend_herdr_workspace_label do, so the launcher never refuses an id the
# backends would happily turn into a container label - including a marker
# written without a trailing newline.
PEER_ID=$(tr -d '[:space:]' < "$HOME_ABS/$PEER_HOME_MARKER" 2>/dev/null || true)
case "$PEER_ID" in
  ''|*[!A-Za-z0-9._-]*)
    echo "error: $HOME_ABS/$PEER_HOME_MARKER does not name a usable peer home id: ${PEER_ID:-<empty>}" >&2
    exit 1
    ;;
esac

for dir in data state config projects; do
  [ -d "$HOME_ABS/$dir" ] || { echo "error: peer home $HOME_ABS is missing $dir/; re-seed it before opening" >&2; exit 1; }
done

command -v "$1" >/dev/null 2>&1 || { echo "error: harness command not found on PATH: $1" >&2; exit 1; }

cd "$FM_ROOT"
export FM_HOME="$HOME_ABS"
exec "$@"
