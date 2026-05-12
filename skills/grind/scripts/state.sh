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
#   slice-in-flight — agent dispatched; data has agent_id, worktree,
#                     optional tokens_in, tokens_out, cost_usd
#   slice-pr-opened — agent returned a PR; data has pr_number, optional
#                     tokens_in, tokens_out, cost_usd
#   slice-reviewed  — review pass complete; data has findings count
#   slice-merged    — auto-merge succeeded; optional tests_delta,
#                     tokens_in, tokens_out, cost_usd
#   slice-deferred  — slice paused/skipped; data has reason
#   slice-skipped   — operator-paced or rejected
#   issue-filed     — follow-up issue tracked
#   decision        — operator-decision invoked; data has verb, free-text, outcome
#   resume          — `/grind --resume` invoked; data has plan_path, resumed_from,
#                     merged_count, total_count, fresh_init (audit-only;
#                     additive — does not mutate slice status directly)
#
# Token / cost fields (all OPTIONAL, nullable):
#   tokens_in   — input/prompt tokens consumed during the agent run
#   tokens_out  — output/completion tokens
#   cost_usd    — dollar cost as a JSON number (e.g. 0.0125)
#   When the runtime cannot report them (codex review, manual edits) the
#   fields are left absent → folded snapshot carries null. The dashboard +
#   recap surface them only when present.
#
# Usage:
#   state.sh init <plan-path>             # write plan-init event from plan
#   state.sh resume <plan-path>           # auto-resume from event log's last slice-merged
#   state.sh next                         # print next ready slice id
#   state.sh ready                        # print all ready slices
#   state.sh mark <slice-id> <type> [reason] [--tokens-in N] [--tokens-out N] [--cost-usd F]
#                                         # append a slice-<type> event;
#                                         # token/cost flags supported on in-flight + merged
#   state.sh set-pr <slice-id> <pr-num> [--tokens-in N] [--tokens-out N] [--cost-usd F]
#   state.sh decision <slice-id> <verb> <outcome> "<free-text>"
#   state.sh add-issue <number>
#   state.sh status                       # human-readable progress (folded snapshot)
#   state.sh trace [slice-id]             # print event log (filtered to slice if given)
#   state.sh snapshot                     # rebuild + print snapshot from event log
#   state.sh replay <slice-id>            # rewind: write a slice-pending event for slice-id

set -u

# Resolve ANVIL_ROOT (in order):
#   1. existing env var       — operator override
#   2. anvil-config.sh next to skills/ — post-install (any prefix; copy or symlink)
#   3. env-honoured anvil-config.sh    — $ANVIL_HOME/$CLAUDE_HOME/$HOME/.claude
#   4. relative-path fallback ($SCRIPT_DIR/../../..)  — in-checkout / dev mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${ANVIL_ROOT:-}" ]; then
  # The script lives at <install-root>/skills/<name>/scripts/<file>.sh; the
  # config file is at <install-root>/anvil-config.sh — 3 levels up.
  _av_cfg="$SCRIPT_DIR/../../../anvil-config.sh"
  if [ -f "$_av_cfg" ]; then
    # shellcheck source=/dev/null
    . "$_av_cfg"
  fi
  unset _av_cfg
fi
if [ -z "${ANVIL_ROOT:-}" ] && [ -f "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh" ]; then
  # shellcheck source=/dev/null
  . "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh"
fi
if [ -z "${ANVIL_ROOT:-}" ]; then
  ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
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

# Acquire an exclusive lock on the events file using mkdir (atomic +
# cross-platform — works on macOS without flock). Returns 0 on lock-held,
# non-zero if another process already holds it. On success, registers a
# trap so the lock is released on exit.
LOCK_HELD=0
acquire_events_lock() {
  local lock_dir="${EVENTS_FILE}.lock"
  if mkdir "$lock_dir" 2>/dev/null; then
    LOCK_HELD=1
    # Store pid for diagnostics; safe to ignore on read.
    echo $$ > "$lock_dir/pid" 2>/dev/null || true
    trap 'release_events_lock' EXIT INT TERM
    return 0
  fi
  return 1
}

