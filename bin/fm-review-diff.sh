#!/usr/bin/env bash
# Review a crewmate branch against the authoritative base.
#
# Pooled project clones do not keep their local default branch current, so this
# helper compares remote-backed projects against origin/<default> after fetching
# the default branch, and local-only projects against the local default branch.
# When state/<id>.meta records pr= (URL or number) for an open PR, the compare
# side is ALWAYS a freshly fetched refs/pull/<n>/head by default so review stays
# current after no-mistakes fix rounds push to the PR. A recorded pr_head= is
# only a fallback when fetch fails (stale recorded SHAs must never win over a
# reachable remote PR head). If neither PR head can be resolved, fall back to
# the local branch with a warning.
#
# A validated-main task never opens a PR, so it never records pr=, but its
# pipeline still runs the push step and commits its own fix rounds - the local
# branch is routinely behind what was published, and bin/fm-merge-main.sh lands
# origin/<branch> whenever it exists. Reviewing the local branch there would show
# a diff that is not the one that lands, so for mode=validated-main the compare
# side is a freshly fetched origin/<branch>. No forge call and no PR number are
# involved. A branch the remote genuinely does not carry means the push step has
# not run yet, which makes the local branch the only candidate head and is not a
# warning; a remote that cannot be reached is, because the published head may
# exist and be newer.
#
# Otherwise, compare the local branch.
#
# Every path prints a "compare: " line naming the side it actually used, because
# the fallbacks above are otherwise indistinguishable from a normal run and a
# reviewer cannot tell which head they read. A head resolved by fetch and a head
# taken from recorded pr_head= are labelled apart: the recorded one is the only
# compare side never confirmed against the remote, so it can legitimately be
# stale, and that path warns on nothing.
# Usage: fm-review-diff.sh <task-id> [--stat]
#   --stat prints only the stat summary; default prints stat summary plus full diff.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
"$FM_ROOT/bin/fm-guard.sh" || true

usage() {
  echo "usage: fm-review-diff.sh <task-id> [--stat]" >&2
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ID=${1:-}
[ -n "$ID" ] || { usage; exit 1; }
STAT_ONLY=false
case "${2:-}" in
  '') ;;
  --stat) STAT_ONLY=true ;;
  *) usage; exit 1 ;;
esac
[ $# -le 2 ] || { usage; exit 1; }

META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }

WT=$(grep '^worktree=' "$META" | cut -d= -f2-)
PROJ=$(grep '^project=' "$META" | cut -d= -f2-)
[ -n "$WT" ] || { echo "error: meta for task $ID is missing worktree=" >&2; exit 1; }
[ -n "$PROJ" ] || { echo "error: meta for task $ID is missing project=" >&2; exit 1; }
[ -d "$WT" ] || { echo "error: worktree for task $ID is missing: $WT" >&2; exit 1; }
[ -d "$PROJ" ] || { echo "error: project for task $ID is missing: $PROJ" >&2; exit 1; }

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

DEFAULT=$(default_branch) || { echo "error: cannot determine default branch for $PROJ; expected origin/HEAD, main, or master" >&2; exit 1; }

BRANCH="fm/$ID"
if ! git -C "$WT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  BRANCH=$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ -n "$BRANCH" ] || { echo "error: branch fm/$ID does not exist and worktree $WT is detached" >&2; exit 1; }
  git -C "$WT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null || { echo "error: branch $BRANCH does not exist in $WT" >&2; exit 1; }
fi

pr_number_from_target() {
  local target=$1 n
  case "$target" in
    '' ) return 1 ;;
    *"/pull/"*)
      n=${target##*/pull/}
      n=${n%%[!0-9]*}
      ;;
    [0-9]*)
      n=${target%%[!0-9]*}
      ;;
    *) return 1 ;;
  esac
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

# Fetch into a private ref so a later base-branch fetch cannot clobber the
# compare tip via FETCH_HEAD, and so we never review a stale local object.
fetch_private_ref() {
  local src=$1 dst=$2 resolved
  git -C "$WT" remote get-url origin >/dev/null 2>&1 || return 1
  git -C "$WT" fetch --quiet origin "+$src:$dst" >/dev/null 2>&1 || return 1
  resolved=$(git -C "$WT" rev-parse --verify "$dst^{commit}" 2>/dev/null) || return 1
  [ -n "$resolved" ] || return 1
  printf '%s' "$resolved"
}

fetch_pull_head() {
  fetch_private_ref "refs/pull/$1/head" "refs/fm-review/pull/$1/head"
}

