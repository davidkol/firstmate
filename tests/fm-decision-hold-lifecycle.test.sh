#!/usr/bin/env bash
# End-to-end tests for durable captain-held decisions discovered by investigations
# and visual reviews.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TEARDOWN="$ROOT/bin/fm-teardown.sh"
BEARINGS="$ROOT/bin/fm-bearings-snapshot.sh"
TMP_ROOT=$(fm_test_tmproot fm-decision-hold)
TASKS_AXI_BIN=$(command -v tasks-axi || true)

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }
command -v tasks-axi >/dev/null 2>&1 || { echo "skip: tasks-axi not found"; exit 0; }

make_home() {  # <name>
  local home="$TMP_ROOT/$1" fakebin
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  cat > "$home/data/backlog.md" <<'EOF'
## In flight

## Queued

## Done
EOF
  fakebin=$(fm_fakebin "$home")
  fm_fake_exit0 "$fakebin" tmux treehouse no-mistakes gh gh-axi
  printf '%s\n' "$home"
}

run_bearings() {  # <home>
  local home=$1
  PATH="$home/fakebin:$PATH" FM_HOME="$home" FM_BEARINGS_NOW=2026-07-14T12:00:00Z \
    "$BEARINGS" --json
}

run_teardown() {  # <home> <id>
  local home=$1 id=$2
  PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$TEARDOWN" "$id"
}

# Reproduces the loss exactly with privacy-safe synthetic names: the investigation
# and visual review have ended, the only genuine unresolved decision is report prose,
# no held backlog item or open status exists, and the authoritative Bearings view
# correctly omits it. Completion must now refuse before teardown can erase the source.
test_uninventoried_report_decision_refuses_completion() {
  local home id json rc
  home=$(make_home omitted-decision)
  id=sample-route-review
  mkdir -p "$home/data/$id"
  cat > "$home/data/backlog.md" <<EOF
## In flight
- [ ] $id - Investigate sample routing (repo: sample) (kind: scout) (since 2026-07-14)

## Queued

## Done
EOF
  fm_write_meta "$home/state/$id.meta" \
    "window=firstmate:fm-$id" \
    "worktree=$home/projects/missing-scratch" \
    "project=$home/projects/sample" \
    "harness=codex" \
    "kind=scout" \
    "mode=scout"
  printf 'done: report and visual review complete\n' > "$home/state/$id.status"
  cat > "$home/data/$id/report.md" <<'EOF'
# Sample route review

The evidence is complete.
The captain still needs to choose route north or route south before follow-up work starts.
EOF

  json=$(run_bearings "$home") || fail "Bearings failed for unresolved-decision regression"
  printf '%s' "$json" | jq -e '
    (.decisions_open | length) == 0
      and (.gates | length) == 0
      and (.reports | any(.id == "sample-route-review"))
  ' >/dev/null || fail "the pre-policy omission shape was not reproduced: $json"

  set +e
  run_teardown "$home" "$id" > "$home/teardown.out" 2> "$home/teardown.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "completed investigation teardown erased a report-only unresolved decision"
  assert_present "$home/state/$id.meta" "refused completion must preserve investigation metadata"
  assert_grep "REFUSED" "$home/teardown.err" "refusal must be explicit"
  pass "report-only unresolved decision is reproduced and completion refuses before loss"
}

tasks_in() {  # <home> <tasks-axi args...>
  local home=$1
  shift
  (cd "$home" && tasks-axi "$@")
}

run_decisions() {  # <home> <command args...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-decision-hold.sh" "$@"
}

write_origin_meta() {  # <home> <id> [kind]
  local home=$1 id=$2 kind=${3:-scout}
  fm_write_meta "$home/state/$id.meta" \
    "window=firstmate:fm-$id" \
    "worktree=$home/projects/missing-$id" \
    "project=$home/projects/sample" \
    "harness=codex" \
    "kind=$kind" \
    "mode=$kind"
}

