#!/usr/bin/env bash
# anvil/learn — search .anvil/learnings.jsonl by substring + filters.
#
# Usage:
#   learn-search.sh "<query>" [--type <type>] [--source <skill>] [--key <key>] [--limit <N>] [--json]
#
# Ranking:
#   - Confidence: high > medium > low.
#   - Re-confirmation count: prior_count > 0 boosts the score.
#   - Recency: newer entries rank higher when score is otherwise tied.
#
# Output:
#   Human-readable table by default; --json emits raw matched entries.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

QUERY=""
TYPE_FILTER=""
SOURCE_FILTER=""
KEY_FILTER=""
LIMIT=10
JSON_OUT=0
SHOW_ALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --type)   TYPE_FILTER="$2"; shift 2;;
    --source) SOURCE_FILTER="$2"; shift 2;;
    --key)    KEY_FILTER="$2"; shift 2;;
    --limit)  LIMIT="$2"; shift 2;;
    --json)   JSON_OUT=1; shift;;
    --all)    SHOW_ALL=1; shift;;
    -*) av_fail "unknown arg: $1"; exit 1;;
    *)
      if [ -z "$QUERY" ]; then QUERY="$1"; else QUERY="$QUERY $1"; fi
      shift;;
  esac
done

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
LEARNINGS_FILE="$REPO_ROOT/.anvil/learnings.jsonl"

if [ ! -f "$LEARNINGS_FILE" ]; then
  av_info "no learnings recorded yet — run /learn add <key> <type> \"<insight>\""
  exit 0
fi

# Build the filter pipeline. We want to:
# 1. Filter by --type / --source / --key.
# 2. Filter by substring match on insight + key + tags.
# 3. Score each: confidence weight * 10 + min(prior_count, 5) + recency-bonus.
# 4. Sort descending by score, then by timestamp descending.
# 5. Take top N.

# shellcheck disable=SC2016
results=$(jq -sc \
  --arg q "$QUERY" \
  --arg type "$TYPE_FILTER" \
  --arg source "$SOURCE_FILTER" \
  --arg key "$KEY_FILTER" \
  --argjson limit "$LIMIT" \
  '
  def conf_weight(c):
    if c == "high" then 3
    elif c == "medium" then 2
    elif c == "low" then 1
    else 0 end;

  def ts_epoch:
    (.timestamp | fromdateiso8601? // 0);

  def matches_q($qq):
    if ($qq | length) == 0 then true
    else
      ([.insight, .key, (.tags // []) | tostring]
        | join(" ")
        | ascii_downcase) | contains(($qq | ascii_downcase))
    end;

  # Score = 10*confidence + min(prior_count,5).
  # Recency contributes only as the tie-breaker via the sort key.
  map(. as $e
      | select(($type | length) == 0 or .type == $type)
      | select(($source | length) == 0 or .source_skill == $source)
      | select(($key | length) == 0 or .key == $key)
      | select(matches_q($q))
      | . + {
          _score: ((conf_weight(.confidence)) * 10 + (((.prior_count // 0) | if . > 5 then 5 else . end)))
        })
  | sort_by(-(._score), -(ts_epoch))
  | (if $show_all == 1
     then .
     else group_by(.key) | map(sort_by(-(._score), -(ts_epoch)) | .[0]) | sort_by(-(._score), -(ts_epoch))
     end)
  | .[0:$limit]
  ' --argjson show_all "$SHOW_ALL" "$LEARNINGS_FILE" 2>/dev/null)

if [ -z "$results" ] || [ "$results" = "[]" ]; then
  av_info "no learnings matched"
  exit 0
fi

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$results"
  exit 0
fi

# Human-readable table.
total_count=$(jq 'length' <<<"$results")
echo
av_info "Top $total_count learnings:"
echo

echo "$results" | jq -r '
  def trunc(n): if length > n then .[0:(n-3)] + "..." else . end;
  .[] |
  "  [" + (.type | ascii_upcase) + "/" + .confidence + "] " + .key +
  (if (.prior_count // 0) > 0 then "  (seen " + ((.prior_count + 1) | tostring) + "x)" else "" end) +
  "\n    " + (.insight | trunc(220)) +
  "\n    source: " + .source_skill + " · " +
  (if ((.files // []) | length) > 0 then "files: " + ((.files // []) | join(", ")) + " · " else "" end) +
  "ts: " + .timestamp + "\n"
'
