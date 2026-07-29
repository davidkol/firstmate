#!/usr/bin/env bash
# fm-project-reconcile.sh - reconcile a project's existing state surfaces.
#
# Day one on a project is a reconciliation, not an install. Every project this
# was built against already had entry points, handoff documents, question
# registers, decision records, notes stores and check commands, and in most of
# them the surface the repo itself pointed at was stale. Installing a fresh set
# over the top adds one more surface to the pile it exists to reduce, so this
# script inventories what is already there, reports where two surfaces cover the
# same job, names what is genuinely missing, and refuses to choose when two
# surfaces disagree about what is true.
#
# The semantic procedure - when to run this, how to route what it reports, and
# who decides a disagreement - is owned by
# .agents/skills/project-management/SKILL.md. This script owns only mechanics.
#
# Usage:
#   fm-project-reconcile.sh [options] <project-dir>
#
# Options:
#   --seed                       write the surfaces reported as genuinely absent
#   --project <name>             registry name, enabling the delivery-mode checks
#   --accept-disagreement <key>  the captain has ruled on <key>; stop blocking on it
#   --offline                    skip every network read (issue registers stay unknown)
#   -h, --help                   this text
#
# Without --seed nothing is written and the target is only read.
#
# Report lines carry stable prefixes so a caller can grep them:
#   PROJECT:      the resolved target directory
#   LANDING:      what "landed" means here, and any push-target hazard
#   SURFACE:      <kind> <scope> <path> - one existing state surface
#   COLLISION:    <kind> - two or more surfaces cover the same job
#   DISAGREEMENT: <key> - two surfaces disagree; the captain owns which survives
#   GAP:          something absent or unlanded that this script cannot resolve
#                 for the project
#   SEED:         a surface this run would create, or did create with --seed
#   PRESENT:      a surface that already exists and was not touched
#
# QUESTIONS.md and handoff/<name>.md are never seeded by any path. Questions
# live on firstmate's board, which already reaches the captain and already
# carries a stated default and a desk-or-play axis; firstmate itself is the
# handoff. A repo-side copy of either is a second queue where an item can be
# open in one place and invisible in the other. An existing copy of either is
# reported as a surface and left alone - nothing is deleted here.
#
# Seeded script/setup, script/check and script/run wrap a command this project
# already had when one is found. When none is found the stub exits 78, which is
# a named gap and never a silent pass: a check that returns 0 without running
# anything is the exact failure the done checklist exists to catch.
#
# Firstmate never writes to a project directly. --seed is a worktree utility for
# the crewmate that carries the change through the project's selected delivery
# path, the same posture as bin/fm-ensure-agents-md.sh, and it refuses to run
# against a clone sitting directly under a firstmate home's projects/ directory.
#
# The reconciler writes inside the project directory and nowhere else. Every
# planned path is resolved through its symlinks before anything is written, and
# the whole plan is refused if any one of them lands outside, so a detector that
# is wrong about what is missing still cannot put a file outside the repo.
#
# Exit status:
#   0  report produced (and seeding completed when --seed was given)
#   1  usage or environment error
#   3  --seed refused: an unaccepted disagreement is open
#   4  --seed refused: the target is a firstmate-owned project clone
#   5  --seed refused: a planned path resolves outside the project directory
#
# This is a project-inspection utility, not a supervision script, so it does not
# call fm-guard.sh.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exit code the seeded stubs use for "this project has no such command yet".
# Distinct from 1 so a caller can tell a named gap from a real failure.
GAP_EXIT=78

# How many surfaces of one kind to name before summarising the rest. A repo with
# seventy handoff files needs the count and a sample, not seventy lines - but the
# remainder is always stated, never silently dropped.
MAX_LIST=6

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0" >&2
}

SEED=0
OFFLINE=0
PROJECT_NAME=
ACCEPTED=
DIR=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --seed) SEED=1; shift ;;
    --offline) OFFLINE=1; shift ;;
    --project)
      [ "$#" -ge 2 ] || { echo "error: --project needs a value" >&2; exit 1; }
      PROJECT_NAME=$2; shift 2 ;;
    --accept-disagreement)
      [ "$#" -ge 2 ] || { echo "error: --accept-disagreement needs a value" >&2; exit 1; }
      ACCEPTED="$ACCEPTED $2 "; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *)
      [ -z "$DIR" ] || { echo "error: only one project directory may be given" >&2; exit 1; }
      DIR=$1; shift ;;
  esac
done

