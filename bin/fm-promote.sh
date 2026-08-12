#!/usr/bin/env bash
# Promote a scout task to a ship task in place: the crewmate keeps its window,
# worktree, and loaded context while its brief becomes the canonical ship prompt.
# The explicit outcome is the authoritative promotion input; the scout report
# remains evidence, and captain-sourced outcomes bind to existing provenance.
# Usage: fm-promote.sh <task-id> --task-tier <tier> --outcome '<authoritative source> => <observable result>' [--prove <evidence>] [--player <evidence>] [--parts <evidence>] [--platform <evidence>] [--correct <evidence>]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
"$FM_ROOT/bin/fm-guard.sh" || true
ID=${1:-}
[ -n "$ID" ] || { echo "error: task id is required" >&2; exit 1; }
shift

TASK_TIER=
OUTCOME=
PROVE=
PLAYER=
PARTS=
PLATFORM=
CORRECT=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-tier)
      [ "$#" -ge 2 ] || { echo "error: --task-tier needs a value" >&2; exit 1; }
      TASK_TIER=$2
      shift 2
      ;;
    --task-tier=*) TASK_TIER=${1#--task-tier=}; shift ;;
    --outcome)
      [ "$#" -ge 2 ] || { echo "error: --outcome needs a value" >&2; exit 1; }
      OUTCOME=$2
      shift 2
      ;;
    --outcome=*) OUTCOME=${1#--outcome=}; shift ;;
    --prove|--player|--parts|--platform|--correct)
      [ "$#" -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 1; }
      case "$1" in
        --prove) PROVE=$2 ;;
        --player) PLAYER=$2 ;;
        --parts) PARTS=$2 ;;
        --platform) PLATFORM=$2 ;;
        --correct) CORRECT=$2 ;;
      esac
      shift 2
      ;;
    --prove=*) PROVE=${1#--prove=}; shift ;;
    --player=*) PLAYER=${1#--player=}; shift ;;
    --parts=*) PARTS=${1#--parts=}; shift ;;
    --platform=*) PLATFORM=${1#--platform=}; shift ;;
    --correct=*) CORRECT=${1#--correct=}; shift ;;
    *) echo "error: unknown promotion argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$TASK_TIER" ] && [ -n "$OUTCOME" ] || {
  echo "error: promotion needs --task-tier and explicit authoritative --outcome; the scout report is evidence only and task $ID remains a scout" >&2
  exit 1
}

META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }
BRIEF="$DATA/$ID/brief.md"
REPORT="$DATA/$ID/report.md"
[ -f "$BRIEF" ] || { echo "error: no scout brief for task $ID at $BRIEF" >&2; exit 1; }
JOURNAL="$DATA/$ID/.promotion"
JOURNAL_DONE="$DATA/$ID/.promotion.done"
JOURNAL_BRIEF="$JOURNAL/brief.md"
JOURNAL_META="$JOURNAL/meta"
JOURNAL_ORIGINAL_BRIEF="$JOURNAL/original-brief.md"
JOURNAL_ORIGINAL_META="$JOURNAL/original-meta"
STAGE=
PUBLISH_TMP=

