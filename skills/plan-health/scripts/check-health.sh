#!/usr/bin/env bash
# anvil/plan-health — per-plan follow-up filing-vs-closing trend gate (non-blocking).
#
# Reads:
#   .anvil/grind-events.jsonl  — for issue-filed / slice-in-flight / slice-merged events.
#   <plan>/tasks.md (or <plan>.md) — slice ordering for the snapshot view.
#   gh issue list (or --fixture) — close-state of each filed issue.
#
# Writes (only when the gate fires AND --dry-run is NOT set):
#   .anvil/grind-events.jsonl  — appends one `plan-health-degraded` event.
#   gh pr comment <pr>         — posts metric snapshot on the most-recent open PR.
#
# Output (always on stdout): a compact human-readable snapshot.
#
# Gate criterion:
#   Per-slice: filed > closed × 1.5 → degraded.
#   Plan: 3 consecutive most-recent merged slices all degraded → flag.
#   Insufficient data (<3 merged slices, or zero filed in window) → no flag.
#
# Usage:
#   check-health.sh <plan-path> [--pr <N>] [--fixture <path>] [--repo <owner/name>] [--dry-run]
#
# Environment:
#   GH_OFFLINE=1  — skip gh invocation; emit "skipped (offline)" + exit 0.

set -u

# Resolve ANVIL_ROOT (mirrors skills/grind/scripts/state.sh + anvil-status).
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
  echo "usage: check-health.sh <plan-path> [--pr <N>] [--fixture <path>] [--repo <owner/name>] [--dry-run]" >&2
  echo "  GH_OFFLINE=1 to skip gh invocation (emits 'skipped (offline)' + exits 0)" >&2
}

PLAN_PATH=""
PR_OVERRIDE=""
FIXTURE=""
REPO=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)        PR_OVERRIDE="${2:-}"; shift 2;;
    --fixture)   FIXTURE="${2:-}"; shift 2;;
    --repo)      REPO="${2:-}"; shift 2;;
    --dry-run)   DRY_RUN=1; shift;;
    -h|--help)   usage; exit 0;;
    -*)          av_fail "unknown arg: $1"; usage; exit 1;;
    *)
      if [ -z "$PLAN_PATH" ]; then
        PLAN_PATH="$1"
      else
        av_fail "unexpected positional arg: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$PLAN_PATH" ]; then
  usage
  exit 1
fi

# ── Resolve plan slug + tasks source ──────────────────────────────────
plan_slug=""
if [ -d "$PLAN_PATH" ]; then
  if [ ! -f "$PLAN_PATH/tasks.md" ]; then
    av_fail "folder plan must contain tasks.md (got: $PLAN_PATH)"
    exit 1
  fi
  plan_slug=$(basename "${PLAN_PATH%/}")
elif [ -f "$PLAN_PATH" ]; then
  fname=$(basename "$PLAN_PATH")
  plan_slug="${fname%.md}"
else
  av_fail "plan not found (neither file nor folder): $PLAN_PATH"
  exit 1
fi

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
EVENTS_FILE="$REPO_ROOT/.anvil/grind-events.jsonl"

if [ ! -f "$EVENTS_FILE" ]; then
  # No event log — nothing to evaluate. This is normal for fresh plans.
  echo "plan-health: $plan_slug"
  echo "  skipped (no event log at $EVENTS_FILE)"
  exit 0
fi

# ── Validate fixture if given ──────────────────────────────────────────
if [ -n "$FIXTURE" ]; then
  if [ ! -f "$FIXTURE" ]; then
    av_fail "fixture file not found: $FIXTURE"
    exit 1
  fi
  if ! jq empty "$FIXTURE" 2>/dev/null; then
    av_fail "fixture is not valid JSON: $FIXTURE"
    exit 1
  fi
fi

# ── Decide gh online vs offline ────────────────────────────────────────
use_gh=1
if [ "${GH_OFFLINE:-0}" = "1" ]; then
  use_gh=0
fi
if [ -n "$FIXTURE" ]; then
  # Fixture mode bypasses gh entirely — it IS the issue source.
  use_gh=0
fi
if [ "$use_gh" -eq 1 ]; then
  if ! command -v gh >/dev/null 2>&1; then
    use_gh=0
  elif ! gh auth status >/dev/null 2>&1; then
    use_gh=0
  fi
fi

# Offline mode (no fixture, no gh) → can't compute close ratios; skip.
if [ "$use_gh" -eq 0 ] && [ -z "$FIXTURE" ]; then
  echo "plan-health: $plan_slug"
  echo "  skipped (offline — no fixture, no gh; close ratios unknowable)"
  exit 0
fi

# ── Resolve repo for live gh fetches (best-effort) ────────────────────
if [ "$use_gh" -eq 1 ] && [ -z "$REPO" ]; then
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$origin" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
fi

