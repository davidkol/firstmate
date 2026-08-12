#!/usr/bin/env bash
# Validate and render the task-local Designer -> Runtime -> Player contract.
# Usage:
#   fm-doctrine-contract.sh check <brief.md>
#   fm-doctrine-contract.sh field <brief.md> <field>
#   fm-doctrine-contract.sh review-intent <brief.md>
#
# The "# Delivery contract" block is the single machine-owned schema.
# Exactly one task-tier and outcome are always required.
# prove, player, parts, platform, and correct are conditional evidence lines.
# This script validates structure and source binding; workers and the selected
# reviewer judge whether the cited evidence establishes the claimed outcome.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

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

COMMAND=${1:-}
BRIEF=${2:-}
[ -n "$COMMAND" ] && [ -n "$BRIEF" ] || { usage >&2; exit 2; }
[ -f "$BRIEF" ] || { echo "error: no brief at $BRIEF" >&2; exit 2; }

check_contract() {
  output_mode=${1:-check}
  awk '
    function trim(value) {
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      return value
    }

    function placeholder(value, lower) {
      value = trim(value)
      lower = tolower(value)
      if (value == "") return 1
      if (value ~ /\{[^}]+\}/) return 1
      if (lower ~ /^(todo|tbd|n\/a|none|null|unknown|placeholder)$/) return 1
      if (lower ~ /^<[^>]+>$/) return 1
      if (lower ~ /^\[[^]]*(fill|placeholder|todo|tbd)[^]]*\]$/) return 1
      return 0
    }

    function finding(message) {
      print "error: " message > "/dev/stderr"
      findings++
    }

    function parse_fence(line, text, char, run) {
      text = line
      sub(/^[ \t]*/, "", text)
      char = substr(text, 1, 1)
      if (char != "`" && char != "~") return 0
      run = 0
      while (substr(text, run + 1, 1) == char) run++
      if (run < 3) return 0
      parsed_fence_char = char
      parsed_fence_length = run
      parsed_fence_tail = substr(text, run + 1)
      return 1
    }

    BEGIN {
      section_count = 0
      in_contract = 0
      in_fence = 0
      findings = 0
    }

    {
      if (!in_fence) {
        if (parse_fence($0)) {
          in_fence = 1
          open_fence_char = parsed_fence_char
          open_fence_length = parsed_fence_length
          next
        }
      } else {
        if (parse_fence($0) && parsed_fence_char == open_fence_char && parsed_fence_length >= open_fence_length && parsed_fence_tail ~ /^[ \t]*$/) {
          in_fence = 0
        }
        next
      }

      if ($0 ~ /^# Delivery contract[ \t]*$/) {
        section_count++
        in_contract = 1
        next
      }
      if ($0 ~ /^#/) {
        in_contract = 0
      }
      if (!in_contract) next

      if ($0 ~ /^[ \t]*$/) next
      if ($0 !~ /^- (task-tier|outcome|prove|player|parts|platform|correct):/) {
        finding("unknown delivery-contract line: " $0)
        next
      }

      line = $0
      sub(/^- /, "", line)
      name = line
      sub(/:.*/, "", name)
      value = line
      sub(/^[^:]*:[ \t]*/, "", value)
      value = trim(value)
      count[name]++
      saved[name] = value
    }

    END {
      if (section_count != 1) finding("expected exactly one # Delivery contract section, found " section_count)

      split("task-tier outcome prove player parts platform correct", names, " ")
      for (item = 1; item <= 7; item++) {
        name = names[item]
        if (count[name] > 1) finding("duplicate delivery-contract field: " name)
        if (count[name] == 1 && placeholder(saved[name])) finding("empty or placeholder delivery-contract field: " name)
      }

      if (count["task-tier"] == 0) finding("missing delivery-contract field: task-tier")
      if (count["outcome"] == 0) finding("missing delivery-contract field: outcome")

      tier = saved["task-tier"]
      if (count["task-tier"] == 1 && tier !~ /^(T0|T1|T2|T3|T4|T4\/T0|T4\/T1|T4\/T2|T4\/T3)$/) {
        finding("illegal task-tier: " tier)
      }

      outcome = saved["outcome"]
      if (count["outcome"] == 1 && !placeholder(outcome)) {
        arrow = index(outcome, "=>")
        if (arrow == 0) {
          finding("outcome must be <authoritative source pointer> => <observable result>")
        } else {
          source = trim(substr(outcome, 1, arrow - 1))
          result = trim(substr(outcome, arrow + 2))
          if (placeholder(source) || placeholder(result)) {
            finding("outcome must contain a non-placeholder source pointer and observable result")
          }
        }
      }

      base = tier
      correction = 0
      if (tier == "T4") {
        base = ""
        correction = 1
      } else if (tier ~ /^T4\//) {
        base = substr(tier, 4)
        correction = 1
      }

      if (base == "T2" && count["player"] != 1) finding("task-tier " tier " requires one player evidence line")
      if (base == "T3") {
        if (count["player"] != 1) finding("task-tier " tier " requires one player evidence line")
        if (count["parts"] != 1) finding("task-tier " tier " requires one parts evidence line")
      }
      if (correction && count["correct"] != 1) finding("task-tier " tier " requires one correct evidence line")
      if (!correction && count["correct"] > 0) finding("correct evidence requires the T4 correction overlay")
      if (base != "T3" && count["parts"] > 0) finding("parts evidence requires a T3 runtime tier")

      exit findings > 0 ? 1 : 0
    }
  ' "$BRIEF" || return 1

  outcome=$(field_value outcome)
  source=${outcome%%=>*}
  source=$(printf '%s\n' "$source" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  matched_receipt=$("$SCRIPT_DIR/fm-authority-receipts.sh" match "$BRIEF" "$source") || return 1
  if [ "$output_mode" = matched-receipt ] && [ -n "$matched_receipt" ]; then
    printf '%s\n' "$matched_receipt"
  fi
}

