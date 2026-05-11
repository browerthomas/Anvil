#!/usr/bin/env bash
# anvil/learn — prune entries older than a cutoff.
#
# Usage:
#   learn-prune.sh --before <YYYY-MM-DD> [--dry-run] [--yes]
#   learn-prune.sh --keep-confidence high --before <date> [--dry-run] [--yes]
#
# Behaviour:
#   - Reads .anvil/learnings.jsonl, splits into "keep" + "drop".
#   - "drop" by default = entries with timestamp older than --before.
#   - --keep-confidence preserves all entries at that confidence level
#     OR higher, regardless of age (high invariants don't decay).
#   - With --dry-run: prints summary, does not write.
#   - Without --yes: prompts the operator interactively.
#   - On confirm: replaces the file atomically (writes to .tmp then mv).
#
# Pruned entries are NOT lost — they're moved to .anvil/learnings.archive.jsonl
# in case the operator wants to undo or audit.

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

BEFORE=""
KEEP_CONF=""
DRY_RUN=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --before)           BEFORE="$2"; shift 2;;
    --keep-confidence)  KEEP_CONF="$2"; shift 2;;
    --dry-run)          DRY_RUN=1; shift;;
    --yes|-y)           ASSUME_YES=1; shift;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

if [ -z "$BEFORE" ]; then
  av_fail "usage: learn-prune.sh --before <YYYY-MM-DD> [--keep-confidence high|medium|low] [--dry-run] [--yes]"
  exit 1
fi

# Normalize the date to ISO 8601 cutoff.
if ! echo "$BEFORE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  av_fail "--before must be YYYY-MM-DD (got: $BEFORE)"
  exit 1
fi
CUTOFF_ISO="${BEFORE}T00:00:00Z"

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
LEARNINGS_FILE="$REPO_ROOT/.anvil/learnings.jsonl"
ARCHIVE_FILE="$REPO_ROOT/.anvil/learnings.archive.jsonl"

if [ ! -f "$LEARNINGS_FILE" ]; then
  av_info "no learnings file at $LEARNINGS_FILE — nothing to prune"
  exit 0
fi

# Compute keep + drop counts via jq.
counts=$(jq -sc \
  --arg cutoff "$CUTOFF_ISO" \
  --arg conf "$KEEP_CONF" \
  '
  def conf_rank(c):
    if c == "high" then 3
    elif c == "medium" then 2
    elif c == "low" then 1
    else 0 end;

  def keep_conf_rank:
    if ($conf | length) == 0 then 999
    else conf_rank($conf) end;

  def ts_epoch:
    (.timestamp | fromdateiso8601? // 0);

  ($cutoff | fromdateiso8601) as $c
  | map(. as $e
        | if (ts_epoch >= $c) or (conf_rank(.confidence) >= keep_conf_rank)
          then {decision: "keep", entry: $e}
          else {decision: "drop", entry: $e} end)
  | {
      keep: (map(select(.decision == "keep")) | length),
      drop: (map(select(.decision == "drop")) | length)
    }
  ' "$LEARNINGS_FILE")

keep_n=$(echo "$counts" | jq -r '.keep')
drop_n=$(echo "$counts" | jq -r '.drop')

echo
av_info "Prune plan:"
echo "  Cutoff:         $CUTOFF_ISO"
[ -n "$KEEP_CONF" ] && echo "  Keep-confidence: $KEEP_CONF and above"
echo "  Keep:            $keep_n entries"
echo "  Drop:            $drop_n entries"
echo "  Archive file:    $ARCHIVE_FILE"
echo

if [ "$drop_n" -eq 0 ]; then
  av_ok "nothing to drop"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  av_info "dry-run; not writing"
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "  Confirm prune $drop_n entries? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    av_info "aborted; nothing changed"
    exit 0
  fi
fi

# Split: write "drop" to archive, "keep" to a new tmp, then atomic-mv.
tmp_keep="$LEARNINGS_FILE.tmp.$$"
tmp_drop="$ARCHIVE_FILE.tmp.$$"

jq -c \
  --arg cutoff "$CUTOFF_ISO" \
  --arg conf "$KEEP_CONF" \
  '
  def conf_rank(c):
    if c == "high" then 3
    elif c == "medium" then 2
    elif c == "low" then 1
    else 0 end;

  def keep_conf_rank:
    if ($conf | length) == 0 then 999
    else conf_rank($conf) end;

  def ts_epoch:
    (.timestamp | fromdateiso8601? // 0);

  ($cutoff | fromdateiso8601) as $c
  | select((ts_epoch >= $c) or (conf_rank(.confidence) >= keep_conf_rank))
  ' "$LEARNINGS_FILE" > "$tmp_keep"

jq -c \
  --arg cutoff "$CUTOFF_ISO" \
  --arg conf "$KEEP_CONF" \
  '
  def conf_rank(c):
    if c == "high" then 3
    elif c == "medium" then 2
    elif c == "low" then 1
    else 0 end;

  def keep_conf_rank:
    if ($conf | length) == 0 then 999
    else conf_rank($conf) end;

  def ts_epoch:
    (.timestamp | fromdateiso8601? // 0);

  ($cutoff | fromdateiso8601) as $c
  | select((ts_epoch < $c) and (conf_rank(.confidence) < keep_conf_rank))
  ' "$LEARNINGS_FILE" > "$tmp_drop"

# Append archive (don't overwrite — preserves prior prunes).
if [ -s "$tmp_drop" ]; then
  cat "$tmp_drop" >> "$ARCHIVE_FILE"
fi
rm -f "$tmp_drop"

# Atomic replace.
mv "$tmp_keep" "$LEARNINGS_FILE"
av_ok "pruned $drop_n entries (archived to $(basename "$ARCHIVE_FILE"))"