test_structured_holds_survive_teardown_and_route_resolution() {
  local home id route_hold access_hold before after json open show
  home=$(make_home durable-lifecycle)
  id=sample-systems-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Investigate sample systems" --kind scout --repo sample --start >/dev/null \
    || fail "could not create investigation backlog fixture"
  write_origin_meta "$home" "$id"
  cat > "$home/state/$id.status" <<'EOF'
needs-decision [key=route]: choose route north or route south
needs-decision [key=access]: choose open or restricted sample access
done: report and visual review complete
EOF
  cat > "$home/data/$id/report.md" <<'EOF'
# Sample systems review

Two choices remain unresolved: the route and the sample access level.
A separate recommendation is already resolved and requires no captain action.
EOF

  if run_decisions "$home" complete "$id" route access > "$home/early-complete.out" 2> "$home/early-complete.err"; then
    fail "completion succeeded before unresolved decisions had captain holds"
  fi
  assert_no_grep "decisions_reviewed=1" "$home/state/$id.meta" \
    "failed completion recorded a false completion attestation"

  route_hold=$(run_decisions "$home" hold "$id" route \
    --title "Choose the sample route" --reason "captain route choice pending" \
    --default "take route north" --repo sample) \
    || fail "could not register route hold"
  [ "$route_hold" = "$id-decision-route" ] || fail "route hold identity was not deterministic: $route_hold"
  run_decisions "$home" hold "$id" route \
    --title "Choose the sample route" --reason "captain route choice pending" \
    --default "take route north" --repo sample >/dev/null \
    || fail "idempotent hold retry failed"
  if run_decisions "$home" complete "$id" route access > "$home/partial-complete.out" 2> "$home/partial-complete.err"; then
    fail "completion succeeded while one of two distinct decisions lacked a hold"
  fi
  access_hold=$(run_decisions "$home" hold "$id" access \
    --title "Choose the sample access level" --reason "captain access choice pending" \
    --default "keep sample access restricted" --repo sample) \
    || fail "could not register access hold"
  [ "$access_hold" = "$id-decision-access" ] || fail "access hold identity was not distinct: $access_hold"
  [ "$(grep -cE "^- \[ \] $route_hold -" "$home/data/backlog.md")" = 1 ] \
    || fail "idempotent retry duplicated the route hold"
  [ "$(grep -cE "^- \[ \] $access_hold -" "$home/data/backlog.md")" = 1 ] \
    || fail "second decision did not retain one distinct backlog identity"

  run_decisions "$home" complete "$id" route access >/dev/null \
    || fail "shared investigation completion gate failed"
  assert_grep "decisions_reviewed=1" "$home/state/$id.meta" "completion attestation missing"
  assert_grep "decision_keys=access,route" "$home/state/$id.meta" "decision inventory was not deterministic"
  open=$(bash -c '. "$1"; status_open_decisions "$2"' _ \
    "$ROOT/bin/fm-classify-lib.sh" "$home/state/$id.status")
  [ -z "$open" ] || fail "captain-held transfer did not close duplicate live status decisions: $open"

  before=$(shasum -a 256 "$home/data/backlog.md" | awk '{print $1}')
  json=$(run_bearings "$home") || fail "Bearings failed with captain-held decisions"
  after=$(shasum -a 256 "$home/data/backlog.md" | awk '{print $1}')
  [ "$before" = "$after" ] || fail "Bearings mutated the authoritative backlog"
  printf '%s' "$json" | jq -e --arg route "$route_hold" --arg access "$access_hold" '
    (.decisions_open | any(.id == $route and .verb == "captain-hold" and .owner == "(main)"))
      and (.decisions_open | any(.id == $access and .verb == "captain-hold" and .owner == "(main)"))
      and (.gates | any(.id == $route or .id == $access) | not)
  ' >/dev/null || fail "Bearings did not surface structured captain holds: $json"

  run_teardown "$home" "$id" >/dev/null 2> "$home/teardown.err" \
    || fail "reviewed investigation teardown failed: $(cat "$home/teardown.err")"
  tasks_in "$home" "done" "$id" --report "data/$id/report.md" --keep 0 >/dev/null \
    || fail "could not archive completed investigation"
  ! grep -E "^- \[[ x]\] $id -" "$home/data/backlog.md" >/dev/null \
    || fail "origin remained in the live backlog after archival"
  grep -E "^- \[x\] $id -" "$home/data/done-archive.md" >/dev/null \
    || fail "origin was not durably archived"
  json=$(run_bearings "$home") || fail "Bearings failed after source teardown and archival"
  printf '%s' "$json" | jq -e --arg route "$route_hold" --arg access "$access_hold" '
    (.decisions_open | any(.id == $route and .verb == "captain-hold"))
      and (.decisions_open | any(.id == $access and .verb == "captain-hold"))
      and (.in_flight | any(.id == "sample-systems-review") | not)
  ' >/dev/null || fail "teardown or archival erased a captain-held decision: $json"

  tasks_in "$home" add sample-route-implementation "Apply the selected sample route" \
    --kind ship --repo sample >/dev/null \
    || fail "could not create dependent work fixture"
  printf 'Use route north for the sample system.\n' > "$home/route-decision.txt"
  if run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-implementation > "$home/early-resolve.out" 2> "$home/early-resolve.err"; then
    fail "captain hold closed before dependent work had a durable routing edge"
  fi
  show=$(tasks_in "$home" show "$route_hold" --full)
  assert_contains "$show" "state: queued" "failed routing attempt closed the hold"
  assert_contains "$show" "held: yes" "failed routing attempt released the hold"
  tasks_in "$home" block sample-route-implementation --by "$route_hold" >/dev/null \
    || fail "could not route dependent work behind the decision hold"
  tasks_in "$home" add sample-route-followup "Check the selected sample route" \
    --kind ship --repo sample --blocked-by "$route_hold" >/dev/null \
    || fail "could not create second dependent work fixture"
  cat > "$home/fakebin/tasks-axi" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = unblock ] && [ "${2:-}" = sample-route-implementation ] \
  && [ ! -f "$FM_HOME/unblock-failed-once" ]; then
  : > "$FM_HOME/unblock-failed-once"
  exit 1
