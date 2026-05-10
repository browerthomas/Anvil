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
# 1. file:line — `<path>:<line>`
echo "$body" | grep -oE "[a-zA-Z0-9_./-]+\.(js|ts|tsx|jsx|md|json|yaml|html|css|sh)(:[0-9]+|#L[0-9]+)" | sort -u | while read -r ref; do
  printf "file_line\t%s\t%s\n" "$ref" "$(echo "$body" | grep -F "$ref" | head -1)"
done

# 2. backtick-quoted symbols — `` `<symbol>` ``
echo "$body" | grep -oE "\`[a-zA-Z_][a-zA-Z0-9_]*(\(\))?\`" | sort -u | while read -r sym; do
  clean=$(echo "$sym" | tr -d '`()')
  # Skip very common false-positive symbols (let, const, function, etc)
  case "$clean" in
    let|const|var|function|return|true|false|null|undefined|async|await|class|new|this|throw|try|catch|if|else|for|while|do|case|switch|break|continue|export|import|from|default|in|of|typeof|instanceof|delete|void|yield) continue;;
  esac
  printf "symbol\t%s\t%s\n" "$clean" "$(echo "$body" | grep -F "$sym" | head -1)"
done

# 3. behavioral claims — lines with hint phrases.
echo "$body" | grep -E "(retries on |retry on |wraps |is wrapped|wraps fetch|custom retry|retry pattern|no retry|auto-retry)" | head -10 | while IFS= read -r line; do
  printf "behavioral\t%s\t%s\n" "$line" "$line"
done

# 4. module references — lines matching "<file.js> — <description>" or "<dir>/<file>:"
echo "$body" | grep -E "^[-*•]?\s*[a-zA-Z0-9_/-]+\.(js|ts)\s+(—|--|-|:)" | while IFS= read -r line; do
  printf "module\t%s\t%s\n" "$line" "$line"
done
