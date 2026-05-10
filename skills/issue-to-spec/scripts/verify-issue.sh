#!/usr/bin/env bash
# anvil/issue-to-spec — fetch an issue body + extract factual claims as a TSV.
#
# Usage:
#   verify-issue.sh --issue <N> [--repo <owner/repo>]
#
# Output (stdout): TSV with columns:
#   <claim-type>\t<claim-text>\t<source-line-from-body>
#
# Claim types: file_line | symbol | behavioral | module
#
# The downstream verification step (the skill orchestrator, i.e. Claude) reads
# the TSV, runs the relevant grep/read for each claim, and writes the corrected
# mini-spec markdown.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

ISSUE=""
REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

[ -z "$ISSUE" ] && { av_fail "--issue required"; exit 1; }

# Default repo from current dir
[ -z "$REPO" ] && REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || true

# Fetch the issue body
body=$(gh issue view "$ISSUE" ${REPO:+--repo "$REPO"} --json body --jq '.body' 2>/dev/null)
[ -z "$body" ] && { av_fail "could not fetch issue $ISSUE"; exit 1; }

# Extract claims via regex.
# 1. file:line — `<path>:<line>` or `<path>#L<line>`
echo "$body" | grep -oE "[a-zA-Z0-9_./-]+\.(js|ts|tsx|jsx|mjs|cjs|md|json|yaml|yml|html|css|sh|py|rs|go|rb)(:[0-9]+|#L[0-9]+)" | sort -u | while read -r ref; do
  printf "file_line\t%s\t%s\n" "$ref" "$(echo "$body" | grep -F "$ref" | head -1)"
done

# 2. backtick-quoted symbols — `` `<symbol>` `` or `` `<symbol>()` ``
echo "$body" | grep -oE "\`[a-zA-Z_][a-zA-Z0-9_]*(\(\))?\`" | sort -u | while read -r sym; do
  clean=$(echo "$sym" | tr -d '`()')
  case "$clean" in
    let|const|var|function|return|true|false|null|undefined|async|await|class|new|this|throw|try|catch|if|else|for|while|do|case|switch|break|continue|export|import|from|default|in|of|typeof|instanceof|delete|void|yield) continue;;
  esac
  printf "symbol\t%s\t%s\n" "$clean" "$(echo "$body" | grep -F "$sym" | head -1)"
done

# 2b. parenthesised symbol lists — issue bodies often write `(openCheckout, markPaid, markDigitalDelivered)`
#     where each symbol is bare (no backticks) but the list shape is recoverable.
echo "$body" | grep -oE "\([a-zA-Z_][a-zA-Z0-9_]*(,\s*[a-zA-Z_][a-zA-Z0-9_]*){1,}\)" | sort -u | while read -r list; do
  # Strip outer parens, split on comma, emit one row per identifier.
  inner=$(echo "$list" | tr -d '()')
  echo "$inner" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | while read -r sym; do
    [ -z "$sym" ] && continue
    case "$sym" in
      let|const|var|function|return|true|false|null|undefined|async|await|class|new|this) continue;;
    esac
    printf "symbol\t%s\t%s\n" "$sym" "$(echo "$body" | grep -F "$list" | head -1)"
  done
done

# 3. file-size claims — "is N LoC" / "has N lines"
echo "$body" | grep -oE "(is|has|with|at)\s+[0-9]+\s*(LoC|lines?\b)" | head -10 | while IFS= read -r claim; do
  printf "file_size\t%s\t%s\n" "$claim" "$(echo "$body" | grep -F "$claim" | head -1)"
done

# 4. line-number claims — "(line N)" / "at line N"
echo "$body" | grep -oE "(at\s+)?\(?line\s+[0-9]+\)?" | sort -u | while read -r claim; do
  printf "line_number\t%s\t%s\n" "$claim" "$(echo "$body" | grep -F "$claim" | head -1)"
done

# 5. count claims — "N+ test sites" / "N callers" / "N references"
echo "$body" | grep -oE "[0-9]+\+?\s+(test sites?|tests?|callers?|references?|usages?|callsites?|callers?)" | head -10 | while IFS= read -r claim; do
  printf "count\t%s\t%s\n" "$claim" "$(echo "$body" | grep -F "$claim" | head -1)"
done

# 6. behavioral claims — lines with hint phrases.
echo "$body" | grep -iE "(retries on |retry on |wraps |is wrapped|wraps fetch|custom retry|retry pattern|no retry|auto-retry|fall back to|falls back to)" | head -10 | while IFS= read -r line; do
  printf "behavioral\t%s\t%s\n" "$line" "$line"
done

# 7. module references — lines matching "<file.js> — <description>" or "<dir>/<file>:"
echo "$body" | grep -E "^[-*•]?\s*[a-zA-Z0-9_/-]+\.(js|ts|tsx|jsx|mjs|cjs|py|rs|go|rb)\s+(—|--|-|:)" | while IFS= read -r line; do
  printf "module\t%s\t%s\n" "$line" "$line"
done
