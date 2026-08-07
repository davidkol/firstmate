#!/usr/bin/env bash
# Scaffold a crewmate brief or persistent secondmate charter at
# data/<task-id>/brief.md under the active firstmate home.
# For ordinary tasks, the standard Setup/Rules/Definition-of-done contract is
# filled in. Firstmate then replaces the {TASK} placeholder with the task
# description, acceptance criteria, and context, and may adjust other sections
# when the task genuinely deviates (e.g. working an existing external PR instead
# of shipping a new one).
# Ship and scout scaffolds also split the brief's provenance into two sections
# firstmate fills in before dispatch. "What the captain decided" takes
# {CAPTAIN_RULINGS}: one bullet per ruling carrying his own words and the date
# he said them, or the single bullet "- None recorded for this task." when he
# ruled on nothing. "What firstmate worked out" takes {FIRSTMATE_INFERENCE}:
# firstmate's own reasoning about how to satisfy those rulings, which carries
# none of his authority, is open to challenge, and may never be armoured as
# "measured", "do not re-derive", "decided", "settled", or "confirmed". Both
# sections are emitted on every ship and scout brief, including when there is
# nothing to put in them. bin/fm-authority-receipts.sh judges the filled-in
# result and bin/fm-spawn.sh runs it before launch. A secondmate charter is
# standing scope rather than a task built from rulings, so it carries neither
# section.
# Usage: fm-brief.sh <task-id> <repo-name> [--scout] [--herdr-lab]
#        fm-brief.sh <task-id> --secondmate {<project>...|--no-projects}
#   --scout writes the scout contract instead: the deliverable is a report at
#   data/<task-id>/report.md (no branch, no push, no PR) and the worktree is scratch.
#   --secondmate writes a persistent secondmate charter. The project list
#   is cloned into the secondmate home, while the natural-language scope
#   tells the main firstmate when to route work there; routine churn stays in its own home;
#   captain-relevant escalations and marked from-firstmate replies append to this
#   home's status file.
#   --no-projects writes a project-less charter for a domain whose subject is the
#   firstmate repo itself (its home is a firstmate worktree, its crews take pooled
#   worktrees of the same repo). It is mutually exclusive with a project list, and
#   omitting both still fails loudly so an accidental omission is never silent.
#   Set FM_SECONDMATE_CHARTER='<charter>' to fill the charter text.
#   Set FM_SECONDMATE_SCOPE='<scope>' to write a routing scope distinct from the charter text.
#   --herdr-lab is mandatory when the task will issue Herdr lifecycle commands.
#   It adds the hard isolation contract backed by bin/fm-herdr-lab.sh.
#   The flag must be explicit because {TASK} is filled after scaffolding and the
#   caller-supplied repo string cannot reliably identify this repo. Briefs made
#   without it carry a loud declaration so an omitted contract cannot be silent.
# For ship tasks, the delivery path inside the definition of done is shaped by the
# project's delivery mode (data/projects.md via fm-project-mode.sh; see the
# project-management skill and AGENTS.md task lifecycle):
#   no-mistakes    implement -> /no-mistakes pipeline -> PR -> captain merge (default)
#   validated-main implement -> same pipeline with its PR and CI steps skipped ->
#                  firstmate merges to main and pushes; no PR is ever opened
#   direct-PR      implement -> review-only pipeline run (the fresh-context reviewer,
#                  with the other eight steps skipped) -> push + open PR via gh-axi
#                  -> captain merge
#   local-only     implement on branch -> review-only pipeline run (publishes nothing)
#                  -> stop and report "ready in branch" (no push/PR); captain
#                  approves, firstmate merges to local main
# Ship briefs begin with a worktree-isolation assertion before the branch step.
# Scout tasks ignore mode - their deliverable is a report, not a merge.
# Every scaffold's status protocol distinguishes the configured
# declared-external-wait verb (FM_CLASSIFY_PAUSED_VERB, default "paused") from
# "blocked:": pause for a known external wait expected to clear on its own,
# blocked when firstmate must act.
# Ship tasks include a project-memory section so durable project-intrinsic
# learnings can be committed to AGENTS.md through the project's delivery path;
# it carries the AGENTS.md authoring bar (widely useful knowledge only, pointers
# over copied detail) and has the crewmate add the fm-ensure-agents-md.sh
# self-governance section when a touched project AGENTS.md lacks it.
# Ship and scout scaffolds both carry an orientation step in their setup section
# and a completion checklist inside their definition of done, because a rule
# holds where the worker is already reading and fails in a document nobody
# reopens.
# The orientation step has the crewmate read `git status` and recent commits
# before trusting any plan, status doc, or handoff.
# The scout checklist is deliberately the shorter one: a scout delivers a report
# rather than a change, so the items that attach to a diff have nothing to attach
# to.
# Both also name any existing curated-notes directory for the project under the
# harness project store (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects), which is
# keyed by the absolute path of the directory a session ran in, so a disposable
# worktree never loads them on its own.
# A store directory is offered only once it is proven to belong to this project,
# either because the location is one this scaffold derives exactly (firstmate's
# clone, or that clone's origin when the origin is a local filesystem path) or
# because the directory's own session transcripts record a working directory
# whose basename is exactly the project name.
# Transcript layout is an external format that can change or vanish without
# notice, so a candidate whose recorded working directory cannot be read is
# dropped silently rather than guessed at.
# Refuses to overwrite an existing brief.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# shellcheck source=bin/fm-marker-lib.sh
. "$SCRIPT_DIR/fm-marker-lib.sh"
# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
PAUSED_VERB=${FM_CLASSIFY_PAUSED_VERB:-$FM_CLASSIFY_PAUSED_VERB_DEFAULT}
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
PROJECTS="${FM_PROJECTS_OVERRIDE:-$FM_HOME/projects}"
KIND=ship
HERDR_LAB=0
NO_PROJECTS=0
POS=()
for a in "$@"; do
  case "$a" in
    --scout) KIND=scout ;;
    --secondmate) KIND=secondmate ;;
    --herdr-lab) HERDR_LAB=1 ;;
    --no-projects) NO_PROJECTS=1 ;;
    *) POS+=("$a") ;;
  esac
