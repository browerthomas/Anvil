#!/usr/bin/env bash
# anvil/grind — read/write the per-plan execution state.
#
# Usage:
#   state.sh init <plan-path>             # initialize state file from plan
#   state.sh next                         # print next ready slice id (or empty if all done)
#   state.sh ready                        # print all slices whose deps are merged + not in-flight
#   state.sh mark <slice-id> <status>     # status: in-flight | merged | deferred | skipped
#   state.sh set-pr <slice-id> <pr-num>
#   state.sh status                       # human-readable progress summary

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
STATE_FILE="$REPO_ROOT/.anvil/grind-state.json"

cmd="${1:-}"
shift || true

ensure_state_file() {
  if [ ! -f "$STATE_FILE" ]; then
    av_fail "state file not initialized — run: state.sh init <plan-path>"
    exit 1
  fi
}

case "$cmd" in
  init)
    plan_path="${1:-}"
    if [ -z "$plan_path" ] || [ ! -f "$plan_path" ]; then
      av_fail "usage: state.sh init <plan-path>"
      exit 1
    fi
    mkdir -p "$REPO_ROOT/.anvil"

    # Extract the YAML slice manifest from the plan.
    # Looks for the first ```yaml ... ``` block containing `slices:`.
    yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){print; exit}; next} flag {print}' "$plan_path")

    if ! echo "$yaml" | grep -q "slices:"; then
      av_fail "plan does not contain a slices: YAML block"
      exit 1
    fi

    # Convert YAML to JSON (best-effort via python; fallback to manual parse).
    if command -v yq >/dev/null 2>&1; then
      slices_json=$(echo "$yaml" | yq -o=json)
    elif command -v python3 >/dev/null 2>&1; then
      slices_json=$(echo "$yaml" | python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin)))' 2>/dev/null)
    else
      av_fail "need yq or python3+pyyaml to parse plan YAML"
      exit 1
    fi

    if [ -z "$slices_json" ]; then
      av_fail "could not parse plan YAML"
      exit 1
    fi

    jq -n \
      --arg plan "$plan_path" \
      --arg now "$(av_iso_now)" \
      --argjson slices "$slices_json" '
      {
        plan_path: $plan,
        started_at: $now,
        slices: ($slices.slices | map({key: .id, value: {
          status: "pending",
          depends_on: (.["depends-on"] // []),
          operator_paced: (.["operator-paced"] // false)
        }}) | from_entries),
        issues_filed: [],
        last_recap: null
      }
    ' > "$STATE_FILE"

    av_ok "state initialized at $STATE_FILE"
    jq -r '.slices | to_entries | length as $n | "  \($n) slices loaded"' "$STATE_FILE"
    ;;

  next)
    ensure_state_file
    # A slice is "ready" if status=pending AND all depends_on are merged.
    jq -r '
      .slices as $s
      | $s
      | to_entries
      | map(select(.value.status == "pending" and .value.operator_paced == false))
      | map(select((.value.depends_on // []) | all($s[.] .status == "merged")))
      | (first // empty).key // empty
    ' "$STATE_FILE"
    ;;

  ready)
    ensure_state_file
    jq -r '
      .slices as $s
      | $s
      | to_entries
      | map(select(.value.status == "pending" and .value.operator_paced == false))
      | map(select((.value.depends_on // []) | all($s[.] .status == "merged")))
      | .[] .key
    ' "$STATE_FILE"
    ;;

  mark)
    ensure_state_file
    slice_id="${1:-}"; status="${2:-}"
    if [ -z "$slice_id" ] || [ -z "$status" ]; then
      av_fail "usage: state.sh mark <slice-id> <status>"
      exit 1
    fi
    case "$status" in
      pending|in-flight|merged|deferred|skipped) ;;
      *) av_fail "invalid status: $status"; exit 1;;
    esac
    tmp=$(mktemp)
    jq --arg id "$slice_id" --arg st "$status" --arg now "$(av_iso_now)" '
      .slices[$id].status = $st
      | .slices[$id]["${st}_at"] = $now
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    av_ok "marked $slice_id → $status"
    ;;

  set-pr)
    ensure_state_file
    slice_id="${1:-}"; pr_num="${2:-}"
    if [ -z "$slice_id" ] || [ -z "$pr_num" ]; then
      av_fail "usage: state.sh set-pr <slice-id> <pr-num>"
      exit 1
    fi
    tmp=$(mktemp)
    jq --arg id "$slice_id" --argjson pr "$pr_num" '.slices[$id].pr = $pr' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    av_ok "set $slice_id PR=#$pr_num"
    ;;

  add-issue)
    ensure_state_file
    issue="${1:-}"
    [ -z "$issue" ] && { av_fail "usage: state.sh add-issue <number>"; exit 1; }
    tmp=$(mktemp)
    jq --argjson n "$issue" '.issues_filed += [$n] | .issues_filed |= unique' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    av_ok "filed issue tracked: #$issue"
    ;;

  status)
    ensure_state_file
    jq -r '
      .slices as $s
      | "Plan: \(.plan_path)\nStarted: \(.started_at)\n\nSlices:\n" +
        ($s | to_entries | map("  [\(.value.status | ascii_upcase)] \(.key)\(if .value.pr then " (#\(.value.pr))" else "" end)\(if .value.depends_on | length > 0 then " ← deps: \(.value.depends_on | join(","))" else "" end)") | join("\n")) +
        "\n\nProgress: " +
        "\($s | [to_entries[] | select(.value.status == "merged")] | length)/\($s | length) merged, " +
        "\($s | [to_entries[] | select(.value.status == "in-flight")] | length) in-flight, " +
        "\($s | [to_entries[] | select(.value.status == "deferred")] | length) deferred"
    ' "$STATE_FILE"
    ;;

  *)
    av_fail "usage: state.sh {init|next|ready|mark|set-pr|add-issue|status} [args]"
    exit 1
    ;;
esac
