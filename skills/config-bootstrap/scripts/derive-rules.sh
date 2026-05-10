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

# Forbidden patterns — lines that flag a rule the codebase enforces.
# Broadened from v0.4: caught only "DO NOT" / "must not" / "never (use|import|add)";
# missed contracted "Don't", capitalised "Never", spaced "do not", and bullet-form
# usage. Now case-insensitive across a wider phrase set, with deduplication.
echo "$content" | grep -niE "(do.{0,3}not|don.t|must not|never[[:space:]]|n[ao]t allowed|deleted in|removed in|deprecated|forbidden|do not bypass|do not commit|do not import|never use|never add)" | head -50 | sort -u -t: -k2 | while IFS= read -r line; do
  printf "forbidden\t%s\n" "$line"
done

# Dispatch defaults — lines that flag a project-wide rule every PR/commit must follow.
# Broadened: also catches "Default to", "always run", "every push", "before commit".
echo "$content" | grep -niE "(every PR must|every commit|every change|every push|always[[:space:]]|default to |tests must|test target|test count|commit message|before commit|before push|before merge|pre-push|pre-commit)" | head -30 | sort -u -t: -k2 | while IFS= read -r line; do
  printf "dispatch\t%s\n" "$line"
done

# Known flakes — lines that admit a chronic flake or retry-once pattern.
# Broadened: also catches "chronic flake", "intermittent", "may fail", "known to fail".
echo "$content" | grep -niE "(flake|flaky|known race|retry once|intermittent|race condition|chronic|may fail|known to fail|sometimes fails)" | head -30 | sort -u -t: -k2 | while IFS= read -r line; do
  printf "flake\t%s\n" "$line"
done