[ -n "$DIR" ] || { usage; exit 1; }
[ -d "$DIR" ] || { echo "error: not a directory: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd -P)

# --- small portability helpers ----------------------------------------------

mtime_of() {  # <path> -> epoch seconds, or 0
  # GNU stat reads -f as "filesystem status", where %m is not a directive: it
  # prints "?" and exits 0, so an exit-status-only fallback never fires. Decide
  # on the value instead, which leaves both stat flavors working.
  local p=$1 t
  t=$(stat -f %m "$p" 2>/dev/null) || t=
  case "$t" in
    ''|*[!0-9]*) t=$(stat -c %Y "$p" 2>/dev/null) || t= ;;
  esac
  case "$t" in
    ''|*[!0-9]*) t=0 ;;
  esac
  printf '%s\n' "$t"
}

lower() { printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'; }

is_git=0
git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 && is_git=1


# --- surface inventory ------------------------------------------------------

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-project-reconcile.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SURFACES="$WORK/surfaces"
: > "$SURFACES"

# kind <TAB> scope <TAB> display-path <TAB> detail
add_surface() {  # <kind> <scope> <display-path> <detail>
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$SURFACES"
}

# Last-changed times for every in-repo surface, resolved in ONE history walk.
# Asking git for each path separately re-walks the whole history per path, which
# costs half a minute on a repo with forty handoff files. git log is newest
# first, so the first time a path appears is its most recent change; a path git
# never names (untracked, or absent from history) falls back to its mtime.
EPOCHS="$WORK/epochs"
: > "$EPOCHS"

build_epoch_table() {
  [ "$is_git" -eq 1 ] || return 0
  local rel
  local -a paths=()
  while IFS=$'\t' read -r _kind scope rel _detail; do
    # Command surfaces carry a command string, not a path; passing one to git as
    # a pathspec fails the whole walk and would empty the table.
    [ "$scope" = repo ] && [ -n "$rel" ] && [ -e "$DIR/$rel" ] || continue
    paths+=("$rel")
  done < "$SURFACES"
  [ "${#paths[@]}" -gt 0 ] || return 0
  git -C "$DIR" log --format='@%ct' --name-only -- "${paths[@]}" 2>/dev/null | awk '
    /^@/ { ts = substr($0, 2); next }
    NF && !($0 in seen) { seen[$0] = 1; print $0 "\t" ts }
  ' > "$EPOCHS" || : > "$EPOCHS"
}

epoch_of() {  # <repo-relative-path> -> epoch seconds
  local rel=$1 t
  t=$(awk -F'\t' -v p="$rel" '$1 == p { print $2; exit }' "$EPOCHS")
  if [ -z "$t" ]; then
    t=$(mtime_of "$DIR/$rel")
  fi
  printf '%s\n' "$t"
}

surfaces_of_kind() { grep "^$1	" "$SURFACES" 2>/dev/null || true; }
count_of_kind() { surfaces_of_kind "$1" | wc -l | tr -d ' '; }
# In-repo surfaces only. A store that lives outside the repo is invisible from
# every isolated worktree, so it can never stand in for one the repo carries.
repo_count_of_kind() { surfaces_of_kind "$1" | awk -F'\t' '$2 == "repo"' | wc -l | tr -d ' '; }

# Classify one repo-relative path into a surface kind, or nothing.
# The name lists are drawn from what the surveyed projects actually used, not
# from a general taxonomy: every entry here was a real surface on a real repo.
# The same word can mean different things as a file and as a directory, and the
# split below follows the evidence rather than tidiness: a findings.md is a
# decision log on one of these projects, while a findings/ directory is a store
# of dated notes on another.
classify() {  # <rel-path> <type f|d> -> kind or empty
  local rel=$1 type=$2 base low
  base=${rel##*/}
  low=$(lower "$base")
  if [ "$type" = d ]; then
    case "$low" in
      notes|findings|build-log|playbooks|self-improvement) printf 'notes-store\n' ;;
      handoff|handoffs|orchestrator-handoffs) printf 'handoff\n' ;;
    esac
    return 0
  fi
  case "$low" in
    agents.md|claude.md) printf 'entry-point\n'; return 0 ;;
    questions.md|open-questions.md|discussion-queue.md|queue.md) printf 'question-register\n'; return 0 ;;
    decisions.md|findings.md) printf 'decision-record\n'; return 0 ;;
    notes.md) printf 'notes-store\n'; return 0 ;;
    status.md|project_state.md|baton.md) printf 'handoff\n'; return 0 ;;
  esac
  case "$low" in
    *handoff*) printf 'handoff\n'; return 0 ;;
    *kickoff*|next-session*) printf 'handoff\n'; return 0 ;;
    *questions*.md) printf 'question-register\n'; return 0 ;;
    *rulings*|*decisions*.md) printf 'decision-record\n'; return 0 ;;
  esac
  return 0
}