cleanup() {
  [ -z "$PUBLISH_TMP" ] || rm -f "$PUBLISH_TMP"
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
    rm -f "$STAGE/scout-task" "$STAGE/ship-task" "$STAGE/promotion-context" \
      "$STAGE/provenance" "$STAGE/contract" "$STAGE/template.md" \
      "$STAGE/brief.md" "$STAGE/meta"
    rmdir "$STAGE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

publish_journal_file() {
  local source=$1 destination=$2
  PUBLISH_TMP=$(mktemp "$(dirname "$destination")/.$(basename "$destination").promote.XXXXXX")
  cp "$source" "$PUBLISH_TMP"
  mv "$PUBLISH_TMP" "$destination"
  PUBLISH_TMP=
}

promotion_result() {
  local home_q
  home_q=$(printf '%q' "$FM_HOME")
  echo "promoted $ID to ship (teardown protection restored)"
  echo "next: FM_HOME=$home_q bin/fm-send.sh fm-$ID '<ship instructions: re-read the updated brief; preserve the scout snapshot; prove a clean default-branch base; create branch fm/$ID; carry only intended fix and regression changes; implement; report done>'"
}

if [ -d "$JOURNAL_DONE" ]; then
  grep -qx 'kind=ship' "$META" || {
    echo "error: completed promotion journal for $ID disagrees with metadata" >&2
    exit 1
  }
  rm -f "$JOURNAL_DONE/ready" "$JOURNAL_DONE/brief.md" "$JOURNAL_DONE/meta" \
    "$JOURNAL_DONE/original-brief.md" "$JOURNAL_DONE/original-meta"
  rmdir "$JOURNAL_DONE"
  promotion_result
  exit 0
fi

if [ -d "$JOURNAL" ]; then
  if [ ! -f "$JOURNAL/ready" ]; then
    if grep -qx 'kind=scout' "$META" && ! grep -Fxq '# Delivery contract' "$BRIEF"; then
      rm -f "$JOURNAL_BRIEF" "$JOURNAL_META" "$JOURNAL_ORIGINAL_BRIEF" \
        "$JOURNAL_ORIGINAL_META" "$JOURNAL/ready"
      rmdir "$JOURNAL" 2>/dev/null || {
        echo "error: incomplete promotion journal for $ID cannot be recovered safely" >&2
        exit 1
      }
    else
      echo "error: incomplete promotion journal for $ID does not match current task state" >&2
      exit 1
    fi
  else
    [ -f "$JOURNAL_BRIEF" ] && [ -f "$JOURNAL_META" ] \
      && [ -f "$JOURNAL_ORIGINAL_BRIEF" ] && [ -f "$JOURNAL_ORIGINAL_META" ] || {
        echo "error: promotion journal for $ID is incomplete" >&2
        exit 1
      }
    if cmp "$BRIEF" "$JOURNAL_ORIGINAL_BRIEF" >/dev/null \
       && cmp "$META" "$JOURNAL_ORIGINAL_META" >/dev/null; then
      publish_journal_file "$JOURNAL_BRIEF" "$BRIEF"
    elif ! cmp "$BRIEF" "$JOURNAL_BRIEF" >/dev/null \
         || ! cmp "$META" "$JOURNAL_ORIGINAL_META" >/dev/null; then
      if cmp "$BRIEF" "$JOURNAL_BRIEF" >/dev/null \
         && cmp "$META" "$JOURNAL_META" >/dev/null; then
        :
      else
        echo "error: promotion journal for $ID does not match current brief and metadata" >&2
        exit 1
      fi
    fi
    if cmp "$META" "$JOURNAL_ORIGINAL_META" >/dev/null; then
      publish_journal_file "$JOURNAL_META" "$META"
    fi
    cmp "$BRIEF" "$JOURNAL_BRIEF" >/dev/null \
      && cmp "$META" "$JOURNAL_META" >/dev/null || {
        echo "error: promotion publication for $ID did not converge" >&2
        exit 1
      }
    mv "$JOURNAL" "$JOURNAL_DONE"
    rm -f "$JOURNAL_DONE/ready" "$JOURNAL_DONE/brief.md" "$JOURNAL_DONE/meta" \
      "$JOURNAL_DONE/original-brief.md" "$JOURNAL_DONE/original-meta"
    rmdir "$JOURNAL_DONE"
    promotion_result
    exit 0
  fi
fi

grep -qx 'kind=scout' "$META" || { echo "error: task $ID is not a scout task (kind=scout not in meta)" >&2; exit 1; }
[ -s "$REPORT" ] || { echo "error: no scout evidence report for task $ID at $REPORT" >&2; exit 1; }

case "$OUTCOME" in
  *'=>'*) ;;
  *) echo "error: --outcome must be <authoritative source pointer> => <accepted scout finding>" >&2; exit 1 ;;
