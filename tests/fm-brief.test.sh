#!/usr/bin/env bash
# Behavior tests for bin/fm-brief.sh.
#
# Regression coverage for the heredoc-in-command-substitution parse bug (issues
# #166, #958, #1069). Building a variable with `VAR=$(cat <<EOF ... EOF)` is
# unsafe on Bash 3.2 (macOS /bin/bash): the lexer scans for the matching `)` of
# the command substitution textually and tracks quote state through the heredoc
# body, so a single apostrophe, unbalanced quote, or unbalanced paren anywhere
# in that body breaks parsing of the *entire rest of the script* - `bash -n`
# fails, not just the generated brief. The DOD and Herdr-section builders now
# use `IFS= read -r -d '' VAR <<EOF || true` instead, which removes the `$(...)`
# wrapper and eliminates the whole defect class regardless of future prose.
# test_no_heredoc_in_command_substitution guards that structure directly.
# Ambient `bash -n` here is Bash 5 and cannot see the bug, so the real
# cross-version enforcement lives in the macos-stock-bash CI job.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-brief)
BRIEF_HOME="$TMP_ROOT/home"
mkdir -p "$BRIEF_HOME/data"

# Pin the harness project store for every scaffold in this suite. The default is
# the developer's real ~/.claude/projects, whose contents change over time, so an
# unpinned test would render a different brief on different machines and on the
# same machine on different days. Tests that need a populated store build one and
# override CLAUDE_CONFIG_DIR per invocation.
export CLAUDE_CONFIG_DIR="$TMP_ROOT/claude-config"
mkdir -p "$CLAUDE_CONFIG_DIR/projects"

# The store directory name for a session location is that location's absolute
# path with every non-alphanumeric character replaced by "-".
mangle_path() {
  printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'
}

store_key_for() {
  local abs
  abs=$(cd "$1" && pwd -P)
  mangle_path "$abs"
}

# A store directory also holds the harness's session transcripts, one JSON record
# per line. Their `cwd` field carries the real absolute path the session ran in,
# before the store key mangled it, which is what proves whose notes a store
# directory holds. The leading record without one mirrors the live format, where
# the field starts appearing a few records in.
seed_store_transcript() {
  local dir=$1 cwd=$2
  mkdir -p "$dir"
  {
    printf '%s\n' '{"type":"mode","mode":"normal","sessionId":"seeded"}'
    printf '{"type":"user","cwd":"%s","sessionId":"seeded"}\n' "$cwd"
  } > "$dir/00000000-0000-4000-8000-000000000000.jsonl"
}

# The script itself must always parse under the ambient bash. That is Bash 5 in
# CI and locally, where the issue #958/#1069 parser bug does not fire, so this
# is a weak guard on its own; test_no_heredoc_in_command_substitution and the
# macos-stock-bash CI job carry the real cross-version enforcement.
test_script_parses() {
  local out rc
  out=$(bash -n "$ROOT/bin/fm-brief.sh" 2>&1); rc=$?
  expect_code 0 "$rc" "bash -n bin/fm-brief.sh must parse cleanly (got: $out)"
  [ -z "$out" ] || fail "bash -n bin/fm-brief.sh emitted unexpected output: $out"
  pass "fm-brief.sh: bash -n succeeds"
}

# Structural class guard (issues #166, #958, #1069): never build a variable by
# wrapping a heredoc in a command substitution (`VAR=$(cat <<EOF ... EOF)`).
# That construct is what breaks Bash 3.2 parsing, and pinning one historical
# apostrophe phrase (as the old test did) missed the #945 reintroduction. This
# guards the *shape* directly against the whole file, so any future DOD or
# section builder that reintroduces the class fails here regardless of prose.
test_no_heredoc_in_command_substitution() {
  local unsafe safe
  unsafe="$TMP_ROOT/heredoc-in-substitution.sh"
  safe="$TMP_ROOT/plain-heredoc.sh"
  # shellcheck disable=SC2016 # Literal shell fixtures must remain unexpanded.
  printf '%s\n' 'value=$(' '  cat <<EOF' 'body' 'EOF' ')' > "$unsafe"
  # shellcheck disable=SC2016 # Literal shell fixtures must remain unexpanded.
  printf '%s\n' 'cat <<EOF' '$(' '  cat <<INNER' 'INNER' ')' 'EOF' > "$safe"
  if no_heredoc_in_command_substitution "$unsafe"; then
    fail "structural guard accepted a multiline heredoc nested in a command substitution"
  fi
  no_heredoc_in_command_substitution "$safe" \
    || fail "structural guard treated heredoc body prose as shell structure"
  no_heredoc_in_command_substitution "$ROOT/bin/fm-brief.sh" \
    || fail "fm-brief.sh wraps a heredoc in a command substitution (breaks Bash 3.2 parsing)"
  pass "fm-brief.sh: no heredoc is nested inside a command substitution (Bash 3.2 parse-safe)"
}

no_heredoc_in_command_substitution() {
  perl - "$1" <<'PERL'
use strict;
use warnings;

my $path = shift;
open my $source, '<', $path or die "$path: $!\n";
my @frames;
my @heredocs;
my $quote = '';
my $line_number = 0;

while (my $line = <$source>) {
  $line_number++;
  if (@heredocs) {
    my $candidate = $line;
    $candidate =~ s/\r?\n\z//;
    $candidate =~ s/^\t+// if $heredocs[0]{strip_tabs};
    shift @heredocs if $candidate eq $heredocs[0]{delimiter};
    next;
  }

  my $length = length $line;
  for (my $i = 0; $i < $length; $i++) {
    my $char = substr($line, $i, 1);
    if ($quote eq "'") {
      $quote = '' if $char eq "'";
      next;
    }
    if ($char eq '\\') {
      $i++;
      next;
    }
    if ($quote eq '"' && $char eq '"') {
      $quote = '';
      next;
    }
    if ($char eq "'" && $quote eq '') {
      $quote = "'";
      next;
    }
    if ($char eq '"' && $quote eq '') {
      $quote = '"';
      next;
    }
    if ($char eq '#' && $quote eq '' && ($i == 0 || substr($line, $i - 1, 1) =~ /[\s;|&()]/)) {
      last;
    }
    if ($char eq '$' && substr($line, $i + 1, 1) eq '(') {
      push @frames, { depth => 1, quote => $quote };
      $quote = '';
      $i++;
      next;
    }
    if (@frames && $quote eq '' && $char eq '(') {
      $frames[-1]{depth}++;
      next;
    }
    if (@frames && $quote eq '' && $char eq ')') {
      $frames[-1]{depth}--;
      if ($frames[-1]{depth} == 0) {
        my $frame = pop @frames;
        $quote = $frame->{quote};
      }
      next;
    }
    next unless $quote eq '' && $char eq '<' && substr($line, $i + 1, 1) eq '<';
    if (@frames) {
      print STDERR "$path:$line_number\n";
      exit 1;
    }

    my $j = $i + 2;
    my $strip_tabs = substr($line, $j, 1) eq '-';
    $j++ if $strip_tabs;
    $j++ while substr($line, $j, 1) =~ /[ \t]/;
    my $delimiter = '';
    my $delimiter_quote = '';
    for (; $j < $length; $j++) {
      my $token = substr($line, $j, 1);
      if ($delimiter_quote) {
        if ($token eq $delimiter_quote) {
          $delimiter_quote = '';
        } elsif ($token eq '\\' && $delimiter_quote eq '"') {
          $j++;
          $delimiter .= substr($line, $j, 1);
        } else {
          $delimiter .= $token;
        }
        next;
      }
      if ($token eq "'" || $token eq '"') {
        $delimiter_quote = $token;
        next;
      }
      if ($token eq '\\') {
        $j++;
        $delimiter .= substr($line, $j, 1);
        next;
      }
      last if $token =~ /[\s;|&()<>]/;
      $delimiter .= $token;
    }
    push @heredocs, { delimiter => $delimiter, strip_tabs => $strip_tabs };
    $i = $j - 1;
  }
}

exit 0;
PERL
}