# A coarse prefilter, deliberately broader than classify(): every state surface
# these projects used is either a directory or a markdown file. classify() stays
# the single owner of which of those is which kind.
scan_repo() {
  find "$DIR" -maxdepth 4 \
    \( -name .git -o -name node_modules -o -name .godot -o -name addons \
       -o -name .venv -o -name vendor -o -name dist -o -name build -o -name target \
       -o -name archive -o -name processed -o -name .godot-mcp-memory \) -prune -o \
    \( -type d -o -iname '*.md' \) -print 2>/dev/null
}

while IFS= read -r abs; do
  [ "$abs" = "$DIR" ] && continue
  rel=${abs#"$DIR"/}
  type=f
  if [ -d "$abs" ]; then type=d; fi
  kind=$(classify "$rel" "$type")
  [ -n "$kind" ] || continue
  # CLAUDE.md that is only a symlink to AGENTS.md is the convention, not a
  # second entry point.
  if [ "$kind" = entry-point ] && [ -L "$abs" ]; then
    continue
  fi
  add_surface "$kind" repo "$rel" ""
done <<EOF
$(scan_repo)
EOF

# --- check / setup / run commands -------------------------------------------

nm_test_command() {
  local f="$DIR/.no-mistakes.yaml"
  [ -f "$f" ] || return 0
  awk '
    /^commands:/ { in_cmd = 1; next }
    /^[^[:space:]]/ { in_cmd = 0 }
    in_cmd && $1 == "test:" {
      sub(/^[[:space:]]*test:[[:space:]]*/, "")
      gsub(/^['"'"'"]|['"'"'"][[:space:]]*$/, "")
      print; exit
    }
  ' "$f"
}

# The nearest package.json, which is not always at the repo root: a project
# whose runtime lives in server/ still has exactly one check command, reached
# with npm --prefix.
PKG_JSON=
PKG_PREFIX=
if [ -f "$DIR/package.json" ]; then
  PKG_JSON="$DIR/package.json"
else
  PKG_JSON=$(find "$DIR" -mindepth 2 -maxdepth 2 -name package.json \
    -not -path '*/node_modules/*' 2>/dev/null | sort | head -1)
  if [ -n "$PKG_JSON" ]; then
    PKG_PREFIX=$(dirname "${PKG_JSON#"$DIR"/}")
  fi
fi

npm_cmd() {  # <args...> -> the npm invocation reaching PKG_JSON
  if [ -n "$PKG_PREFIX" ]; then
    printf 'npm --prefix %s %s\n' "$PKG_PREFIX" "$*"
  else
    printf 'npm %s\n' "$*"
  fi
}

json_has_script() {  # <name>
  [ -n "$PKG_JSON" ] && grep -Eq "\"$1\"[[:space:]]*:" "$PKG_JSON" 2>/dev/null
}

make_has_target() {  # <name>
  [ -f "$DIR/Makefile" ] && grep -Eq "^$1:" "$DIR/Makefile" 2>/dev/null
}

# A command read from a project's own config names its script the way that
# config resolves it, which is often bare ("tests/gate.sh"). Executing that from
# a wrapper searches PATH instead of the repo, so anchor a first token that is a
# real file in this project. Anything else is passed through untouched.
anchor_command() {  # <command-string>
  local cmd=$1 first=${1%% *}
  case "$first" in
    ./*|/*|*=*) printf '%s\n' "$cmd"; return 0 ;;
  esac
  if [ -f "$DIR/$first" ]; then
    printf './%s\n' "$cmd"
  else
    printf '%s\n' "$cmd"
  fi
}

# Echo the best existing check command for this project, or nothing.
detect_check_command() {
  local c
  c=$(nm_test_command)
  if [ -n "$c" ]; then anchor_command "$c"; return 0; fi
  for p in tests/gate.sh tools/run_tests.sh run_tests.sh tests/run.sh; do
    [ -x "$DIR/$p" ] && { printf './%s\n' "$p"; return 0; }
  done
  json_has_script ci && { npm_cmd run ci; return 0; }
  json_has_script test && { npm_cmd test; return 0; }
  make_has_target check && { echo 'make check'; return 0; }
  make_has_target test && { echo 'make test'; return 0; }
  return 0
}

detect_setup_command() {
  for p in .regime/setup.sh scripts/setup.sh scripts/setup-hooks.sh bootstrap.sh; do
    [ -x "$DIR/$p" ] && { printf './%s\n' "$p"; return 0; }
  done
  make_has_target setup && { echo 'make setup'; return 0; }
  [ -n "$PKG_JSON" ] && { npm_cmd ci; return 0; }
  return 0
}

detect_run_command() {
  make_has_target run && { echo 'make run'; return 0; }
  json_has_script start && { npm_cmd start; return 0; }
  return 0
}

# A stub this script seeded that only names the gap is a placeholder, not a
# command. Telling the two apart keeps the gap reported for as long as it is
# unreplaced, so a re-run after seeding never reads as "this project verifies".
seeded_gap_stub() {  # <repo-relative-path>
  local f="$DIR/$1"
  [ -f "$f" ] || return 1
  grep -q 'Seeded by firstmate' "$f" 2>/dev/null || return 1
  grep -qx "exit $GAP_EXIT" "$f" 2>/dev/null
}

for name in check setup run; do
  path="script/$name"
  if [ -e "$DIR/$path" ]; then
    if seeded_gap_stub "$path"; then
      add_surface "$name-command" repo "$path" \
        "a seeded placeholder that names the gap and exits $GAP_EXIT, not a $name command yet"
    else
      add_surface "$name-command" repo "$path" "the conventional name"
    fi
  fi
done

CHECK_CMD=$(detect_check_command)
SETUP_CMD=$(detect_setup_command)
RUN_CMD=$(detect_run_command)

# A command this project already has, under whatever name it uses. A reconciler
# whose whole job is finding what already exists must not hide one behind a
# placeholder it planted itself, so the placeholder does not suppress it - the
# report names both and chooses neither.
add_command_surface() {  # <name> <command>
  local name=$1 cmd=$2 path="script/$1"
  [ -n "$cmd" ] || return 0
  if [ ! -e "$DIR/$path" ]; then
    add_surface "$name-command" repo "$cmd" "under another name"
  elif seeded_gap_stub "$path"; then
    add_surface "$name-command" repo "$cmd" "under another name, shadowed by the placeholder at $path"
  fi
}

add_command_surface check "$CHECK_CMD"
add_command_surface setup "$SETUP_CMD"
add_command_surface run "$RUN_CMD"

# --- surfaces outside the repo ----------------------------------------------

# Harness agent memory is keyed by the absolute path of the checkout, so a store
# built up against the primary copy is invisible from every isolated worktree -
# which is where the process requires the work to happen. That silent
# disappearance is why an out-of-repo store is inventoried as a real surface.
CLAUDE_HOME=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
MEMORY_DIR=
memory_key=$(printf '%s\n' "$DIR" | tr '/.' '--')
if [ -d "$CLAUDE_HOME/projects/$memory_key/memory" ]; then
  MEMORY_DIR="$CLAUDE_HOME/projects/$memory_key/memory"
  count=$(find "$MEMORY_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  add_surface notes-store external "$MEMORY_DIR" "$count files, keyed to this absolute path"
fi

if [ "$OFFLINE" -eq 0 ] && [ "$is_git" -eq 1 ] && command -v gh-axi >/dev/null 2>&1; then
  origin_url=$(git -C "$DIR" remote get-url origin 2>/dev/null || true)
  case "$origin_url" in
    *github.com*)
      open_issues=$(cd "$DIR" && gh-axi issue list --state open --limit 1 2>/dev/null |
        awk '$1 == "count:" { print $2; exit }')
      if [ -n "$open_issues" ] && [ "$open_issues" -gt 0 ] 2>/dev/null; then
        add_surface question-register external "GitHub issues" "$open_issues open"
      fi
      ;;
  esac
fi

# --- landing ----------------------------------------------------------------

DEFAULT_BRANCH=
ORIGIN_URL=
LANDING_HAZARD=
if [ "$is_git" -eq 1 ]; then
  ORIGIN_URL=$(git -C "$DIR" remote get-url origin 2>/dev/null || true)
  ref=$(git -C "$DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    DEFAULT_BRANCH=${ref#origin/}
  else
    for b in main master trunk; do
      git -C "$DIR" rev-parse --verify --quiet "refs/heads/$b" >/dev/null 2>&1 && { DEFAULT_BRANCH=$b; break; }
    done
  fi
  # An origin that is itself a non-bare working repo refuses a push to whatever
  # branch it has checked out, so "landed" cannot mean "pushed" here.
  case "$ORIGIN_URL" in
    ''|*://*|*@*:*) ;;
    *)
      if [ -d "$ORIGIN_URL" ] &&
        [ "$(git -C "$ORIGIN_URL" rev-parse --is-bare-repository 2>/dev/null || echo unknown)" = false ]; then
        LANDING_HAZARD="origin is a non-bare working repo at $ORIGIN_URL; git refuses a push to its checked-out branch"
      fi
      ;;
  esac
fi

# --- collisions -------------------------------------------------------------

COLLISIONS="$WORK/collisions"
: > "$COLLISIONS"
for kind in entry-point handoff question-register decision-record notes-store \
            check-command setup-command run-command; do
  n=$(count_of_kind "$kind")
  if [ "$n" -gt 1 ]; then
    joined=$(surfaces_of_kind "$kind" | cut -f3 | head -"$MAX_LIST" | paste -sd, - | sed 's/,/, /g')
    if [ "$n" -gt "$MAX_LIST" ]; then
      joined="$joined, and $((n - MAX_LIST)) more"
    fi
    printf '%s\t%s\t%s\n' "$kind" "$n" "$joined" >> "$COLLISIONS"
  fi
done

# --- disagreements ----------------------------------------------------------

build_epoch_table

DISAGREEMENTS="$WORK/disagreements"
: > "$DISAGREEMENTS"

add_disagreement() {  # <key> <text>
  printf '%s\t%s\n' "$1" "$2" >> "$DISAGREEMENTS"
}

ENTRY_FILE=
for c in AGENTS.md CLAUDE.md; do
  if [ -f "$DIR/$c" ] && [ ! -L "$DIR/$c" ]; then ENTRY_FILE="$DIR/$c"; break; fi
done

# The repo names one surface as the place to look, and a same-job surface is
# newer than the one it names. Believing the named one is how a session picks up
# a month-old thread; this script will not silently pick the newer one instead.
if [ -n "$ENTRY_FILE" ]; then
  for kind in handoff question-register decision-record notes-store; do
    [ "$(count_of_kind "$kind")" -gt 1 ] || continue
    named_path=; newest_path=; newest_epoch=0
    while IFS=$'\t' read -r _k _scope path _detail; do
      # Only in-repo regular files compete here. A directory path is a prefix of
      # its own children, and an out-of-repo store is reported as its own gap, so
      # letting either compete produces a comparison that is not a disagreement.
      [ -n "$path" ] && [ -f "$DIR/$path" ] || continue
      epoch=$(epoch_of "$path")
      if [ "$epoch" -gt "$newest_epoch" ]; then newest_epoch=$epoch; newest_path=$path; fi
      if [ -z "$named_path" ] && grep -Fq "$path" "$ENTRY_FILE" 2>/dev/null; then
        named_path=$path
      fi
    done <<EOF
$(surfaces_of_kind "$kind")
EOF
    [ -n "$named_path" ] || continue
    [ "$newest_path" != "$named_path" ] || continue
    grep -Fq "$newest_path" "$ENTRY_FILE" 2>/dev/null && continue
    add_disagreement "stale-entry-pointer-$kind" \
      "${ENTRY_FILE##*/} routes to $named_path, but $newest_path covers the same job and changed later"
  done
fi

# Work that lives only in the working tree is named in no document, so a session
# following the project's own onboarding rebuilds what already exists. That is
# not two surfaces disagreeing about which is authoritative and there is nothing
# for the captain to rule on, so it is a named gap that lists what is uncommitted
# rather than a hold that blocks the seed.
UNCOMMITTED_COUNT=0
UNCOMMITTED_LIST=
if [ "$is_git" -eq 1 ]; then
  uncommitted="$WORK/uncommitted"
  git -C "$DIR" status --porcelain 2>/dev/null | cut -c4- | grep . > "$uncommitted" || : > "$uncommitted"
  UNCOMMITTED_COUNT=$(grep -c . "$uncommitted" || true)
  if [ "$UNCOMMITTED_COUNT" -gt 0 ]; then
    UNCOMMITTED_LIST=$(head -"$MAX_LIST" "$uncommitted" | paste -sd, - | sed 's/,/, /g')
    if [ "$UNCOMMITTED_COUNT" -gt "$MAX_LIST" ]; then
      UNCOMMITTED_LIST="$UNCOMMITTED_LIST, and $((UNCOMMITTED_COUNT - MAX_LIST)) more"
    fi
  fi
fi

# A delivery mode that promises a PR, against a repo with nowhere to push, is
# how work gets marked done while stranded outside the owner's only copy.
# fm-project-mode.sh warns and falls back to "no-mistakes off" whenever it cannot
# resolve the name, so a warning means the registry records nothing here. The
# fallback is not a record and must not be checked against a remote as if it
# were: that manufactures a hold about a mode nobody ever chose.
MODE_UNRESOLVED=
if [ -n "$PROJECT_NAME" ] && [ -x "$SCRIPT_DIR/fm-project-mode.sh" ]; then
  mode_err="$WORK/mode.err"
  mode_line=$("$SCRIPT_DIR/fm-project-mode.sh" "$PROJECT_NAME" 2>"$mode_err" || true)
  MODE=${mode_line%% *}
  if [ -s "$mode_err" ]; then
    MODE_UNRESOLVED=$(sed -e 's/^warn: //' -e 's/;.*$//' "$mode_err" | head -1)
  else
    case "$MODE" in
      no-mistakes|direct-PR)
        if [ -z "$ORIGIN_URL" ]; then
          add_disagreement delivery-mode-vs-remote \
            "the registry records $PROJECT_NAME as $MODE, which lands work through a pushed PR, but this repo has no origin remote"
        elif [ -n "$LANDING_HAZARD" ]; then
          add_disagreement delivery-mode-vs-remote \
            "the registry records $PROJECT_NAME as $MODE, but $LANDING_HAZARD"
        fi
        ;;
    esac
  fi