fi
exec "$REAL_TASKS_AXI" "$@"
EOF
  chmod +x "$home/fakebin/tasks-axi"
  if run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-implementation --routed-to sample-route-followup \
    > "$home/partial-route.out" 2> "$home/partial-route.err"; then
    fail "resolution succeeded after a partial dependent-routing failure"
  fi
  show=$(tasks_in "$home" show "$route_hold" --full)
  assert_contains "$show" "state: queued" "partial routing failure closed the hold"
  show=$(tasks_in "$home" show sample-route-followup --full)
  assert_contains "$show" "blocked: no" "partial routing fixture did not release its first dependent"
  show=$(tasks_in "$home" show sample-route-implementation --full)
  assert_contains "$show" "blocked: yes" "partial routing fixture unexpectedly released its second dependent"
  if run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-followup > "$home/reduced-retry.out" 2> "$home/reduced-retry.err"; then
    fail "partial resolution retry accepted a reduced routed task set"
  fi
  printf 'Use route south for the sample system.\n' > "$home/changed-route-decision.txt"
  if run_decisions "$home" resolve "$id" route --decision-file "$home/changed-route-decision.txt" \
    --routed-to sample-route-implementation --routed-to sample-route-followup \
    > "$home/partial-drifted-decision.out" 2> "$home/partial-drifted-decision.err"; then
    fail "partial resolution retry accepted a different captain decision"
  fi
  tasks_in "$home" "done" sample-route-followup >/dev/null \
    || fail "could not complete already-routed dependent work"
  run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-implementation --routed-to sample-route-followup >/dev/null \
    || fail "could not resume and complete partial decision routing"
  run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-implementation --routed-to sample-route-followup >/dev/null \
    || fail "identical resolution retry was not idempotent"
  if run_decisions "$home" resolve "$id" route --decision-file "$home/changed-route-decision.txt" \
    --routed-to sample-route-implementation --routed-to sample-route-followup \
    > "$home/drifted-decision.out" 2> "$home/drifted-decision.err"; then
    fail "resolution retry accepted a different captain decision"
  fi
  if run_decisions "$home" resolve "$id" route --decision-file "$home/route-decision.txt" \
    --routed-to sample-route-implementation \
    > "$home/drifted-routes.out" 2> "$home/drifted-routes.err"; then
    fail "resolution retry accepted a different routed task set"
  fi
  show=$(tasks_in "$home" show "$route_hold" --full)
  assert_contains "$show" "state: done" "resolved hold did not close"
  assert_contains "$show" "Resolution recorded by fm-decision-hold" "resolved hold lost the decision record"
  show=$(tasks_in "$home" show sample-route-implementation --full)
  assert_contains "$show" "blocked: no" "recorded decision did not release dependent work"
  json=$(run_bearings "$home") || fail "Bearings failed after decision resolution"
  printf '%s' "$json" | jq -e --arg route "$route_hold" --arg access "$access_hold" '
    (.decisions_open | any(.id == $route) | not)
      and (.decisions_open | any(.id == $access and .verb == "captain-hold"))
      and (.gates | any(.id == "sample-route-implementation"))
      and (.decisions_open | any(.id == "sample-systems-review") | not)
  ' >/dev/null || fail "resolved or decision-like report prose produced a false hold: $json"
  pass "captain holds are idempotent, distinct, teardown-safe, Bearings-visible, and durably routed before close"
}

test_scout_teardown_always_requires_inventory_verification() {
  local home id
  home=$(make_home unconditional-teardown)
  id=sample-absent-review
  mkdir -p "$home/data/$id"
  write_origin_meta "$home" "$id"
  printf '# Sample absent review\n\nNo decision inventory was recorded.\n' > "$home/data/$id/report.md"
  if run_teardown "$home" "$id" > "$home/absent-teardown.out" 2> "$home/absent-teardown.err"; then
    fail "scout teardown skipped verification when its backlog task was absent"
  fi
  assert_present "$home/state/$id.meta" "refused absent-task teardown removed metadata"

  home=$(make_home unavailable-teardown)
  id=sample-unavailable-review
  mkdir -p "$home/data/$id"
  write_origin_meta "$home" "$id"
  printf '# Sample unavailable review\n\nNo decision inventory was recorded.\n' > "$home/data/$id/report.md"
  cat > "$home/fakebin/tasks-axi" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "$home/fakebin/tasks-axi"
  if run_teardown "$home" "$id" > "$home/unavailable-teardown.out" 2> "$home/unavailable-teardown.err"; then
    fail "scout teardown skipped verification when tasks-axi was unavailable"
  fi
  assert_present "$home/state/$id.meta" "refused unavailable-task teardown removed metadata"
  pass "non-forced scout teardown always requires durable inventory verification"
}

test_origin_slug_validation_precedes_path_construction() {
  local home escaped
  home=$(make_home origin-validation)
  escaped="$home/escaped-origin.meta"
  printf 'sentinel=unchanged\n' > "$escaped"
  if run_decisions "$home" complete ../escaped-origin --none \
    > "$home/invalid-complete.out" 2> "$home/invalid-complete.err"; then
    fail "completion accepted an origin path traversal"
  fi
  if run_decisions "$home" verify ../escaped-origin \
    > "$home/invalid-verify.out" 2> "$home/invalid-verify.err"; then
    fail "verification accepted an origin path traversal"
  fi
  [ "$(cat "$escaped")" = "sentinel=unchanged" ] \
    || fail "invalid origin changed metadata outside the state directory"
  pass "completion and verification validate origins before constructing paths"
}

test_visual_review_uses_shared_completion_owner() {
  local home id hold json
  home=$(make_home visual-review)
  id=sample-board-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review the sample board" --kind scout --repo sample --start >/dev/null
  write_origin_meta "$home" "$id"
  printf 'done: investigation complete\n' > "$home/state/$id.status"
  printf '# Sample board investigation\n\nThe initial findings need no captain choice.\n' > "$home/data/$id/report.md"
  run_decisions "$home" complete "$id" --none >/dev/null \
    || fail "initial investigation could not pass the shared completion owner"
  run_teardown "$home" "$id" >/dev/null 2> "$home/visual-teardown.err" \
    || fail "completed investigation teardown failed: $(cat "$home/visual-teardown.err")"
  tasks_in "$home" "done" "$id" --report "data/$id/report.md" --keep 0 >/dev/null

  mkdir -p "$home/.lavish"
  printf '<html><body>Synthetic sample board</body></html>\n' > "$home/.lavish/sample-board.html"
  hold=$(run_decisions "$home" hold "$id" layout \
    --title "Choose the sample layout" --reason "captain layout choice pending" \
    --default "keep the current sample layout" --repo sample) \
    || fail "post-teardown visual review could not use the shared hold owner"
  run_decisions "$home" complete "$id" layout >/dev/null \
    || fail "post-teardown visual review could not use the shared completion owner"
  [ "$hold" = "$id-decision-layout" ] || fail "visual review used a separate identity policy"
  json=$(run_bearings "$home") || fail "Bearings failed after the ended visual review"
  printf '%s' "$json" | jq -e --arg hold "$hold" '
    .decisions_open | any(.id == $hold and .verb == "captain-hold")
  ' >/dev/null || fail "ended visual review did not leave its durable Captain Call: $json"
  [ ! -e "$home/data/visual-review-decisions.json" ] \
    || fail "visual review created a second decision database"
  pass "ended visual review follows the same decision-hold completion owner"
}