test_help_includes_entire_header() {
  local help
  help=$("$ROOT/bin/fm-brief.sh" --help)
  assert_contains "$help" "Refuses to overwrite an existing brief." "fm-brief.sh --help omitted its header terminator"
  pass "fm-brief.sh: --help renders the complete header"
}

# Registry with one project per delivery mode, so each ship-mode DOD branch is
# exercised. A project absent from the registry defaults to no-mistakes.
write_registry() {
  local home=$1
  mkdir -p "$home/data"
  cat > "$home/data/projects.md" <<'EOF'
- direct-proj [direct-PR] - fixture for direct-PR mode (added 2026-07-01)
- local-proj [local-only] - fixture for local-only mode (added 2026-07-01)
- main-proj [validated-main] - fixture for validated-main mode (added 2026-07-28)
EOF
}

# fm-brief.sh must exit 0 and produce a brief with no unreplaced shell
# metacharacter corruption for every ship delivery mode. This also guards
# against any *new* unescaped apostrophe or unbalanced quote later added to
# one of these DOD blocks, since a broken heredoc corrupts or empties the
# generated brief content, not just the script's own syntax.
test_ship_modes_generate_clean_briefs() {
  local home id brief status
  home="$TMP_ROOT/ship-home"
  write_registry "$home"

  for id_proj in "brief-nomistakes-a1:no-registry-proj" "brief-directpr-a2:direct-proj" "brief-localonly-a3:local-proj" "brief-validatedmain-a5:main-proj"; do
    id=${id_proj%%:*}
    proj=${id_proj##*:}
    FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" "$proj" >/dev/null 2>&1; status=$?
    expect_code 0 "$status" "fm-brief.sh $id $proj should exit 0"
    brief="$home/data/$id/brief.md"
    assert_present "$brief" "$id: brief was not scaffolded"
    assert_grep "# Definition of done" "$brief" "$id: brief missing Definition of done section"
    assert_grep "{TASK}" "$brief" "$id: brief missing the {TASK} placeholder"
    assert_grep "mid-task \`working:\` line (including setup complete) is nonterminal" "$brief" \
      "$id: brief missing nonterminal working:/setup-complete gate protection"
    assert_no_grep "EOF" "$brief" "$id: brief leaked a heredoc EOF marker (unterminated heredoc)"
  done
  pass "fm-brief.sh: no-mistakes/validated-main/direct-PR/local-only briefs generate cleanly"
}

# validated-main drops the PR but NOT the automated review: the pipeline's review,
# test, document and lint steps are exactly what makes landing straight on main
# safe. A brief that let a worker read "no PR" as "no pipeline" would remove the
# only thing standing between an unread change and the default branch, so pin both
# halves - the review stays, and only the two host-facing steps are skipped.
test_validated_main_brief_keeps_the_review_and_skips_only_pr_and_ci() {
  local home id brief
  home="$TMP_ROOT/validated-main-home"
  write_registry "$home"
  id="brief-validated-main-a6"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" main-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"

  assert_grep "Skipping the PR does NOT skip the review" "$brief" \
    "validated-main brief lost the review-is-retained statement"
  assert_grep "bin/fm-validate.sh $id --intent" "$brief" \
    "validated-main brief lost the mode-derived run command, so the skip set stops being structural"
  assert_no_grep '--skip pr,ci' "$brief" \
    "validated-main brief asks a worker to type the skip flags; they must be derived from the recorded mode instead"
  assert_grep 'never omits review, test, document or lint' "$brief" \
    "validated-main brief lost the statement that the local review surface is always kept"
  assert_grep "no-mistakes doctor" "$brief" \
    "validated-main brief lost the pipeline setup step, so the pipeline may not be initialized"
  assert_grep "done: validated on fm/$id, ready to land" "$brief" \
    "validated-main brief lost its no-PR ready signal"
  assert_no_grep "done: PR" "$brief" \
    "validated-main brief still reports a PR ready signal"
  assert_grep "Firstmate lands the validated branch on \`main\` and pushes it" "$brief" \
    "validated-main brief lost who performs the landing"
  pass "fm-brief.sh: validated-main brief keeps the automated review and skips only the PR and CI steps"
}

# The light path's whole safeguard is one review by an agent that did not write the
# change. Before 2026-07-30 this brief said "Do NOT run /no-mistakes" and nothing
# read the change before the PR opened. Pin the four halves that make the safeguard
# real: the run is started, it is started through the mode-derived command rather
# than typed flags, the worker knows the reviewer is not itself, and the PR waits for
# the review's outcome.
test_direct_pr_brief_runs_one_fresh_context_review_before_the_pr() {
  local home id brief
  home="$TMP_ROOT/direct-pr-review-home"
  write_registry "$home"
  id="brief-direct-review-a7"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" direct-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"

  assert_grep "bin/fm-validate.sh $id --intent" "$brief" \
    "direct-PR brief lost the mode-derived run command, so the light path runs no review at all"
  assert_no_grep '--skip intent,rebase' "$brief" \
    "direct-PR brief asks a worker to type the skip flags; they must be derived from the recorded mode instead"
  assert_grep "did not write your change and does not share your session" "$brief" \
    "direct-PR brief lost the statement that the reviewer is a different context"
  assert_grep "never skips the review step itself" "$brief" \
    "direct-PR brief lost the statement that review is always kept"
  assert_grep "no-mistakes doctor" "$brief" \
    "direct-PR brief lost the pipeline setup step, so the review may have no gate to run through"
  assert_grep "When the run reaches a successful terminal outcome" "$brief" \
    "direct-PR brief lets the worker open the PR before the review finishes"
  assert_grep "terminal but NOT successful" "$brief" \
    "direct-PR brief lets a failed or cancelled review satisfy its push gate"
  assert_no_grep "Do NOT run /no-mistakes" "$brief" \
    "direct-PR brief still forbids the pipeline outright, which would skip the review too"
  assert_grep "done: PR {url}" "$brief" \
    "direct-PR brief lost its PR ready signal"
  pass "fm-brief.sh: direct-PR brief runs one fresh-context review before the PR is opened"
}

# local-only lands on the captain's local default branch with no PR and no remote, so
# before 2026-07-30 nothing read it at all. It now runs the same review-only pass.
# The load-bearing extra half here is that the review must not publish: local-only
# forbids reaching any remote, and the run's skipped push step is what keeps that
# true, so the brief has to say so rather than leave a worker guessing.
test_local_only_brief_runs_a_review_that_publishes_nothing() {
  local home id brief
  home="$TMP_ROOT/local-only-review-home"
  write_registry "$home"
  id="brief-local-review-a7"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" local-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"

  assert_grep "bin/fm-validate.sh $id --intent" "$brief" \
    "local-only brief lost the mode-derived run command, so the light path runs no review at all"
  assert_grep "did not write your change and does not share your session" "$brief" \
    "local-only brief lost the statement that the reviewer is a different context"
  assert_grep "publishes nothing" "$brief" \
    "local-only brief lost the statement that the local gate publishes nothing"
  assert_grep "The publishing step is one of the eight skipped" "$brief" \
    "local-only brief lost why the review cannot reach a remote"
  assert_grep "Never push to any remote and never open a PR" "$brief" \
    "local-only brief lost its no-remote rule"
  assert_grep "When the run reaches a successful terminal outcome" "$brief" \
    "local-only brief declares the branch ready before the review finishes"
  assert_grep "terminal but NOT successful" "$brief" \
    "local-only brief lets a failed or cancelled review declare the branch ready"
  assert_grep "done: ready in branch fm/$id" "$brief" \
    "local-only brief lost its ready signal"
  assert_no_grep "done: PR" "$brief" \
    "local-only brief must never report a PR"
  pass "fm-brief.sh: local-only brief runs a fresh-context review that publishes nothing"
}

test_faster_paths_use_configured_authority_without_stacked_review() {
  local home id brief
  home="$TMP_ROOT/configured-authority-home"
  write_registry "$home"
  id="brief-direct-authority-a4"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" direct-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "The configured merge authority decides whether to merge the PR; firstmate relays the outcome." "$brief" \
    "direct-PR brief lost configured merge authority"
  assert_no_grep "The captain reviews and merges the PR" "$brief" \
    "direct-PR brief hard-coded captain-only authority"
  id="brief-local-authority-a4"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" local-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "The configured merge authority approves the ready branch, then firstmate merges it into local \`main\` through the guarded fast-forward path." "$brief" \
    "local-only brief lost configured merge authority and guarded landing"
  assert_no_grep "The captain approves the ready branch" "$brief" \
    "local-only brief hard-coded captain-only authority"
  assert_no_grep "Firstmate then reviews your branch diff" "$brief" \
    "local-only brief retained a personal review stacked on the selected delivery path"
  pass "fm-brief.sh: faster paths use configured authority without stacked review"
}

# Pin the specific line the bug lived on: the no-mistakes DOD's no-mistakes
# reference must render as plain prose with no dangling apostrophe artifact.
test_no_mistakes_dod_wording() {
  local home id brief
  home="$TMP_ROOT/wording-home"
  mkdir -p "$home/data"
  id="brief-wording-b1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"
  assert_grep "no-mistakes itself provides for the mechanics" "$brief" \
    "no-mistakes DOD lost its guidance-reference sentence"
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks must stay literal
  assert_grep '`no-mistakes axi run --help`' "$brief" \
    "no-mistakes DOD must render literal backticks around the help command"
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks must stay literal
  assert_grep '`help`' "$brief" \
    "no-mistakes DOD must render literal backticks around help"
  # The apostrophe in "firstmate's authority check" is now structurally safe
  # (no `$(...)` wrapper around the heredoc), so it renders verbatim instead of
  # being reworded or escaped away. test_no_heredoc_in_command_substitution
  # guards the structure that makes it safe.
  assert_grep "firstmate's authority check" "$brief" \
    "no-mistakes DOD lost the apostrophe prose that the structural fix makes parse-safe"
  pass "fm-brief.sh: no-mistakes DOD keeps its apostrophe prose, now parse-safe"
}

# The no-mistakes ready signal is the pipeline's CI-ready return point, which a
# PR that registers no checks reaches once the registration grace elapses. The
# brief used to describe a green check result as the only way to get there, so a
# worker on a repository with hosted CI off waited by hand for a signal that
# could not arrive. docs/verification/validation-pipeline.md records the
# pipeline behavior this wording depends on.
test_no_mistakes_dod_no_checks_is_ready() {
  local home id brief emitted
  home="$TMP_ROOT/no-checks-home"
  mkdir -p "$home/data"
  id="brief-no-checks-d1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"
  assert_grep "CI-ready return point" "$brief" \
    "no-mistakes DOD must name the CI-ready return point as the ready signal"
  assert_grep "registered no checks at all" "$brief" \
    "no-mistakes DOD must state that no registered checks satisfies the return point"
  assert_grep "never a reason to wait for a green signal by hand" "$brief" \
    "no-mistakes DOD must forbid waiting by hand for checks that cannot arrive"
  # The literal status token stays "checks green" in both cases:
  # bin/fm-crew-state.sh's log_reports_ci_ready matches it to classify the task
  # as CI-ready, so rewording it here would silently break state reconciliation.
  assert_grep 'done: PR {url} checks green' "$brief" \
    "no-mistakes DOD lost the literal status token fm-crew-state.sh matches"
  # Couple the two files mechanically rather than trusting the comment above.
  # log_reports_ci_ready reads globals and lives in a non-sourceable script, so
  # assert both halves of the contract: the matcher still carries this glob, and
  # the line the brief actually tells a worker to emit still satisfies it.
  grep -qF '*PR*"checks green"*' "$ROOT/bin/fm-crew-state.sh" \
    || fail "fm-crew-state.sh no longer matches the token the brief emits"
  emitted=$(grep -o 'done: PR {url} checks green' "$brief" | head -1)
  emitted=${emitted/\{url\}/https://github.com/o/r/pull/7}
  case "$emitted" in
    *PR*"checks green"*|*"checks green"*PR*) ;;
    *) fail "the brief's own done line does not satisfy log_reports_ci_ready" ;;
  esac
  pass "fm-brief.sh: no-mistakes DOD treats no registered checks as CI-ready"
}

test_ship_project_memory_wording() {
  local home id brief
  home="$TMP_ROOT/project-memory-home"
  mkdir -p "$home/data"
  id="brief-memory-c1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded"
  assert_grep "Record only project knowledge useful to almost every future session." "$brief" \
    "project-memory contract lost the durable-knowledge bar"
  assert_grep "prefer a pointer to the authoritative file, command, or doc over copying the detail" "$brief" \
    "project-memory contract lost pointer-over-copy guidance"
  assert_grep "lacks \`## Maintaining this file\`, add that short self-governance section" "$brief" \
    "project-memory contract lost the self-governance add-in-same-pass rule"
  pass "fm-brief.sh: ship project-memory wording carries the AGENTS.md authoring bar"
}

test_herdr_lab_contract_is_explicit_and_complete() {
  local home id brief
  home="$TMP_ROOT/herdr-lab-home"
  mkdir -p "$home/data"
  id="brief-herdr-lab-d1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" firstmate --herdr-lab >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "Herdr lab brief was not scaffolded"
  assert_grep "# Herdr isolation - HARD SAFETY CONTRACT" "$brief" \
    "Herdr lab brief missing its hard safety contract"
  assert_grep "HERDR_LAB_HELPER='$ROOT/bin/fm-herdr-lab.sh'" "$brief" \
    "Herdr lab brief must bind the absolute Firstmate helper path"
  assert_grep "HERDR_LAB_SESSION=\$(\"\$HERDR_LAB_HELPER\" name $id)" "$brief" \
    "Herdr lab brief missing helper-owned session naming"
  assert_grep "\"\$HERDR_LAB_HELPER\" provision \"\$HERDR_LAB_SESSION\"" "$brief" \
    "Herdr lab brief missing helper-owned provisioning"
  assert_grep "\"\$HERDR_LAB_HELPER\" teardown \"\$HERDR_LAB_SESSION\"" "$brief" \
    "Herdr lab brief missing helper-owned teardown"
  assert_grep "required trailing \`--session \"\$HERDR_LAB_SESSION\"\`" "$brief" \
    "Herdr lab brief missing the per-call trailing session contract"
  assert_grep "direct \`herdr server stop\`" "$brief" \
    "Herdr lab brief missing the forbidden server-global command list"
  assert_grep "records the live default session before provisioning" "$brief" \
    "Herdr lab brief missing the before tripwire"
  assert_grep "verifies the identical fleet state after teardown" "$brief" \
    "Herdr lab brief missing the after tripwire"
  assert_no_grep "Herdr lifecycle declaration - NOT ENABLED" "$brief" \
    "Herdr lab brief retained the unguarded declaration"
  pass "fm-brief.sh: --herdr-lab emits the complete hard safety contract"
}

test_herdr_lab_contract_quotes_foreign_firstmate_path() {
  local home id brief foreign_root helper
  home="$TMP_ROOT/herdr-lab-foreign-home"
  foreign_root="$TMP_ROOT/firstmate helper's root"
  mkdir -p "$home/data"
  id="brief-herdr-lab-foreign-d2"
  helper=$(printf '%s' "$foreign_root/bin/fm-herdr-lab.sh" | sed "s/'/'\\\\''/g")
  helper="'$helper'"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$foreign_root" "$ROOT/bin/fm-brief.sh" "$id" foreign --scout --herdr-lab >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "HERDR_LAB_HELPER=$helper" "$brief" \
    "Herdr lab brief must shell-quote an absolute Firstmate helper path"
  assert_no_grep "bin/fm-herdr-lab.sh name $id" "$brief" \
    "Herdr lab brief must not invoke a worktree-relative helper"
  pass "fm-brief.sh: --herdr-lab uses its quoted Firstmate-owned helper path"
}

test_herdr_lab_omission_is_loud_for_ship_and_scout() {
  local home id brief
  home="$TMP_ROOT/herdr-gate-home"
  mkdir -p "$home/data"
  for kind in ship scout; do
    id="brief-herdr-gate-$kind"
    if [ "$kind" = scout ]; then
      FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" firstmate --scout >/dev/null 2>&1
    else
      FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" firstmate >/dev/null 2>&1
    fi
    brief="$home/data/$id/brief.md"
    assert_grep "# Herdr lifecycle declaration - NOT ENABLED" "$brief" \
      "$kind brief silently omitted the Herdr declaration"
    assert_grep "regenerate the brief with \`--herdr-lab\` before dispatch" "$brief" \
      "$kind brief missing the fail-visible regeneration instruction"
  done
  pass "fm-brief.sh: ship and scout scaffolds make omitted Herdr intent fail-visible"
}

test_secondmate_no_projects_charter() {
  local home brief status
  home="$TMP_ROOT/no-projects-home"
  mkdir -p "$home/data"

  # The deliberate --no-projects signal scaffolds a valid project-less charter for
  # a domain whose subject is the firstmate repo itself (no clones needed).
  FM_HOME="$home" FM_SECONDMATE_CHARTER='firstmate self-development' \
    FM_SECONDMATE_SCOPE='firstmate repo work' \
    "$ROOT/bin/fm-brief.sh" fdev --secondmate --no-projects >/dev/null 2>&1; status=$?
  expect_code 0 "$status" "--no-projects secondmate brief should exit 0"
  brief="$home/data/fdev/brief.md"
  assert_present "$brief" "project-less charter was not scaffolded"
  assert_grep "# Project clones" "$brief" "project-less charter dropped the Project clones heading"
  assert_grep "None. This is a project-less domain" "$brief" \
    "project-less charter did not render a sensible no-clones note"
  assert_grep "its crews take pooled worktrees of that repo" "$brief" \
    "project-less charter operating model lost the pooled-worktree note"
  assert_no_grep "The projects above are local clones" "$brief" \
    "project-less charter kept the with-projects operating-model line"
  assert_grep 'working [key=<work-slug>]' "$brief" \
    "secondmate charter did not key material routed-work phases"
  assert_grep 'resolved [key=<work-slug>]' "$brief" \
    "secondmate charter did not close a quietly ended routed-work phase"
  assert_grep 'use the same key on its later' "$brief" \
    "secondmate charter did not supersede working phases with later states"
  if grep -nE '^-[[:space:]]*$' "$brief" >/dev/null; then
    fail "project-less charter left a stray empty project bullet"
  fi

  # Accidental omission (no projects, no signal) still fails loudly, writing nothing.
  FM_HOME="$home" FM_SECONDMATE_CHARTER='x' "$ROOT/bin/fm-brief.sh" oops --secondmate >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "secondmate brief with no projects and no --no-projects must fail"
  assert_absent "$home/data/oops/brief.md" "loud-failure secondmate brief still wrote a file"

  # --no-projects is mutually exclusive with a project list.
  FM_HOME="$home" FM_SECONDMATE_CHARTER='x' "$ROOT/bin/fm-brief.sh" oops2 --secondmate --no-projects alpha >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "--no-projects combined with a project list must fail"

  # --no-projects applies only to secondmate charters, never a ship/scout brief.
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" oops3 somerepo --no-projects >/dev/null 2>&1; status=$?
  expect_code 1 "$status" "--no-projects on a ship brief must fail"

  pass "fm-brief.sh: --no-projects scaffolds a project-less charter and guards misuse"
}

test_secondmate_marked_request_reporting_contract() {
  local home brief
  home="$TMP_ROOT/marked-request-reporting-home"
  mkdir -p "$home/data"
  FM_HOME="$home" FM_CLASSIFY_PAUSED_VERB=paused \
    FM_SECONDMATE_CHARTER='Handle routed domain work.' \
    "$ROOT/bin/fm-brief.sh" marked-request-reporting --secondmate --no-projects >/dev/null 2>&1
  brief="$home/data/marked-request-reporting/brief.md"

  assert_grep 'A marked request requires one correlated answer after the work' "$brief" \
    "secondmate charter did not require the correlated answer after the work"
  assert_grep 'does not require a separate receipt or start acknowledgement' "$brief" \
    "secondmate charter did not reject a separate receipt/start acknowledgement"
  assert_grep "Never append \`working:\` merely to acknowledge receipt or announce that a marked request has started." "$brief" \
    "secondmate charter did not forbid a generic working acknowledgement"
  assert_no_grep "Give every routed-work phase a stable key: open it with \`working" "$brief" \
    "secondmate charter retained the unconditional working opener"
  assert_grep 'When a routed-work phase has a supervisor-actionable material change worth reporting under the rule above' "$brief" \
    "secondmate charter did not limit keyed phases to reportable material changes"
  assert_grep "If its first reportable event is \`working [key=<work-slug>]: {material phase}\`" "$brief" \
    "secondmate charter lost keyed working syntax for a reportable material phase"
  assert_grep "use the same key on its later \`paused\`, \`done\`, \`failed\`, \`needs-decision\`, or \`blocked\` event" "$brief" \
    "secondmate charter lost same-key closure for a reportable material phase"
  assert_grep 'resolved [key=<work-slug>]' "$brief" \
    "secondmate charter lost resolved closure for a keyed material phase"

  assert_grep 'include that exact token in your parent status reply' "$brief" \
    "secondmate charter lost correlated parent results"
  assert_grep 'For a terse result, a status line is the whole answer.' "$brief" \
    "secondmate charter lost terse result reporting"
  assert_grep 'append a status line that points to that doc' "$brief" \
    "secondmate charter lost detailed document pointers"
  assert_grep 'Report only true captain-relevant outcomes or a declared external wait' "$brief" \
    "secondmate charter lost declared external waits"
  assert_grep 'a captain decision, a real blocker, a failure, or work ready for review' "$brief" \
    "secondmate charter lost decisions, blockers, failures, or ready outcomes"
  assert_grep 'States: working, needs-decision, blocked, paused, done, failed.' "$brief" \
    "secondmate charter changed the preserved status vocabulary"
  pass "fm-brief.sh: marked requests avoid generic acknowledgements and preserve material reporting"
}

test_herdr_lab_contract_applies_to_scouts_but_not_secondmates() {
  local home brief status=0
  home="$TMP_ROOT/herdr-kind-home"
  mkdir -p "$home/data"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" herdr-scout firstmate --scout --herdr-lab >/dev/null 2>&1
  brief="$home/data/herdr-scout/brief.md"
  assert_grep "# Herdr isolation - HARD SAFETY CONTRACT" "$brief" \
    "scout --herdr-lab brief missing the contract"

  FM_HOME="$home" FM_SECONDMATE_CHARTER=ops "$ROOT/bin/fm-brief.sh" herdr-secondmate --secondmate firstmate --herdr-lab >/dev/null 2>&1 || status=$?
  expect_code 1 "$status" "secondmate --herdr-lab must be rejected"
  assert_absent "$home/data/herdr-secondmate/brief.md" \
    "rejected secondmate --herdr-lab still wrote a brief"
  pass "fm-brief.sh: Herdr lab contract covers scouts and rejects secondmate misuse"
}

test_pause_verb_override_renders_all_brief_scaffolds() {
  local home kind id brief
  home="$TMP_ROOT/pause-verb-home"
  mkdir -p "$home/data"

  for kind in ship scout secondmate; do
    id="brief-pause-verb-$kind"
    case "$kind" in
      ship)
        FM_HOME="$home" FM_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/fm-brief.sh" "$id" firstmate >/dev/null 2>&1
        ;;
      scout)
        FM_HOME="$home" FM_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/fm-brief.sh" "$id" firstmate --scout >/dev/null 2>&1
        ;;
      secondmate)
        FM_HOME="$home" FM_CLASSIFY_PAUSED_VERB=awaiting \
          "$ROOT/bin/fm-brief.sh" "$id" --secondmate --no-projects >/dev/null 2>&1
        ;;
    esac
    brief="$home/data/$id/brief.md"
    assert_grep "States: working, needs-decision, blocked, awaiting, done, failed." "$brief" \
      "$kind brief did not render the configured pause verb in its states list"
    # shellcheck disable=SC2016 # Literal backticks and braces must remain unexpanded.
    assert_grep 'Use `awaiting: {why}`' "$brief" \
      "$kind brief did not instruct the configured pause status"
    # shellcheck disable=SC2016 # Literal backticks and braces must remain unexpanded.
    assert_no_grep '`paused: {why}`' "$brief" \
      "$kind brief still instructs the default paused status"
    assert_grep 'or a blocker clears' "$brief" \
      "$kind brief did not require durable resolution when a blocker clears"
  done
  pass "fm-brief.sh: custom pause verb renders in every scaffold"
}

test_scout_and_secondmate_load_decision_hold_policy() {
  local home scout charter
  home="$TMP_ROOT/decision-policy-home"
  mkdir -p "$home/data"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-brief.sh" sample-investigation sample --scout >/dev/null 2>&1
  scout="$home/data/sample-investigation/brief.md"
  assert_grep "$ROOT/.agents/skills/decision-hold-lifecycle/SKILL.md" "$scout" \
    "scout brief did not load the unresolved-decision policy before done"
  assert_grep "pass its shared completion gate for the report and any visual review" "$scout" \
    "scout brief did not cross-reference visual-review completion"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_SECONDMATE_CHARTER='sample reviews' \
    "$ROOT/bin/fm-brief.sh" sample-mate --secondmate --no-projects >/dev/null 2>&1
  charter="$home/data/sample-mate/brief.md"
  assert_grep "load \`decision-hold-lifecycle\`" "$charter" \
    "secondmate charter did not load the shared decision policy for detailed investigations"
  pass "fm-brief.sh: investigation and visual-review completions load the shared decision policy"
}

# The completion checklist has to arrive inside the brief, because that is the
# text every worker demonstrably reads; the same rules in a separate document
# were contradicted by most of the work that was audited.
test_ship_checklist_is_in_the_brief() {
  local home id brief
  home="$TMP_ROOT/checklist-home"
  mkdir -p "$home/data"
  id="brief-checklist-e1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "Answer every item below explicitly before the final \`done:\` line the delivery path below names for this task" "$brief" \
    "ship checklist is not bound to the terminal done gate"
  assert_grep "never before an earlier progress append" "$brief" \
    "ship checklist can still be read against the first done append"
  assert_grep "an item you cannot satisfy is named as a gap, never skipped in silence" "$brief" \
    "ship checklist lost the no-silent-skip rule"
  # All seven items, in the brief itself.
  assert_grep "The check command passes" "$brief" "checklist missing the check item"
  assert_grep "One edit named that would make a new test go red - made, confirmed red, reverted." "$brief" \
    "checklist missing the break-it-on-purpose item"
  assert_grep "A different context reviewed the diff than the one that wrote it." "$brief" \
    "checklist missing the second-context review item"
  assert_grep "No new question left unasked." "$brief" "checklist missing the open-question item"
  assert_grep "Any owner decision quoted verbatim, with its date." "$brief" \
    "checklist missing the verbatim-decision item"
  assert_grep "Any lesson learned the hard way that clears the Project memory bar above is a dated note in that project \`AGENTS.md\`." "$brief" \
    "checklist missing the dated-note item anchored to its destination"
  assert_grep "A task that produced no such lesson satisfies this with nothing written." "$brief" \
    "the dated-note item cannot be satisfied by a task that produced no durable lesson"
  [ "$(grep -cF 'Record only project knowledge useful to almost every future session' "$brief")" = 1 ] \
    || fail "the checklist restated the Project memory bar instead of pointing at its one owner"
  assert_grep "Nothing added to a document that no execution touches." "$brief" \
    "checklist missing the no-inert-document item"
  [ "$(grep -c '^- \[ \] ' "$brief")" = 7 ] || fail "ship checklist is no longer seven items"
  pass "fm-brief.sh: the ship brief carries all seven completion items"
}

# An item a worker cannot satisfy where it stops is worse than no item: it forces
# a gap on every task and drains the meaning out of naming one. Both of these
# named a destination the crewmate never reaches - the default branch it is
# forbidden to touch, and a handoff artifact the brief never defines - so they
# are gone and must not creep back.
test_ship_checklist_omits_unsatisfiable_items() {
  local home id brief
  home="$TMP_ROOT/checklist-omissions-home"
  mkdir -p "$home/data"
  cat > "$home/data/projects.md" <<'EOF'
- direct-proj [direct-PR] - fixture for direct-PR mode (added 2026-07-01)
- local-proj [local-only] - fixture for local-only mode (added 2026-07-01)
EOF
  for id_proj in "brief-omit-nomistakes:no-registry-proj" "brief-omit-directpr:direct-proj" "brief-omit-localonly:local-proj"; do
    id=${id_proj%%:*}
    FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" "${id_proj##*:}" >/dev/null 2>&1
    brief="$home/data/$id/brief.md"
    assert_no_grep "Handoff updated." "$brief" "$id: the undefined handoff item returned"
    assert_no_grep "- [ ] Landed" "$brief" "$id: the landed item returned"
    assert_no_grep "is not landed, remote or no remote" "$brief" \
      "$id: the landed item returned in its no-remote phrasing"
    assert_no_grep "reaches the default branch" "$brief" \
      "$id: the checklist again demands a branch rule 1 forbids the worker to touch"
  done
  pass "fm-brief.sh: the ship checklist omits the items no crewmate can satisfy"
}

# The check item is wrong as literally written and must stay corrected: most
# projects have no `script/check`, and a project with no verification at all can
# only satisfy it by saying so. A silent pass is the failure mode.
test_checklist_check_item_is_satisfiable() {
  local home id brief
  home="$TMP_ROOT/checklist-fixes-home"
  mkdir -p "$home/data"
  cat > "$home/data/projects.md" <<'EOF'
- local-proj [local-only] - fixture for a repo with no remote (added 2026-07-01)
EOF
  id="brief-checklist-fixes-e2"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" local-proj >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  # shellcheck disable=SC2016  # literal backticks must survive into the brief
  assert_grep 'otherwise the command `AGENTS.md` names' "$brief" \
    "check item lost its fallback to the command the project actually names"
  assert_grep "If this project has no verification at all, name that gap in your done line" "$brief" \
    "check item can be satisfied without naming a missing-verification gap"
  assert_grep "a silent pass here is the failure this list exists to catch" "$brief" \
    "check item lost the silent-pass warning"
  pass "fm-brief.sh: the check item works in a project with no script/check"
}

# The working tree outranks every document: a session that reads a status doc
# instead of `git status` rebuilds work that already exists.
test_orientation_step_precedes_the_work() {
  local home brief kind id
  home="$TMP_ROOT/orient-home"
  mkdir -p "$home/data"
  for kind in ship scout; do
    id="brief-orient-$kind"
    if [ "$kind" = scout ]; then
      FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj --scout >/dev/null 2>&1
    else
      FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj >/dev/null 2>&1
    fi
    brief="$home/data/$id/brief.md"
    # shellcheck disable=SC2016  # literal backticks must survive into the brief
    assert_grep 'Run `git status` and `git log --oneline -15`' "$brief" \
      "$kind brief lost the read-the-repository-first step"
    assert_grep "before you trust any plan, status doc, or handoff" "$brief" \
      "$kind brief lost the document-comes-second ordering"
    assert_grep "The repository state outranks every document, always" "$brief" \
      "$kind brief lost the working-tree-wins rule"
  done
  # The isolation assertion is a safety contract and still comes first.
  brief="$home/data/brief-orient-ship/brief.md"
  if [ "$(grep -n 'Verify isolation before anything else' "$brief" | cut -d: -f1)" -gt \
       "$(grep -n 'Run .git status' "$brief" | cut -d: -f1)" ]; then
    fail "the orientation step displaced the worktree-isolation assertion"
  fi
  pass "fm-brief.sh: ship and scout briefs orient on the repository before any document"
}

# Curated notes are stored per session location, under a directory named by
# mangling that location's absolute path (every non-alphanumeric becomes "-").
# A crewmate worktree has a different absolute path, so it loads none of them
# unless the brief names them. Both locations this scaffold can derive exactly -
# the firstmate clone, and the clone's origin when that origin is a local path -
# are named.
test_project_memory_paths_are_named_when_they_exist() {
  local home store captain clone brief id
  home="$TMP_ROOT/memory-home"
  store="$TMP_ROOT/memory-store"
  captain="$TMP_ROOT/memory-captain/Widget"
  clone="$home/projects/Widget"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$captain"
  git clone --quiet "$captain" "$clone"
  mkdir -p "$store/projects/$(store_key_for "$captain")/memory"
  mkdir -p "$store/projects/$(store_key_for "$clone")/memory"
  mkdir -p "$store/projects/-Users-someone-projects-Godot-OtherThing/memory"

  id="brief-memory-f1"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "Curated notes for this project already exist" "$brief" \
    "brief did not name the existing curated notes"
  assert_grep "nothing loads them for you because this copy sits at a different path" "$brief" \
    "brief did not explain why the notes are invisible to this copy"
  assert_grep "$store/projects/$(store_key_for "$captain")/memory" "$brief" \
    "brief missed the notes under the captain checkout the clone points at"
  assert_grep "$store/projects/$(store_key_for "$clone")/memory" "$brief" \
    "brief missed the notes under the firstmate clone"
  assert_no_grep "OtherThing" "$brief" "brief offered another project's notes"

  # Scouts read repositories too, so they get the same pointer.
  id="brief-memory-f2"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget --scout >/dev/null 2>&1
  assert_grep "$store/projects/$(store_key_for "$captain")/memory" "$home/data/$id/brief.md" \
    "scout brief did not name the existing curated notes"
  pass "fm-brief.sh: existing curated project notes are named for ship and scout briefs"
}

# The store key is a lossy mangling: "/", " ", "." and "_" all become "-", so a
# store name cannot be split back into path components and a project-name suffix
# match cannot tell a separator from a literal dash. Matching "Dungeon" that way
# hands a crewmate the notes of "/captain/projects/Godot/Gacha Dungeon".
# The suffix match does select that directory, so the rejection has to come from
# the working directory its transcripts recorded: basename "Gacha Dungeon" is not
# "Dungeon".
# Handing over the wrong project's owner-level context is the failure that must
# never happen; finding nothing is the acceptable outcome.
test_project_memory_never_resolves_to_another_project() {
  local home store clone brief id
  home="$TMP_ROOT/memory-collision-home"
  store="$TMP_ROOT/memory-collision-store"
  clone="$home/projects/Dungeon"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$clone"
  mkdir -p "$store/projects/-captain-projects-Godot-Gacha-Dungeon/memory"
  seed_store_transcript "$store/projects/-captain-projects-Godot-Gacha-Dungeon" \
    "/captain/projects/Godot/Gacha Dungeon"

  id="brief-memory-collision-i1"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Dungeon >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Gacha-Dungeon" "$brief" \
    "brief handed over another project's notes through a trailing-word match"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief announced curated notes it could not prove belong to this project"

  # A clone whose origin is a local path is only followed when that path is a
  # real directory named exactly for the project; anything else is unproven.
  home="$TMP_ROOT/memory-foreign-origin-home"
  store="$TMP_ROOT/memory-foreign-origin-store"
  clone="$home/projects/Widget"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$TMP_ROOT/memory-foreign-origin/Widgets"
  git clone --quiet "$TMP_ROOT/memory-foreign-origin/Widgets" "$clone"
  mkdir -p "$store/projects/$(store_key_for "$TMP_ROOT/memory-foreign-origin/Widgets")/memory"

  id="brief-memory-collision-i2"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief followed an origin whose directory is not named for this project"
  pass "fm-brief.sh: notes that cannot be proven to belong to this project are dropped"
}

# `git -C <dir>` answers from the nearest ancestor repository when <dir> is not
# itself one, and a home's `projects/` lives inside the firstmate repo. So a
# project directory left as a plain directory - a seed that failed after
# `mkdir -p`, or anything that never became a clone - would otherwise hand back
# firstmate's OWN origin and offer that home's notes as the project's.
test_project_memory_ignores_an_ancestor_repository_origin() {
  local home store captain brief id
  home="$TMP_ROOT/memory-ancestor-home"
  store="$TMP_ROOT/memory-ancestor-store"
  captain="$TMP_ROOT/memory-ancestor-origin/Widget"
  mkdir -p "$home/data" "$home/projects/Widget" "$captain"
  fm_git_init_commit "$home"
  git -C "$home" remote add origin "$captain"
  mkdir -p "$store/projects/$(store_key_for "$captain")/memory"

  id="brief-memory-ancestor-j1"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief read an ancestor repository's origin as if it were the project clone"
  assert_no_grep "$store/projects" "$brief" \
    "brief offered notes derived from the surrounding home rather than the project"
  pass "fm-brief.sh: a project directory that is not a clone contributes nothing"
}

# Most clones know their origin only as a remote URL, so nothing about the owner's
# own checkout is derivable from them and deriving alone reaches almost no notes.
# The store directory itself supplies the missing proof: its transcripts record
# the working directory the owner's sessions ran in, and that path never went
# through the mangling, so its basename is compared to the project name exactly.
test_project_memory_confirms_a_candidate_by_its_recorded_cwd() {
  local home store clone owner brief id
  home="$TMP_ROOT/memory-cwd-home"
  store="$TMP_ROOT/memory-cwd-store"
  clone="$home/projects/Widget"
  # The owner's checkout is not on this machine at all - only the store knows it.
  owner="/captain/projects/Godot/Widget"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$clone"
  git -C "$clone" remote add origin "https://github.com/someone/Widget.git"
  mkdir -p "$store/projects/$(mangle_path "$owner")/memory"
  seed_store_transcript "$store/projects/$(mangle_path "$owner")" "$owner"

  id="brief-memory-cwd-k1"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "Curated notes for this project already exist" "$brief" \
    "brief missed notes whose only proof is the working directory its sessions recorded"
  assert_grep "$store/projects/$(mangle_path "$owner")/memory" "$brief" \
    "brief did not name the confirmed notes directory"
  pass "fm-brief.sh: a candidate is confirmed by the working directory its sessions recorded"
}

# The transcript layout belongs to the harness, not to this repo, so it can change
# shape or vanish. Every way of failing to read a working directory back has to
# end in silence: falling back to the unconfirmed suffix match is exactly how a
# crewmate would be handed another project's notes.
test_project_memory_drops_a_candidate_with_no_recorded_cwd() {
  local home store clone owner brief id
  home="$TMP_ROOT/memory-nocwd-home"
  store="$TMP_ROOT/memory-nocwd-store"
  clone="$home/projects/Widget"
  owner="/captain/projects/Godot/Widget"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$clone"
  git -C "$clone" remote add origin "https://github.com/someone/Widget.git"
  # Notes that suffix-match the project, with no transcript to confirm them.
  mkdir -p "$store/projects/$(mangle_path "$owner")/memory"

  id="brief-memory-nocwd-k2"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief offered notes it could not confirm, with no transcript present"
  assert_no_grep "$store/projects" "$brief" \
    "brief fell back to an unconfirmed suffix match"

  # A transcript the layout has moved past - no working directory in it - is the
  # same silence.
  printf '%s\n' '{"type":"mode","mode":"normal"}' \
    > "$store/projects/$(mangle_path "$owner")/11111111-1111-4111-8111-111111111111.jsonl"
  id="brief-memory-nocwd-k3"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Widget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief offered notes whose transcript records no working directory"
  assert_no_grep "$store/projects" "$brief" \
    "brief guessed at a candidate an unreadable transcript left unproven"
  pass "fm-brief.sh: a candidate whose working directory cannot be read back is dropped"
}

# Pointing a worker at a directory that does not exist is worse than saying
# nothing, so an absent store or an absent match emits no section at all.
test_project_memory_says_nothing_when_absent() {
  local home store clone brief id
  home="$TMP_ROOT/memory-absent-home"
  store="$TMP_ROOT/memory-absent-store"
  clone="$home/projects/Gadget"
  mkdir -p "$home/data" "$home/projects"
  fm_git_init_commit "$clone"
  mkdir -p "$store/projects/-Users-someone-projects-Godot-Widget/memory"

  id="brief-memory-absent-g1"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Gadget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief announced curated notes for a project that has none"
  assert_no_grep "$store/projects" "$brief" "brief leaked an unrelated notes path"

  # A session location the store knows but that holds no notes is never offered.
  mkdir -p "$store/projects/$(store_key_for "$clone")"
  id="brief-memory-absent-g2"
  CLAUDE_CONFIG_DIR="$store" FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" Gadget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief offered a session location that holds no notes"

  # No store at all is the same silence, and must not break scaffolding.
  id="brief-memory-absent-g3"
  CLAUDE_CONFIG_DIR="$TMP_ROOT/no-such-store" FM_HOME="$home" \
    "$ROOT/bin/fm-brief.sh" "$id" Gadget >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_present "$brief" "brief was not scaffolded when the notes store is absent"
  assert_no_grep "Curated notes for this project" "$brief" \
    "brief announced curated notes with no store present"
  pass "fm-brief.sh: a missing notes directory produces no pointer at all"
}

# A scout produces a report, not a change, so it carries only the items that can
# apply and none of the ship-only ones.
test_scout_checklist_is_reduced() {
  local home brief id
  home="$TMP_ROOT/scout-checklist-home"
  mkdir -p "$home/data"
  id="brief-scout-checklist-h1"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" some-proj --scout >/dev/null 2>&1
  brief="$home/data/$id/brief.md"
  assert_grep "Answer each item below explicitly before you report done" "$brief" \
    "scout checklist lost its framing"
  assert_grep "a previous session summarising the owner is not evidence that the owner said it" "$brief" \
    "scout checklist lost the owner-quote evidence rule"
  assert_grep "with what would have caught it earlier" "$brief" \
    "scout checklist lost the what-would-have-caught-this note"
  assert_grep "Nothing recommended that no execution would touch." "$brief" \
    "scout checklist lost the no-inert-recommendation item"
  assert_no_grep "The check command passes" "$brief" \
    "scout brief carried the ship-only check item"
  assert_no_grep "One edit named that would make a new test go red" "$brief" \
    "scout brief carried the ship-only red-test item"
  assert_no_grep "A different context reviewed the diff" "$brief" \
    "scout brief carried the ship-only second-context item"
  [ "$(grep -c '^- \[ \] ' "$brief")" = 3 ] || fail "scout checklist is no longer three items"
  pass "fm-brief.sh: the scout brief carries a reduced checklist without ship-only items"
}

# Scout and secondmate paths still scaffold well-formed briefs.
test_scout_and_secondmate_scaffold() {
  local brief
  FM_HOME="$BRIEF_HOME" "$ROOT/bin/fm-brief.sh" brief-scout-q6 alpha --scout >/dev/null 2>&1 \
    || fail "fm-brief.sh scout scaffold exited non-zero"
  brief="$BRIEF_HOME/data/brief-scout-q6/brief.md"
  assert_present "$brief" "scout brief was not scaffolded"
  assert_grep "SCOUT task" "$brief" "scout brief must declare itself a scout task"
  assert_grep "report.md" "$brief" "scout brief must point at the report deliverable"

  FM_SECONDMATE_CHARTER='Supervise the alpha domain.' \
    FM_HOME="$BRIEF_HOME" "$ROOT/bin/fm-brief.sh" brief-sm-q6 --secondmate alpha >/dev/null 2>&1 \
    || fail "fm-brief.sh secondmate scaffold exited non-zero"
  brief="$BRIEF_HOME/data/brief-sm-q6/brief.md"
  assert_present "$brief" "secondmate charter was not scaffolded"
  assert_grep "persistent second mate" "$brief" \
    "secondmate charter must declare its role"
  pass "fm-brief: scout and secondmate code paths still scaffold well-formed briefs"
}

test_script_parses
test_no_heredoc_in_command_substitution
test_help_includes_entire_header
test_ship_modes_generate_clean_briefs
test_validated_main_brief_keeps_the_review_and_skips_only_pr_and_ci
test_direct_pr_brief_runs_one_fresh_context_review_before_the_pr
test_local_only_brief_runs_a_review_that_publishes_nothing
test_faster_paths_use_configured_authority_without_stacked_review
test_no_mistakes_dod_wording
test_no_mistakes_dod_no_checks_is_ready
test_ship_project_memory_wording
test_herdr_lab_contract_is_explicit_and_complete
test_herdr_lab_contract_quotes_foreign_firstmate_path
test_herdr_lab_omission_is_loud_for_ship_and_scout
test_herdr_lab_contract_applies_to_scouts_but_not_secondmates
test_secondmate_no_projects_charter
test_secondmate_marked_request_reporting_contract
test_pause_verb_override_renders_all_brief_scaffolds
test_scout_and_secondmate_load_decision_hold_policy
test_ship_checklist_is_in_the_brief
test_ship_checklist_omits_unsatisfiable_items
test_checklist_check_item_is_satisfiable
test_orientation_step_precedes_the_work
test_project_memory_paths_are_named_when_they_exist
test_project_memory_never_resolves_to_another_project
test_project_memory_ignores_an_ancestor_repository_origin
test_project_memory_confirms_a_candidate_by_its_recorded_cwd
test_project_memory_drops_a_candidate_with_no_recorded_cwd
test_project_memory_says_nothing_when_absent
test_scout_checklist_is_reduced
test_scout_and_secondmate_scaffold