fi

# --- report -----------------------------------------------------------------

echo "PROJECT: $DIR"

if [ "$is_git" -eq 0 ]; then
  echo "LANDING: not a git repository; there is no branch and no push target"
elif [ -z "$ORIGIN_URL" ]; then
  echo "LANDING: no remote - landed means merged into local ${DEFAULT_BRANCH:-the default branch}; there is no push target"
elif [ -n "$LANDING_HAZARD" ]; then
  echo "LANDING: $LANDING_HAZARD - landed means merged into local ${DEFAULT_BRANCH:-the default branch}"
else
  echo "LANDING: origin $ORIGIN_URL - landed means merged into ${DEFAULT_BRANCH:-the default branch} on origin"
fi

for kind in entry-point handoff question-register decision-record notes-store \
            check-command setup-command run-command; do
  n=$(count_of_kind "$kind")
  [ "$n" -gt 0 ] || continue
  shown=0
  while IFS=$'\t' read -r _kind scope path detail; do
    [ -n "$_kind" ] || continue
    [ "$shown" -lt "$MAX_LIST" ] || continue
    shown=$((shown + 1))
    if [ -n "$detail" ]; then
      echo "SURFACE: $kind $scope $path - $detail"
    else
      echo "SURFACE: $kind $scope $path"
    fi
  done <<EOF
