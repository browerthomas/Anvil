#!/usr/bin/env bash
# anvil/config-bootstrap — extract candidate rules from a context doc.
#
# Reads a markdown doc on stdin or as $1. Emits TSV on stdout:
#   <target>\t<rule-text>
# where <target> is one of: forbidden | dispatch | flake.
#
# The skill orchestrator (Claude) reads the TSV, normalises each row into the
# right format for its target file, and writes the populated .anvil/ file.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

input="${1:-/dev/stdin}"
content=$(cat "$input")

# Forbidden patterns — lines that say "do not", "never", "deprecated", "deleted"
echo "$content" | grep -niE "(DO NOT|must not|never (use|import|add)|deleted in|removed in|deprecated|forbidden|do not bypass|do not commit)" | head -30 | while IFS= read -r line; do
  printf "forbidden\t%s\n" "$line"
done

# Dispatch defaults — lines that say "always", "every PR", "default to", "tests must"
echo "$content" | grep -niE "(every PR must|always |default to |tests must|every commit|every change|test target|test count|commit message)" | head -30 | while IFS= read -r line; do
  printf "dispatch\t%s\n" "$line"
done

# Known flakes — lines that mention "flake", "retry once", "known race"
echo "$content" | grep -niE "(flake|flaky|known race|retry once|intermittent failure|race condition)" | head -30 | while IFS= read -r line; do
  printf "flake\t%s\n" "$line"
done