done
ID=${POS[0]}

if [ "$KIND" = secondmate ] && [ "$HERDR_LAB" -eq 1 ]; then
  echo "error: --herdr-lab applies only to crewmate ship or scout briefs" >&2
  exit 1
fi

if [ "$NO_PROJECTS" -eq 1 ] && [ "$KIND" != secondmate ]; then
  echo "error: --no-projects applies only to --secondmate charters" >&2
  exit 1
fi

BRIEF="$DATA/$ID/brief.md"
[ -e "$BRIEF" ] && { echo "error: $BRIEF already exists" >&2; exit 1; }
mkdir -p "$DATA/$ID"

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

STATUS_FILE=$(shell_quote "$STATE/$ID.status")

if [ "$KIND" = secondmate ]; then
SECONDMATE_PROJECTS=""
idx=1
while [ "$idx" -lt "${#POS[@]}" ]; do
  SECONDMATE_PROJECTS="${SECONDMATE_PROJECTS}${SECONDMATE_PROJECTS:+ }${POS[$idx]}"
  idx=$((idx + 1))
done
if [ "$NO_PROJECTS" -eq 1 ]; then
  [ -z "$SECONDMATE_PROJECTS" ] || { echo "error: --no-projects cannot be combined with a project list" >&2; exit 1; }
else
  [ -n "$SECONDMATE_PROJECTS" ] || { echo "error: --secondmate requires at least one project, or --no-projects for a project-less home" >&2; exit 1; }
fi
SECONDMATE_CHARTER=${FM_SECONDMATE_CHARTER:-"{TASK}"}
SECONDMATE_SCOPE=${FM_SECONDMATE_SCOPE:-${FM_SECONDMATE_CHARTER:-"{TASK}"}}
if [ "$NO_PROJECTS" -eq 1 ]; then
  PROJECT_CLONES_BODY="None. This is a project-less domain: its subject is the firstmate repo this home lives in, so it needs no separate clones under \`projects/\`; its crews take pooled worktrees of that firstmate repo."
  PROJECT_CLONES_NOTE="This domain has no separate project clones: its subject is the firstmate repo this home lives in, and its crews take pooled worktrees of that repo."
else
  PROJECT_CLONES_BODY=$(printf '%s\n' "$SECONDMATE_PROJECTS" | tr ' ' '\n' | sed 's/^/- /')
  PROJECT_CLONES_NOTE="The projects above are local clones for work you supervise; they are not an exclusive ownership claim."
fi
cat > "$BRIEF" <<EOF
You are a persistent second mate managed by the main firstmate. Work on your own; do not wait for a human.

# Charter
$SECONDMATE_CHARTER

# Routing scope
$SECONDMATE_SCOPE

# Project clones
$PROJECT_CLONES_BODY