test_none_inventory_and_resolved_prose_do_not_create_holds() {
  local home id json
  home=$(make_home no-false-holds)
  id=sample-resolved-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review a resolved sample finding" --kind scout --repo sample --start >/dev/null
  write_origin_meta "$home" "$id"
  printf 'resolved [key=old-choice]: the sample choice was already recorded\ndone: report complete\n' \
    > "$home/state/$id.status"
  cat > "$home/data/$id/report.md" <<'EOF'
# Resolved sample finding

Decision record: the earlier choice is resolved.
The recommendation is informational and needs no captain action.
EOF
  run_decisions "$home" complete "$id" --none >/dev/null \
    || fail "explicit no-decision inventory failed"
  json=$(run_bearings "$home") || fail "Bearings failed for no-decision inventory"
  printf '%s' "$json" | jq -e '
    (.decisions_open | any(.id | startswith("sample-resolved-review")) | not)
  ' >/dev/null || fail "resolved findings or decision-like prose created a false hold: $json"
  pass "resolved findings and decision-like prose do not create false holds"
}

test_terminal_single_owner_status_decision_does_not_block_empty_inventory() {
  local home id open secondmate
  home=$(make_home stale-terminal-decision)
  id=sample-terminal-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review a terminal sample finding" --kind scout --repo sample --start >/dev/null
  write_origin_meta "$home" "$id"
  printf 'needs-decision [key=default]: choose route A or route B\ndone: report complete\n' \
    > "$home/state/$id.status"
  printf '# Terminal sample review\n\nNo unresolved captain choice remains.\n' > "$home/data/$id/report.md"
  open=$(bash -c '. "$1"; status_open_decisions "$2"' _ \
    "$ROOT/bin/fm-classify-lib.sh" "$home/state/$id.status")
  assert_contains "$open" "default" "fixture must retain the raw stale status decision"
  run_decisions "$home" complete "$id" --none >/dev/null \
    || fail "terminal single-owner stale status decision blocked empty inventory completion"
  run_decisions "$home" verify "$id" >/dev/null \
    || fail "terminal single-owner stale status decision blocked inventory verification"
  run_teardown "$home" "$id" >/dev/null 2> "$home/terminal-teardown.err" \
    || fail "terminal single-owner stale status decision blocked teardown: $(cat "$home/terminal-teardown.err")"

  secondmate=sample-secondmate
  write_origin_meta "$home" "$secondmate" secondmate
  printf 'needs-decision [key=route]: choose route A or route B\ndone: heartbeat complete\n' \
    > "$home/state/$secondmate.status"
  if run_decisions "$home" complete "$secondmate" --none \
    > "$home/secondmate-terminal.out" 2> "$home/secondmate-terminal.err"; then
    fail "secondmate terminal status decision was incorrectly cleared"
  fi
  pass "terminal single-owner stale status decisions do not block empty inventory"
}

test_secondmate_hold_stays_in_authoritative_home() {
  local parent mate origin hold json
  parent=$(make_home main-routing)
  mate="$TMP_ROOT/sample-mate-home"
  mkdir -p "$mate/data" "$mate/state" "$mate/config" "$mate/projects" "$mate/bin"
  cp "$ROOT/.tasks.toml" "$mate/.tasks.toml"
  printf '# Synthetic secondmate home\n' > "$mate/AGENTS.md"
  printf 'sample-mate\n' > "$mate/.fm-secondmate-home"
  cat > "$mate/data/backlog.md" <<'EOF'
## In flight

## Queued

## Done
EOF
  fakebin=$(fm_fakebin "$mate")
  fm_fake_exit0 "$fakebin" tmux treehouse no-mistakes gh gh-axi
  origin=sample-mate-review
  mkdir -p "$mate/data/$origin"
  tasks_in "$mate" add "$origin" "Investigate secondmate sample" --kind scout --repo sample --start >/dev/null
  write_origin_meta "$mate" "$origin"
  printf 'done: report and visual review complete\n' > "$mate/state/$origin.status"
  printf '# Sample secondmate review\n\nOne captain choice remains.\n' > "$mate/data/$origin/report.md"
  hold=$(run_decisions "$mate" hold "$origin" release \
    --title "Choose the sample release" --reason "captain release choice pending" \
    --default "hold the sample release until the next window" --repo sample) \
    || fail "secondmate-owned hold creation failed"
  run_decisions "$mate" complete "$origin" release >/dev/null \
    || fail "secondmate-owned completion failed"
  run_teardown "$mate" "$origin" >/dev/null 2> "$mate/teardown.err" \
    || fail "secondmate investigation teardown failed: $(cat "$mate/teardown.err")"
  tasks_in "$mate" "done" "$origin" --report "data/$origin/report.md" --keep 0 >/dev/null

  printf -- '- sample-mate - synthetic scope (home: %s; scope: sample reviews; projects: sample; added 2026-07-14)\n' \
    "$mate" > "$parent/data/secondmates.md"
  fm_write_secondmate_meta "$parent/state/sample-mate.meta" "$mate" \
    "firstmate:fm-sample-mate" sample
  json=$(run_bearings "$parent") || fail "parent Bearings could not read secondmate hold"
  printf '%s' "$json" | jq -e --arg hold "$hold" '
    .decisions_open | any(.owner == "sample-mate" and .verb == "captain-hold" and (.id | endswith($hold)))
  ' >/dev/null || fail "secondmate captain hold did not surface with authoritative owner: $json"
  assert_no_grep "$hold" "$parent/data/backlog.md" "secondmate hold leaked into the main backlog"
  assert_grep "$hold" "$mate/data/backlog.md" "secondmate hold left its authoritative backlog"
  pass "main-home and secondmate-home captain holds remain correctly routed"
}

