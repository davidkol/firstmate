#!/usr/bin/env bash
# fm-learning-promote.sh - the upward path for a home-local learning that turns
# out to be true of firstmate itself.
#
# A home's data/learnings.md is gitignored and home-local by captain decision,
# and there is deliberately no shared learnings file between homes. The only
# path that reaches every home runs UPWARD: the lesson lands in this repo's
# shared tracked material through the normal delivery pipeline, and every home
# picks it up on the next fast-forward (bin/fm-update.sh).
#
# Hand-running that path exposes two failures this script exists to close.
# Retiring the local entry before the tracked change lands destroys the lesson,
# because data/ is gitignored and has no recovery. Never retiring it leaves the
# same lesson in two places, which is exactly the rot the no-shared-file
# decision guards against. So promotion is two phases with a checked gate
# between them, and the in-flight record lives inside data/learnings.md, which
# the session-start digest already prints in full - an unfinished promotion is
# visible every session until it is landed.
#
# The semantic half - when a learning has earned promotion at all - is owned by
# .agents/skills/stow/SKILL.md. This script never judges that. It refuses an
# unstated case (--evidence and --checkable are required and are recorded
# durably) and it refuses an unlanded retirement. Judging whether the stated
# evidence is true stays with the agent and the review pipeline.
#
# Usage:
#   fm-learning-promote.sh start <slug> --to <repo-relative-path> \
#     --evidence <one line> --checkable <one line>
#   fm-learning-promote.sh list
#   fm-learning-promote.sh land <slug>
#
# `start` records a promotion in flight in the ACTIVE HOME's data/learnings.md
# (created on first use). <slug> is a privacy-safe [A-Za-z0-9._-]+ identifier,
# unique among this home's in-flight promotions. `--to` names the destination
# inside the tracked code root, repo-relative; a path git ignores there is
# refused, because promoting into a gitignored path reaches no other home. The
# destination need not exist yet. `start` records the destination's current blob
# id on the code root's default branch, or `absent`, as the landing baseline.
#
# `list` prints one tab-separated `<landed|waiting> <slug> <path> <started>` row
# per in-flight promotion, and nothing when there are none. A destination whose
# default-branch blob still equals the recorded baseline is `waiting`.
#
# `land <slug>` refuses while the destination is unchanged on the default
# branch, and on success replaces the in-flight block in data/learnings.md with
# a one-line pointer to the tracked owner. The block is its marker line through
# the next blank line, which is exactly what `start` wrote, so keep that blank
# line if you curate around an in-flight record by hand. Pruning the original local entry that
# the pointer now supersedes is the agent's edit, in the same pass, under the
# stow skill's inspect-then-update contract; this script owns the gate and the
# pointer, not the surrounding curation.
#
# The landing check proves the named destination changed on the default branch
# since `start`, not that this particular sentence is what changed it. That is
# the honest limit of a check that imposes no marker on the tracked prose, and
# it is enough to stop the failure that loses knowledge.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
LEARNINGS="$DATA/learnings.md"

# shellcheck source=bin/fm-ff-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-ff-lib.sh"

# Marker fields are whitespace-delimited, so every field recorded on this line
# must be whitespace-free by validation. That invariant is what keeps the sed
# readers (marker_field, find_marker, cmd_list) and replace_block's awk
# fixed-string matcher agreeing on where a field ends.
MARKER='<!-- fm-promotion '

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

fail() {
  printf 'fm-learning-promote: %s\n' "$*" >&2
  exit 1
}

validate_slug() {  # <slug>
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) fail "slug must be a non-empty privacy-safe identifier: $1" ;;
  esac
}

# Field text is embedded in an HTML comment and in Markdown prose, so it must be
# one line and must not carry the comment terminator.
validate_field() {  # <label> <value>
  local label=$1 value=$2
  [ -n "$value" ] || fail "$label must not be empty"
  case "$value" in
    *$'\n'*|*$'\r'*) fail "$label must be one line" ;;
    *'-->'*) fail "$label must not contain '-->'" ;;
  esac
}

resolve_default_branch() {
  default_branch "$FM_ROOT" || fail "cannot determine the default branch of $FM_ROOT"
}

# Blob id of <path> on the code root's default branch, or `absent`.
destination_blob() {  # <default-branch> <path>
  git -C "$FM_ROOT" rev-parse --verify --quiet "$1:$2" 2>/dev/null || printf '%s\n' absent
}

# Echo the `key=value` field <key> from a marker line, empty when unset.
marker_field() {  # <marker-line> <key>
  printf '%s\n' "$1" | sed -n "s/.*[[:space:]]$2=\\([^[:space:]]*\\).*/\\1/p"
}

# Echo the marker line for <slug>, or return 1 when no promotion is in flight.
find_marker() {  # <slug>
  local slug=$1 line
  [ -f "$LEARNINGS" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "$MARKER"*) ;;
      *) continue ;;
    esac
    [ "$(marker_field "$line" slug)" = "$slug" ] || continue
    printf '%s\n' "$line"
    return 0
  done < "$LEARNINGS"
  return 1
}

# Replace the in-flight block for <slug> - its marker line through the next
# blank line - with <replacement>, which may be empty.
replace_block() {  # <slug> <replacement>
  local slug=$1 replacement=$2 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/fm-learning-promote.XXXXXX")
  # Fixed-string field match, never a regex: a slug may contain `.` and `-`.
  awk -v needle=" slug=$slug " -v marker="$MARKER" -v replacement="$replacement" '
    index($0, marker) == 1 && index($0, needle) > 0 {
      dropping = 1
      if (replacement != "") print replacement
      next
    }
    dropping && $0 == "" { dropping = 0; next }
    dropping { next }
    { print }
  ' "$LEARNINGS" > "$tmp" || { rm -f "$tmp"; fail "could not rewrite $LEARNINGS"; }
  mv "$tmp" "$LEARNINGS"
}

