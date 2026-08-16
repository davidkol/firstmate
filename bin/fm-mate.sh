#!/usr/bin/env bash
# Open a named peer Firstmate home through a short global-friendly command.
#
# Usage: mate <project> <harness> [harness-args...]
#
# The project is a peer-home id under FM_HOMES_ROOT, which defaults to
# ~/fm-homes. The harness and remaining arguments pass unchanged to fm-open.sh.
# This script resolves its own symlink so ~/.local/bin/mate can point directly
# at the tracked copy and automatically follow Firstmate updates.
set -eu

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do
  SOURCE_DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)
  LINK_TARGET=$(readlink "$SOURCE")
  case "$LINK_TARGET" in
    /*) SOURCE=$LINK_TARGET ;;
    *) SOURCE=$SOURCE_DIR/$LINK_TARGET ;;
  esac
done
SCRIPT_DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)
FM_ROOT=${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd -P)}
HOMES_ROOT=${FM_HOMES_ROOT:-$HOME/fm-homes}

usage() {
  echo "usage: mate <project> <harness> [harness-args...]" >&2
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[ $# -ge 2 ] || { usage; exit 1; }

PEER_ID=$1
shift
case "$PEER_ID" in
  ''|.|..|*[!A-Za-z0-9._-]*)
    echo "error: peer home id must match [A-Za-z0-9._-]+: ${PEER_ID:-<empty>}" >&2
    exit 1
    ;;
esac

PEER_HOME=$HOMES_ROOT/$PEER_ID
[ -d "$PEER_HOME" ] || {
  echo "error: peer home not found: $PEER_ID ($PEER_HOME)" >&2
  exit 1
}

exec "$FM_ROOT/bin/fm-open.sh" "$PEER_HOME" "$@"
