#!/usr/bin/env bash
# anvil/recap — per-slice agent token / tool-use / wall-time rollup.
#
# Reads `agent-completed` events from `.anvil/grind-events.jsonl` and prints
# a per-slice table + grand total. Multiple agents per slice (review fix-ups,
# dispatched fixers) sum together; the row shows the sum.
#
# Usage:
#   grind-summary.sh \
#     [--events <path>] \
#     [--plan <plan-path>] \
#     [--slug <label>] \
#     [--repo-root <path>]
#
# Output (stdout):
#   === Grind summary: <plan-path or "(no plan)"> ===
#
#   Slice  PR      Tokens     Tool uses  Wall time
#   B0     #949    150,200    88         12m 14s
#   B2     #952    202,018    140        17m 36s
#   ...
#   ────────────────────────────────────────────────
#   Total          1,847,221  1,002      4h 12m  (n=11 agents)
#   + orchestrator: run `/cost` in Claude Code for parent-side tokens
#
# When no `agent-completed` events exist, prints a one-line "(no agent-
# completed events recorded)" notice + exits 0 — this is not an error.
#
# Exit codes:
#   0 — rollup printed (including the empty-log case)
#   3 — input error (bad args, missing dependencies)

set -u

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

EVENTS_FILE=""
PLAN_PATH=""
SLUG=""
REPO_ROOT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --events)     EVENTS_FILE="$2"; shift 2;;
    --plan)       PLAN_PATH="$2"; shift 2;;
    --slug)       SLUG="$2"; shift 2;;
    --repo-root)  REPO_ROOT_OVERRIDE="$2"; shift 2;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0;;
    *) av_fail "unknown arg: $1"; exit 3;;
  esac
done

for tool in jq awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    av_fail "missing dependency: $tool"
    exit 3
  fi
done

if [ -z "$EVENTS_FILE" ]; then
  if [ -n "$REPO_ROOT_OVERRIDE" ]; then
    REPO_ROOT="$REPO_ROOT_OVERRIDE"
  else
    REPO_ROOT=$(av_repo_root) || REPO_ROOT="$PWD"
  fi
  EVENTS_FILE="$REPO_ROOT/.anvil/grind-events.jsonl"
fi

LABEL="${PLAN_PATH:-}"
if [ -z "$LABEL" ] && [ -n "$SLUG" ]; then
  LABEL="$SLUG"
fi
[ -z "$LABEL" ] && LABEL="(no plan)"

echo "=== Grind summary: $LABEL ==="
echo

if [ ! -f "$EVENTS_FILE" ]; then
  echo "(no event log at $EVENTS_FILE)"
  echo "+ orchestrator: run \`/cost\` in Claude Code for parent-side tokens"
  exit 0
fi

# Fold all agent-completed events into per-slice rows. The data shape we
# emit is one tab-delimited row per slice from jq, then awk renders the
# final table.
#
# Row shape (tab-separated):
#   <slice>\t<pr_or_blank>\t<total_tokens>\t<tool_uses>\t<duration_ms>\t<agents>
#
# jq pulls the PR number from a sibling slice-pr-opened event when one exists
# for the same slice (so the rollup can label rows with #N).
ROWS=$(jq -s --raw-output '
  # Drop sentinel/doc lines.
  map(select(.ev != null and (.ev | type) == "string")) as $events
  | ($events
     | map(select(.ev == "slice-pr-opened"))
     | map({key: .slice, value: .data.pr_number})
     | from_entries) as $prs
  | $events
  | map(select(.ev == "agent-completed"))
  | group_by(.slice)
  | map({
      slice: (.[0].slice // ""),
      pr:    ($prs[.[0].slice] // null),
      total: (map(.data.total_tokens // 0) | add // 0),
      tools: (map(.data.tool_uses    // 0) | add // 0),
      dur:   (map(.data.duration_ms  // 0) | add // 0),
      n:     length
    })
  | sort_by(.slice)
  | .[]
  | [
      .slice,
      (if .pr != null then "#" + (.pr | tostring) else "" end),
      (.total | tostring),
      (.tools | tostring),
      (.dur   | tostring),
      (.n     | tostring)
    ]
  | @tsv
' "$EVENTS_FILE" 2>/dev/null || true)

if [ -z "$ROWS" ]; then
  echo "(no agent-completed events recorded)"
  echo "+ orchestrator: run \`/cost\` in Claude Code for parent-side tokens"
  exit 0
fi

# Render. awk handles thousands-separator + wall-time pretty-print.
#   ms <  60_000     → "N.Ns" (1dp)
#   ms <  3_600_000  → "Mm SSs"
#   ms >= 3_600_000  → "Hh MMm"
printf '%s\n' "$ROWS" | awk -F'\t' '
  function commafy(n,    s, out, len, i) {
    s = sprintf("%d", n + 0)
    len = length(s)
    out = ""
    for (i = 1; i <= len; i++) {
      out = out substr(s, i, 1)
      if (((len - i) % 3) == 0 && i < len) out = out ","
    }
    return out
  }
  function walltime(ms,    s, m, h) {
    ms = ms + 0
    if (ms < 60000) {
      return sprintf("%.1fs", ms / 1000.0)
    } else if (ms < 3600000) {
      m = int(ms / 60000)
      s = int((ms % 60000) / 1000)
      return sprintf("%dm %02ds", m, s)
    } else {
      h = int(ms / 3600000)
      m = int((ms % 3600000) / 60000)
      return sprintf("%dh %02dm", h, m)
    }
  }
  BEGIN {
    printf "%-7s %-8s %-12s %-10s %s\n", "Slice", "PR", "Tokens", "Tool uses", "Wall time"
    total_tokens = 0
    total_tools  = 0
    total_dur    = 0
    total_agents = 0
  }
  {
    slice = $1
    pr    = $2
    t     = $3 + 0
    tools = $4 + 0
    dur   = $5 + 0
    n     = $6 + 0
    total_tokens += t
    total_tools  += tools
    total_dur    += dur
    total_agents += n
    printf "%-7s %-8s %-12s %-10s %s\n", slice, pr, commafy(t), commafy(tools), walltime(dur)
  }
  END {
    sep = "────────────────────────────────────────────────"
    print sep
    printf "%-7s %-8s %-12s %-10s %s  (n=%d %s)\n", \
      "Total", "", commafy(total_tokens), commafy(total_tools), walltime(total_dur), \
      total_agents, (total_agents == 1 ? "agent" : "agents")
  }
'

echo "+ orchestrator: run \`/cost\` in Claude Code for parent-side tokens"
exit 0