$(surfaces_of_kind "$kind")
EOF
  if [ "$n" -gt "$MAX_LIST" ]; then
    echo "SURFACE: $kind - and $((n - MAX_LIST)) more of this kind, not listed"
  fi
done

while IFS=$'\t' read -r kind n joined; do
  [ -n "$kind" ] || continue
  echo "COLLISION: $kind - $n surfaces cover this job: $joined"
done < "$COLLISIONS"

open_disagreements=0
while IFS=$'\t' read -r key text; do
  [ -n "$key" ] || continue
  case "$ACCEPTED" in
    *" $key "*) echo "DISAGREEMENT: $key - $text (accepted)" ;;
    *)
      echo "DISAGREEMENT: $key - $text"
      open_disagreements=$((open_disagreements + 1))
      ;;
  esac
done < "$DISAGREEMENTS"

# What is absent or unlanded that this script cannot resolve for the project.
# Every one of these is named out loud and none is ever skipped in silence.
if [ -n "$ENTRY_FILE" ]; then
  read_entry="; read ${ENTRY_FILE##*/} for one this project names, and if there is none,"
else
  read_entry=" and there is no entry point naming one;"
fi
if seeded_gap_stub script/check && [ -n "$CHECK_CMD" ]; then
  echo "GAP: check-command - script/check is still the seeded placeholder that exits $GAP_EXIT, standing in front of $CHECK_CMD, which this project already has; which of the two is authoritative is the captain's call, and until it is made a done claim here degrades to this named gap, never a silent pass"