# tasks-axi quotes multi-entry blocked_by values as "a,b,c". resolve must strip
# those surrounding quotes before comma-boundary membership so the first and last
# list elements match, not only middle elements.
test_resolve_matches_quoted_blocked_by_edges() {
  local home origin hold_first hold_mid hold_last hold_absent show
  home=$(make_home quoted-blocked-by-edges)
  origin=sample-quote-review
  mkdir -p "$home/data/$origin"
  tasks_in "$home" add "$origin" "Quoted blocked_by edge review" --kind scout --repo sample --start >/dev/null \
    || fail "could not create quote-edge origin"
  write_origin_meta "$home" "$origin"
  printf 'done: report complete\n' > "$home/state/$origin.status"
  printf '# Quote edge review\n\nThree edge decisions and one absent control.\n' > "$home/data/$origin/report.md"

  hold_first=$(run_decisions "$home" hold "$origin" edge-first \
    --title "First edge decision" --reason "captain first pending" \
    --default "keep the first edge as built" --repo sample) \
    || fail "could not register first-edge hold"
  hold_mid=$(run_decisions "$home" hold "$origin" edge-mid \
    --title "Middle edge decision" --reason "captain mid pending" \
    --default "keep the middle edge as built" --repo sample) \
    || fail "could not register mid-edge hold"
  hold_last=$(run_decisions "$home" hold "$origin" edge-last \
    --title "Last edge decision" --reason "captain last pending" \
    --default "keep the last edge as built" --repo sample) \
    || fail "could not register last-edge hold"
  hold_absent=$(run_decisions "$home" hold "$origin" edge-absent \
    --title "Absent edge decision" --reason "captain absent pending" \
    --default "keep the absent edge as built" --repo sample) \
    || fail "could not register absent-edge hold"

  tasks_in "$home" add pad-a "Pad A" --kind ship --repo sample >/dev/null \
    || fail "could not create pad-a blocker"
  tasks_in "$home" add pad-b "Pad B" --kind ship --repo sample >/dev/null \
    || fail "could not create pad-b blocker"

  tasks_in "$home" add dep-first "Dep first position" --kind ship --repo sample >/dev/null \
    || fail "could not create first-position dependent"
  tasks_in "$home" block dep-first --by "$hold_first" >/dev/null || fail "could not block dep-first by first hold"
  tasks_in "$home" block dep-first --by pad-a >/dev/null || fail "could not block dep-first by pad-a"
  tasks_in "$home" block dep-first --by pad-b >/dev/null || fail "could not block dep-first by pad-b"
  show=$(tasks_in "$home" show dep-first --full)
  assert_contains "$show" "blocked_by: \"$hold_first,pad-a,pad-b\"" \
    "first-position fixture must quote multi-entry blocked_by"
  printf 'Decide first edge.\n' > "$home/d-first.txt"
  if ! run_decisions "$home" resolve "$origin" edge-first --decision-file "$home/d-first.txt" \
    --routed-to dep-first > "$home/first.out" 2> "$home/first.err"; then
    fail "resolve failed when hold id is FIRST in quoted blocked_by: $(cat "$home/first.err")"
  fi

  tasks_in "$home" add dep-mid "Dep mid position" --kind ship --repo sample >/dev/null \
    || fail "could not create mid-position dependent"
  tasks_in "$home" block dep-mid --by pad-a >/dev/null || fail "could not block dep-mid by pad-a"
  tasks_in "$home" block dep-mid --by "$hold_mid" >/dev/null || fail "could not block dep-mid by mid hold"
  tasks_in "$home" block dep-mid --by pad-b >/dev/null || fail "could not block dep-mid by pad-b"
  show=$(tasks_in "$home" show dep-mid --full)
  assert_contains "$show" "blocked_by: \"pad-a,$hold_mid,pad-b\"" \
    "middle-position fixture must quote multi-entry blocked_by"
  printf 'Decide mid edge.\n' > "$home/d-mid.txt"
  if ! run_decisions "$home" resolve "$origin" edge-mid --decision-file "$home/d-mid.txt" \
    --routed-to dep-mid > "$home/mid.out" 2> "$home/mid.err"; then
    fail "resolve failed when hold id is MIDDLE in quoted blocked_by: $(cat "$home/mid.err")"
  fi

  tasks_in "$home" add dep-last "Dep last position" --kind ship --repo sample >/dev/null \
    || fail "could not create last-position dependent"
  tasks_in "$home" block dep-last --by pad-a >/dev/null || fail "could not block dep-last by pad-a"
  tasks_in "$home" block dep-last --by pad-b >/dev/null || fail "could not block dep-last by pad-b"
  tasks_in "$home" block dep-last --by "$hold_last" >/dev/null || fail "could not block dep-last by last hold"
  show=$(tasks_in "$home" show dep-last --full)
  assert_contains "$show" "blocked_by: \"pad-a,pad-b,$hold_last\"" \
    "last-position fixture must quote multi-entry blocked_by"
  printf 'Decide last edge.\n' > "$home/d-last.txt"
  if ! run_decisions "$home" resolve "$origin" edge-last --decision-file "$home/d-last.txt" \
    --routed-to dep-last > "$home/last.out" 2> "$home/last.err"; then
    fail "resolve failed when hold id is LAST in quoted blocked_by: $(cat "$home/last.err")"
  fi

  tasks_in "$home" add dep-absent "Dep absent control" --kind ship --repo sample >/dev/null \
    || fail "could not create absent-control dependent"
  tasks_in "$home" block dep-absent --by pad-a >/dev/null || fail "could not block dep-absent by pad-a"
  tasks_in "$home" block dep-absent --by pad-b >/dev/null || fail "could not block dep-absent by pad-b"
  show=$(tasks_in "$home" show dep-absent --full)
  assert_contains "$show" "blocked_by: \"pad-a,pad-b\"" \
    "absent-control fixture must quote multi-entry blocked_by without the hold id"
  printf 'Decide absent edge.\n' > "$home/d-absent.txt"
  if run_decisions "$home" resolve "$origin" edge-absent --decision-file "$home/d-absent.txt" \
    --routed-to dep-absent > "$home/absent.out" 2> "$home/absent.err"; then
    fail "resolve succeeded when hold id is genuinely absent from blocked_by"
  fi
  assert_grep "not durably blocked by" "$home/absent.err" \
    "absent id must fail with durable-block error"
  show=$(tasks_in "$home" show "$hold_absent" --full)
  assert_contains "$show" "state: queued" "failed absent resolve must leave the hold open"
  assert_contains "$show" "held: yes" "failed absent resolve must leave the hold held"

  pass "resolve matches first/middle/last in quoted blocked_by and rejects a genuinely absent id"
}

