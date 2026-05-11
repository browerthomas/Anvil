#!/usr/bin/env bash
# anvil/anvil-status — read-only text dashboard of plan state.
#
# Reads:
#   .anvil/grind-events.jsonl  — primary state source (folded into a snapshot)
#   <plan>/tasks.md (or <plan>.md) — slice manifest for ordering + names
#   gh pr list (optional, when online) — current PR state of in-flight slices
#
# Writes: nothing. Stdout only.
#
# Output shape (rank-locked, first non-blank line is always NEXT:):
#   NEXT: <slice-id> (parallel/deps-blocking, N follow-ups)
#   IN-FLIGHT: <slice-id> (PR #N, codex-pending/operator-pending)
#   BLOCKED: <slice-id> (deps: <list>)
#   SHIPPED: <slice-ids> (N slices, +M tests, K follow-ups)
#   DEFERRED: <slice-ids>
#
#   Tests: <total> cumulative (Δ across N slices)
#   Follow-ups: <open> open / <closed> closed
#
# Sections are omitted when empty. Footer is always present.
#
# Usage:
#   build-status.sh <plan-path>
#
# Environment:
#   GH_OFFLINE=1  — skip gh invocation entirely; read PR linkage from event log only.

set -u

# Resolve ANVIL_ROOT (mirrors skills/grind/scripts/state.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${ANVIL_ROOT:-}" ]; then
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

usage() {
  echo "usage: build-status.sh <plan-path>" >&2
  echo "  GH_OFFLINE=1 to skip gh invocation" >&2
}

plan_path="${1:-}"
if [ -z "$plan_path" ]; then
  usage
  exit 1
fi

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
ANVIL_DIR="$REPO_ROOT/.anvil"
EVENTS_FILE="$ANVIL_DIR/grind-events.jsonl"

# Friendly no-op: empty/missing event log + plan still resolvable = print a
# placeholder + exit 0. The skill is read-only; nothing to fail-loud on when
# the operator runs it before /grind has touched the plan.
if [ ! -f "$EVENTS_FILE" ] || [ ! -s "$EVENTS_FILE" ]; then
  echo "NEXT: (event log empty — run /grind <plan-path> to initialize state)"
  echo
  echo "Tests: 0 cumulative (Δ across 0 slices)"
  echo "Follow-ups: 0 open / 0 closed"
  exit 0
fi

# Resolve tasks source — flat or folder layout.
tasks_source=""
if [ -d "$plan_path" ]; then
  if [ ! -f "$plan_path/tasks.md" ]; then
    av_fail "folder plan must contain tasks.md (got: $plan_path)"
    exit 1
  fi
  tasks_source="$plan_path/tasks.md"
elif [ -f "$plan_path" ]; then
  tasks_source="$plan_path"
else
  av_fail "plan not found (neither file nor folder): $plan_path"
  exit 1
fi

# ── Decide gh online vs offline ────────────────────────────────────────
# Auto-fall-back to offline if gh missing or unauthenticated. Explicit
# GH_OFFLINE=1 always forces offline. The auto-detect is silent (no
# warning) so test runners + CI without credentials produce clean output.
use_gh=1
if [ "${GH_OFFLINE:-0}" = "1" ]; then
  use_gh=0
fi
if [ "$use_gh" -eq 1 ]; then
  if ! command -v gh >/dev/null 2>&1; then
    use_gh=0
  elif ! gh auth status >/dev/null 2>&1; then
    use_gh=0
  fi
fi