# ── Fold events into per-slice timing windows ─────────────────────────
# For each slice that has BOTH a slice-in-flight AND a slice-merged event,
# emit: {slice, dispatched_at, merged_at}. Ordered by merged_at ascending.
slice_windows=$(jq -s '
  map(select(.ev != null and (.ev | type) == "string")) as $events
  | ($events | map(select(.ev == "slice-in-flight")) | group_by(.slice)
              | map({slice: .[0].slice, dispatched_at: (sort_by(.t) | last | .t)})) as $disp
  | ($events | map(select(.ev == "slice-merged"))    | group_by(.slice)
              | map({slice: .[0].slice, merged_at:    (sort_by(.t) | last | .t),
                     pr: (sort_by(.t) | last | .data.pr_number // null)})) as $merged
  # Inner join on slice id.
  | [
      $disp[] as $d
      | $merged[]
      | select(.slice == $d.slice)
      | {slice: .slice, dispatched_at: $d.dispatched_at, merged_at: .merged_at, pr: .pr}
    ]
  | sort_by(.merged_at)
' "$EVENTS_FILE")

merged_slice_count=$(echo "$slice_windows" | jq 'length')

# ── Insufficient data: <3 merged slices → no flag, exit 0 ─────────────
if [ "$merged_slice_count" -lt 3 ]; then
  echo "plan-health: $plan_slug"
  echo "  window: insufficient ($merged_slice_count merged slice(s); need 3)"
  echo "  flagged: no"
  exit 0
fi

# ── Build issues-by-slice: issue-filed events whose .t falls in window ─
# Inputs: $slice_windows (last 3 windows of merged slices), $EVENTS_FILE.
last_three=$(echo "$slice_windows" | jq '.[-3:]')

# Collect: per slice, the list of issue numbers filed in its window.
# An issue counts toward a slice if its issue-filed timestamp is BETWEEN
# slice.dispatched_at (inclusive) and slice.merged_at (inclusive).
filed_per_slice=$(jq -s --argjson windows "$last_three" '
  map(select(.ev == "issue-filed" and (.data.number // null) != null)) as $filed
  | $windows
  | map(. as $w
      | . + {
          filed_numbers: (
            $filed
            | map(select(.t >= $w.dispatched_at and .t <= $w.merged_at))
            | map(.data.number)
            | unique
          )
        })
' "$EVENTS_FILE")

# Collect all unique issue numbers across the 3-slice window.
all_filed_nums=$(echo "$filed_per_slice" | jq -r '[.[].filed_numbers[]] | unique | .[]')

# ── Fetch issue close state (gh or fixture) ───────────────────────────
# We need: for each filed issue number, its closed_at timestamp (or null
# if still open). Then count "closed in window" for each slice.
close_data="{}"

# Build a map number→closed_at (string or null).
if [ -n "$FIXTURE" ]; then
  # Fixture shape: array of {number, state, closedAt} or {number, state, closed_at}.
  close_data=$(jq '
    map({
      key: (.number | tostring),
      value: (.closedAt // .closed_at // null)
    }) | from_entries
  ' "$FIXTURE")
elif [ "$use_gh" -eq 1 ] && [ -n "$all_filed_nums" ]; then
  if [ -z "$REPO" ]; then
    av_warn "could not derive repo from origin; close ratios will be incomplete"
  else
    # Build the map issue by issue (gh issue view is the only reliable per-number lookup).
    tmpmap=$(mktemp 2>/dev/null || echo "/tmp/plan-health-$$.json")
    echo "{}" > "$tmpmap"
    for num in $all_filed_nums; do
      [ -z "$num" ] && continue
      closed_at=$(gh issue view "$num" --repo "$REPO" --json closedAt --jq '.closedAt // ""' 2>/dev/null || echo "")
      if [ -n "$closed_at" ]; then
        jq --arg k "$num" --arg v "$closed_at" '. + {($k): $v}' "$tmpmap" > "$tmpmap.new" 2>/dev/null && mv "$tmpmap.new" "$tmpmap"
      else
        jq --arg k "$num" '. + {($k): null}' "$tmpmap" > "$tmpmap.new" 2>/dev/null && mv "$tmpmap.new" "$tmpmap"
      fi
    done
    close_data=$(cat "$tmpmap")
    rm -f "$tmpmap" "$tmpmap.new" 2>/dev/null
  fi
fi

# ── Compute per-slice ratios + flag decision ──────────────────────────
# For each slice in the window:
#   filed   = |filed_numbers|
#   closed  = |{n in filed_numbers : close_data[n] != null AND close_data[n] <= merged_at}|
#   ratio   = (closed > 0 ? filed/closed : "inf" if filed > 0 else 0)
#   degraded = filed > closed × 1.5
metric=$(echo "$filed_per_slice" | jq --argjson closes "$close_data" '
  map(. as $w
      | ($w.filed_numbers | length) as $f
      | ([$w.filed_numbers[]
          | tostring as $n
          | ($closes[$n] // null) as $c
          | select($c != null and $c <= $w.merged_at)]
         | length) as $cl
      | $w + {
          filed:    $f,
          closed:   $cl,
          ratio:    (if $cl == 0 then (if $f == 0 then 0 else null end) else ($f / $cl) end),
          degraded: ($f > ($cl * 1.5))
        })
')

# Count consecutive degraded slices (from oldest to newest in our window).
# Flag fires when ALL 3 are degraded AND total filed > 0.
all_three_degraded=$(echo "$metric" | jq '[.[] | .degraded] | all')
total_filed=$(echo "$metric" | jq '[.[] | .filed] | add')

flag="no"
if [ "$all_three_degraded" = "true" ] && [ "$total_filed" -gt 0 ]; then
  flag="yes"
fi

# ── Stdout snapshot ────────────────────────────────────────────────────
window_slices=$(echo "$metric" | jq -r '[.[] | .slice] | join(", ")')
filed_csv=$(echo "$metric" | jq -r '[.[] | .filed | tostring] | join(", ")')
closed_csv=$(echo "$metric" | jq -r '[.[] | .closed | tostring] | join(", ")')
ratio_csv=$(echo "$metric" | jq -r '[.[] | if .ratio == null then "inf" elif .ratio == 0 then "0" else (.ratio | tostring) end] | join(", ")')

echo "plan-health: $plan_slug"
echo "  window: $window_slices"
echo "  filed:   $filed_csv"
echo "  closed:  $closed_csv"
echo "  ratio:   $ratio_csv"
echo "  flagged: $flag (criterion: 3 consecutive slices with filed > closed × 1.5)"

if [ "$flag" = "no" ]; then
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "  (dry-run — event NOT appended, PR comment NOT posted)"
  exit 0
fi

# ── Flag fired: append event + post PR comment ────────────────────────
latest_slice=$(echo "$metric" | jq -r '.[-1] | .slice')
latest_pr=$(echo "$metric" | jq -r '.[-1] | .pr // empty')

# Event payload — arrays in slice order (oldest to newest in window).
ev_window=$(echo "$metric" | jq -c '[.[] | .slice]')
ev_filed=$(echo "$metric" | jq -c '[.[] | .filed]')
ev_closed=$(echo "$metric" | jq -c '[.[] | .closed]')
ev_ratios=$(echo "$metric" | jq -c '[.[] | .ratio]')

event_payload=$(jq -nc \
  --argjson window "$ev_window" \
  --argjson filed "$ev_filed" \
  --argjson closed "$ev_closed" \
  --argjson ratios "$ev_ratios" \
  --arg plan_slug "$plan_slug" \
  '{window: $window, filed: $filed, closed: $closed, ratios: $ratios, plan_slug: $plan_slug}')

event_line=$(jq -nc \
  --arg t "$(av_iso_now)" \
  --arg ev "plan-health-degraded" \
  --arg slice "$latest_slice" \
  --argjson data "$event_payload" \
  '{t: $t, ev: $ev, slice: $slice, data: $data}')

mkdir -p "$REPO_ROOT/.anvil"
echo "$event_line" >> "$EVENTS_FILE"

# ── Resolve PR target for comment ─────────────────────────────────────
target_pr=""
if [ -n "$PR_OVERRIDE" ]; then
  target_pr="$PR_OVERRIDE"
elif [ -n "$latest_pr" ] && [ "$latest_pr" != "null" ]; then
  # Use the latest merged slice's PR (it's now closed, but the comment still posts).
  # Prefer an open PR if one exists. Find via event log: most recent slice-pr-opened
  # whose slice does NOT yet have a slice-merged event.
  open_pr=$(jq -s '
    map(select(.ev != null and (.ev | type) == "string")) as $events
    | ($events | map(select(.ev == "slice-pr-opened")) | sort_by(.t)) as $opened
    | ($events | map(select(.ev == "slice-merged")) | map(.slice)) as $merged_slices
    | $opened
    | map(select(.slice as $s | $merged_slices | index($s) | not))
    | last
    | (.data.pr_number // empty)
  ' "$EVENTS_FILE")
  if [ -n "$open_pr" ] && [ "$open_pr" != "null" ]; then
    target_pr="$open_pr"
  else
    target_pr="$latest_pr"
  fi
fi

# ── Post PR comment (best-effort) ─────────────────────────────────────
if [ -n "$target_pr" ] && [ "$use_gh" -eq 1 ]; then
  table_rows=$(echo "$metric" | jq -r '
    .[] |
    "| \(.slice) | \(.filed) | \(.closed) | " +
    (if .ratio == null then "inf" elif .ratio == 0 then "0" else (.ratio | tostring) end) +
    " |"
  ')
  body=$(cat <<EOF
**plan-health: degraded** — _${plan_slug}_

The most recent 3 merged slices each filed more follow-ups than they closed by 1.5× or more.

| Slice | Filed | Closed | Ratio |
|---|---|---|---|
$table_rows

Non-blocking — this PR is unaffected. Consider whether the plan needs a cleanup slice before launching the next phase.
EOF
)
  if [ -n "$REPO" ]; then
    gh pr comment "$target_pr" --repo "$REPO" --body "$body" 2>/dev/null || \
      av_warn "could not post PR comment to #$target_pr (gh failure; event was appended)"
  else
    gh pr comment "$target_pr" --body "$body" 2>/dev/null || \
      av_warn "could not post PR comment to #$target_pr (gh failure; event was appended)"
  fi
fi

# Always exit 0 — non-blocking gate. Event appended is the audit trail.
exit 0
