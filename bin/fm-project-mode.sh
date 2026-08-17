#!/usr/bin/env bash
# Resolve a project's delivery mode and yolo flag from the data/projects.md registry.
# Prints two words to stdout: "<mode> <yolo>" where mode is one of
# no-mistakes|validated-main|direct-PR|local-only and yolo is on|off.
#
# Registry line format (data/projects.md):
#   - <name> - <desc> (added <date>)                  -> no-mistakes off  (legacy default)
#   - <name> [<mode>] - <desc> (added <date>)          -> <mode> off
#   - <name> [<mode> +yolo] - <desc> (added <date>)    -> <mode> on
#   Primary and peer entries require the next indented line to be an absolute
#   canonical Git root: "  path: /absolute/path".
#   Secondmate entries may omit it and resolve their provisioned projects/<name> clone.
#
# mode = how a finished change reaches main:
#   no-mistakes    full pipeline -> PR -> captain merge (default)
#   validated-main same full pipeline, PR and CI steps skipped -> guarded merge to
#                  main -> push to origin; no PR is ever opened
#   direct-PR      review-only pipeline run, then push + PR via gh-axi -> captain
#                  merge; the other eight pipeline steps are skipped
#   local-only     local branch, review-only pipeline run that publishes nothing, no
#                  remote/PR -> captain approve -> guarded local merge
# yolo (orthogonal) = when on, firstmate may make routine approval decisions itself.
#   AGENTS.md section 7 is the single owner of authority exceptions, including
#   ask-user contract expansion and stronger captain boundaries.
#
# Invalid registry identity or a missing canonical path refuses rather than silently
# selecting another repository.
# Usage: fm-project-mode.sh <project-name>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-project-lib.sh
. "$SCRIPT_DIR/fm-project-lib.sh"
NAME=${1:?usage: fm-project-mode.sh <project-name>}
fm_project_resolve "$NAME"
printf '%s %s\n' "$FM_PROJECT_MODE" "$FM_PROJECT_YOLO"