elif seeded_gap_stub script/check; then
  echo "GAP: check-command - script/check is still the seeded placeholder that exits $GAP_EXIT, so no check command exists under any conventional name$read_entry a done claim here degrades to this named gap, never a silent pass"
elif [ -z "$CHECK_CMD" ] && [ ! -e "$DIR/script/check" ]; then
  echo "GAP: check-command - no check command exists under any conventional name$read_entry a done claim here degrades to this named gap, never a silent pass"
fi
if [ "$UNCOMMITTED_COUNT" -gt 0 ]; then
  echo "GAP: uncommitted-state - $UNCOMMITTED_COUNT path(s) hold work that is not committed and that no document describes: $UNCOMMITTED_LIST; read them before rebuilding state this project already has"
fi
if [ -n "$MODE_UNRESOLVED" ]; then
  echo "GAP: delivery-mode-unresolved - $MODE_UNRESOLVED, so what landing means for $PROJECT_NAME is unrecorded; register the project before its delivery mode can be checked against this repo"
fi
if [ -n "$MEMORY_DIR" ]; then
  echo "GAP: memory-outside-repo - $MEMORY_DIR is keyed to this absolute path, so it is invisible from every isolated worktree"
fi
# --- seed plan --------------------------------------------------------------

# Surfaces this script may create, and the single existence test that decides
# whether each is genuinely missing. Nothing here ever replaces or rewrites an
# existing surface.
seed_targets() {
  cat <<'EOF'
AGENTS.md
script/setup
script/check
script/run
DECISIONS.md
notes
EOF
}

# QUESTIONS.md and handoff/ are never in seed_targets. This guard makes that a
# refusal rather than an omission, so a future edit cannot reintroduce either by
# accident.
NEVER_SEED='QUESTIONS.md handoff'
refuse_never_seeded() {  # <target>
  local t=$1 n
  for n in $NEVER_SEED; do
    if [ "$t" = "$n" ]; then
      echo "error: $t is never seeded; questions live on firstmate's board and firstmate is the handoff" >&2
      exit 1
    fi
  done
}