esac
OUTCOME_RESULT=${OUTCOME#*=>}
OUTCOME_RESULT=$(printf '%s\n' "$OUTCOME_RESULT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$OUTCOME_RESULT" ] || { echo "error: --outcome has no observable result" >&2; exit 1; }

PROJECT=$(sed -n 's/^project=//p' "$META" | sed -n '1p')
[ -n "$PROJECT" ] || { echo "error: task $ID has no project in $META" >&2; exit 1; }
REPO=$(basename "$PROJECT")
read -r PROMOTION_MODE PROMOTION_YOLO <<EOF
$("$FM_ROOT/bin/fm-project-mode.sh" "$REPO")
EOF

STAGE=$(mktemp -d "$DATA/$ID/.promote.XXXXXX")
SCOUT_TASK="$STAGE/scout-task"
SHIP_TASK="$STAGE/ship-task"
PROMOTION_CONTEXT="$STAGE/promotion-context"
PROVENANCE="$STAGE/provenance"
CONTRACT="$STAGE/contract"
TEMPLATE="$STAGE/template.md"
CANDIDATE="$STAGE/brief.md"
META_NEXT="$STAGE/meta"

awk '
  $0 == "# Task" { active = 1; next }
  active && $0 == "# What the captain decided" { exit }
  active { print }
' "$BRIEF" > "$SCOUT_TASK"
grep -q '[^[:space:]]' "$SCOUT_TASK" || { echo "error: scout brief has no task body to promote" >&2; exit 1; }
grep -Fx '{TASK}' "$SCOUT_TASK" >/dev/null && { echo "error: scout brief still has an unresolved task placeholder" >&2; exit 1; }

printf 'Deliver the accepted outcome: %s\n' "$OUTCOME_RESULT" > "$SHIP_TASK"
{
  printf '%s\n' '# Promotion evidence and scout context' \
    'The original scout task and report below are provisional evidence only; the accepted outcome above owns the ship target.' \
    '' \
    '## Original scout task'
  awk '{ print ($0 == "" ? ">" : "> " $0) }' "$SCOUT_TASK"
  printf '%s\n' '' '## Scout report'
  awk '{ print ($0 == "" ? ">" : "> " $0) }' "$REPORT"
  printf '\n'
} > "$PROMOTION_CONTEXT"

awk '
  $0 == "# What the captain decided" { active = 1 }
  active && $0 ~ /^# / && $0 != "# What the captain decided" && $0 != "# What firstmate worked out" { exit }
  active { print }
' "$BRIEF" > "$PROVENANCE"
grep -Fx '# What firstmate worked out' "$PROVENANCE" >/dev/null || {
  echo "error: scout brief has no complete captain/firstmate provenance split" >&2
  exit 1
}
"$FM_ROOT/bin/fm-authority-receipts.sh" "$BRIEF" >/dev/null || {
  echo "error: scout brief has invalid captain provenance; task $ID remains a scout" >&2
  exit 1
}

{
  printf '%s\n' "- task-tier: $TASK_TIER" "- outcome: $OUTCOME"
  [ -z "$PROVE" ] || printf '%s\n' "- prove: $PROVE"
  [ -z "$PLAYER" ] || printf '%s\n' "- player: $PLAYER"
  [ -z "$PARTS" ] || printf '%s\n' "- parts: $PARTS"
  [ -z "$PLATFORM" ] || printf '%s\n' "- platform: $PLATFORM"
  [ -z "$CORRECT" ] || printf '%s\n' "- correct: $CORRECT"
} > "$CONTRACT"

HERDR_ARG=
if grep -Fx '# Herdr isolation - HARD SAFETY CONTRACT' "$BRIEF" >/dev/null; then
  HERDR_ARG=--herdr-lab
fi
if [ -n "$HERDR_ARG" ]; then
  FM_BRIEF_PATH_OVERRIDE="$TEMPLATE" FM_BRIEF_MODE_OVERRIDE="$PROMOTION_MODE" FM_BRIEF_YOLO_OVERRIDE="$PROMOTION_YOLO" FM_PROMOTED_SCOUT=1 \
    "$FM_ROOT/bin/fm-brief.sh" "$ID" "$REPO" "$HERDR_ARG" >/dev/null
else
  FM_BRIEF_PATH_OVERRIDE="$TEMPLATE" FM_BRIEF_MODE_OVERRIDE="$PROMOTION_MODE" FM_BRIEF_YOLO_OVERRIDE="$PROMOTION_YOLO" FM_PROMOTED_SCOUT=1 \
    "$FM_ROOT/bin/fm-brief.sh" "$ID" "$REPO" >/dev/null
fi

awk -v task_file="$SHIP_TASK" -v context_file="$PROMOTION_CONTEXT" -v provenance_file="$PROVENANCE" -v contract_file="$CONTRACT" '
  function emit(file, line) {
    while ((getline line < file) > 0) print line
    close(file)
  }
  skip_task {
    if ($0 == "# Delivery contract") {
      skip_task = 0
      print
      emit(contract_file)
      skip_contract = 1
    }
    next
  }
  skip_contract {
    if ($0 ~ /^# /) {
      skip_contract = 0
      print
    }
    next
  }
  skip_provenance {
    if ($0 ~ /^# / && $0 != "# What the captain decided" && $0 != "# What firstmate worked out") {
      skip_provenance = 0
      print
    }
    next
  }
  $0 == "# Task" {
    print
    emit(task_file)
    skip_task = 1
    next
  }
  $0 == "# What the captain decided" {
    emit(context_file)
    emit(provenance_file)
    skip_provenance = 1
    next
  }
  { print }
' "$TEMPLATE" > "$CANDIDATE"

"$FM_ROOT/bin/fm-doctrine-contract.sh" check "$CANDIDATE" || {
  echo "error: promoted ship contract is invalid; task $ID remains a scout" >&2
  exit 1
}
"$FM_ROOT/bin/fm-authority-receipts.sh" "$CANDIDATE" >/dev/null || {
  echo "error: promoted ship prompt does not preserve valid captain provenance; task $ID remains a scout" >&2
  exit 1
}

grep -vE '^(kind|mode|yolo)=' "$META" > "$META_NEXT"
echo "kind=ship" >> "$META_NEXT"
echo "mode=$PROMOTION_MODE" >> "$META_NEXT"
echo "yolo=$PROMOTION_YOLO" >> "$META_NEXT"
mkdir "$JOURNAL" || { echo "error: promotion journal already exists for $ID" >&2; exit 1; }
cp "$BRIEF" "$JOURNAL_ORIGINAL_BRIEF"
cp "$META" "$JOURNAL_ORIGINAL_META"
cp "$CANDIDATE" "$JOURNAL_BRIEF"
cp "$META_NEXT" "$JOURNAL_META"
: > "$JOURNAL/ready"
publish_journal_file "$JOURNAL_BRIEF" "$BRIEF"
publish_journal_file "$JOURNAL_META" "$META"
cmp "$BRIEF" "$JOURNAL_BRIEF" >/dev/null && cmp "$META" "$JOURNAL_META" >/dev/null || {
  echo "error: promotion publication for $ID did not converge" >&2
  exit 1
}
mv "$JOURNAL" "$JOURNAL_DONE"
rm -f "$JOURNAL_DONE/ready" "$JOURNAL_DONE/brief.md" "$JOURNAL_DONE/meta" \
  "$JOURNAL_DONE/original-brief.md" "$JOURNAL_DONE/original-meta"
rmdir "$JOURNAL_DONE"
promotion_result
