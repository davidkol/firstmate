#!/usr/bin/env bash
# Detach a command into its own process session, fully orphaned from the caller.
#
# macOS ships no setsid(1), so this is the repo's single owner of the
# "survive the caller's process group" primitive. It double-forks through
# POSIX::setsid so the final process is a session leader reparented to init:
# the caller returns immediately, and nothing the caller's own lifecycle does
# to its process group can reap the detached child.
#
# Usage: fm-codex-detach.sh <command> [args...]
# Exits 0 as soon as the detached process has been launched; the caller never
# learns that process's own exit status, by design.
#
# This is NOT a general "fire and forget from a model tool call" escape hatch.
# bin/fm-afk-start.sh documents why a backgrounded child of a Codex TOOL CALL is
# unsafe. This helper exists for the opposite position: a Codex HOOK process,
# whose lifetime ends with the hook itself, launching supervision that must
# outlive it (bin/fm-codex-stop-autoarm.sh).
set -eu

[ "$#" -ge 1 ] || { echo "usage: $(basename "$0") <command> [args...]" >&2; exit 2; }
case "${1:-}" in
  -h|--help)
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

exec perl -e '
  use strict; use warnings; use POSIX qw(setsid);
  my $pid = fork();
  die "fork: $!\n" unless defined $pid;
  exit 0 if $pid;
  setsid() or die "setsid: $!\n";
  my $second = fork();
  die "fork: $!\n" unless defined $second;
  exit 0 if $second;
  open(STDIN,  "<", "/dev/null");
  open(STDOUT, ">", "/dev/null");
  open(STDERR, ">", "/dev/null");
  exec { $ARGV[0] } @ARGV or die "exec: $!\n";
' "$@"
