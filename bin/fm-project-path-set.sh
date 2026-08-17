#!/usr/bin/env bash
# Atomically add or replace one canonical project path in data/projects.md.
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-project-lib.sh
. "$SCRIPT_DIR/fm-project-lib.sh"

PROJECT_ID=${1:?usage: fm-project-path-set.sh <project-id> <absolute-repo-root> [--mode <mode>]}
PROJECT_PATH=${2:?usage: fm-project-path-set.sh <project-id> <absolute-repo-root> [--mode <mode>]}
shift 2
NEW_MODE=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      [ "$#" -ge 2 ] || { printf '%s\n' 'error: --mode requires a value' >&2; exit 2; }
      NEW_MODE=$2
      shift 2
      ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

fm_project_init
[ -f "$FM_PROJECT_REGISTRY" ] || { printf 'PROJECT_REGISTRY_MISSING: %s\n' "$FM_PROJECT_REGISTRY" >&2; exit 1; }
TARGET_REGISTRY=$FM_PROJECT_REGISTRY
case "$NEW_MODE" in
  ''|no-mistakes|validated-main|direct-PR|local-only) ;;
  *) printf 'PROJECT_REGISTRY_INVALID: unknown mode: %s\n' "$NEW_MODE" >&2; exit 1 ;;
esac

PHYSICAL=$(fm_project_validate_root "$PROJECT_ID" "$PROJECT_PATH") || exit 1
ENTRY=$(awk -v id="$PROJECT_ID" '$1 == "-" && $2 == id { print; exit }' "$TARGET_REGISTRY")
[ -n "$ENTRY" ] || { printf 'PROJECT_NOT_FOUND: %s\n' "$PROJECT_ID" >&2; exit 1; }

CURRENT_PATH=$(awk -v id="$PROJECT_ID" '
  $1 == "-" { active=($2 == id); next }
  active && /^  path: / { line=$0; sub(/^  path: /, "", line); print line; exit }
' "$TARGET_REGISTRY")
[ -n "$CURRENT_PATH" ] || CURRENT_PATH="$FM_PROJECT_HOME/projects/$PROJECT_ID"

CURRENT_PHYSICAL=$(fm_project_physical_dir "$CURRENT_PATH" 2>/dev/null || true)
[ -n "$CURRENT_PHYSICAL" ] || {
  printf 'PROJECT_REMOTE_IDENTITY_UNAVAILABLE: %s has no existing checkout at %s\n' "$PROJECT_ID" "$CURRENT_PATH" >&2
  exit 1
}
CURRENT_REMOTE=$(fm_project_remote_identity "$CURRENT_PHYSICAL" 2>/dev/null || true)
NEW_REMOTE=$(fm_project_remote_identity "$PHYSICAL" 2>/dev/null || true)
[ -n "$CURRENT_REMOTE" ] && [ -n "$NEW_REMOTE" ] || {
  printf 'PROJECT_REMOTE_IDENTITY_UNAVAILABLE: %s requires origin remotes on both existing and requested repositories\n' "$PROJECT_ID" >&2
  exit 1
}
[ "$CURRENT_REMOTE" = "$NEW_REMOTE" ] || {
  printf 'PROJECT_REMOTE_MISMATCH: %s existing origin %s does not match requested origin %s\n' \
    "$PROJECT_ID" "$CURRENT_REMOTE" "$NEW_REMOTE" >&2
  exit 1
}

if [ -d "$FM_PROJECT_HOME/state" ]; then
  for meta in "$FM_PROJECT_HOME"/state/*.meta; do
    [ -f "$meta" ] || continue
    META_PROJECT=$(sed -n 's/^project=//p' "$meta" | tail -1)
    META_PHYSICAL=$(fm_project_physical_dir "$META_PROJECT" 2>/dev/null || true)
    if [ "$META_PROJECT" = "$CURRENT_PATH" ] \
       || { [ -n "$META_PHYSICAL" ] && [ "$META_PHYSICAL" = "$CURRENT_PHYSICAL" ]; }; then
      printf 'PROJECT_PATH_IN_USE: %s still names %s\n' "$(basename "$meta")" "$CURRENT_PATH" >&2
      exit 1
    fi
  done
fi

TMP=$(mktemp "$FM_PROJECT_DATA/.projects.md.XXXXXX")
trap 'rm -f "$TMP"' EXIT HUP INT TERM
awk -v id="$PROJECT_ID" -v path="$PHYSICAL" -v requested_mode="$NEW_MODE" '
  function render(line,    mode,yolo,flags,desc,n,a,i) {
    mode="no-mistakes"
    yolo=""
    if (match(line, /\[[^]]*\]/)) {
      flags=substr(line, RSTART + 1, RLENGTH - 2)
      n=split(flags, a, " ")
      for (i=1; i<=n; i++) {
        if (a[i] == "+yolo") yolo=" +yolo"
        else if (a[i] != "") mode=a[i]
      }
    }
    if (requested_mode != "") mode=requested_mode
    desc=line
    sub(/^- [^ ]+( \[[^]]*\])? /, "", desc)
    return "- " id " [" mode yolo "] " desc
  }
  pending {
    if (/^  path: /) {
      print "  path: " path
      pending=0
      next
    }
    print "  path: " path
    pending=0
  }
  $1 == "-" && $2 == id {
    print render($0)
    pending=1
    next
  }
  { print }
  END { if (pending) print "  path: " path }
' "$TARGET_REGISTRY" > "$TMP"

FM_PROJECT_REGISTRY_OVERRIDE="$TMP" fm_project_resolve "$PROJECT_ID" || exit 1
[ "$FM_PROJECT_PATH" = "$PHYSICAL" ] || { printf '%s\n' 'PROJECT_PATH_INVALID: migrated path did not resolve identically' >&2; exit 1; }
mv "$TMP" "$TARGET_REGISTRY"
trap - EXIT HUP INT TERM
printf 'updated %s -> %s\n' "$PROJECT_ID" "$PHYSICAL"
