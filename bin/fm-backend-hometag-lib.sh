#!/usr/bin/env bash
# bin/fm-backend-hometag-lib.sh - shared per-installation home-tag derivation
# for session-provider backends whose container has ONE namespace shared by
# every firstmate home on the machine, with no native per-home split (cmux's
# one app-global workspace list, zellij's one shared "firstmate" session's
# tab bar). Without a per-home discriminator embedded in the actual
# title/name, two firstmate homes (two secondmates, a primary plus a
# secondmate, or two independent primary installations) whose task ids
# happen to collide can send/peek/close each other's tabs - the gap a
# captain-directed no-mistakes review gate caught for cmux
# (docs/cmux-backend.md) and this same tag mechanism was later ported to
# zellij to close for the same reason (docs/zellij-backend.md "Home-scoped
# tab titles").
#
# fm_backend_hometag() derives a short, stable tag: a readable prefix
# ("firstmate" for the primary home, "2ndmate-<id>" for a secondmate home
# carrying .fm-secondmate-home, "peer-<id>" for a peer home carrying
# .fm-peer-home) plus a short hash of the resolved FM_ROOT
# path, so distinct installations - including multiple primaries on one
# machine - never collide even though they share one backend-global
# namespace. Callers source this file AFTER resolving their own
# FM_HOME/FM_ROOT fallbacks (both adapters already do this for their own
# purposes before any other function runs).
#
# The FM_ROOT hash alone cannot separate peer homes, because every peer home
# deliberately runs the SAME tracked code root and is distinguished only by
# FM_HOME - so the readable prefix carries that identity instead.
#
# Moving/relocating a firstmate installation changes its FM_ROOT path and
# therefore its tag; titles created under the old tag simply stop matching -
# an accepted limitation, no worse than the existing fact that a task's
# recorded absolute worktree path does not survive a move either.

FM_BACKEND_HOMETAG_SECONDMATE_MARKER=".fm-secondmate-home"
FM_BACKEND_HOMETAG_PEER_MARKER=".fm-peer-home"

fm_backend_hometag_marker_id() {
  local marker=$1
  [ -f "$marker" ] || return 0
  tr -d '[:space:]' < "$marker" 2>/dev/null
}

fm_backend_hometag() {
  local id prefix root hash
  prefix="firstmate"
  id=$(fm_backend_hometag_marker_id "$FM_HOME/$FM_BACKEND_HOMETAG_SECONDMATE_MARKER")
  if [ -n "$id" ]; then
    prefix="2ndmate-$id"
  else
    id=$(fm_backend_hometag_marker_id "$FM_HOME/$FM_BACKEND_HOMETAG_PEER_MARKER")
    [ -z "$id" ] || prefix="peer-$id"
  fi
  root=$(cd "$FM_ROOT" 2>/dev/null && pwd -P) || root=$FM_ROOT
  if command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | shasum -a 256 | awk '{print substr($1,1,8)}')
  elif command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | sha256sum | awk '{print substr($1,1,8)}')
  else
    hash=$(printf '%s' "$root" | cksum | awk '{printf "%08x", $1}')
  fi
  printf '%s-%s' "$prefix" "$hash"
}