# A captain question with no stated default is the shape that leaves the queue
# blocked while it waits, so `hold` must refuse it before creating any backlog
# identity, and a question that cannot be answered without playing the build must
# be separable from one answerable at a desk.
test_stated_default_and_desk_play_split() {
  local home id play_hold desk_hold rows before after
  home=$(make_home stated-default)
  id=sample-feel-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review the sample feel" --kind scout --repo sample --start >/dev/null \
    || fail "could not create stated-default origin"
  write_origin_meta "$home" "$id"
  printf 'done: report complete\n' > "$home/state/$id.status"
  printf '# Sample feel review\n\nOne desk choice and one play choice remain.\n' > "$home/data/$id/report.md"

  if run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" --repo sample \
    > "$home/no-default.out" 2> "$home/no-default.err"; then
    fail "hold accepted a captain question with no stated default"
  fi
  assert_grep "--default is required" "$home/no-default.err" "refusal must name the missing default"
  assert_no_grep "$id-decision-burn-cost" "$home/data/backlog.md" \
    "refused hold created a backlog identity before validation"

  if run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" \
    --default "keep the shipped shove (unchanged)" --repo sample \
    > "$home/paren-default.out" 2> "$home/paren-default.err"; then
    fail "hold accepted a default containing parentheses that tasks-axi rejects"
  fi
  if run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" \
    --default "keep it | answerable: desk" --repo sample \
    > "$home/marker-default.out" 2> "$home/marker-default.err"; then
    fail "hold accepted a default that forges the stored answerable marker"
  fi
  if run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" \
    --default "keep the shipped shove, tune it later" --repo sample \
    > "$home/comma-default.out" 2> "$home/comma-default.err"; then
    fail "hold accepted a default whose comma truncates the stored hold field"
  fi
  assert_grep "must not contain commas" "$home/comma-default.err" \
    "the comma refusal must name the constraint"
  if run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" \
    --default "keep the shipped shove" --answerable maybe --repo sample \
    > "$home/bad-axis.out" 2> "$home/bad-axis.err"; then
    fail "hold accepted an answerable value outside desk and play"
  fi
  assert_no_grep "$id-decision-burn-cost" "$home/data/backlog.md" \
    "a refused hold left a backlog identity behind"

  play_hold=$(run_decisions "$home" hold "$id" burn-cost \
    --title "Choose the sample burn cost" --reason "captain burn cost pending" \
    --default "keep the shipped shove and tune later" --answerable play --repo sample) \
    || fail "could not register a play question"
  desk_hold=$(run_decisions "$home" hold "$id" adopt-process \
    --title "Adopt the sample process" --reason "captain process choice pending" \
    --default "adopt the first four sections only" --repo sample) \
    || fail "could not register a desk question"
  assert_grep "hold: captain burn cost pending | default if unanswered: keep the shipped shove and tune later | answerable: play" \
    "$home/data/backlog.md" "the play hold did not store its default and axis in the backlog"
  assert_grep "hold: captain process choice pending | default if unanswered: adopt the first four sections only | answerable: desk" \
    "$home/data/backlog.md" "an unspecified axis did not fall back to the safe desk value"

  rows=$(run_decisions "$home" list) || fail "list failed"
  [ "$(printf '%s\n' "$rows" | head -1)" = "$(printf 'play\t%s\tkeep the shipped shove and tune later\tChoose the sample burn cost' "$play_hold")" ] \
    || fail "list did not put the play question first with its stated default: $rows"
  [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 2 ] || fail "list did not return both questions: $rows"
  rows=$(run_decisions "$home" list --answerable play) || fail "play-only list failed"
  [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 1 ] || fail "play-only list was not separable: $rows"
  assert_contains "$rows" "$play_hold" "play-only list lost the play question"
  rows=$(run_decisions "$home" list --answerable desk) || fail "desk-only list failed"
  [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 1 ] || fail "desk-only list was not separable: $rows"
  assert_contains "$rows" "$desk_hold" "desk-only list lost the desk question"
  if run_decisions "$home" list --answerable playtest > "$home/bad-list.out" 2> "$home/bad-list.err"; then
    fail "list accepted an answerable value outside desk and play"
  fi

  # The teardown gate is the enforced part of this contract and must still hold.
  if run_teardown "$home" "$id" > "$home/ungated.out" 2> "$home/ungated.err"; then
    fail "teardown erased an investigation whose questions were not yet inventoried"
  fi
  run_decisions "$home" complete "$id" burn-cost adopt-process >/dev/null \
    || fail "completion failed with stated defaults recorded"
  run_decisions "$home" verify "$id" >/dev/null || fail "verification failed with stated defaults recorded"
  run_teardown "$home" "$id" >/dev/null 2> "$home/gated.err" \
    || fail "inventoried investigation teardown failed: $(cat "$home/gated.err")"

  before=$(tasks_in "$home" show "$play_hold" --full | grep '^  hold_reason:')
  tasks_in "$home" add sample-burn-work "Apply the sample burn cost" --kind ship --repo sample \
    --blocked-by "$play_hold" >/dev/null || fail "could not create dependent work"
  printf 'A sample burn knocks a grounded crewmate down.\n' > "$home/burn-decision.txt"
  run_decisions "$home" resolve "$id" burn-cost --decision-file "$home/burn-decision.txt" \
    --routed-to sample-burn-work >/dev/null || fail "could not resolve the play question"
  after=$(tasks_in "$home" show "$play_hold" --full | grep '^  hold_reason:')
  [ "$before" = "$after" ] \
    || fail "resolution changed the stated default or the answerable axis: $before -> $after"
  assert_contains "$after" "default if unanswered: keep the shipped shove and tune later" \
    "the resolved hold lost its stated default"
  pass "every captain question carries a stated default and a desk or play axis through resolution"
}

