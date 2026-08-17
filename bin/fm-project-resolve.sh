#!/usr/bin/env bash
# Resolve one project to its canonical physical repository root and policy.
# Prints: <id><tab><path><tab><mode><tab><yolo>
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-project-lib.sh
. "$SCRIPT_DIR/fm-project-lib.sh"

PROJECT_ARG=${1:?usage: fm-project-resolve.sh <project-id-or-canonical-path>}
fm_project_resolve_arg "$PROJECT_ARG"
printf '%s\t%s\t%s\t%s\n' \
  "$FM_PROJECT_ID" "$FM_PROJECT_PATH" "$FM_PROJECT_MODE" "$FM_PROJECT_YOLO"
