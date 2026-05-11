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

QUERY=""
TYPE_FILTER=""
SOURCE_FILTER=""
KEY_FILTER=""
AFFECTED_FILTER=""
LIMIT=10
JSON_OUT=0
SHOW_ALL=0

# /learn decisions subcommand sugar: if the only positional is `decisions`,
# treat it as `--type decision` with no query. /learn decisions routes
# through this path. A real substring query of "decisions" plus another
# token still works (the sugar only fires when `decisions` is the SOLE
# positional).
POSITIONALS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --type)     TYPE_FILTER="$2"; shift 2;;
    --source)   SOURCE_FILTER="$2"; shift 2;;
    --key)      KEY_FILTER="$2"; shift 2;;
    --affected) AFFECTED_FILTER="$2"; shift 2;;
    --limit)    LIMIT="$2"; shift 2;;
    --json)     JSON_OUT=1; shift;;
    --all)      SHOW_ALL=1; shift;;
    -*) av_fail "unknown arg: $1"; exit 1;;
    *)
      POSITIONALS+=("$1")
      shift;;
  esac
done

if [ ${#POSITIONALS[@]} -eq 1 ] && [ "${POSITIONALS[0]}" = "decisions" ]; then
  # Subcommand sugar — only when `decisions` is the sole positional.
  if [ -z "$TYPE_FILTER" ]; then
    TYPE_FILTER="decision"
  fi
else
  # Existing behavior — concatenate positionals into a substring QUERY.
  for p in "${POSITIONALS[@]}"; do
    if [ -z "$QUERY" ]; then QUERY="$p"; else QUERY="$QUERY $p"; fi
  done
fi

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
  --arg affected "$AFFECTED_FILTER" \
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

  def matches_affected($a):
    if ($a | length) == 0 then true
    else
      ((.affected_slices // []) | index($a)) != null
    end;

  # Score = 10*confidence + min(prior_count,5).
  # Recency contributes only as the tie-breaker via the sort key.
  map(. as $e
      | select(($type | length) == 0 or .type == $type)
      | select(($source | length) == 0 or .source_skill == $source)
      | select(($key | length) == 0 or .key == $key)
      | select(matches_affected($affected))
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
  "  [" + (.type | ascii_upcase) +
  (if .decision_type then "/" + .decision_type else "" end) +
  "/" + .confidence + "] " + .key +
  (if (.prior_count // 0) > 0 then "  (seen " + ((.prior_count + 1) | tostring) + "x)" else "" end) +
  "\n    " + (.insight | trunc(220)) +
  "\n    source: " + .source_skill + " · " +
  (if ((.files // []) | length) > 0 then "files: " + ((.files // []) | join(", ")) + " · " else "" end) +
  (if ((.affected_slices // []) | length) > 0 then "affects: " + ((.affected_slices // []) | join(", ")) + " · " else "" end) +
  "ts: " + .timestamp + "\n"
'