resolve_pr_head() {
  local pr_url=$1 recorded_head=$2 n resolved
  n=$(pr_number_from_target "$pr_url") || true
  if [ -n "$n" ]; then
    if resolved=$(fetch_pull_head "$n"); then
      printf 'fetched refs/pull/%s/head %s' "$n" "$resolved"
      return 0
    fi
  fi
  # Offline / unreachable remote, or a pr= this parser cannot turn into a PR
  # number: recorded pr_head is better than the local branch, but never preferred
  # over a successful pull-head fetch above. Reached either way it was not
  # confirmed against the remote, so the caller labels it apart.
  if [ -n "$recorded_head" ] \
    && git -C "$WT" cat-file -e "$recorded_head^{commit}" 2>/dev/null; then
    printf 'recorded %s' "$recorded_head"
    return 0
  fi
  return 1
}

fetch_published_head() {
  fetch_private_ref "refs/heads/$1" "refs/fm-review/heads/$1"
}

# A fetch refspec for a ref the remote does not carry fails exactly like an
# unreachable remote, and the two mean opposite things for review. ls-remote
# --exit-code answers 2 only when the remote replied and matched nothing.
published_branch_absent() {
  local rc=0
  git -C "$WT" ls-remote --exit-code --heads origin "refs/heads/$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

PR_URL=$(grep '^pr=' "$META" | tail -1 | cut -d= -f2- || true)
PR_HEAD_RECORDED=$(grep '^pr_head=' "$META" | tail -1 | cut -d= -f2- || true)
MODE=$(grep '^mode=' "$META" | tail -1 | cut -d= -f2- || true)
COMPARE_REF=$BRANCH
COMPARE_DESC="local branch $BRANCH"
COMPARE_NOTE=
if [ -n "$PR_URL" ]; then
  if PR_HEAD_RESULT=$(resolve_pr_head "$PR_URL" "$PR_HEAD_RECORDED"); then
    PR_HEAD=${PR_HEAD_RESULT##* }
    PR_HEAD_SOURCE=${PR_HEAD_RESULT% *}
    COMPARE_REF=$PR_HEAD
    case "$PR_HEAD_SOURCE" in
      recorded)
        COMPARE_DESC="recorded PR head $PR_HEAD (from task meta, unconfirmed against the remote; may be stale)"
        ;;
      *)
        COMPARE_DESC="PR head $PR_HEAD ($PR_HEAD_SOURCE)"
        ;;
    esac
  else
    COMPARE_DESC="local branch $BRANCH (PR head unavailable)"
    echo "warning: PR head unavailable; diff may lag the open PR (using local branch $BRANCH)" >&2
  fi
elif [ "$MODE" = validated-main ]; then
  if PUBLISHED_HEAD=$(fetch_published_head "$BRANCH"); then
    COMPARE_REF=$PUBLISHED_HEAD
    COMPARE_DESC="published head origin/$BRANCH $PUBLISHED_HEAD"
    AHEAD=$(git -C "$WT" rev-list --count "$BRANCH" --not "$PUBLISHED_HEAD" -- 2>/dev/null || true)
    if [ -n "$AHEAD" ] && [ "$AHEAD" -gt 0 ]; then
      COMPARE_NOTE="note: local branch $BRANCH has $AHEAD commit(s) the published head does not contain; they are not in this diff"
    fi
  elif published_branch_absent "$BRANCH"; then
    COMPARE_DESC="local branch $BRANCH (nothing published to origin; not a validated published head)"
  else
    COMPARE_DESC="local branch $BRANCH (published head unavailable)"
    echo "warning: published head origin/$BRANCH unavailable; diff may lag the validated branch (using local branch $BRANCH)" >&2
  fi
fi

if git -C "$PROJ" remote get-url origin >/dev/null 2>&1; then
  # Update the remote-tracking ref itself; a bare single-branch fetch can leave
  # origin/<default> stale on some Git versions and only refresh FETCH_HEAD.
  git -C "$WT" fetch origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" --quiet
  BASE="origin/$DEFAULT"
else
  BASE="$DEFAULT"
fi

git -C "$WT" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || { echo "error: base $BASE does not exist in $WT" >&2; exit 1; }
git -C "$WT" rev-parse --verify --quiet "$COMPARE_REF^{commit}" >/dev/null || { echo "error: compare ref $COMPARE_REF does not resolve in $WT" >&2; exit 1; }

echo "diff base: $BASE"
echo "compare: $COMPARE_DESC"
[ -z "$COMPARE_NOTE" ] || echo "$COMPARE_NOTE"
if git -C "$WT" diff --quiet "$BASE...$COMPARE_REF" --; then
  echo "no changes vs $BASE"
  exit 0
fi

git -C "$WT" diff --stat "$BASE...$COMPARE_REF" --
if ! "$STAT_ONLY"; then
  echo
  git -C "$WT" diff "$BASE...$COMPARE_REF" --
fi