entry_point_present() { [ -e "$DIR/AGENTS.md" ] || [ -e "$DIR/CLAUDE.md" ]; }

# Presence is decided from the inventory AND from the filesystem, because
# neither sees everything. A project carrying findings/, build-log/ or
# playbooks/ already has a notes store and only the inventory knows that; a
# store reached through a symlink is not a directory to find(1) and only the
# filesystem knows that. Either is a naming difference rather than an absence,
# and seeding a second store is the duplication this exists to prevent. -L is
# tested alongside -e so a dangling symlink still counts as something there.
notes_path_present() {
  [ -e "$DIR/notes" ] || [ -L "$DIR/notes" ] || [ -e "$DIR/notes.md" ] || [ -L "$DIR/notes.md" ]
}

target_present() {  # <target>
  case "$1" in
    AGENTS.md) entry_point_present ;;
    notes) [ "$(repo_count_of_kind notes-store)" -gt 0 ] || notes_path_present ;;
    DECISIONS.md) [ "$(repo_count_of_kind decision-record)" -gt 0 ] ;;
    *) [ -e "$DIR/$1" ] ;;
  esac
}

# --- the write boundary -----------------------------------------------------

# Where a write to a path would actually land, following every symlink on the
# way, the same physical resolution the target directory itself already gets
# from pwd -P. A path that cannot be resolved returns non-zero and is treated as
# an escape, because "cannot tell" is not permission to write.
phys_of() {  # <absolute-path> [depth]
  local p=$1 depth=${2:-0} target d b
  [ "$depth" -lt 40 ] || return 1
  if [ -d "$p" ]; then
    if ! (cd "$p" 2>/dev/null && pwd -P); then return 1; fi
    return 0
  fi
  if [ -L "$p" ]; then
    target=$(readlink "$p" 2>/dev/null) || return 1
    case "$target" in
      /*) ;;
      *) target="$(dirname "$p")/$target" ;;
    esac
    if phys_of "$target" "$((depth + 1))"; then return 0; fi
    return 1
  fi
  d=$(phys_of "$(dirname "$p")" "$((depth + 1))") || return 1
  b=$(basename "$p")
  printf '%s/%s\n' "$d" "$b"
}

inside_repo() {  # <physical-path>
  case "$1" in
    "$DIR"|"$DIR"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Every path seeding one target writes, so the whole plan can be checked before
# any of it runs.
seed_paths() {  # <target>
  case "$1" in
    AGENTS.md) printf 'AGENTS.md\nCLAUDE.md\n' ;;
    notes) printf 'notes\nnotes/README.md\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# shellcheck disable=SC2016  # single quotes are deliberate: the generated stub
# must contain these expressions literally, not this script's expansion of them.
write_stub() {  # <path> <purpose> <command-or-empty>
  local path=$1 purpose=$2 cmd=$3 abs="$DIR/$1"
  mkdir -p "$(dirname "$abs")"
  {
    echo '#!/usr/bin/env bash'
    echo "# $purpose"
    if [ -n "$cmd" ]; then
      echo '# Seeded by firstmate under the conventional name; it wraps the command this'
      echo '# project already had, so nothing that names the original has to change.'
      echo 'set -eu'
      echo 'cd "$(dirname "$0")/.."'
      echo "exec $cmd"
    else
      echo '# Seeded by firstmate. This project had no such command, so this stub reports a'
      echo "# named gap and exits $GAP_EXIT. Replace the two lines below with the real command."
      echo '# Never make it exit 0 without running something: a silent pass is the failure'
      echo '# the done checklist exists to catch.'
      echo 'set -eu'
      echo "echo \"$path: no ${path##*/} command defined for this project yet\" >&2"
      echo "exit $GAP_EXIT"
    fi
  } > "$abs"
  chmod +x "$abs"
}

write_decisions() {
  cat > "$DIR/DECISIONS.md" <<'EOF'
# Decisions

Only this file records what the owner said, and only as a dated verbatim quote.
A previous session's summary of the owner is not evidence the owner said it.

Append newest last, one entry per decision:

## YYYY-MM-DD - what was decided

> the owner's own words, quoted exactly

What changed as a result, in a line or two.
EOF
}

write_notes() {
  mkdir -p "$DIR/notes"
  cat > "$DIR/notes/README.md" <<'EOF'
# Notes

One small dated note per file, named `YYYY-MM-DD-short-slug.md`.

Append only. Never rewrite, renumber or merge an existing note, so two machines
writing at once never collide.

Write one whenever something is learned the hard way, and end it with the line:
what would have caught this earlier?
EOF
}