# The 27 captain questions already on the board were created before defaults
# existed. They must keep listing, completing, verifying, gating teardown and
# resolving, and nothing here may rewrite their bodies.
test_holds_without_a_stated_default_keep_working() {
  local home id legacy body_before body_after row
  home=$(make_home legacy-holds)
  id=sample-legacy-review
  legacy="$id-decision-legacy-choice"
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review the sample legacy surface" --kind scout --repo sample --start >/dev/null \
    || fail "could not create legacy origin"
  write_origin_meta "$home" "$id"
  printf 'done: report complete\n' > "$home/state/$id.status"
  printf '# Sample legacy review\n\nOne pre-existing captain choice remains.\n' > "$home/data/$id/report.md"

  # Exactly what the pre-default script wrote: no default, no answerable marker.
  tasks_in "$home" add "$legacy" "Choose the sample legacy option" --kind captain --repo sample \
    --body "$(printf 'Origin: %s\nDecision key: legacy-choice\nState: awaiting captain decision.' "$id")" >/dev/null \
    || fail "could not create the pre-default hold fixture"
  tasks_in "$home" hold "$legacy" --reason "captain legacy choice pending" --kind captain >/dev/null \
    || fail "could not activate the pre-default hold fixture"
  body_before=$(tasks_in "$home" show "$legacy" --full | grep '^  body:')

  row=$(run_decisions "$home" list) || fail "list failed on a hold with no stated default"
  [ "$row" = "$(printf 'desk\t%s\t-\tChoose the sample legacy option' "$legacy")" ] \
    || fail "a hold with no stated default did not read back as a desk question: $row"
  [ -z "$(run_decisions "$home" list --answerable play)" ] \
    || fail "a hold with no stated default was mistaken for a play question"

  run_decisions "$home" complete "$id" legacy-choice >/dev/null \
    || fail "completion failed for a hold with no stated default"
  run_decisions "$home" verify "$id" >/dev/null \
    || fail "verification failed for a hold with no stated default"
  run_teardown "$home" "$id" >/dev/null 2> "$home/legacy-teardown.err" \
    || fail "teardown failed for a hold with no stated default: $(cat "$home/legacy-teardown.err")"
  body_after=$(tasks_in "$home" show "$legacy" --full | grep '^  body:')
  [ "$body_before" = "$body_after" ] || fail "a read path rewrote a pre-existing hold body: $body_after"
  assert_grep "hold: captain legacy choice pending)" "$home/data/backlog.md" \
    "a read path rewrote a pre-existing hold reason"

  # Re-holding a pre-existing question adds the missing default in place.
  run_decisions "$home" hold "$id" legacy-choice \
    --title "Choose the sample legacy option" --reason "captain legacy choice pending" \
    --default "keep the current sample legacy option" --repo sample >/dev/null \
    || fail "could not add a stated default to a pre-existing hold"
  body_after=$(tasks_in "$home" show "$legacy" --full | grep '^  body:')
  [ "$body_before" = "$body_after" ] || fail "adding a stated default rewrote the pre-existing body: $body_after"
  assert_grep "hold: captain legacy choice pending | default if unanswered: keep the current sample legacy option | answerable: desk" \
    "$home/data/backlog.md" "re-holding did not add the stated default in place"

  tasks_in "$home" add sample-legacy-work "Apply the sample legacy option" --kind ship --repo sample \
    --blocked-by "$legacy" >/dev/null || fail "could not create legacy dependent work"
  printf 'Keep the current sample legacy option.\n' > "$home/legacy-decision.txt"
  run_decisions "$home" resolve "$id" legacy-choice --decision-file "$home/legacy-decision.txt" \
    --routed-to sample-legacy-work >/dev/null || fail "could not resolve a pre-existing hold"
  pass "captain questions created before stated defaults keep working and keep their bodies"
}

