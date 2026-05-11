#!/usr/bin/env bash
# anvil/findings-rollup — extract P0/P1/P2/P3 finding lists from a review markdown.
#
# Reads the review file on stdin or as $1. Emits a JSON object on stdout:
#   { "p0": ["..."], "p1": [...], "p2": [...], "p3": [...], "verdict": "BLOCK|PROCEED-WITH-CAUTION|CLEAN" }
#
# Each finding is the raw markdown line (the bullet, including severity tag + summary + file:line).
# Multi-line explanation + fix details under each bullet are kept attached via newlines.

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

input="${1:-/dev/stdin}"
[ ! -f "$input" ] && [ "$input" != "/dev/stdin" ] && { av_fail "review file not found: $input"; exit 1; }

# Read all input
content=$(cat "$input")

# Extract verdict (last "Verdict:" line)
verdict=$(echo "$content" | grep -E "^(Verdict|## Verdict)" | tail -1 | grep -oE "BLOCK|PROCEED-WITH-CAUTION|CLEAN" | head -1)
[ -z "$verdict" ] && verdict="UNKNOWN"

# Extract findings under each P{0,1,2,3} heading.
# A finding starts with `- [P0]` or `- [P1]` etc. and continues until the next finding or the next heading.
extract_section() {
  local sev="$1"
  echo "$content" | awk -v sev="$sev" '
    BEGIN { in_section=0; in_finding=0; buf="" }
    /^## P[0-3] findings/ {
      if (in_finding && buf != "") { print buf; buf="" }
      in_section=0; in_finding=0
      if ($0 ~ "## " sev " findings") { in_section=1 }
      next
    }
    /^## / && !/^## P[0-3] / {
      if (in_finding && buf != "") { print buf; buf="" }
      in_section=0; in_finding=0
      next
    }
    in_section && /^- \[/ {
      if (in_finding && buf != "") { print buf }
      buf=$0; in_finding=1
      next
    }
    in_section && in_finding {
      if ($0 == "") {
        if (buf != "") { print buf; buf=""; in_finding=0 }
      } else {
        buf = buf "\n" $0
      }
    }
    END { if (in_finding && buf != "") { print buf } }
  '
}

# Convert findings to JSON array — one element per finding (multi-line-safe via base64).
findings_to_json() {
  local sev="$1"
  extract_section "$sev" | awk 'BEGIN{first=1; printf "["} NF{
    if (!first) printf ","; first=0
    # Use a safe-to-jq encoding: pipe through jq raw-input
    printf "%s", $0 ORS
  } END{printf "]"}' | jq -Rs '
    split("\n---FINDING-DELIM---\n")
    | map(select(length > 0))
  ' 2>/dev/null || echo "[]"
}

# Simpler: build the JSON via jq directly from the extracted text.
build_json() {
  local sev="$1"
  extract_section "$sev" | jq -Rs 'split("\n\n") | map(select(length > 0))' 2>/dev/null || echo "[]"
}

p0=$(build_json "P0")
p1=$(build_json "P1")
p2=$(build_json "P2")
p3=$(build_json "P3")

jq -n --argjson p0 "$p0" --argjson p1 "$p1" --argjson p2 "$p2" --argjson p3 "$p3" --arg verdict "$verdict" \
  '{p0: $p0, p1: $p1, p2: $p2, p3: $p3, verdict: $verdict}'