seed_one() {  # <target>
  case "$1" in
    AGENTS.md)
      "$SCRIPT_DIR/fm-ensure-agents-md.sh" "$DIR" >/dev/null
      ;;
    script/check) write_stub script/check 'The one command that says pass or fail for this project.' "$CHECK_CMD" ;;
    script/setup) write_stub script/setup 'Clone to working, in one command.' "$SETUP_CMD" ;;
    script/run)   write_stub script/run   'Launch this project.' "$RUN_CMD" ;;
    DECISIONS.md) write_decisions ;;
    notes)        write_notes ;;
  esac
}

planned="$WORK/planned"
: > "$planned"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  refuse_never_seeded "$t"
  if target_present "$t"; then
    echo "PRESENT: $t"
  else
    echo "$t" >> "$planned"
  fi
done <<EOF
$(seed_targets)
EOF

# Resolve the whole plan before writing any of it. Validating each target as it
# is written would leave the targets ahead of the bad one already on disk, and a
# half-seeded project is worse than a refused one.
ESCAPES="$WORK/escapes"
: > "$ESCAPES"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    phys=$(phys_of "$DIR/$p") || phys=
    if [ -z "$phys" ] || ! inside_repo "$phys"; then
      printf '%s -> %s\n' "$p" "${phys:-unresolvable}" >> "$ESCAPES"
    fi
  done <<EOF
$(seed_paths "$t")
EOF
done < "$planned"

# Named here as well as in the refusal, and from the same two values, because a
# read-only report that lists a plan --seed will refuse wholesale is a report
# that describes something that cannot happen. Firstmate briefs a crewmate from
# this report, so what it says and what --seed does have to be the same thing.
ESCAPED_COUNT=$(grep -c . "$ESCAPES" || true)
ESCAPED_LIST=
if [ "$ESCAPED_COUNT" -gt 0 ]; then
  ESCAPED_LIST=$(head -"$MAX_LIST" "$ESCAPES" | paste -sd, - | sed 's/,/, /g')
  if [ "$ESCAPED_COUNT" -gt "$MAX_LIST" ]; then
    ESCAPED_LIST="$ESCAPED_LIST, and $((ESCAPED_COUNT - MAX_LIST)) more"
  fi
  echo "GAP: seed-path-outside-project - $ESCAPED_COUNT planned path(s) resolve outside $DIR: $ESCAPED_LIST; this script writes inside the project directory and nowhere else, so --seed refuses the whole plan below with exit 5 rather than writing the part of it that would land inside"
fi

# --- seed refusals ----------------------------------------------------------

# Every refusal is decided before a single SEED line prints, so a refused run
# never says it created anything. Grepping SEED lines is the documented way to
# consume this report, and "(creating)" is reserved for a run that goes on to
# write; a refused run still shows the plan, as "(would create)".
REFUSAL=
REFUSAL_CODE=0
if [ "$SEED" -eq 1 ]; then
  parent=$(dirname "$DIR")
  if [ "$open_disagreements" -gt 0 ]; then
    REFUSAL="REFUSED: $open_disagreements disagreement(s) are open; two surfaces disagree about what is true and the captain owns which one survives. Nothing was written. Re-run with --accept-disagreement <key> once each is ruled on."
    REFUSAL_CODE=3
  # Firstmate reads projects and crewmates change them. A clone sitting directly
  # under a firstmate home's projects/ directory is the copy firstmate operates
  # from, so seeding into it would bypass the delivery path.
  elif [ "$(basename "$parent")" = projects ] && [ -f "$(dirname "$parent")/data/projects.md" ]; then
    REFUSAL="REFUSED: $DIR is a firstmate-owned project clone. Seed from the crewmate worktree that carries the change through this project's delivery path, not from the copy firstmate reads. Nothing was written."
    REFUSAL_CODE=4
  elif [ "$ESCAPED_COUNT" -gt 0 ]; then
    REFUSAL="REFUSED: $ESCAPED_COUNT planned path(s) resolve outside $DIR: $ESCAPED_LIST. This script writes inside the project directory and nowhere else, so the whole plan is refused rather than the part of it that would have landed inside. Nothing was written."
    REFUSAL_CODE=5
  fi
fi

while IFS= read -r t; do
  [ -n "$t" ] || continue
  if [ "$SEED" -eq 1 ] && [ -z "$REFUSAL" ]; then
    echo "SEED: $t (creating)"
  else
    echo "SEED: $t (would create)"
  fi
done < "$planned"

if [ -n "$REFUSAL" ]; then
  echo "$REFUSAL" >&2
  exit "$REFUSAL_CODE"
fi

[ "$SEED" -eq 1 ] || exit 0

# --- seeding ----------------------------------------------------------------

while IFS= read -r t; do
  [ -n "$t" ] || continue
  seed_one "$t"
done < "$planned"