field_value() {
  field_name=$1
  awk -v wanted="$field_name" '
    function trim(value) {
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      return value
    }
    function parse_fence(line, text, char, run) {
      text = line
      sub(/^[ \t]*/, "", text)
      char = substr(text, 1, 1)
      if (char != "`" && char != "~") return 0
      run = 0
      while (substr(text, run + 1, 1) == char) run++
      if (run < 3) return 0
      parsed_fence_char = char
      parsed_fence_length = run
      parsed_fence_tail = substr(text, run + 1)
      return 1
    }
    {
      if (!in_fence) {
        if (parse_fence($0)) {
          in_fence = 1
          open_fence_char = parsed_fence_char
          open_fence_length = parsed_fence_length
          next
        }
      } else {
        if (parse_fence($0) && parsed_fence_char == open_fence_char && parsed_fence_length >= open_fence_length && parsed_fence_tail ~ /^[ \t]*$/) {
          in_fence = 0
        }
        next
      }
    }
    /^# Delivery contract[ \t]*$/ { in_contract = 1; next }
    in_contract && /^#/ { exit }
    in_contract && $0 ~ ("^- " wanted ":[ \t]*") {
      value = $0
      sub(/^[^:]*:[ \t]*/, "", value)
      print trim(value)
      exit
    }
  ' "$BRIEF"
}

render_review_intent() {
  matched_receipt=$(check_contract matched-receipt)
  tier=$(field_value task-tier)
  outcome=$(field_value outcome)

  printf '%s\n' 'Firstmate Designer -> Runtime -> Player selected review.'
  printf 'task-tier: %s\n' "$tier"
  printf 'outcome: %s\n' "$outcome"
  if [ -n "$matched_receipt" ]; then
    printf '%s\n' 'matched captain authority receipt:'
    printf '%s\n' "$matched_receipt"
  fi
  for evidence_name in prove player parts platform correct; do
    evidence_value=$(field_value "$evidence_name")
    [ -z "$evidence_value" ] || printf '%s: %s\n' "$evidence_name" "$evidence_value"
  done

  case "$tier" in
    T2|T4/T2)
      printf '%s\n' 'Required depth: inspect the ordinary player-path evidence on the final change; one execution may also be the focused proof when it is genuinely the same oracle.'
      ;;
    T3|T4/T3)
      printf '%s\n' 'Required depth: inspect the ordinary player path, causal evidence for every separable architecture-bearing part, and one full project regression on the final change.'
      ;;
    T4|T4/T0|T4/T1)
      printf '%s\n' 'Required depth: inspect bounded current authority-bearing owners and active descendants; live false canon must be corrected, while clearly labeled historical evidence may remain.'
      ;;
    *)
      printf '%s\n' 'Required depth: inspect the focused evidence actually warranted by this bounded task and do not demand empty evidence ceremony.'
      ;;
  esac

  case "$tier" in
    T4|T4/*)
      case "$tier" in
        T4|T4/T0|T4/T1) : ;;
        *) printf '%s\n' 'Also inspect the bounded correction search and permit clearly labeled historical evidence to remain.' ;;
      esac
      ;;
  esac

  printf '%s\n' 'Check the tier choice, exact outcome and source, executing control flow, actual evidence from the final diff, and whether the task was under-tiered.'
  printf '%s\n' 'A queued task, plan, report, comment, test, status line, or agent-authored brief remains a provisional claim and cannot become designer intent merely by being copied.'
  printf '%s\n' 'Return a mapped defect to the same worker when needed, but do not invent a new product target or require a second review role.'
}

case "$COMMAND" in
  check)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    check_contract
    ;;
  field)
    [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    case "$3" in
      task-tier|outcome|prove|player|parts|platform|correct) ;;
      *) echo "error: unknown delivery-contract field: $3" >&2; exit 2 ;;
    esac
    check_contract
    field_value "$3"
    ;;
  review-intent)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    render_review_intent
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
