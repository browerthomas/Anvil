#!/usr/bin/env bash
# anvil/learn — print last N entries grouped by type.
#
# Usage:
#   learn-summary.sh [--limit <N>] [--since <YYYY-MM-DD>]
#
# Output: human-readable, grouped by type, ordered by recency within group.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

LIMIT=20
SINCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2;;
    --since) SINCE="$2"; shift 2;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
LEARNINGS_FILE="$REPO_ROOT/.anvil/learnings.jsonl"

if [ ! -f "$LEARNINGS_FILE" ]; then
  av_info "no learnings recorded yet"
  exit 0
fi

SINCE_ARG="null"
if [ -n "$SINCE" ]; then
  if ! echo "$SINCE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    av_fail "--since must be YYYY-MM-DD"
    exit 1
  fi
  SINCE_ARG=$(jq -n --arg s "${SINCE}T00:00:00Z" '$s')
fi

# Print: total, then grouped sections.
total=$(wc -l < "$LEARNINGS_FILE" | tr -d ' ')
echo
av_info "Learnings summary ($total total entries)"
echo

jq -sc \
  --argjson limit "$LIMIT" \
  --argjson since "$SINCE_ARG" \
  '
  def ts_epoch:
    (.timestamp | fromdateiso8601? // 0);

  (if $since == null then 0
   else ($since | fromdateiso8601) end) as $cutoff
  | map(select(ts_epoch >= $cutoff))
  | sort_by(-ts_epoch)
  | .[0:$limit]
  | group_by(.type)
  | sort_by(.[0].type)
  ' "$LEARNINGS_FILE" \
| jq -r '
    .[] | (
      "## " + (.[0].type | ascii_upcase) + " (\(length))",
      "",
      (.[] |
        "  - [" + .confidence + "] " + .key +
        (if (.prior_count // 0) > 0 then "  (seen \(.prior_count + 1)x)" else "" end) +
        "\n    " + (.insight | if length > 200 then .[0:197] + "..." else . end) +
        "\n    source: " + .source_skill + " · " + .timestamp
      ),
      ""
    )
  '
