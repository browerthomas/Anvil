#!/usr/bin/env bash
# anvil/grind — append-only event log + snapshot fold for per-plan execution state.
#
# Storage: .anvil/grind-events.jsonl  (append-only, one JSON event per line)
#          .anvil/grind-snapshot.json  (auto-derived snapshot, never edited by hand)
#
# Event shape:
#   {"t": "<iso-ts>", "ev": "<event-type>", "slice": "<id>", "data": {...}}
#
# Event types:
#   plan-init       — plan loaded; data has slice list + deps
#   slice-pending   — slice queued (initial state)
#   slice-in-flight — agent dispatched; data has agent_id, worktree
#   slice-pr-opened — agent returned a PR; data has pr_number
#   slice-reviewed  — review pass complete; data has findings count
#   slice-merged    — auto-merge succeeded
#   slice-deferred  — slice paused/skipped; data has reason
#   slice-skipped   — operator-paced or rejected
#   issue-filed     — follow-up issue tracked
#   decision        — operator-decision invoked; data has verb, free-text, outcome
#
# Usage:
#   state.sh init <plan-path>             # write plan-init event from plan
#   state.sh next                         # print next ready slice id
#   state.sh ready                        # print all ready slices
#   state.sh mark <slice-id> <type>       # append a slice-<type> event
#   state.sh set-pr <slice-id> <pr-num>   # append slice-pr-opened
#   state.sh decision <slice-id> <verb> <outcome> "<free-text>"
#   state.sh add-issue <number>
#   state.sh status                       # human-readable progress (folded snapshot)
#   state.sh trace [slice-id]             # print event log (filtered to slice if given)
#   state.sh snapshot                     # rebuild + print snapshot from event log
#   state.sh replay <slice-id>            # rewind: write a slice-pending event for slice-id

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
ANVIL_DIR="$REPO_ROOT/.anvil"
EVENTS_FILE="$ANVIL_DIR/grind-events.jsonl"
SNAPSHOT_FILE="$ANVIL_DIR/grind-snapshot.json"

ensure_events_file() {
  if [ ! -f "$EVENTS_FILE" ]; then
    av_fail "event log not initialized — run: state.sh init <plan-path>"
    exit 1
  fi
}

# Append a single event line to the event log.
emit_event() {
  local ev="$1" slice="$2" data="$3"
  mkdir -p "$ANVIL_DIR"
  local frame
  frame=$(jq -nc \
    --arg t "$(av_iso_now)" \
    --arg ev "$ev" \
    --arg slice "$slice" \
    --argjson data "${data:-null}" \
    '{t:$t, ev:$ev, slice:$slice, data:$data}')
  echo "$frame" >> "$EVENTS_FILE"
  refresh_snapshot
}

