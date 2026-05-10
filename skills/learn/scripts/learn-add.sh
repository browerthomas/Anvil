#!/usr/bin/env bash
# anvil/learn — append a learning to .anvil/learnings.jsonl
#
# Usage:
#   learn-add.sh <key> <type> "<insight>" \
#     [--confidence <low|medium|high>] \
#     [--source <skill-name>] \
#     [--file <path>]... \
#     [--tag <name>]... \
#     [--slice <id>]
#
# Behaviour:
#   - Validates <type> against the closed vocabulary.
#   - Dedup-by-key: if the same <key> already exists, this counts as a
#     re-confirmation. We DO NOT overwrite — the JSONL stays append-only —
#     instead the new line gets `prior_count` set to the number of prior
#     entries with the same key. A future `/learn search` ranks by this.
#   - Idempotent enough for auto-emit: if --idempotency-window <seconds> is
#     set and an identical (key, source) entry already exists within that
#     window, this is a no-op (exit 0, prints note). Default window: 60s.
#   - Auto-creates .anvil/learnings.jsonl if missing.
#   - On any failure (disk full, bad jq, etc.) the script exits 0 with a
#     warning to stderr — auto-emit hooks must not block the parent skill.
#     Pass --strict to exit non-zero on failure (use in tests).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

# --- Soft-fail wrapper ----------------------------------------------------
# Auto-emit hooks must NEVER kill the parent skill. We catch any error and
# print to stderr but exit 0, unless --strict is set.
STRICT=0
soft_fail() {
  local msg="$1"
  if [ "$STRICT" -eq 1 ]; then
    av_fail "$msg"
    exit 1
  else
    av_warn "/learn add soft-fail: $msg" >&2
    exit 0
  fi
}

# --- Parse args -----------------------------------------------------------
KEY=""
TYPE=""
INSIGHT=""
CONFIDENCE="medium"
SOURCE="manual"
FILES=()
TAGS=()
SLICE_ID=""
IDEM_WINDOW="60"

VALID_TYPES="flake gotcha invariant decision cost perf migration-shape"
VALID_CONFIDENCES="low medium high"

# Positional: <key> <type> "<insight>"
if [ $# -lt 3 ]; then
  echo "usage: learn-add.sh <key> <type> \"<insight>\" [--confidence ...] [--source ...] [--file ...] [--tag ...] [--slice ...] [--idempotency-window <seconds>] [--strict]" >&2
  exit 1
fi
KEY="$1"; TYPE="$2"; INSIGHT="$3"
shift 3

while [ $# -gt 0 ]; do
  case "$1" in
    --confidence) CONFIDENCE="$2"; shift 2;;
    --source)     SOURCE="$2"; shift 2;;
    --file)       FILES+=("$2"); shift 2;;
    --tag)        TAGS+=("$2"); shift 2;;
    --slice)      SLICE_ID="$2"; shift 2;;
    --idempotency-window) IDEM_WINDOW="$2"; shift 2;;
    --strict)     STRICT=1; shift;;
    *) soft_fail "unknown arg: $1";;
  esac
done

# --- Validate --------------------------------------------------------------
if [ -z "$KEY" ]; then soft_fail "key is required"; fi
if [ -z "$TYPE" ]; then soft_fail "type is required"; fi
if [ -z "$INSIGHT" ]; then soft_fail "insight is required"; fi

if ! echo " $VALID_TYPES " | grep -q " $TYPE "; then
  soft_fail "invalid type: $TYPE (one of: $VALID_TYPES)"
fi
if ! echo " $VALID_CONFIDENCES " | grep -q " $CONFIDENCE "; then
  soft_fail "invalid confidence: $CONFIDENCE (one of: $VALID_CONFIDENCES)"
fi

# Key must be slug-safe.
if ! echo "$KEY" | grep -Eq '^[a-z0-9][a-z0-9._-]*$'; then
  soft_fail "key must be lowercase slug: $KEY"
fi

# --- Resolve target file ---------------------------------------------------
REPO_ROOT=$(av_repo_root) || soft_fail "not in a git repo"
ANVIL_DIR="$REPO_ROOT/.anvil"
LEARNINGS_FILE="$ANVIL_DIR/learnings.jsonl"

mkdir -p "$ANVIL_DIR" 2>/dev/null || soft_fail "cannot create $ANVIL_DIR"

# --- Idempotency: check if a recent identical entry exists ---------------
if [ -f "$LEARNINGS_FILE" ] && [ "$IDEM_WINDOW" -gt 0 ] 2>/dev/null; then
  cutoff_epoch=$(( $(date -u +%s) - IDEM_WINDOW ))
  # Find prior entry with same (key, source) and timestamp newer than cutoff.
  # Compatible with both GNU date and BSD date by passing ISO 8601 to jq + computing in jq.
  recent=$(jq -c --arg k "$KEY" --arg s "$SOURCE" --argjson cutoff "$cutoff_epoch" '
    select(.key == $k and .source_skill == $s)
    | select((.timestamp | fromdateiso8601? // 0) >= $cutoff)
  ' "$LEARNINGS_FILE" 2>/dev/null | tail -1)
  if [ -n "$recent" ]; then
    av_info "/learn add: idempotent skip (same key+source within ${IDEM_WINDOW}s)"
    exit 0
  fi
fi

# --- Count prior entries with this key (for prior_count) ------------------
PRIOR_COUNT=0
if [ -f "$LEARNINGS_FILE" ]; then
  PRIOR_COUNT=$(jq -c --arg k "$KEY" 'select(.key == $k)' "$LEARNINGS_FILE" 2>/dev/null | wc -l | tr -d ' ')
  [ -z "$PRIOR_COUNT" ] && PRIOR_COUNT=0
fi

# --- Build the JSON line --------------------------------------------------
files_json="[]"
if [ ${#FILES[@]} -gt 0 ]; then
  files_json=$(printf '%s\n' "${FILES[@]}" | jq -R . | jq -sc .)
fi

tags_json="[]"
if [ ${#TAGS[@]} -gt 0 ]; then
  tags_json=$(printf '%s\n' "${TAGS[@]}" | jq -R . | jq -sc .)
fi

slice_arg="null"
if [ -n "$SLICE_ID" ]; then
  slice_arg=$(jq -n --arg s "$SLICE_ID" '$s')
fi

line=$(jq -nc \
  --arg key "$KEY" \
  --arg type "$TYPE" \
  --arg insight "$INSIGHT" \
  --arg confidence "$CONFIDENCE" \
  --arg source "$SOURCE" \
  --arg ts "$(av_iso_now)" \
  --argjson files "$files_json" \
  --argjson tags "$tags_json" \
  --argjson slice "$slice_arg" \
  --argjson prior "$PRIOR_COUNT" \
  '{
    key: $key,
    type: $type,
    insight: $insight,
    confidence: $confidence,
    source_skill: $source,
    files: $files,
    tags: $tags,
    slice_id: $slice,
    prior_count: $prior,
    timestamp: $ts
  }' 2>/dev/null) || soft_fail "jq failed to build line"

# --- Append (atomic-ish) --------------------------------------------------
if ! echo "$line" >> "$LEARNINGS_FILE" 2>/dev/null; then
  soft_fail "cannot append to $LEARNINGS_FILE"
fi

if [ "$PRIOR_COUNT" -gt 0 ]; then
  av_ok "learning re-confirmed: $KEY (now seen $((PRIOR_COUNT + 1))x)"
else
  av_ok "learning recorded: $KEY [$TYPE/$CONFIDENCE]"
fi