cmd_start() {
  local slug=${1:-} to='' evidence='' checkable='' default base today
  shift || true
  validate_slug "$slug"
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) to=${2:-}; shift 2 || fail "--to needs a value" ;;
      --evidence) evidence=${2:-}; shift 2 || fail "--evidence needs a value" ;;
      --checkable) checkable=${2:-}; shift 2 || fail "--checkable needs a value" ;;
      *) fail "unknown option: $1" ;;
    esac
  done

  [ -n "$to" ] || fail "start needs --to <repo-relative-path>"
  validate_field "--to" "$to"
  case "$to" in
    *[[:space:]]*)
      fail "--to must not contain whitespace, because the in-flight marker records it as a whitespace-delimited field: $to" ;;
    /*|*..*) fail "--to must be a repo-relative path inside $FM_ROOT: $to" ;;
  esac
  # A gitignored destination reaches no other home, which is the whole point of
  # promoting upward, so refuse it rather than recording a promotion that cannot
  # land.
  if git -C "$FM_ROOT" check-ignore -q -- "$to" 2>/dev/null; then
    fail "--to names a gitignored path, which no other home would receive: $to"
  fi

  # The graduation rule is the captain's: a note graduates only when it is true
  # in more than one project AND somebody makes it checkable. This script cannot
  # judge either, so it refuses to record an unstated case and keeps both
  # statements in the durable record for review.
  [ -n "$evidence" ] || fail "start needs --evidence: where this proved true in more than one project"
  [ -n "$checkable" ] || fail "start needs --checkable: what makes this checkable, or it stays a note"
  validate_field "--evidence" "$evidence"
  validate_field "--checkable" "$checkable"

  if find_marker "$slug" >/dev/null; then
    fail "a promotion for '$slug' is already in flight in $LEARNINGS"
  fi

  default=$(resolve_default_branch)
  base=$(destination_blob "$default" "$to")
  today=$(date +%Y-%m-%d)

  mkdir -p "$DATA"
  if [ ! -f "$LEARNINGS" ]; then
    printf '# Operational learnings\n\n' > "$LEARNINGS"
  elif [ -s "$LEARNINGS" ] && [ -n "$(tail -c 1 "$LEARNINGS")" ]; then
    printf '\n' >> "$LEARNINGS"
  fi

  # shellcheck disable=SC2016 # Literal Markdown backticks, not expansions.
  {
    printf '%sslug=%s to=%s base=%s started=%s -->\n' "$MARKER" "$slug" "$to" "$base" "$today"
    printf -- '- **Promotion in flight:** `%s` -> `%s` (started %s).\n' "$slug" "$to" "$today"
    printf -- '  True in more than one project: %s\n' "$evidence"
    printf -- '  Checkable by: %s\n' "$checkable"
    printf -- '  Land it with `bin/fm-learning-promote.sh land %s` once the tracked change is on the default branch.\n' "$slug"
    printf '\n'
  } >> "$LEARNINGS"

  printf 'started: %s -> %s (baseline %s on %s)\n' "$slug" "$to" "$base" "$default"
  printf 'ship the tracked change through this repo'"'"'s normal delivery path, then run: %s land %s\n' \
    "$(basename "$0")" "$slug"
}

cmd_list() {
  local default line slug to base started now
  [ -f "$LEARNINGS" ] || return 0
  default=$(resolve_default_branch)
  while IFS= read -r line; do
    case "$line" in
      "$MARKER"*) ;;
      *) continue ;;
    esac
    slug=$(marker_field "$line" slug)
    to=$(marker_field "$line" to)
    base=$(marker_field "$line" base)
    started=$(marker_field "$line" started)
    now=$(destination_blob "$default" "$to")
    if [ "$now" = "$base" ]; then
      printf 'waiting\t%s\t%s\t%s\n' "$slug" "$to" "$started"
    else
      printf 'landed\t%s\t%s\t%s\n' "$slug" "$to" "$started"
    fi
  done < "$LEARNINGS"
}

cmd_land() {
  local slug=${1:-} line to base started default now today pointer
  shift || true
  [ $# -eq 0 ] || fail "unknown option: $1"
  validate_slug "$slug"

  line=$(find_marker "$slug") || fail "no promotion in flight for '$slug' in $LEARNINGS"
  to=$(marker_field "$line" to)
  base=$(marker_field "$line" base)
  started=$(marker_field "$line" started)
  default=$(resolve_default_branch)
  now=$(destination_blob "$default" "$to")

  if [ "$now" = "$base" ]; then
    fail "not landed: $to is unchanged on $default since $started, so the local entry must stay"
  fi

  today=$(date +%Y-%m-%d)
  # shellcheck disable=SC2016 # Literal Markdown backticks, not expansions.
  pointer=$(printf -- '- `%s` was promoted to `%s` on %s; read it there rather than keeping a second copy in this home.' \
    "$slug" "$to" "$today")
  replace_block "$slug" "$pointer"

  printf 'landed: %s -> %s (%s %s -> %s)\n' "$slug" "$to" "$default" "$base" "$now"
  printf 'now prune the local entry this pointer supersedes, so the lesson lives in one place.\n'
}

case "${1:-}" in
  -h|--help|'') usage; exit 0 ;;
  start) shift; cmd_start "$@" ;;
  list) shift; [ $# -eq 0 ] || fail "list takes no arguments"; cmd_list ;;
  land) shift; cmd_land "$@" ;;
  *) usage >&2; exit 1 ;;
esac