release_events_lock() {
  if [ "$LOCK_HELD" = "1" ]; then
    local lock_dir="${EVENTS_FILE}.lock"
    rm -rf "$lock_dir" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

# Resolve the YAML→slices JSON for a given plan path. Echoes the JSON.
# Exits 1 on failure with a user-facing av_fail message.
parse_plan_yaml() {
  local plan_path="$1"
  local yaml_source
  if [ -d "$plan_path" ]; then
    local tasks_file="$plan_path/tasks.md"
    if [ ! -f "$tasks_file" ]; then
      av_fail "folder plan must contain tasks.md (got: $plan_path)"
      return 1
    fi
    yaml_source="$tasks_file"
  elif [ -f "$plan_path" ]; then
    yaml_source="$plan_path"
  else
    av_fail "plan not found (neither file nor folder): $plan_path"
    return 1
  fi

  local yaml
  yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){exit}; next} flag {print}' "$yaml_source")
  if ! echo "$yaml" | grep -q "slices:"; then
    av_fail "plan does not contain a slices: YAML block (looked in $yaml_source)"
    return 1
  fi

  local slices_json
  if command -v yq >/dev/null 2>&1; then
    slices_json=$(echo "$yaml" | yq -o=json)
  elif command -v python3 >/dev/null 2>&1; then
    slices_json=$(echo "$yaml" | python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin)))' 2>/dev/null)
  else
    av_fail "need yq or python3+pyyaml to parse plan YAML"
    return 1
  fi
  if [ -z "$slices_json" ]; then
    av_fail "could not parse plan YAML"
    return 1
  fi
  echo "$slices_json"
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
#
# Token / cost accumulation: tokens_in, tokens_out, cost_usd may appear on
# slice-in-flight, slice-pr-opened, and slice-merged events. Each is added
# (when present) to the slice's running counters so a slice that re-dispatched
# accumulates correctly. The slice and plan-wide totals are exposed in the
# folded snapshot under .slices[id].tokens_in etc., and at the top level via
# the `cost_total_usd` etc. roll-ups below.
refresh_snapshot() {
  jq -s '
    # Drop sentinel/doc lines (no .ev field) up front so downstream filters
    # never see a null .ev. Fixtures sometimes carry a first-line {"_doc":...}
    # comment for the backward-compat-guard pattern (mirrors anvil-status).
    map(select(.ev != null and (.ev | type) == "string")) as $events
    | ($events
       | map(select(.ev == "plan-init")) | last) as $init
    | ($init.data.slices // {}) as $slices
    | ($events
       | map(select(.ev == "issue-filed")) | map(.data.number) | unique) as $issues
    | ($events
       | map(select(.ev | startswith("slice-") or . == "decision"))) as $slice_events
    | reduce $slice_events[] as $e (
        {plan_path: ($init.data.plan_path // null), started_at: ($init.t // null), slices: $slices, issues_filed: $issues, decisions: []};
        if $e.ev == "slice-in-flight"  then .slices[$e.slice].status = "in-flight"  | .slices[$e.slice].agent_id = $e.data.agent_id | .slices[$e.slice].worktree = $e.data.worktree | .slices[$e.slice].dispatched_at = $e.t
          | (if ($e.data.tokens_in // null)  != null then .slices[$e.slice].tokens_in  = ((.slices[$e.slice].tokens_in // 0)  + $e.data.tokens_in)  else . end)
          | (if ($e.data.tokens_out // null) != null then .slices[$e.slice].tokens_out = ((.slices[$e.slice].tokens_out // 0) + $e.data.tokens_out) else . end)
          | (if ($e.data.cost_usd // null)   != null then .slices[$e.slice].cost_usd   = ((.slices[$e.slice].cost_usd // 0)   + $e.data.cost_usd)   else . end)
        elif $e.ev == "slice-pr-opened" then .slices[$e.slice].pr = $e.data.pr_number | .slices[$e.slice].pr_at = $e.t
          | (if ($e.data.tokens_in // null)  != null then .slices[$e.slice].tokens_in  = ((.slices[$e.slice].tokens_in // 0)  + $e.data.tokens_in)  else . end)
          | (if ($e.data.tokens_out // null) != null then .slices[$e.slice].tokens_out = ((.slices[$e.slice].tokens_out // 0) + $e.data.tokens_out) else . end)
          | (if ($e.data.cost_usd // null)   != null then .slices[$e.slice].cost_usd   = ((.slices[$e.slice].cost_usd // 0)   + $e.data.cost_usd)   else . end)
        elif $e.ev == "slice-reviewed"  then .slices[$e.slice].review = $e.data | .slices[$e.slice].reviewed_at = $e.t
        elif $e.ev == "slice-merged"    then .slices[$e.slice].status = "merged"    | .slices[$e.slice].merged_at = $e.t
          | (if ($e.data.pr_number   // null) != null then .slices[$e.slice].pr = $e.data.pr_number else . end)
          | (if ($e.data.tests_delta // null) != null then .slices[$e.slice].tests_delta = $e.data.tests_delta else . end)
          | (if ($e.data.tokens_in   // null) != null then .slices[$e.slice].tokens_in  = ((.slices[$e.slice].tokens_in // 0)  + $e.data.tokens_in)  else . end)
          | (if ($e.data.tokens_out  // null) != null then .slices[$e.slice].tokens_out = ((.slices[$e.slice].tokens_out // 0) + $e.data.tokens_out) else . end)
          | (if ($e.data.cost_usd    // null) != null then .slices[$e.slice].cost_usd   = ((.slices[$e.slice].cost_usd // 0)   + $e.data.cost_usd)   else . end)
        elif $e.ev == "slice-deferred"  then .slices[$e.slice].status = "deferred"  | .slices[$e.slice].deferred_at = $e.t | .slices[$e.slice].defer_reason = $e.data.reason
        elif $e.ev == "slice-skipped"   then .slices[$e.slice].status = "skipped"   | .slices[$e.slice].skipped_at = $e.t
        elif $e.ev == "slice-pending"   then .slices[$e.slice].status = "pending"
        elif $e.ev == "decision"        then .decisions += [{slice: $e.slice, t: $e.t, verb: $e.data.verb, outcome: $e.data.outcome, response: $e.data.response}]
        else . end
      )
    | . + {
        cost_total_usd:   (.slices | to_entries | map(.value.cost_usd   // 0) | add // 0),
        tokens_in_total:  (.slices | to_entries | map(.value.tokens_in  // 0) | add // 0),
        tokens_out_total: (.slices | to_entries | map(.value.tokens_out // 0) | add // 0)
      }
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

    # Plan must be a flat file or a folder layout.
    if [ -d "$plan_path" ]; then
      av_info "loaded folder plan: $plan_path"
    elif [ -f "$plan_path" ]; then
      av_info "loaded flat plan: $plan_path"
    else
      av_fail "plan not found (neither file nor folder): $plan_path"
      exit 1
    fi
    mkdir -p "$ANVIL_DIR"

    # Extract slices JSON via shared helper.
    slices_json=$(parse_plan_yaml "$plan_path") || exit 1

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

  resume)
    plan_path="${1:-}"
    if [ -z "$plan_path" ]; then
      av_fail "usage: state.sh resume <plan-path>"
      exit 1
    fi
    # Validate plan path exists (file or folder layout).
    if [ ! -e "$plan_path" ]; then
      av_fail "plan not found (neither file nor folder): $plan_path"
      exit 1
    fi
    if [ -d "$plan_path" ] && [ ! -f "$plan_path/tasks.md" ]; then
      av_fail "folder plan must contain tasks.md (got: $plan_path)"
      exit 1
    fi

    mkdir -p "$ANVIL_DIR"

    # Acquire lock — second concurrent invocation prints warning + exits 0
    # without dispatching (no resume event written, idempotency preserved).
    if ! acquire_events_lock; then
      av_warn "another /grind --resume is in flight (lock held: ${EVENTS_FILE}.lock) — exiting without resume"
      exit 0
    fi

    # If event log does not exist yet, initialize it first.
    fresh_init=0
    if [ ! -f "$EVENTS_FILE" ]; then
      slices_json=$(parse_plan_yaml "$plan_path") || exit 1
      init_payload=$(jq -nc --arg plan "$plan_path" --argjson sj "$slices_json" '
        {plan_path: $plan, slices: ($sj.slices | map({key: .id, value: {
          status: "pending",
          depends_on: (.["depends-on"] // []),
          operator_paced: (.["operator-paced"] // false)
        }}) | from_entries)}
      ')
      : > "$EVENTS_FILE"
      emit_event "plan-init" "" "$init_payload"
      for sid in $(jq -r '.slices | keys[]' "$SNAPSHOT_FILE"); do
        emit_event "slice-pending" "$sid" "null"
      done
      fresh_init=1
    fi

    # Refresh snapshot so the resume payload can quote correct status counts.
    refresh_snapshot

    # Any non-merged, non-pending slices (deferred / in-flight / skipped) get
    # re-pended so the next/ready queries pick them up. `failed != merged` —
    # the operator's --resume retries failed slices.
    deferred_slices=$(jq -r '
      .slices | to_entries
      | map(select(.value.status == "deferred" or .value.status == "in-flight"))
      | .[] .key
    ' "$SNAPSHOT_FILE")
    for sid in $deferred_slices; do
      emit_event "slice-pending" "$sid" "null"
    done

    # Compute next ready slice.
    refresh_snapshot
    resumed_from=$(jq -r '
      .slices as $s
      | $s | to_entries
      | map(select(.value.status == "pending" and .value.operator_paced == false))
      | map(select((.value.depends_on // []) | all($s[.] .status == "merged")))
      | (first // empty).key // empty
    ' "$SNAPSHOT_FILE")

    merged_count=$(jq '[.slices | to_entries[] | select(.value.status == "merged")] | length' "$SNAPSHOT_FILE")
    total_count=$(jq '.slices | length' "$SNAPSHOT_FILE")

    resume_data=$(jq -nc \
      --arg plan "$plan_path" \
      --arg from "$resumed_from" \
      --argjson merged "$merged_count" \
      --argjson total "$total_count" \
      --argjson fresh "$fresh_init" \
      '{plan_path: $plan, resumed_from: (if $from == "" then null else $from end), merged_count: $merged, total_count: $total, fresh_init: ($fresh == 1)}')
    emit_event "resume" "" "$resume_data"

    if [ -z "$resumed_from" ]; then
      av_ok "resumed plan $plan_path — no ready slice (all $total_count merged or blocked)"
    else
      av_ok "resumed plan $plan_path — next slice: $resumed_from ($merged_count/$total_count merged)"
      echo "$resumed_from"
    fi
    release_events_lock
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
    shift 2 || true
    # Positional `reason` is still accepted for backward compatibility — if the
    # next arg is not a flag, treat it as the reason. Token/cost fields are
    # accepted as flags AFTER the optional reason (in any order).
    reason=""
    tokens_in=""
    tokens_out=""
    cost_usd=""
    tests_delta=""
    pr_number=""
    if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
      reason="$1"
      shift
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason)        reason="$2"; shift 2;;
        --tokens-in)     tokens_in="$2"; shift 2;;
        --tokens-out)    tokens_out="$2"; shift 2;;
        --cost-usd)      cost_usd="$2"; shift 2;;
        --tests-delta)   tests_delta="$2"; shift 2;;
        --pr|--pr-number) pr_number="$2"; shift 2;;
        *) av_fail "mark: unknown flag '$1' (accepted: --reason / --tokens-in / --tokens-out / --cost-usd / --tests-delta / --pr)"; exit 1;;
      esac
    done
    # Build the data object incrementally with jq so types stay correct.
    data=$(jq -nc \
      --arg reason "$reason" \
      --arg tin   "$tokens_in" \
      --arg tout  "$tokens_out" \
      --arg cost  "$cost_usd" \
      --arg tests "$tests_delta" \
      --arg pr    "$pr_number" \
      '
        ({}
         | (if $reason != "" then .reason = $reason else . end)
         | (if $tin    != "" then .tokens_in  = ($tin  | tonumber) else . end)
         | (if $tout   != "" then .tokens_out = ($tout | tonumber) else . end)
         | (if $cost   != "" then .cost_usd   = ($cost | tonumber) else . end)
         | (if $tests  != "" then .tests_delta = ($tests | tonumber) else . end)
         | (if $pr     != "" then .pr_number   = ($pr    | tonumber) else . end)
        ) as $d
        | (if ($d | length) == 0 then null else $d end)
      ')
    emit_event "slice-${status}" "$slice_id" "$data"
    av_ok "marked $slice_id → $status"
    ;;

  set-pr)
    ensure_events_file
    slice_id="${1:-}"; pr="${2:-}"
    [ -z "$slice_id" ] || [ -z "$pr" ] && { av_fail "usage: state.sh set-pr <slice-id> <pr-num> [--tokens-in N] [--tokens-out N] [--cost-usd F]"; exit 1; }
    shift 2 || true
    tokens_in=""
    tokens_out=""
    cost_usd=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --tokens-in)  tokens_in="$2"; shift 2;;
        --tokens-out) tokens_out="$2"; shift 2;;
        --cost-usd)   cost_usd="$2"; shift 2;;
        *) av_fail "set-pr: unknown flag '$1' (accepted: --tokens-in / --tokens-out / --cost-usd)"; exit 1;;
      esac
    done
    data=$(jq -nc \
      --argjson p "$pr" \
      --arg tin  "$tokens_in" \
      --arg tout "$tokens_out" \
      --arg cost "$cost_usd" \
      '
        {pr_number: $p}
        | (if $tin  != "" then .tokens_in  = ($tin  | tonumber) else . end)
        | (if $tout != "" then .tokens_out = ($tout | tonumber) else . end)
        | (if $cost != "" then .cost_usd   = ($cost | tonumber) else . end)
      ')
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

  from)
    # DEPRECATED alias for `resume`. Emits a warning + chains to resume so
    # any operator scripts still calling `state.sh from <plan-path>` keep
    # working. Will be removed in a future major release.
    av_warn "'state.sh from' is deprecated — use 'state.sh resume <plan-path>' (chaining now)"
    exec "$0" resume "$@"
    ;;

  *)
    av_fail "usage: state.sh {init|resume|from(deprecated)|next|ready|mark|set-pr|decision|add-issue|status|trace|snapshot|replay} [args]"
    av_fail "  mark/set-pr accept optional --tokens-in N / --tokens-out N / --cost-usd F flags."
    exit 1
    ;;
esac
