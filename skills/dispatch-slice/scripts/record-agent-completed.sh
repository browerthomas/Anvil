#!/usr/bin/env bash
# anvil/dispatch-slice — append an `agent-completed` event to the grind
# event log after a sub-agent returns.
#
# Step 6 of /dispatch-slice (issue #75): the orchestrator parses the agent's
# completion notification for its `<usage>` block (total_tokens / tool_uses /
# duration_ms) and persists one event per agent return. /recap reads these
# back into a per-slice token + tool + wall-time rollup.
#
# Soft-fail contract:
#   - Missing usage block / file → log a warning, exit 0, no event written.
#   - Missing jq                 → log a warning, exit 0, no event written.
#   - Bad notification file path → log a warning, exit 0, no event written.
#
# The dispatcher MUST NOT crash the slice if this script fails — older
# runtimes and manual /dispatch-slice invocations don't carry the block.
#
# Usage:
#   record-agent-completed.sh \
#     --slice <slice-id> \
#     --agent <agent-id> \
#     --model <model-name> \
#     --branch <branch> \
#     [--notification-file <path>] \
#     [--total-tokens N --tool-uses N --duration-ms N]
#
# Either --notification-file (which is parsed for a <usage> block) OR the
# three numeric flags must be supplied. The flag form is for tests + for
# callers that already have the values in hand.

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

SLICE=""
AGENT=""
MODEL=""
BRANCH=""
NOTIFICATION_FILE=""
TOTAL_TOKENS=""
TOOL_USES=""
DURATION_MS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --slice)              SLICE="$2"; shift 2;;
    --agent)              AGENT="$2"; shift 2;;
    --model)              MODEL="$2"; shift 2;;
    --branch)             BRANCH="$2"; shift 2;;
    --notification-file)  NOTIFICATION_FILE="$2"; shift 2;;
    --total-tokens)       TOTAL_TOKENS="$2"; shift 2;;
    --tool-uses)          TOOL_USES="$2"; shift 2;;
    --duration-ms)        DURATION_MS="$2"; shift 2;;
    *)
      av_warn "record-agent-completed: unknown arg '$1' — ignoring (soft-fail)"
      shift
      ;;
  esac
done

if [ -z "$SLICE" ]; then
  av_warn "record-agent-completed: --slice required — skipping event append"
  exit 0
fi

# Resolve usage counters. If the explicit flags were passed, use them.
# Otherwise parse the notification file for a <usage> block.
if [ -z "$TOTAL_TOKENS" ] && [ -z "$TOOL_USES" ] && [ -z "$DURATION_MS" ]; then
  if [ -z "$NOTIFICATION_FILE" ] || [ ! -f "$NOTIFICATION_FILE" ]; then
    av_warn "record-agent-completed: no --notification-file and no counter flags — skipping event append (slice=$SLICE)"
    exit 0
  fi
  parsed=$(av_parse_agent_usage "$NOTIFICATION_FILE" 2>/dev/null) || {
    av_warn "record-agent-completed: <usage> block missing or unparseable in $NOTIFICATION_FILE — skipping event append (slice=$SLICE)"
    exit 0
  }
  TOTAL_TOKENS=$(printf '%s\n' "$parsed" | sed -n '1p')
  TOOL_USES=$(printf '%s\n'   "$parsed" | sed -n '2p')
  DURATION_MS=$(printf '%s\n' "$parsed" | sed -n '3p')
fi

# Validate numeric — drop anything that isn't a non-negative integer so a
# parse glitch can't smuggle a string into the event log.
_is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }
_is_uint "${TOTAL_TOKENS:-}" || TOTAL_TOKENS=""
_is_uint "${TOOL_USES:-}"    || TOOL_USES=""
_is_uint "${DURATION_MS:-}"  || DURATION_MS=""

if [ -z "$TOTAL_TOKENS" ] && [ -z "$TOOL_USES" ] && [ -z "$DURATION_MS" ]; then
  av_warn "record-agent-completed: all three counters empty/non-numeric — skipping event append (slice=$SLICE)"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  av_warn "record-agent-completed: jq not found — skipping event append (slice=$SLICE)"
  exit 0
fi

REPO_ROOT=$(av_repo_root) || REPO_ROOT="$PWD"
ANVIL_DIR="$REPO_ROOT/.anvil"
EVENTS_FILE="$ANVIL_DIR/grind-events.jsonl"

if ! mkdir -p "$ANVIL_DIR" 2>/dev/null; then
  av_warn "record-agent-completed: cannot create $ANVIL_DIR — skipping event append (slice=$SLICE)"
  exit 0
fi

NOW="$(av_iso_now)"

# Build the data object — empty counters become JSON null so the rollup
# can distinguish "agent reported zero" from "runtime didn't report".
data=$(jq -nc \
  --arg agent "${AGENT:-}" \
  --arg model "${MODEL:-}" \
  --arg branch "${BRANCH:-}" \
  --arg total "${TOTAL_TOKENS:-}" \
  --arg tool  "${TOOL_USES:-}" \
  --arg dur   "${DURATION_MS:-}" \
  '
    {
      agent:  (if $agent  != "" then $agent  else null end),
      model:  (if $model  != "" then $model  else null end),
      branch: (if $branch != "" then $branch else null end),
      total_tokens: (if $total != "" then ($total | tonumber) else null end),
      tool_uses:    (if $tool  != "" then ($tool  | tonumber) else null end),
      duration_ms:  (if $dur   != "" then ($dur   | tonumber) else null end)
    }
  ') || {
  av_warn "record-agent-completed: jq failed to build event payload — skipping event append (slice=$SLICE)"
  exit 0
}

frame=$(jq -nc \
  --arg t "$NOW" \
  --arg slice "$SLICE" \
  --argjson data "$data" \
  '{t:$t, ev:"agent-completed", slice:$slice, data:$data}') || {
  av_warn "record-agent-completed: jq failed to build event frame — skipping event append (slice=$SLICE)"
  exit 0
}

printf '%s\n' "$frame" >> "$EVENTS_FILE" || {
  av_warn "record-agent-completed: append to $EVENTS_FILE failed — skipping event (slice=$SLICE)"
  exit 0
}

av_ok "agent-completed event recorded (slice=$SLICE)"
exit 0
