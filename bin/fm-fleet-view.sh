#!/usr/bin/env bash
# fm-fleet-view.sh - concise human status and detailed diagnostics over the
# canonical fleet snapshot.
#
# The default status deliberately counts only current-state-backed work
# (run-step or semantic busy evidence). A status-log-only working event stays
# visible but is explicitly unverified, and inactive metadata becomes a
# reconciliation record rather than inflating the active-work count.
# --details retains the fuller operator diagnostic view. Neither path parses
# raw fleet state itself; both render fm-fleet-snapshot.sh --json.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
usage: fm-fleet-view.sh [--json|--details]

Render a concise human fleet status from fm-fleet-snapshot.sh.
Use --details for the full operator diagnostic view, or --json to print the
underlying snapshot.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --json) "$SCRIPT_DIR/fm-fleet-snapshot.sh" --json; exit $? ;;
  --details) VIEW_MODE=details ;;
  "") VIEW_MODE=status ;;
  *) usage >&2; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "fm-fleet-view: jq not found" >&2; exit 1; }

SNAPSHOT=$("$SCRIPT_DIR/fm-fleet-snapshot.sh" --json) || exit $?

render_status() {
  printf '%s\n' "$SNAPSHOT" | jq -r '
    def dash($v): if $v == null or $v == "" then "-" else $v end;
    def title_of($t): $t.backlog.title // $t.id;
    def repo_of($t): dash($t.backlog.repo // $t.project);
    def line($t): "- \(title_of($t)) (\(repo_of($t))) [\($t.id)]";
    def active:
      .current_state.state == "working"
      and (.current_state.source == "run-step" or .current_state.source == "pane");
    def reported_working:
      .current_state.state == "working" and .current_state.source == "status-log";
    def completed_investigation:
      .kind == "scout" and .current_state.state == "done";
    def attention:
      .current_state.state == "parked"
      or .current_state.state == "blocked"
      or .current_state.state == "paused"
      or .current_state.state == "failed";
    def attention_note($t):
      if $t.hints.pending_decision then "needs a decision"
      elif $t.current_state.state == "parked" then "waiting at a review gate"
      elif $t.current_state.state == "paused" then "waiting externally"
      else $t.current_state.state end;
    def record_list($rows):
      ($rows[0:5] | map("\(.id) (\(.current_state.state))") | join(", ")) as $shown
      | if ($rows | length) > 5
        then $shown + ", +" + ((($rows | length) - 5) | tostring) + " more"
        else $shown end;
    ([.tasks[] | select(active)]) as $active
    | ([.tasks[] | select(reported_working)]) as $reported
    | ([.tasks[] | select(completed_investigation)]) as $completed
    | ([.tasks[] | select(attention)]) as $attention
    | ([.tasks[] | select((active or reported_working or completed_investigation or attention) | not)]) as $reconcile
    | [
        "# Fleet Status",
        "",
        (if ($active | length) == 0 then
           "Active work: none."
         else
           "Active work (\($active | length)):",
           ($active[] | line(.))
         end),
        (if ($reported | length) == 0 then empty else
           "",
           "Reported working, not verified (\($reported | length)):",
           ($reported[] | "\(line(.)) - reports working only from its status log.")
         end),
        (if ($attention | length) == 0 then empty else
           "",
           "Needs attention (\($attention | length)):",
           ($attention[] | "\(line(.)) - \(attention_note(.)).")
         end),
        (if ($completed | length) == 0 then empty else
           "",
           "Completed investigations (\($completed | length)):",
           ($completed[] | line(.))
         end),
        "",
        (if ($reconcile | length) == 0 then
           "Task records needing reconciliation: none."
         else
           "Task records needing reconciliation (\($reconcile | length)): \(record_list($reconcile))."
         end),
        "Details: bin/fm-fleet-view.sh --details"
      ]
    | .[]
  '
}

render_details() {
  printf '%s\n' "$SNAPSHOT" | jq -r '
  def dash($v): if $v == null or $v == "" then "-" else $v end;
  def endpoint_exists($t):
    if $t.endpoint.exists == null then "unknown"
    elif $t.endpoint.exists then "present"
    else "absent" end;
  def endpoint_of($t):
    if $t.kind == "secondmate" then "\(endpoint_exists($t)) / \($t.endpoint.agent_alive)"
    else endpoint_exists($t) end;
  def artifact($t):
    if $t.pr.url != null then $t.pr.url
    elif $t.paths.report.present then $t.paths.report.path
    else "-" end;
  def path_of($t):
    if $t.paths.home.present then $t.paths.home.path
    elif $t.paths.home.path != null then $t.paths.home.path + " (absent)"
    elif $t.paths.worktree.present then $t.paths.worktree.path
    elif $t.paths.worktree.path != null then $t.paths.worktree.path + " (absent)"
    else "-" end;
  def action_of($t):
    if $t.kind == "secondmate" then "\($t.actions.send) - \($t.actions.watch)"
    else $t.actions.watch end;
  def task_row($t):
    "| \($t.id) | \($t.current_state.state) / \($t.current_state.source) | \($t.kind) | \(dash($t.backlog.repo // $t.project)) | \($t.backend) | \(endpoint_of($t)) | \(artifact($t)) | \(path_of($t)) | \(action_of($t)) |";
  def blocker($r):
    if ($r.blocked_by // "") == "" then "-"
    elif ($r.blocked_reason // "") == "" then $r.blocked_by
    else "\($r.blocked_by) - \($r.blocked_reason)" end;
  def backlog_row($r):
    "| \($r.id // "-") | \(dash($r.title // $r.raw)) | \(dash($r.repo)) | \(dash($r.kind)) | \(blocker($r)) | \(dash($r.pr_url // $r.report_path // $r.local_note)) |";

  "# Fleet Diagnostics",
  "",
  "Schema: \(.schema)",
  "Home: \(.fm_home)",
  "",
  "## Task Records",
  (if (.tasks | length) == 0 then
    "No live task metadata found."
   else
    "| ID | Current | Kind | Repo/Project | Backend | Endpoint | Artifact | Path | Watch / return channel |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    (.tasks[] | task_row(.))
   end),
  "",
  "## Queued",
  (if ([.backlog.records[]? | select(.state == "queued")] | length) == 0 then
    "No queued backlog records found."
   else
    "| ID | Title | Repo | Kind | Blocked By | Artifact |",
    "| --- | --- | --- | --- | --- | --- |",
    (.backlog.records[] | select(.state == "queued") | backlog_row(.))
   end),
  "",
  "## Done",
  (if ([.backlog.records[]? | select(.state == "done")] | length) == 0 then
    "No done backlog records found."
   else
    "| ID | Title | Repo | Kind | Blocked By | Artifact |",
    "| --- | --- | --- | --- | --- | --- |",
    (.backlog.records[] | select(.state == "done") | backlog_row(.))
   end),
  "",
  "## Secondmates",
  .secondmate_guidance.note
'
}

case "$VIEW_MODE" in
  status) render_status ;;
  details) render_details ;;
esac