# Fold all events into a snapshot view + write to grind-snapshot.json.
refresh_snapshot() {
  jq -s '
    # Find plan-init
    (map(select(.ev == "plan-init")) | last) as $init
    | ($init.data.slices // {}) as $slices
    | (map(select(.ev == "issue-filed")) | map(.data.number) | unique) as $issues
    | (map(select(.ev | startswith("slice-") or . == "decision"))) as $slice_events
    | reduce $slice_events[] as $e (
        {plan_path: ($init.data.plan_path // null), started_at: ($init.t // null), slices: $slices, issues_filed: $issues, decisions: []};
        if $e.ev == "slice-in-flight"  then .slices[$e.slice].status = "in-flight"  | .slices[$e.slice].agent_id = $e.data.agent_id | .slices[$e.slice].worktree = $e.data.worktree | .slices[$e.slice].dispatched_at = $e.t
        elif $e.ev == "slice-pr-opened" then .slices[$e.slice].pr = $e.data.pr_number | .slices[$e.slice].pr_at = $e.t
        elif $e.ev == "slice-reviewed"  then .slices[$e.slice].review = $e.data | .slices[$e.slice].reviewed_at = $e.t
        elif $e.ev == "slice-merged"    then .slices[$e.slice].status = "merged"    | .slices[$e.slice].merged_at = $e.t
        elif $e.ev == "slice-deferred"  then .slices[$e.slice].status = "deferred"  | .slices[$e.slice].deferred_at = $e.t | .slices[$e.slice].defer_reason = $e.data.reason
        elif $e.ev == "slice-skipped"   then .slices[$e.slice].status = "skipped"   | .slices[$e.slice].skipped_at = $e.t
        elif $e.ev == "slice-pending"   then .slices[$e.slice].status = "pending"
        elif $e.ev == "decision"        then .decisions += [{slice: $e.slice, t: $e.t, verb: $e.data.verb, outcome: $e.data.outcome, response: $e.data.response}]
        else . end
      )
  ' "$EVENTS_FILE" > "$SNAPSHOT_FILE"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  init)
    plan_path="${1:-}"
    if [ -z "$plan_path" ]; then
      av_fail "usage: state.sh init <plan-path>"
      exit 1
    fi

    # Plan can be a flat file OR a folder (OpenSpec-style layout).
    # Folder must contain tasks.md with the slice manifest.
    if [ -d "$plan_path" ]; then
      # Folder layout
      tasks_file="$plan_path/tasks.md"
      if [ ! -f "$tasks_file" ]; then
        av_fail "folder plan must contain tasks.md (got: $plan_path)"
        exit 1
      fi
      yaml_source="$tasks_file"
      av_info "loaded folder plan: $plan_path"
    elif [ -f "$plan_path" ]; then
      # Flat file layout
      yaml_source="$plan_path"
      av_info "loaded flat plan: $plan_path"
    else
      av_fail "plan not found (neither file nor folder): $plan_path"
      exit 1
    fi
    mkdir -p "$ANVIL_DIR"

    # Extract YAML manifest from plan
    yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){print; exit}; next} flag {print}' "$yaml_source")
    if ! echo "$yaml" | grep -q "slices:"; then
      av_fail "plan does not contain a slices: YAML block (looked in $yaml_source)"
      exit 1
    fi

    if command -v yq >/dev/null 2>&1; then
      slices_json=$(echo "$yaml" | yq -o=json)
    elif command -v python3 >/dev/null 2>&1; then
      slices_json=$(echo "$yaml" | python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin)))' 2>/dev/null)
    else
      av_fail "need yq or python3+pyyaml to parse plan YAML"
      exit 1
    fi
    [ -z "$slices_json" ] && { av_fail "could not parse plan YAML"; exit 1; }

    # Build the plan-init payload
    init_payload=$(jq -nc --arg plan "$plan_path" --argjson sj "$slices_json" '
      {plan_path: $plan, slices: ($sj.slices | map({key: .id, value: {
        status: "pending",
        depends_on: (.["depends-on"] // []),
        operator_paced: (.["operator-paced"] // false)
      }}) | from_entries)}
    ')

    # Truncate event log + emit fresh plan-init
    : > "$EVENTS_FILE"
    emit_event "plan-init" "" "$init_payload"

    # Emit a slice-pending for each slice
    for sid in $(jq -r '.slices | keys[]' "$SNAPSHOT_FILE"); do
      emit_event "slice-pending" "$sid" "null"
    done

    av_ok "event log initialized at $EVENTS_FILE"
    n=$(jq '.slices | length' "$SNAPSHOT_FILE")
    echo "  $n slices loaded"
    ;;

  next)
    ensure_events_file
    refresh_snapshot
    jq -r '
      .slices as $s
      | $s | to_entries
      | map(select(.value.status == "pending" and .value.operator_paced == false))
      | map(select((.value.depends_on // []) | all($s[.] .status == "merged")))
      | (first // empty).key // empty
    ' "$SNAPSHOT_FILE"
    ;;

  ready)
    ensure_events_file
    refresh_snapshot
    jq -r '
      .slices as $s
      | $s | to_entries
      | map(select(.value.status == "pending" and .value.operator_paced == false))
      | map(select((.value.depends_on // []) | all($s[.] .status == "merged")))
      | .[] .key
    ' "$SNAPSHOT_FILE"
    ;;

  mark)
    ensure_events_file
    slice_id="${1:-}"; status="${2:-}"
    case "$status" in
      pending|in-flight|merged|deferred|skipped) ;;
      *) av_fail "invalid status: $status (one of: pending|in-flight|merged|deferred|skipped)"; exit 1;;
    esac
    [ -z "$slice_id" ] && { av_fail "usage: state.sh mark <slice-id> <status>"; exit 1; }
    reason="${3:-}"
    if [ -n "$reason" ]; then
      data=$(jq -nc --arg r "$reason" '{reason: $r}')
    else
      data="null"
    fi
    emit_event "slice-${status}" "$slice_id" "$data"
    av_ok "marked $slice_id → $status"
    ;;

  set-pr)
    ensure_events_file
    slice_id="${1:-}"; pr="${2:-}"
    [ -z "$slice_id" ] || [ -z "$pr" ] && { av_fail "usage: state.sh set-pr <slice-id> <pr-num>"; exit 1; }
    data=$(jq -nc --argjson p "$pr" '{pr_number: $p}')
    emit_event "slice-pr-opened" "$slice_id" "$data"
    av_ok "set $slice_id PR=#$pr"
    ;;

  decision)
    ensure_events_file
    slice_id="${1:-}"; verb="${2:-}"; outcome="${3:-}"; response="${4:-}"
    if [ -z "$slice_id" ] || [ -z "$verb" ] || [ -z "$outcome" ]; then
      av_fail 'usage: state.sh decision <slice-id> <verb> <outcome> "<response>"'
      exit 1
    fi
    case "$verb" in approve|edit|reject|respond|"(default applied)") ;;
      *) av_fail "invalid verb: $verb"; exit 1;;
    esac
    data=$(jq -nc --arg v "$verb" --arg o "$outcome" --arg r "$response" '{verb: $v, outcome: $o, response: $r}')
    emit_event "decision" "$slice_id" "$data"
    av_ok "decision recorded: $slice_id verb=$verb outcome=$outcome"
    ;;

  add-issue)
    ensure_events_file
    issue="${1:-}"
    [ -z "$issue" ] && { av_fail "usage: state.sh add-issue <number>"; exit 1; }
    data=$(jq -nc --argjson n "$issue" '{number: $n}')
    emit_event "issue-filed" "" "$data"
    av_ok "issue tracked: #$issue"
    ;;

  status)
    ensure_events_file
    refresh_snapshot
    jq -r '
      .slices as $s
      | "Plan: \(.plan_path)\nStarted: \(.started_at)\n\nSlices:\n" +
        ($s | to_entries | map("  [\(.value.status | ascii_upcase)] \(.key)\(if .value.pr then " (#\(.value.pr))" else "" end)\(if .value.depends_on | length > 0 then " ← deps: \(.value.depends_on | join(","))" else "" end)") | join("\n")) +
        "\n\nProgress: " +
        "\($s | [to_entries[] | select(.value.status == "merged")] | length)/\($s | length) merged, " +
        "\($s | [to_entries[] | select(.value.status == "in-flight")] | length) in-flight, " +
        "\($s | [to_entries[] | select(.value.status == "deferred")] | length) deferred" +
        (if .decisions | length > 0 then "\n\nDecisions: \(.decisions | length)" else "" end) +
        (if .issues_filed | length > 0 then "\nFollow-ups filed: \(.issues_filed | length)" else "" end)
    ' "$SNAPSHOT_FILE"
    ;;

  trace)
    ensure_events_file
    slice_id="${1:-}"
    if [ -z "$slice_id" ]; then
      cat "$EVENTS_FILE" | jq -r '"\(.t) [\(.ev)] \(.slice // "-") \(.data // {} | tostring | if length > 60 then .[0:57] + "..." else . end)"'
    else
      grep "\"slice\":\"$slice_id\"" "$EVENTS_FILE" | jq -r '"\(.t) [\(.ev)] \(.data // {} | tostring | if length > 60 then .[0:57] + "..." else . end)"'
    fi
    ;;

  snapshot)
    ensure_events_file
    refresh_snapshot
    cat "$SNAPSHOT_FILE"
    ;;

  replay)
    ensure_events_file
    slice_id="${1:-}"
    [ -z "$slice_id" ] && { av_fail "usage: state.sh replay <slice-id>"; exit 1; }
    # Append a slice-pending event to "rewind" the slice (subsequent events overlay)
    emit_event "slice-pending" "$slice_id" 'null'
    av_ok "replayed $slice_id (back to pending — re-dispatch via /grind or /dispatch-slice)"
    ;;

  *)
    av_fail "usage: state.sh {init|next|ready|mark|set-pr|decision|add-issue|status|trace|snapshot|replay} [args]"
    exit 1
    ;;
esac
