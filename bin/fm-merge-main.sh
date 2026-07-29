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
# local commits the validated head does not contain, a branch published to a remote
# other than origin (the local no-mistakes gate remote is bookkeeping, not
# publication, and does not count), and a default branch that has moved on the host.
# See AGENTS.md prime directives and task lifecycle.
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

# `no-mistakes init` adds a remote named "no-mistakes" pointing at the local bare
# gate repository, and every gate run leaves a refs/remotes/no-mistakes/fm/<id>
# tracking ref behind. Those refs are gate bookkeeping, not a publication target,
# and a validated-main project is required to be gate-initialized - counting them
# as off-origin publication would refuse every real landing. The exclusion is
# narrow: it applies only to a remote of that name whose URL is a local path, so a
# hosted fork remote still trips the guard below even if it carries that name.
GATE_REMOTE=
case "$(git -C "$PROJ" remote get-url no-mistakes 2>/dev/null || true)" in
  /*|file://*) GATE_REMOTE=no-mistakes ;;
esac

# This path reads the validated head from origin only. Under fork push routing
# (no-mistakes init --fork-url) the pipeline publishes elsewhere, and silently
# falling back to the local head would land code the reviewer never saw. No fleet
# project uses fork routing today, so stop and report instead of guessing.
elsewhere=$(git -C "$PROJ" for-each-ref --format='%(refname)' "refs/remotes/*/$BRANCH" | grep -v "^refs/remotes/origin/$BRANCH\$" || true)
if [ -n "$elsewhere" ] && [ -n "$GATE_REMOTE" ]; then
  elsewhere=$(printf '%s\n' "$elsewhere" | grep -v "^refs/remotes/$GATE_REMOTE/$BRANCH\$" || true)
fi
if [ -n "$elsewhere" ]; then
  echo "REFUSED: $BRANCH also exists on a remote other than origin:" >&2
  printf '%s\n' "$elsewhere" >&2
  echo "This landing path reads the validated head from origin only; resolve the push routing before landing." >&2
  exit 1
fi

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

# A re-run after a successful landing is not a divergence. The published branch was
# retired, so SOURCE falls back to the local task branch, whose head both $DEFAULT
# and origin/$DEFAULT already contain - the checks below would read that as "the
# branch diverged" and send the worker off to rebase and re-validate work that is
# already on the host. Report it plainly instead, and touch nothing: this path does
# not push and does not retire a branch. The rejected-push retry is deliberately not
# caught here, because origin/$DEFAULT does not contain the work in that case.
if git -C "$PROJ" merge-base --is-ancestor "$SOURCE" "refs/remotes/origin/$DEFAULT" &&
   git -C "$PROJ" merge-base --is-ancestor "$SOURCE" "$DEFAULT"; then
  echo "already landed: $DEFAULT and origin/$DEFAULT both contain $SOURCE_DESC ($(git -C "$PROJ" rev-parse --short "$SOURCE")) in $PROJ; nothing to do"
  exit 0
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
# Full sha of what landed, resolved before any ref this script may later delete.
LANDED=$(git -C "$PROJ" rev-parse "$DEFAULT")
# A rejected push is reported, never worked around: the forge's own message above
# is the evidence, and branch protection is discovered this way rather than by
# guessing at it. Nothing is lost - the work is on local $DEFAULT and still on the
# published branch, which is why the retirement below is not reached.
# Re-running this script is the retry: local $DEFAULT already contains $SOURCE, so
# the merge is a no-op and only the push is attempted again.
git -C "$PROJ" push --quiet origin "$DEFAULT" || {
  echo "error: merged $SOURCE_DESC into local $DEFAULT ($before -> $after) but the push to origin/$DEFAULT was rejected" >&2
  echo "The message above is the forge's own reason. The change is safe on local $DEFAULT and on origin/$BRANCH." >&2
  echo "Re-run bin/fm-merge-main.sh $ID to retry the push once the cause is resolved; do not tear the task down first." >&2
  exit 1
}
echo "landed $SOURCE_DESC on $DEFAULT ($before -> $after) and pushed to origin in $PROJ"

# Retiring the published branch is cleanup, not a discard - but only once another
# remote ref provably contains its commits. The task worktree is a linked worktree
# of this clone, so it shares refs/remotes, and fm-teardown.sh proves work is landed
# with `git log HEAD --not --remotes` there. Deleting origin/<branch> while
# origin/<default> did not yet contain the commits would remove the last remote
# reference to landed work and make that check refuse. Push normally updates the
# remote-tracking ref; refresh it anyway rather than assuming, then verify.
if git -C "$PROJ" rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null; then
  git -C "$PROJ" fetch --quiet origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" 2>/dev/null || true
  if ! git -C "$PROJ" merge-base --is-ancestor "$LANDED" "refs/remotes/origin/$DEFAULT" 2>/dev/null; then
    echo "note: leaving origin/$BRANCH in place; could not confirm origin/$DEFAULT contains the landed commits" >&2
  elif git -C "$PROJ" push --quiet origin --delete "$BRANCH" 2>/dev/null; then
    echo "retired published branch origin/$BRANCH"
  else
    echo "note: could not retire published branch origin/$BRANCH; it is redundant now that $DEFAULT contains it" >&2
  fi
fi