# Operating model
You are in an isolated firstmate home. The local \`AGENTS.md\` is your job description, and your local \`data/\`, \`state/\`, \`config/\`, and \`projects/\` dirs are yours to operate.
$PROJECT_CLONES_NOTE
Delegate project work to your own crewmates with the normal firstmate lifecycle: brief, spawn, status, watcher, steer, teardown, and recovery.
Do not invent a second delegation system.
You do not generate your own work.
Act only on tasks the main firstmate routes to you.
Never start a survey, audit, or "find improvements" sweep on your own initiative; that is not your job and it is unwanted.

# Requests from the main firstmate
You are a firstmate in your own home, so an incoming message reaches you in your own chat.
You must distinguish who it is from, because the answer goes to a different place.
A request relayed to you by the main firstmate is tagged with a leading \`$FM_FROMFIRST_LABEL\` marker followed by an invisible system separator; this marker is untypable, so a human never produces it.
When a message carries that marker, do the work, then respond via the STATUS/ESCALATION path below, never only in this chat: the main firstmate does not read your chat, so a chat-only reply is lost.
Marked requests also carry a privacy-safe \`corr=<id>\` token after the marker; include that exact token in your parent status reply (or in the status pointer to a detailed doc) so the parent can correlate the answer.
Optional helper: \`bin/fm-secondmate-report.sh\` can append a correlated status line for you, but a plain \`echo\` that includes the same \`corr=<id>\` is equally valid - do not depend on the helper being present.
For a terse result, a status line is the whole answer.
For a detailed answer (an investigation, a plan, an audit), write it to a doc under your home's \`data/\` and append a status line that points to that doc - the scout-report pattern - so the main firstmate is woken and can read it.
Before treating an investigation or visual review as complete, load \`decision-hold-lifecycle\` from this home's \`.agents/skills/\` and pass its shared completion gate.
A message with NO marker is the captain typing directly into your pane: treat it as authoritative captain intervention and stay conversational exactly as you would for any captain message; do not force it onto the status path.

# Escalation to main firstmate
Handle routine work yourself.
Report only true captain-relevant outcomes or a declared external wait by appending one line:
   \`echo "{state}: {one short line}" >> $STATUS_FILE\`
States: working, needs-decision, blocked, $PAUSED_VERB, done, failed.
Use \`$PAUSED_VERB: {why}\` (distinct from \`blocked:\`) only when your domain is deliberately idling on a known external wait you expect to clear on its own; use \`blocked:\` when you are stuck and need firstmate to act.
Use this only for material phase changes, a captain decision, a real blocker, a failure, or work ready for review.
This is also how you return the answer to a marked from-firstmate request above.
A marked request requires one correlated answer after the work; it does not require a separate receipt or start acknowledgement.
Never append \`working:\` merely to acknowledge receipt or announce that a marked request has started.
When a routed-work phase has a supervisor-actionable material change worth reporting under the rule above, give that reported phase a stable key.
If its first reportable event is \`working [key=<work-slug>]: {material phase}\`, use the same key on its later \`$PAUSED_VERB\`, \`done\`, \`failed\`, \`needs-decision\`, or \`blocked\` event so the earlier working phase is superseded.
When a keyed phase ends without another reportable state, append \`resolved [key=<work-slug>]: {why it is no longer active}\`.
\`resolved\` separately closes an escalated decision or blocker, and only a \`resolved\` line carrying that decision's exact key closes it: a later \`done\` or \`working\` event never does, even when the answer is what started that work.
The \`[key=<slug>]\` token always goes BETWEEN the verb and the colon, exactly as shown above, and the slug is letters, digits, dot, underscore or hyphen only - no spaces; a token written after the colon, or one whose slug uses any other character, does NOT carry the key you wrote, and the event opens under the key \`default\` instead.
The main firstmate's answer normally writes that closing line at answer time, but do not rely on that alone: append \`resolved: {how it was decided or unblocked}\` yourself (keyed with \`[key=<slug>]\` in that same position if you opened it with one) as your domain resumes, both after an answer lands and when a blocker or wait clears on its own without one.
A second \`resolved\` line for an already-closed key is harmless, so always closing it yourself costs nothing and keeps the decision from resurfacing if the answer did not close it.
Routine internal supervision, heartbeats, retries, and crewmate churn stay inside your own home and must not touch that status file.

# Definition of done
You are persistent by default. Do not exit just because your queue is empty.
On startup and restart, run normal firstmate bootstrap and recovery through \`bin/fm-session-start.sh\` for your own home, but only to RECONCILE work that is already yours: in-flight crewmates, tracked backlog items, and durable watches recorded in this home.
When you have no assigned or in-flight work after that reconciliation, go idle and wait silently for the main firstmate to route you a task.
An empty queue is a healthy resting state, not a cue to invent work: never spawn a survey, audit, or any self-directed "find work" task on your own initiative.
If this charter cannot be carried out, append \`blocked: {why}\` or \`failed: {why}\` to the main status file and stop.
EOF
if [ "$SECONDMATE_CHARTER" = "{TASK}" ]; then
  echo "scaffolded: $BRIEF (secondmate charter; replace {TASK})"
else
  echo "scaffolded: $BRIEF (secondmate charter)"
fi
exit 0
fi

REPO=${POS[1]}

# Reads back the absolute path a store directory's sessions actually ran in, from
# the first `cwd` field of one of its session transcripts.
# The read is bounded on purpose: one transcript per directory - a live one holds
# over 500 - and only its leading bytes, because the field appears in the opening
# records.
# The transcript layout is an external format that may change or disappear
# without notice, so a missing, unreadable or unrecognized transcript prints
# nothing and the caller must fall back to silence rather than to a guess.
store_recorded_cwd() {
  local dir=$1 transcript
  for transcript in "$dir"/*.jsonl; do
    [ -f "$transcript" ] || return 0
    head -c 131072 "$transcript" 2>/dev/null |
      sed -n '/"cwd":"/{s/.*"cwd":"\([^"]*\)".*/\1/p;q;}'
    return 0
  done
}

# Curated per-project notes live in the harness project store, one directory per
# session location, named by mangling that location's ABSOLUTE path: every
# character outside [A-Za-z0-9] becomes "-". A crewmate runs in a disposable
# worktree whose absolute path is neither firstmate's clone nor the captain's own
# checkout, so it loads none of them.
# The mangling is lossy - "/", " ", "." and "_" all collapse to "-" - so nothing
# inside a mangled name can distinguish a path separator from a literal dash or
# space, and matching store names by project-name suffix resolves project
# "Dungeon" to the notes of ".../Godot/Gacha Dungeon".
# So a suffix match only selects candidates, and a candidate is offered only
# once it is confirmed by one of two proofs.
# The first proof is exact derivation: firstmate's clone at $PROJECTS/<repo>,
# and that clone's origin when the origin is a local filesystem path rather than
# a URL. Each must be a real directory whose basename is exactly the project
# name.
# $PROJECTS/<repo> must itself be a repository root, not merely a directory
# inside one: `git -C` walks up to the nearest ancestor repository, and this
# home's own `projects/` sits inside the firstmate repo, so a project directory
# left as a plain directory would answer with firstmate's OWN origin.
# The second proof is the candidate's own recorded working directory, read back
# from its session transcripts, which holds the real absolute path before
# mangling. Its basename must equal the project name exactly, which rejects
# "Gacha Dungeon" for "Dungeon" and reaches a captain checkout whose clone knows
# it only through a remote URL.
# Every candidate must also actually hold notes; anything unproven is dropped
# rather than guessed at.
# Prints nothing when the store, the clone, or a matching notes directory does
# not exist.
project_memory_dirs() {
  local repo=$1 base clone clone_abs toplevel origin candidate abs store seen="" key dir cwd
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  [ -d "$base" ] || return 0
  clone_abs=""
  origin=""
  clone="$PROJECTS/$repo"
  if [ -d "$clone" ] &&
     clone_abs=$(cd "$clone" && pwd -P) &&
     toplevel=$(git -C "$clone" rev-parse --show-toplevel 2>/dev/null) &&
     [ -n "$toplevel" ] && [ -d "$toplevel" ] &&
     toplevel=$(cd "$toplevel" && pwd -P) &&
     [ "$toplevel" = "$clone_abs" ]; then
    origin=$(git -C "$clone" remote get-url origin 2>/dev/null || true)
    case "$origin" in
      file://*) origin=${origin#file://} ;;
      /*) : ;;
      *) origin="" ;;
    esac
  else
    clone_abs=""
  fi
  for candidate in "$clone_abs" "$origin"; do
    [ -n "$candidate" ] && [ -d "$candidate" ] || continue
    abs=$(cd "$candidate" && pwd -P) || continue
    [ "${abs##*/}" = "$repo" ] || continue
    store="$base/$(printf '%s' "$abs" | sed 's/[^a-zA-Z0-9]/-/g')"
    [ -d "$store/memory" ] || continue
    case "$seen" in *"|$store|"*) continue ;; esac
    seen="$seen|$store|"
    printf -- '- %s\n' "$store/memory"
  done
  key=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9]/-/g')
  for dir in "$base"/*-"$key"; do
    [ -d "$dir/memory" ] || continue
    case "$seen" in *"|$dir|"*) continue ;; esac
    cwd=$(store_recorded_cwd "$dir")
    [ -n "$cwd" ] || continue
    [ "${cwd##*/}" = "$repo" ] || continue
    seen="$seen|$dir|"
    printf -- '- %s\n' "$dir/memory"
  done
}

MEMORY_LIST=$(project_memory_dirs "$REPO")
if [ -n "$MEMORY_LIST" ]; then
  MEMORY_SECTION="

Curated notes for this project already exist, and nothing loads them for you because this copy sits at a different path - read them first:
$MEMORY_LIST"
else
  MEMORY_SECTION=""
fi

# Provenance split (ship and scout briefs; a secondmate charter is standing
# scope rather than a task built from rulings, so it has no rulings to split).
# A brief used to carry captain-sourced rulings and firstmate-derived inference
# in one document at one authority level, and a worker could not tell them
# apart. On 2026-08-03 that cost the captain a mechanism he never approved: an
# inference of firstmate's own reached a work order under a heading that
# claimed his authority and was armoured with "measured, do not re-derive", so
# the one load-bearing line was the one line the worker was forbidden to check.
# Both sections are always emitted, including with nothing to put in them,
# because a missing section reads as "no rulings" exactly as loudly as a
# deliberate "none", and only one of those is true.
# bin/fm-authority-receipts.sh checks the filled-in result, and bin/fm-spawn.sh
# runs it before launch, so an unreceipted claim of the captain never reaches a
# worker at all.
IFS= read -r -d '' PROVENANCE <<'EOF' || true
# What the captain decided
{CAPTAIN_RULINGS}

Every entry above is one bullet carrying the captain's own words and the date he said them, and nothing else may be written here.
Those rulings are closed: build to them, and do not re-litigate them.
If he ruled on nothing that bears on this task, the whole entry is one bullet reading `- None recorded for this task.`, which is complete and honest; a paraphrase written from memory is not, because a paraphrase under this heading is exactly how an invented mechanism reached a shipped game once already.

# What firstmate worked out
{FIRSTMATE_INFERENCE}

That is firstmate's own reasoning about how to satisfy the section above, and it carries none of the captain's authority.
It is inference, it is open to challenge, and challenging it is part of your job rather than an interruption of it.
If you find it wrong, say so and stop; do not build around it and do not quietly repair it.
If anything in it would replace, weaken, or work around anything in the section above, that contradiction is the captain's to settle and not yours: append `blocked:` naming both lines and stop.
Nothing here may be marked "measured", "do not re-derive", "decided", "settled", "confirmed", or given any other armour that puts it beyond checking, and firstmate may not add such a label later.
EOF
PROVENANCE=${PROVENANCE%$'\n'}

ORIENT_1="Run \`git status\` and \`git log --oneline -15\`, and read both before you trust any plan, status doc, or handoff."
ORIENT_2="The repository state outranks every document, always: work that exists only in the tree or in unmentioned recent commits gets rebuilt from scratch by a session that believes the document instead."

if [ "$HERDR_LAB" -eq 1 ]; then
HERDR_LAB_HELPER=$(shell_quote "$FM_ROOT/bin/fm-herdr-lab.sh")
# shellcheck disable=SC2016  # single quotes are deliberate: these lines are literal brief text whose backtick-wrapped $(...) and "$HERDR_LAB_SESSION" snippets must reach the reading agent verbatim, not expand at scaffold time; only the '"$VAR"' break-outs interpolate.
HERDR_SECTION=$(printf '%s\n' \
'# Herdr isolation - HARD SAFETY CONTRACT' \
'This brief was explicitly scaffolded with `--herdr-lab` because the task will drive Herdr lifecycle behavior.' \
'On Herdr 0.7.3 the API socket is not relocatable by `HERDR_CONFIG_PATH`, `XDG_CONFIG_HOME`, or `HOME`.' \
'A named non-`default` session plus a trailing `--session <name>` on every call is the only viable local isolation.' \
'' \
'1. Set `HERDR_LAB_HELPER='"$HERDR_LAB_HELPER"'` and generate the session name with `HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name '"$ID"')`.' \
'   Install `trap '\''"$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION"'\'' EXIT` before provisioning, then provision only with `"$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION"`.' \
'2. Run every task-specific non-lifecycle Herdr command through `"$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" <arguments...>`.' \
'   The helper appends the required trailing `--session "$HERDR_LAB_SESSION"`; `HERDR_SESSION` alone is never accepted as isolation.' \
'3. Teardown only through `"$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION"`.' \
'   It re-checks refuse-default immediately before stop and again immediately before delete, and fails closed on ambiguity.' \
'4. If an experiment requires a deliberate mid-run session stop, use only `"$HERDR_LAB_HELPER" stop "$HERDR_LAB_SESSION"`; it performs the same immediate refuse-default check.' \
'5. Forbidden commands: direct `herdr server stop`, every other server-global operation such as `herdr server live-handoff` or reload/update operations, direct `herdr session stop`, direct `herdr session delete`, and any Herdr call scoped only by ambient or inline `HERDR_SESSION`.' \
'6. The helper records the live default session before provisioning and verifies the identical fleet state after teardown.' \
'   A missing, stopped, or changed default session is a hard tripwire failure, never a cleanup warning to ignore.' \
'' \
'Never bypass the helper, even for a read-only lifecycle probe or cleanup after failure.' \
'The captain fleet uses the running `default` session.')
else
IFS= read -r -d '' HERDR_SECTION <<'EOF' || true
# Herdr lifecycle declaration - NOT ENABLED
**HARD SAFETY GATE:** this scaffold cannot inspect the task text that replaces `{TASK}` later.
If the task will start, stop, delete, restart, profile, or otherwise drive Herdr lifecycle behavior, stop and regenerate the brief with `--herdr-lab` before dispatch.
Do not add Herdr lifecycle commands to this unguarded brief by hand.
EOF
HERDR_SECTION=${HERDR_SECTION%$'\n'}
fi

if [ "$KIND" = scout ]; then
cat > "$BRIEF" <<EOF
You are a crewmate: an autonomous worker agent managed by firstmate. Work on your own; do not wait for a human.

# Task
{TASK}

$PROVENANCE

$HERDR_SECTION

# Setup
You are in a disposable git worktree of $REPO, at a detached HEAD on a clean default branch.
This is a SCOUT task: the deliverable is a written report, not a PR.
The worktree is your laboratory - install, run, edit, and make scratch commits freely, because all of it is discarded at teardown and the report is the only thing that survives.

**Orient before anything else.** $ORIENT_1
$ORIENT_2$MEMORY_SECTION

# Rules
1. Never push to any remote and never open a PR.
2. Stay inside this worktree; the only files you may write outside it are the report and the status file below.
3. Use gh-axi for GitHub operations and chrome-devtools-axi for browser operations.
4. Report status by appending one line:
   \`echo "{state}: {one short line}" >> $STATUS_FILE\`
   States: working, needs-decision, blocked, $PAUSED_VERB, done, failed.
   Each append wakes firstmate, so report sparingly: only phase changes a supervisor
   would act on and the needs-decision/blocked/paused/done/failed states. No step-by-step
   FYI progress lines; firstmate reads your pane for that.
   Use \`$PAUSED_VERB: {why}\` - distinct from \`blocked:\` - ONLY when you are deliberately idling on a
   known external wait you expect to clear on its own (an upstream release, a rate-limit reset):
   firstmate then leaves your idle pane alone and rechecks it on a long cadence instead of
   treating it as a possible wedge. Use \`blocked:\` when you are stuck and need help.
5. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; firstmate will help.
6. If a decision belongs to a human (product choices, destructive actions),
   append \`needs-decision: {summary of options}\` and stop. Firstmate will reply with the decision.
   A decision or blocker you opened stays open until a \`resolved\` line carrying its exact key lands; a later \`done:\` or \`working:\` line never closes it, even when the answer is what started that work.
   If you key a decision, the \`[key=<slug>]\` token goes BETWEEN the verb and the colon, never after it, and the slug is letters, digits, dot, underscore or hyphen only - no spaces.
   A token written after the colon, or one whose slug uses any other character, does NOT carry the key you wrote: the decision opens under the key \`default\` instead, and the answer then has to be sent against \`default\` rather than the slug you wrote.
   Copy this shape exactly, both lines:
       needs-decision [key=api-shape]: REST or RPC for the sync endpoint
       resolved [key=api-shape]: went with REST
   Firstmate's reply normally writes that closing line at answer time, but do not rely on that alone: append \`resolved: {how it was decided or unblocked}\` yourself (same \`[key=<slug>]\` in that same position if you opened it with one) as you resume, both after firstmate's reply lands and when a blocker or wait clears on its own without one.
   A second \`resolved\` line for an already-closed key is harmless, so always closing it yourself costs nothing and keeps the decision from resurfacing if the reply did not close it.
7. Never stop, restart, or update the shared \`no-mistakes\` daemon - it is one instance serving
   every lane/home, so restarting it kills other lanes' in-flight pipeline runs. On ANY no-mistakes
   daemon error, append \`blocked: {the daemon error}\` and stop; only firstmate manages the daemon.

# Definition of done
Write your findings to \`$DATA/$ID/report.md\`.
The report must stand alone: what you did, what you found, the evidence (commands run, output, file:line references), and what you recommend.
Answer each item below explicitly before you report done; an item you cannot satisfy is named as a gap, never skipped in silence.
- [ ] Any owner decision the report relies on is quoted verbatim with its date - a previous session summarising the owner is not evidence that the owner said it.
- [ ] Anything you learned the hard way is a dated note in the report, with what would have caught it earlier.
- [ ] Nothing recommended that no execution would touch.

Before reporting done, read and follow \`$FM_ROOT/.agents/skills/decision-hold-lifecycle/SKILL.md\` and pass its shared completion gate for the report and any visual review.
When the report is complete, append \`done: {one-line conclusion}\` to the status file and stop.
If your findings reveal work that should ship (e.g. you reproduced a bug and the fix is clear), say so in the report; firstmate may promote this task in place, and you would then receive mode-specific ship instructions as a follow-up message.
EOF
echo "scaffolded: $BRIEF (scout; replace {TASK}, {CAPTAIN_RULINGS}, {FIRSTMATE_INFERENCE})"
exit 0
fi

# Ship task: shape Setup / Rule 1 / Definition of done by the project's delivery mode.
# yolo does not affect the brief because the worker never owns approval decisions;
# firstmate applies the authority contract in AGENTS.md section 7, so discard it.
read -r MODE _ <<EOF
$("$FM_ROOT/bin/fm-project-mode.sh" "$REPO")
EOF

case "$MODE" in
  direct-PR)
    SETUP2="
3. Run \`no-mistakes doctor\`; if it reports the repo is not initialized here, run \`no-mistakes init\`."
    RULE1='1. Never push to the default branch (push only your `fm/'"$ID"'` branch). Never merge a PR.'
    IFS= read -r -d '' DOD <<EOF || true
This project ships **direct-PR**: you raise the PR yourself, and exactly one automated review runs before you do.
That review is a separate agent the no-mistakes daemon starts. It did not write your change and does not share your session, which is the whole point of it - an agent that watched the code get written is biased toward believing it is correct.
Review is the ONLY pipeline step that runs on this path; the other eight are skipped, so this costs a couple of minutes rather than a full pipeline run.

The task is complete only when committed on your branch.
When it is implemented and committed, start the review with this exact command, from inside your worktree:
\`$FM_ROOT/bin/fm-validate.sh $ID --intent "<what the captain set out to accomplish>"\`
Do NOT call \`no-mistakes axi run\` directly. Which steps this path skips is derived from the task's recorded delivery mode inside that command rather than typed by you, so it is inherited automatically, including on any re-run after a failure. Use the same command every time you need to start or restart the review.
It never skips the review step itself, for any mode.
You drive the review by responding to its gate: do not hand-edit, commit, or fix findings yourself while a run is active, because the pipeline applies every fix.
Follow the guidance no-mistakes itself provides for the mechanics: \`no-mistakes axi run --help\` plus the \`help\` lines in each \`axi\` response are authoritative and version-matched to the installed binary.
Two firstmate-specific rules layer on top of it:
- ask-user findings are never yours to answer: escalate to firstmate (rule 6) and stop. Firstmate applies the authority contract in its \`AGENTS.md\` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with \`no-mistakes axi respond\` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- Avoid \`--yes\`: it would silently bypass firstmate's authority check and any required captain escalation.

When the run reaches a successful terminal outcome, push your branch and open a PR with \`gh-axi\`, then append \`done: PR {url}\` to the status file and stop.
Pushing before the review reaches that outcome defeats the one safeguard this path has.
A failed or cancelled run is terminal but NOT successful: never open the PR on one - escalate to firstmate (rule 6) and stop.
The configured merge authority decides whether to merge the PR; firstmate relays the outcome.
EOF
    ;;
  validated-main)
    SETUP2="
3. Run \`no-mistakes doctor\`; if it reports the repo is not initialized here, run \`no-mistakes init\`."
    RULE1='1. Never push to the default branch and never merge. Push only your `fm/'"$ID"'` branch, and only through the pipeline.'
    IFS= read -r -d '' DOD <<EOF || true
This project ships **validated-main**: the same full validation pipeline as no-mistakes, landed on \`main\` without a PR.
Skipping the PR does NOT skip the review - the pipeline's review, test, document and lint steps all run locally and are exactly what makes landing straight on \`main\` safe. Only the two steps that talk to the host are dropped.

The task is complete only when committed on your branch.
When you believe it is complete, append \`done: {summary}\` to the status file and stop.
Firstmate will then instruct you to run /no-mistakes to validate the branch.

Start the run with this exact command, from inside your worktree:
\`$FM_ROOT/bin/fm-validate.sh $ID --intent "<what the captain set out to accomplish>"\`
Do NOT call \`no-mistakes axi run\` directly. This project's delivery path omits the PR and CI steps, and that omission is derived from the task's recorded delivery mode inside that command rather than typed by you - so it is inherited automatically, including on any re-run after a failure. Use the same command every time you need to start or restart validation.
It never omits review, test, document or lint for any mode.
You drive no-mistakes by responding to its gates: do not hand-edit, commit, or fix findings yourself while a run is active, because the pipeline applies every fix.
Follow the guidance no-mistakes itself provides for the mechanics: it loads when you invoke /no-mistakes, and \`no-mistakes axi run --help\` plus the \`help\` lines in each \`axi\` response are authoritative and version-matched to the installed binary.
Two firstmate-specific rules layer on top of it:
- ask-user findings are never yours to answer: escalate to firstmate (rule 6) and stop. Firstmate applies the authority contract in its \`AGENTS.md\` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with \`no-mistakes axi respond\` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- Avoid \`--yes\`: it would silently bypass firstmate's authority check and any required captain escalation.

The pipeline commits its own fix rounds and pushes them, so your local branch may end up behind what it published. That is expected and is not yours to reconcile by hand.
When the run reaches a successful terminal outcome, append \`done: validated on fm/$ID, ready to land\` and stop. You are finished.
Firstmate lands the validated branch on \`main\` and pushes it; you never merge and never open a PR.
EOF
    ;;
  local-only)
    SETUP2="
3. Run \`no-mistakes doctor\`; if it reports the repo is not initialized here, run \`no-mistakes init\`. This sets up a LOCAL gate only; it publishes nothing."
    RULE1="1. Never push to any remote and never open a PR. Work only on your \`fm/$ID\` branch; firstmate handles the merge into local \`main\`."
    IFS= read -r -d '' DOD <<EOF || true
This project ships **local-only**: no remote, no PR, and exactly one automated review before the branch is ready.
That review is a separate agent the no-mistakes daemon starts. It did not write your change and does not share your session, which is the whole point of it - an agent that watched the code get written is biased toward believing it is correct.
Review is the ONLY pipeline step that runs on this path; the other eight are skipped, so this costs a couple of minutes rather than a full pipeline run. The publishing step is one of the eight skipped, so the review reads your branch and pushes nothing.

The task is complete only when committed on your branch \`fm/$ID\`. Do NOT push, do NOT open a PR, do NOT merge.
Keep your branch a clean fast-forward onto the current default branch - if \`main\` has advanced, rebase onto it so the eventual merge stays a fast-forward.
When it is implemented and committed, start the review with this exact command, from inside your worktree:
\`$FM_ROOT/bin/fm-validate.sh $ID --intent "<what the captain set out to accomplish>"\`
Do NOT call \`no-mistakes axi run\` directly. Which steps this path skips is derived from the task's recorded delivery mode inside that command rather than typed by you, so it is inherited automatically, including on any re-run after a failure. Use the same command every time you need to start or restart the review.
It never skips the review step itself, for any mode.
You drive the review by responding to its gate: do not hand-edit, commit, or fix findings yourself while a run is active, because the pipeline applies every fix.
Follow the guidance no-mistakes itself provides for the mechanics: \`no-mistakes axi run --help\` plus the \`help\` lines in each \`axi\` response are authoritative and version-matched to the installed binary.
Two firstmate-specific rules layer on top of it:
- ask-user findings are never yours to answer: escalate to firstmate (rule 6) and stop. Firstmate applies the authority contract in its \`AGENTS.md\` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with \`no-mistakes axi respond\` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- Avoid \`--yes\`: it would silently bypass firstmate's authority check and any required captain escalation.

When the run reaches a successful terminal outcome, append \`done: ready in branch fm/$ID\` to the status file and stop.
A failed or cancelled run is terminal but NOT successful: never declare the branch ready on one - escalate to firstmate (rule 6) and stop, because firstmate fast-forwards a ready branch straight into local \`main\`.
The configured merge authority approves the ready branch, then firstmate merges it into local \`main\` through the guarded fast-forward path.
EOF
    ;;
  *)  # no-mistakes (default)
    SETUP2="
3. Run \`no-mistakes doctor\`; if it reports the repo is not initialized here, run \`no-mistakes init\`."
    RULE1='1. Never push to the default branch. Never merge a PR.'
    IFS= read -r -d '' DOD <<EOF || true
The task is complete only when committed on your branch.
When you believe it is complete, append \`done: {summary}\` to the status file and stop.
Firstmate will then instruct you to run /no-mistakes to validate and ship a PR.

You drive no-mistakes by responding to its gates: do not hand-edit, commit, or fix findings yourself while a run is active, because the pipeline applies every fix.
Follow the guidance no-mistakes itself provides for the mechanics: it loads when you invoke /no-mistakes, and \`no-mistakes axi run --help\` plus the \`help\` lines in each \`axi\` response are authoritative and version-matched to the installed binary.
Two firstmate-specific rules layer on top of it:
- ask-user findings are never yours to answer: escalate to firstmate (rule 6) and stop. Firstmate applies the authority contract in its \`AGENTS.md\` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with \`no-mistakes axi respond\` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- Avoid \`--yes\`: it would silently bypass firstmate's authority check and any required captain escalation.

After /no-mistakes reaches its CI-ready return point, append \`done: PR {url} checks green\` and stop. You are finished.
Two things satisfy that return point: checks passed, or the PR registered no checks at all once the pipeline's registration grace elapsed.
A repository with no checks configured is normal here and reports as ready; it is not a failure, and it is never a reason to wait for a green signal by hand.
In both cases do not wait for the step to keep monitoring in the background until merge.
EOF
    ;;
esac

# read -r -d '' preserves the heredoc's trailing newline that the removed
# $(...) command substitution used to strip. Drop that one newline so generated
# briefs stay byte-identical to the historical Bash 5 output.
DOD=${DOD%$'\n'}

# Checklist text is built with printf, not a heredoc in a command substitution,
# so no apostrophe in it can break parsing of the rest of this script.
# shellcheck disable=SC2016  # single quotes are deliberate: backticks and {} must reach the brief verbatim.
CHECKLIST=$(printf '%s\n' \
'Answer every item below explicitly before the final `done:` line the delivery path below names for this task, never before an earlier progress append; an item you cannot satisfy is named as a gap, never skipped in silence.' \
'- [ ] The check command passes - `script/check` if it exists, otherwise the command `AGENTS.md` names. If this project has no verification at all, name that gap in your done line, because a silent pass here is the failure this list exists to catch.' \
'- [ ] One edit named that would make a new test go red - made, confirmed red, reverted.' \
'- [ ] A different context reviewed the diff than the one that wrote it.' \
'- [ ] No new question left unasked.' \
'- [ ] Any owner decision quoted verbatim, with its date.' \
'- [ ] Any lesson learned the hard way that clears the Project memory bar above is a dated note in that project `AGENTS.md`. A task that produced no such lesson satisfies this with nothing written.' \
'- [ ] Nothing added to a document that no execution touches.')

cat > "$BRIEF" <<EOF
You are a crewmate: an autonomous worker agent managed by firstmate. Work on your own; do not wait for a human.

# Task
{TASK}

$PROVENANCE

$HERDR_SECTION

# Setup
You are in a disposable git worktree of $REPO, at a detached HEAD on a clean default branch.

**Verify isolation before anything else.** Run \`pwd -P\` and \`git rev-parse --show-toplevel\`; both must resolve to the disposable task worktree you were launched in, such as a treehouse pool path or an Orca-managed worktree, not the primary checkout firstmate operates from.
The path check is authoritative: \`git rev-parse --git-dir\` and \`git rev-parse --git-common-dir\` can help inspect the repo, but they do not prove you are outside the primary checkout.
If the top-level path is the primary checkout or not the worktree you were launched in, STOP - do not branch or commit here - append \`blocked: launched in primary checkout, not an isolated worktree\` to the status file and stop.

1. First action: create your branch: \`git checkout -b fm/$ID\`
2. Then orient, before you build anything. $ORIENT_1
   $ORIENT_2$SETUP2$MEMORY_SECTION

# Rules
$RULE1
2. Stay inside this worktree; modify nothing outside it.
3. Use gh-axi for GitHub operations and chrome-devtools-axi for browser operations.
4. Report status by appending one line:
   \`echo "{state}: {one short line}" >> $STATUS_FILE\`
   States: working, needs-decision, blocked, $PAUSED_VERB, done, failed.
   Each append wakes firstmate, so report sparingly: only phase changes a supervisor
   would act on (setup done, bug reproduced, fix implemented, validation passed) and the
   needs-decision/blocked/paused/done/failed states. No step-by-step FYI progress lines;
   firstmate reads your pane for that.
   A mid-task \`working:\` line (including setup complete) is nonterminal: do not end the
   turn after it; continue the same stage until a defined \`done:\` gate under Definition of done.
   Use \`$PAUSED_VERB: {why}\` - distinct from \`blocked:\` - ONLY when you are deliberately idling on a
   known external wait you expect to clear on its own (an upstream release, a rate-limit reset,
   a scheduled window): firstmate then leaves your idle pane alone and rechecks it on a long
   cadence instead of treating it as a possible wedge. Use \`blocked:\` when you are stuck and need help.
5. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; firstmate will help.
6. If a decision belongs above the implementation worker (product choices, destructive actions, ask-user findings),
   append \`needs-decision: {summary of options}\` and stop. Firstmate will apply the configured authority and reply with the decision.
   A decision or blocker you opened stays open until a \`resolved\` line carrying its exact key lands; a later \`done:\` or \`working:\` line never closes it, even when the answer is what started that work.
   If you key a decision, the \`[key=<slug>]\` token goes BETWEEN the verb and the colon, never after it, and the slug is letters, digits, dot, underscore or hyphen only - no spaces.
   A token written after the colon, or one whose slug uses any other character, does NOT carry the key you wrote: the decision opens under the key \`default\` instead, and the answer then has to be sent against \`default\` rather than the slug you wrote.
   Copy this shape exactly, both lines:
       needs-decision [key=api-shape]: REST or RPC for the sync endpoint
       resolved [key=api-shape]: went with REST
   Firstmate's reply normally writes that closing line at answer time, but do not rely on that alone: append \`resolved: {how it was decided or unblocked}\` yourself (same \`[key=<slug>]\` in that same position if you opened it with one) as you resume, both after firstmate's reply lands and when a blocker or wait clears on its own without one.
   A second \`resolved\` line for an already-closed key is harmless, so always closing it yourself costs nothing and keeps the decision from resurfacing if the reply did not close it.
7. Never stop, restart, or update the shared \`no-mistakes\` daemon - it is one instance serving
   every lane/home, so restarting it kills other lanes' in-flight pipeline runs. On ANY no-mistakes
   daemon error, append \`blocked: {the daemon error}\` and stop; only firstmate manages the daemon.

# Project memory
If \`AGENTS.md\` or \`CLAUDE.md\` already exists, or if this task produced durable project-intrinsic knowledge, run \`$FM_ROOT/bin/fm-ensure-agents-md.sh .\` in the worktree; skip it for a trivial task that produced no durable project knowledge.
Record only project knowledge useful to almost every future session.
For anything the codebase already shows, prefer a pointer to the authoritative file, command, or doc over copying the detail.
If you touch a project \`AGENTS.md\` that lacks \`## Maintaining this file\`, add that short self-governance section from \`$FM_ROOT/bin/fm-ensure-agents-md.sh\` in the same pass.

# Definition of done
$CHECKLIST

$DOD
EOF
echo "scaffolded: $BRIEF (ship, mode=$MODE; replace {TASK}, {CAPTAIN_RULINGS}, {FIRSTMATE_INFERENCE})"