# `list` is the captain-facing question view, so it omits a hold whose hold kind
# is not captain and a hold tasks-axi still reports as blocked. A parked or
# load-gated backlog item and a question whose prerequisite work is unfinished
# are not waiting questions. Once pruning archives a Done blocker out of the
# backlog the two readiness views part company on purpose, and the deliberate
# direction is to show the question rather than hide it.
test_list_omits_other_hold_kinds_and_blocked_questions() {
  local home id open_hold blocked_hold parked_hold load_hold rows
  home=$(make_home list-invariants)
  id=sample-list-review
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "Review the sample list surface" --kind scout --repo sample --start >/dev/null \
    || fail "could not create list-invariant origin"
  write_origin_meta "$home" "$id"
  printf 'done: report complete\n' > "$home/state/$id.status"
  printf '# Sample list review\n\nOne waiting question, one blocked question, two other hold kinds.\n' \
    > "$home/data/$id/report.md"

  open_hold=$(run_decisions "$home" hold "$id" open-choice \
    --title "Choose the open sample option" --reason "captain open choice pending" \
    --default "keep the current sample option" --answerable play --repo sample) \
    || fail "could not register the waiting question"
  blocked_hold=$(run_decisions "$home" hold "$id" blocked-choice \
    --title "Choose the blocked sample option" --reason "captain blocked choice pending" \
    --default "keep the blocked sample option" --answerable play --repo sample) \
    || fail "could not register the blocked question"
  tasks_in "$home" add sample-prerequisite "Finish the sample prerequisite" --kind ship --repo sample >/dev/null \
    || fail "could not create the prerequisite fixture"
  tasks_in "$home" block "$blocked_hold" --by sample-prerequisite >/dev/null \
    || fail "could not block a captain question behind unfinished work"

  parked_hold="$id-decision-parked-choice"
  tasks_in "$home" add "$parked_hold" "Parked sample backlog item" --kind captain --repo sample >/dev/null \
    || fail "could not create the parked fixture"
  tasks_in "$home" hold "$parked_hold" --reason "parked until the next window" --kind parked >/dev/null \
    || fail "could not park the fixture"
  load_hold="$id-decision-load-choice"
  tasks_in "$home" add "$load_hold" "Load-gated sample backlog item" --kind captain --repo sample >/dev/null \
    || fail "could not create the load-gated fixture"
  tasks_in "$home" hold "$load_hold" --reason "waiting on fleet load" --kind load >/dev/null \
    || fail "could not load-gate the fixture"
  [ "$(tasks_in "$home" list --state held --kind captain | grep -cE "^  ($parked_hold|$load_hold|$blocked_hold),")" = 3 ] \
    || fail "the fixture must reproduce the raw listing that returns all four items"

  rows=$(run_decisions "$home" list) || fail "list failed with other hold kinds and a blocked question on the board"
  [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 1 ] \
    || fail "list did not omit the other hold kinds and the blocked question: $rows"
  assert_contains "$rows" "$open_hold" "list lost the one waiting question"
  assert_not_contains "$rows" "$parked_hold" "a parked backlog item was printed as a waiting question"
  assert_not_contains "$rows" "$load_hold" "a load-gated backlog item was printed as a waiting question"
  assert_not_contains "$rows" "$blocked_hold" "a question with unfinished prerequisite work was printed as waiting"
  rows=$(run_decisions "$home" list --answerable play) || fail "play-only list failed"
  assert_not_contains "$rows" "$blocked_hold" "a blocked play question was relayed as its own group"
  [ -z "$(run_decisions "$home" list --answerable desk)" ] \
    || fail "an item held for another reason surfaced as a desk question"

  tasks_in "$home" "done" sample-prerequisite >/dev/null \
    || fail "could not complete the prerequisite work"
  rows=$(run_decisions "$home" list --answerable play) || fail "play-only list failed after the blocker cleared"
  assert_contains "$rows" "$blocked_hold" "a question did not become a waiting question once its blocker was done"

  tasks_in "$home" prune --keep 0 >/dev/null || fail "could not archive the completed prerequisite"
  assert_grep "blocked-by: sample-prerequisite" "$home/data/backlog.md" \
    "the pruned-blocker fixture must retain the stale edge the fleet snapshot still reads"
  rows=$(run_decisions "$home" list --answerable play) || fail "play-only list failed after the blocker was pruned"
  assert_contains "$rows" "$blocked_hold" \
    "a question was hidden after routine pruning archived its finished blocker"
  pass "list shows captain-held questions once tasks-axi reports their blockers cleared"
}

test_uninventoried_report_decision_refuses_completion

test_scout_teardown_always_requires_inventory_verification
test_structured_holds_survive_teardown_and_route_resolution
test_origin_slug_validation_precedes_path_construction
test_visual_review_uses_shared_completion_owner
test_none_inventory_and_resolved_prose_do_not_create_holds
test_terminal_single_owner_status_decision_does_not_block_empty_inventory
test_secondmate_hold_stays_in_authoritative_home
test_resolve_matches_quoted_blocked_by_edges
test_stated_default_and_desk_play_split
test_holds_without_a_stated_default_keep_working
test_list_omits_other_hold_kinds_and_blocked_questions