# ── Fold the event log into a state map (read-only — never writes the snapshot) ─
# Mirrors skills/grind/scripts/state.sh#refresh_snapshot but in-process so
# we don't perturb the live snapshot file even on read.
fold_state() {
  jq -s '
    # Drop sentinel/doc lines (no .ev field) up front so downstream filters
    # never see a null .ev. Fixtures sometimes carry a first-line {"_doc":...}
    # comment for the backward-compat-guard pattern.
    map(select(.ev != null and (.ev | type) == "string")) as $events
    | ($events | map(select(.ev == "plan-init")) | last) as $init
    | ($init.data.slices // {}) as $slices
    | ($events | map(select(.ev == "issue-filed")) | map(.data.number) | unique) as $issues
    | ($events | map(select(.ev | startswith("slice-") or . == "decision"))) as $slice_events
    | reduce $slice_events[] as $e (
        {plan_path: ($init.data.plan_path // null),
         started_at: ($init.t // null),
         slices: $slices,
         issues_filed: $issues,
         decisions: []};
        if $e.ev == "slice-in-flight" then
          .slices[$e.slice].status = "in-flight"
          | .slices[$e.slice].agent_id = $e.data.agent_id
          | .slices[$e.slice].worktree = $e.data.worktree
          | .slices[$e.slice].dispatched_at = $e.t
        elif $e.ev == "slice-pr-opened" then
          .slices[$e.slice].pr = $e.data.pr_number
          | .slices[$e.slice].pr_at = $e.t
        elif $e.ev == "slice-reviewed" then
          .slices[$e.slice].review = $e.data
          | .slices[$e.slice].reviewed_at = $e.t
        elif $e.ev == "slice-merged" then
          .slices[$e.slice].status = "merged"
          | .slices[$e.slice].merged_at = $e.t
          | (if $e.data.pr_number then .slices[$e.slice].pr = $e.data.pr_number else . end)
          | (if $e.data.tests_delta then .slices[$e.slice].tests_delta = $e.data.tests_delta else . end)
        elif $e.ev == "slice-deferred" then
          .slices[$e.slice].status = "deferred"
          | .slices[$e.slice].deferred_at = $e.t
          | .slices[$e.slice].defer_reason = $e.data.reason
        elif $e.ev == "slice-skipped" then
          .slices[$e.slice].status = "skipped"
          | .slices[$e.slice].skipped_at = $e.t
        elif $e.ev == "slice-pending" then
          .slices[$e.slice].status = "pending"
        elif $e.ev == "decision" then
          .decisions += [{slice: $e.slice, t: $e.t, verb: $e.data.verb,
                          outcome: $e.data.outcome, response: $e.data.response}]
        else . end
      )
  ' "$EVENTS_FILE"
}

snapshot=$(fold_state)

# Extract slice ids in declaration order from the plan's tasks.md so output
# ordering matches the plan, not jq's hash order.
# Try yq first (preserves order natively); fall back to a small awk pass that
# pulls `id:` keys out of the slices block in document order.
slice_ids_in_order() {
  local yaml
  yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){exit}; next} flag {print}' "$tasks_source")
  if [ -z "$yaml" ]; then
    # No YAML manifest — fall back to event-log order.
    echo "$snapshot" | jq -r '.slices | keys[]'
    return
  fi
  # awk extracts `id: <value>` lines under `slices:` in document order.
  printf '%s\n' "$yaml" | awk '
    /^slices:/ { in_slices=1; next }
    in_slices && /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
    }
  '
}

ordered_ids=$(slice_ids_in_order)

# ── Section builders ───────────────────────────────────────────────────
# All return text on stdout. Empty output → caller suppresses the section.

# Count open / closed follow-up issues per slice. Open = filed but not
# referenced by a `slice-merged` of the SAME slice id after the issue-filed
# event (cheap heuristic — the event log doesn't record issue close events).
# For the dashboard we report TOTAL open + TOTAL closed across the plan.
followup_totals() {
  local total_filed total_closed
  total_filed=$(jq -s 'map(select((.ev // null) == "issue-filed")) | length' "$EVENTS_FILE")
  # Treat any issue filed BEFORE the most-recent slice-merged for its slice
  # as "closed" if the same slice subsequently merged. This is approximate;
  # the exact closure state lives in GH. For offline + CI use we treat all
  # filed issues as open (conservative).
  if [ "$use_gh" -eq 1 ]; then
    # Try to count closed via gh; fall back if it errors.
    local closed
    closed=$(jq -s -r 'map(select((.ev // null) == "issue-filed") | .data.number) | unique | .[]' "$EVENTS_FILE" 2>/dev/null \
      | while read -r num; do
          [ -z "$num" ] && continue
          state=$(gh issue view "$num" --json state --jq '.state' 2>/dev/null)
          [ "$state" = "CLOSED" ] && echo 1
        done | wc -l | tr -d ' ')
    total_closed="$closed"
  else
    total_closed=0
  fi
  echo "$total_filed $total_closed"
}

