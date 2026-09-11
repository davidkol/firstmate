#!/usr/bin/env bash
# Ordinary contributions need no no-mistakes signature; direct CI remains intact.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
assert_absent "$ROOT/.github/workflows/no-mistakes-required.yml" "mandatory signature workflow was restored"
assert_present "$ROOT/.github/workflows/ci.yml" "direct repository CI was removed"
assert_grep 'bin/fm-lint.sh' "$ROOT/.github/workflows/ci.yml" "CI lost direct lint"
assert_grep 'bin/fm-test-run.sh --check-coverage' "$ROOT/.github/workflows/ci.yml" "CI lost test coverage guard"
pass "ordinary PRs need no pipeline signature and retain direct CI checks"
