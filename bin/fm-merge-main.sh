#!/usr/bin/env bash
# Land an approved validated-main ship task: fast-forward the project's default
# branch onto the validated task branch, then push it to the host.
#
# This is firstmate's merge gate-action for mode=validated-main. The no-mistakes
# pipeline validates the task branch locally (review, tests, documentation, lint)
# and publishes it with its push step; this script then moves the default branch
# onto that validated head and pushes it. No pull request exists at any point -
# the host stores the repository and is not a step in the workflow.
#
# Like fm-merge-local.sh this is a sanctioned exception to hard rule #1 "never run
# state-changing git in projects/", and it is equally narrow: it runs only for
# mode=validated-main tasks, only after the configured merge authority approves
# (captain approval, or yolo=on), and only as a clean fast-forward. It refuses a
# diverged branch, a dirty or off-default project checkout, a task branch carrying
# local commits the validated head does not contain, and a default branch that has
# moved on the host. See AGENTS.md prime directives and task lifecycle.
#
# The merge source is the published head (origin/fm/<id>) whenever it exists,
# because the pipeline commits its own fix rounds and pushes them - the local task
# branch can legitimately be behind it, and merging the stale local head would land
# unvalidated code. The local branch is used only when nothing was published.
# Usage: fm-merge-main.sh <task-id>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
"$FM_ROOT/bin/fm-guard.sh" || true
ID=${1:?usage: fm-merge-main.sh <task-id>}
META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }

PROJ=$(grep '^project=' "$META" | cut -d= -f2-)
MODE=$(grep '^mode=' "$META" | cut -d= -f2- || true)
[ "$MODE" = validated-main ] || { echo "error: task $ID is mode=$MODE, not validated-main; land local-only tasks with bin/fm-merge-local.sh and PR tasks with bin/fm-pr-merge.sh <id> <PR url>" >&2; exit 1; }

default_branch() {
  local ref branch
  ref=$(git -C "$PROJ" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    echo "${ref#origin/}"
    return 0
  fi
  for branch in main master; do
    if git -C "$PROJ" show-ref --verify --quiet "refs/heads/$branch"; then
      echo "$branch"
      return 0
    fi
  done
  return 1
}

BRANCH="fm/$ID"
git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null || { echo "error: branch $BRANCH does not exist in $PROJ" >&2; exit 1; }

DEFAULT=$(default_branch) || { echo "error: cannot determine default branch for $PROJ; expected origin/HEAD, main, or master" >&2; exit 1; }

# validated-main lands on the host, so an origin remote is required. A project
# with no remote belongs in local-only, which merges without pushing.
git -C "$PROJ" remote get-url origin >/dev/null 2>&1 || { echo "error: $PROJ has no origin remote; a validated-main project must have one (use local-only for a project with no remote)" >&2; exit 1; }

# The project's main checkout must be on its default branch and clean, so the
# fast-forward lands predictably (firstmate never writes here otherwise).
cur=$(git -C "$PROJ" symbolic-ref --short HEAD 2>/dev/null || echo "")
[ "$cur" = "$DEFAULT" ] || { echo "error: $PROJ is on '$cur', expected default branch '$DEFAULT'; cannot merge safely" >&2; exit 1; }
if [ -n "$(git -C "$PROJ" status --porcelain 2>/dev/null | head -1)" ]; then
  echo "error: $PROJ has a dirty working tree; refusing to merge into it" >&2
  exit 1
fi

# Refresh the host's view of the default branch. Landing without it could push a
# default branch that has already moved, so a failed fetch refuses rather than
# guessing.
git -C "$PROJ" fetch --quiet origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" || {
  echo "error: cannot fetch origin/$DEFAULT for $PROJ; refusing to land without the host's current default branch" >&2
  exit 1
}
# The published task branch is optional: absent means the pipeline's push step did
# not run, and the local branch is then the only candidate head.
git -C "$PROJ" fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null || true

SOURCE="$BRANCH"
SOURCE_DESC="local $BRANCH"
if git -C "$PROJ" rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null; then
  # The pipeline's published head is authoritative. Local commits it does not
  # contain mean the branch was edited after validation, so the validated head and
  # the local head disagree about what was reviewed.
  ahead=$(git -C "$PROJ" log --oneline "$BRANCH" --not "refs/remotes/origin/$BRANCH" -- 2>/dev/null | head -5)
  if [ -n "$ahead" ]; then
    echo "REFUSED: $BRANCH has commits the validated head origin/$BRANCH does not contain." >&2
    printf 'commits only on the local branch:\n%s\n' "$ahead" >&2
    echo "Those commits were not validated. Have the worker synchronize and re-validate, then retry." >&2
    exit 1
  fi
  SOURCE="refs/remotes/origin/$BRANCH"
  SOURCE_DESC="validated head origin/$BRANCH"
fi

# Clean fast-forward only, against both the local and the host default branch.
if ! git -C "$PROJ" merge-base --is-ancestor "$DEFAULT" "$SOURCE"; then
  echo "REFUSED: $SOURCE_DESC is not a fast-forward of $DEFAULT (it has diverged)." >&2
  echo "Have the worker rebase $BRANCH onto $DEFAULT and re-validate, then retry." >&2
  exit 1
fi
if ! git -C "$PROJ" merge-base --is-ancestor "refs/remotes/origin/$DEFAULT" "$SOURCE"; then
  echo "REFUSED: $SOURCE_DESC does not contain origin/$DEFAULT; the host's default branch has moved." >&2
  echo "Have the worker rebase $BRANCH onto the current $DEFAULT and re-validate, then retry." >&2
  exit 1
fi

before=$(git -C "$PROJ" rev-parse --short "$DEFAULT")
git -C "$PROJ" merge --ff-only "$SOURCE" >/dev/null
after=$(git -C "$PROJ" rev-parse --short "$DEFAULT")
git -C "$PROJ" push --quiet origin "$DEFAULT" || {
  echo "error: merged $SOURCE_DESC into local $DEFAULT ($before -> $after) but the push to origin/$DEFAULT failed" >&2
  echo "The local default branch already holds the change; retry the push before tearing the task down." >&2
  exit 1
}
echo "landed $SOURCE_DESC on $DEFAULT ($before -> $after) and pushed to origin in $PROJ"

# The task branch's commits are now reachable from the pushed default branch, so
# retiring the published branch is safe cleanup, not a discard. Best-effort: a
# failure here leaves a stale branch on the host and nothing else.
if git -C "$PROJ" rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null; then
  if git -C "$PROJ" push --quiet origin --delete "$BRANCH" 2>/dev/null; then
    echo "retired published branch origin/$BRANCH"
  else
    echo "note: could not retire published branch origin/$BRANCH; it is redundant now that $DEFAULT contains it" >&2
  fi
fi