# Test delta — sum tests_delta across slice-merged events.
tests_delta_total() {
  jq -s -r '
    map(select((.ev // null) == "slice-merged" and .data and .data.tests_delta != null) | .data.tests_delta)
    | add // 0
  ' "$EVENTS_FILE"
}

merged_slice_count() {
  jq -s -r 'map(select((.ev // null) == "slice-merged")) | length' "$EVENTS_FILE"
}

# Per-slice follow-up count — uses the event log's slice field on issue-filed.
followups_for_slice() {
  local sid="$1"
  jq -s -r --arg s "$sid" '
    map(select((.ev // null) == "issue-filed" and .slice == $s)) | length
  ' "$EVENTS_FILE"
}

# Resolve a slice's PR# — prefer snapshot (online or offline both reach here
# via the event-log fold). Returns empty string if no PR recorded.
slice_pr() {
  local sid="$1"
  echo "$snapshot" | jq -r --arg s "$sid" '.slices[$s].pr // ""'
}

# Slice status from the folded snapshot.
slice_status() {
  local sid="$1"
  echo "$snapshot" | jq -r --arg s "$sid" '.slices[$s].status // "pending"'
}

# Slice depends-on (returns space-separated ids, empty if none).
slice_deps() {
  local sid="$1"
  echo "$snapshot" | jq -r --arg s "$sid" '.slices[$s].depends_on // [] | join(" ")'
}

# Slice review state when online — emits codex-pending / merge-ready / etc.
# Offline: returns empty (the dashboard says "operator-pending" as a generic
# annotation).
slice_review_state() {
  local sid="$1"
  if [ "$use_gh" -eq 0 ]; then
    echo ""
    return
  fi
  local pr
  pr=$(slice_pr "$sid")
  [ -z "$pr" ] && { echo ""; return; }
  # gh pr view returns mergeable + mergeStateStatus.
  local state mergeable
  state=$(gh pr view "$pr" --json state,mergeable --jq '"\(.state) \(.mergeable)"' 2>/dev/null)
  if [ -z "$state" ]; then
    echo ""
    return
  fi
  # Trim the gh output; we don't need a perfect taxonomy here.
  case "$state" in
    *MERGEABLE*) echo "merge-ready" ;;
    *CONFLICTING*) echo "conflict" ;;
    *) echo "operator-pending" ;;
  esac
}

# ── Section assemblers ─────────────────────────────────────────────────

# NEXT — earliest pending slice whose deps are all merged. Honour plan order
# (not alphabetical) so the operator's intent surfaces first.
emit_next() {
  local sid status deps dep dep_status all_merged ready_ids found
  found=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    status=$(slice_status "$sid")
    [ "$status" != "pending" ] && continue
    deps=$(slice_deps "$sid")
    all_merged=1
    if [ -n "$deps" ]; then
      for dep in $deps; do
        dep_status=$(slice_status "$dep")
        if [ "$dep_status" != "merged" ]; then
          all_merged=0
          break
        fi
      done
    fi
    if [ "$all_merged" -eq 1 ]; then
      if [ -z "$found" ]; then
        found="$sid"
      fi
      ready_ids="$ready_ids $sid"
    fi
  done <<< "$ordered_ids"

  [ -z "$found" ] && return 0

  # Count ready siblings — annotation says parallel vs deps-blocking.
  local ready_count
  ready_count=$(echo "$ready_ids" | tr ' ' '\n' | grep -cv '^$')
  local mode="deps-blocking"
  if [ "$ready_count" -gt 1 ]; then
    mode="parallel"
  fi

  local fu
  fu=$(followups_for_slice "$found")
  echo "NEXT: $found ($mode, $fu follow-ups)"
}

# IN-FLIGHT — slices with status in-flight. Annotation: PR# + review state.
emit_in_flight() {
  local lines=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    local status pr review annotation
    status=$(slice_status "$sid")
    [ "$status" != "in-flight" ] && continue
    pr=$(slice_pr "$sid")
    review=$(slice_review_state "$sid")
    if [ -n "$pr" ] && [ -n "$review" ]; then
      annotation="PR #$pr, $review"
    elif [ -n "$pr" ]; then
      annotation="PR #$pr, operator-pending"
    else
      annotation="no PR yet"
    fi
    lines="${lines}IN-FLIGHT: $sid ($annotation)
"
  done <<< "$ordered_ids"
  # Trim trailing newline.
  printf '%s' "${lines%
}"
}

# BLOCKED — pending slices whose deps are NOT all merged. Cite the failing
# (deferred) dep specifically if present; otherwise list all non-merged deps.
emit_blocked() {
  local lines=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    local status deps dep dep_status non_merged failing
    status=$(slice_status "$sid")
    [ "$status" != "pending" ] && continue
    deps=$(slice_deps "$sid")
    [ -z "$deps" ] && continue
    non_merged=""
    failing=""
    for dep in $deps; do
      dep_status=$(slice_status "$dep")
      if [ "$dep_status" != "merged" ]; then
        non_merged="$non_merged $dep"
        if [ "$dep_status" = "deferred" ] || [ "$dep_status" = "skipped" ]; then
          failing="$failing $dep"
        fi
      fi
    done
    if [ -n "$non_merged" ]; then
      local annotation deps_list
      deps_list=$(echo "$non_merged" | xargs | tr ' ' ',')
      if [ -n "$failing" ]; then
        local failing_list
        failing_list=$(echo "$failing" | xargs | tr ' ' ',')
        annotation="deps: $deps_list (failed: $failing_list)"
      else
        annotation="deps: $deps_list"
      fi
      lines="${lines}BLOCKED: $sid ($annotation)
"
    fi
  done <<< "$ordered_ids"
  printf '%s' "${lines%
}"
}

# SHIPPED — merged slices. One summary line.
emit_shipped() {
  local merged_ids
  merged_ids=$(echo "$snapshot" | jq -r '.slices | to_entries | map(select(.value.status == "merged")) | .[] .key')
  [ -z "$merged_ids" ] && return 0
  local n delta fu
  n=$(echo "$merged_ids" | grep -cv '^$')
  delta=$(tests_delta_total)
  # Total follow-ups filed across the plan.
  local fu_pair
  fu_pair=$(followup_totals)
  local fu_total
  fu_total=$(echo "$fu_pair" | awk '{print $1}')
  local ids_csv
  ids_csv=$(echo "$merged_ids" | xargs | tr ' ' ',')
  local sign=""
  if [ "$delta" -ge 0 ]; then
    sign="+"
  fi
  echo "SHIPPED: $ids_csv ($n slices, ${sign}${delta} tests, $fu_total follow-ups)"
}

# DEFERRED — slices with slice-deferred + no subsequent slice-merged.
emit_deferred() {
  local deferred_ids
  deferred_ids=$(echo "$snapshot" | jq -r '.slices | to_entries | map(select(.value.status == "deferred")) | .[] .key')
  [ -z "$deferred_ids" ] && return 0
  local ids_csv
  ids_csv=$(echo "$deferred_ids" | xargs | tr ' ' ',')
  echo "DEFERRED: $ids_csv"
}

# ── Render the dashboard ───────────────────────────────────────────────
next_line=$(emit_next)
in_flight_lines=$(emit_in_flight)
blocked_lines=$(emit_blocked)
shipped_line=$(emit_shipped)
deferred_line=$(emit_deferred)

# NEXT is always first non-blank line. If no pending slice, print a fallback.
if [ -z "$next_line" ]; then
  # If everything's merged + nothing deferred, the plan is done.
  pending_count=$(echo "$snapshot" | jq '.slices | to_entries | map(select(.value.status == "pending")) | length')
  if [ "$pending_count" -eq 0 ]; then
    echo "NEXT: (plan complete — all slices merged or deferred)"
  else
    echo "NEXT: (no ready slice — every pending slice is blocked on deps)"
  fi
else
  echo "$next_line"
fi

[ -n "$in_flight_lines" ] && echo "$in_flight_lines"
[ -n "$blocked_lines" ] && echo "$blocked_lines"
[ -n "$shipped_line" ] && echo "$shipped_line"
[ -n "$deferred_line" ] && echo "$deferred_line"

# Footer.
delta=$(tests_delta_total)
merged=$(merged_slice_count)
fu_pair=$(followup_totals)
fu_total=$(echo "$fu_pair" | awk '{print $1}')
fu_closed=$(echo "$fu_pair" | awk '{print $2}')
fu_open=$((fu_total - fu_closed))
echo
sign=""
[ "$delta" -ge 0 ] && sign="+"
echo "Tests: ${sign}${delta} cumulative (Δ across $merged slices)"
echo "Follow-ups: $fu_open open / $fu_closed closed"
