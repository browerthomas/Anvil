#!/usr/bin/env bash
# anvil/dispatch-slice — assemble the agent prompt from minimal args.
#
# Usage:
#   build-prompt.sh \
#     --id <slice-id> \
#     --scope "<one-paragraph scope>" \
#     [--branch <branch>] \
#     [--worktree <path>] \
#     [--base <base-branch>] \
#     [--issue <issue-number>] \
#     [--tests <test-target>] \
#     [--baseline <test-baseline>] \
#     [--commit-prefix <feat|fix|refactor|chore|docs|test>] \
#     [--scope-name <commit-scope-name>] \
#     [--constraints "<extra-constraints>"] \
#     [--no-codex]
#
# Emits the assembled agent prompt to stdout.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

ID=""
SCOPE=""
BRANCH=""
WORKTREE=""
BASE=""
ISSUE=""
TESTS_TARGET=""
TESTS_BASELINE=""
COMMIT_PREFIX="fix"
SCOPE_NAME=""
EXTRA_CONSTRAINTS=""
NO_CODEX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID="$2"; shift 2;;
    --scope) SCOPE="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --worktree) WORKTREE="$2"; shift 2;;
    --base) BASE="$2"; shift 2;;
    --issue) ISSUE="$2"; shift 2;;
    --tests) TESTS_TARGET="$2"; shift 2;;
    --baseline) TESTS_BASELINE="$2"; shift 2;;
    --commit-prefix) COMMIT_PREFIX="$2"; shift 2;;
    --scope-name) SCOPE_NAME="$2"; shift 2;;
    --constraints) EXTRA_CONSTRAINTS="$2"; shift 2;;
    --no-codex) NO_CODEX=1; shift;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

[ -z "$ID" ] && { av_fail "--id required"; exit 1; }
[ -z "$SCOPE" ] && { av_fail "--scope required"; exit 1; }

# Resolve defaults
[ -z "$BRANCH" ] && BRANCH="${COMMIT_PREFIX}-${ID}"
[ -z "$WORKTREE" ] && WORKTREE=$(av_worktree_path_for "$ID")
[ -z "$BASE" ] && BASE=$(av_default_base_branch)
[ -z "$SCOPE_NAME" ] && SCOPE_NAME="$ID"

# Read project-defaults if present
REPO_ROOT=$(av_repo_root) || REPO_ROOT="."
PROJECT_DEFAULTS_FILE="$REPO_ROOT/.anvil/dispatch-defaults.txt"
PROJECT_CONSTRAINTS=""
if [ -f "$PROJECT_DEFAULTS_FILE" ]; then
  PROJECT_CONSTRAINTS=$(cat "$PROJECT_DEFAULTS_FILE")
fi

# Build commit message
if [ -n "$ISSUE" ]; then
  COMMIT_MSG="${COMMIT_PREFIX}(${SCOPE_NAME}): #${ISSUE} — <imperative summary>"
  ISSUE_LINE="**Issue:** #${ISSUE}"
else
  COMMIT_MSG="${COMMIT_PREFIX}(${SCOPE_NAME}): <imperative summary>"
  ISSUE_LINE=""
fi

# Codex section
CODEX_SECTION=""
if [ "$NO_CODEX" -eq 0 ]; then
  CODEX_SECTION='

## Review

After implementation, the orchestrator will run `/codex-review` (cross-model, preferred) or `/self-review` (Opus fallback) before merge. If you want adversarial feedback on a tricky design decision DURING implementation, fire `/codex-confer` from your worktree.'
fi

# Assemble
cat <<EOF
You are implementing **${ID}**.

${ISSUE_LINE}
**Worktree:** \`${WORKTREE}\` on branch \`${BRANCH}\` based on \`${BASE}\`.

Deps may already be installing in background. If \`node_modules\` is empty in any package, run \`npm install\` first.

## Scope

${SCOPE}

## Required tests
EOF

if [ -n "$TESTS_TARGET" ]; then
  echo
  echo "Tests target: **${TESTS_TARGET}+ passing**${TESTS_BASELINE:+ (current baseline: $TESTS_BASELINE)}."
fi

cat <<EOF

## Hard constraints

- DO NOT touch unrelated files. NO comments-only changes outside this slice's surface.
- DO NOT add new env vars unless strictly required.
- All architectural fitness ratchets must stay green.
- Producer-command-owns-tx pattern stays intact (if your project has one).
- Tests target: ${TESTS_TARGET:-current-baseline}+ passing.
- Commit message format: \`${COMMIT_MSG}\`
- Default Opus reasoning. Quality over token-thrift.
EOF

if [ -n "$PROJECT_CONSTRAINTS" ]; then
  echo
  echo "### Project-specific constraints"
  echo
  echo "$PROJECT_CONSTRAINTS" | sed 's/^/- /'
fi

if [ -n "$EXTRA_CONSTRAINTS" ]; then
  echo
  echo "### Slice-specific constraints"
  echo
  echo "$EXTRA_CONSTRAINTS" | sed 's/^/- /'
fi

cat <<EOF

## Procedure

1. \`npm install\` if any package's \`node_modules\` is empty.
2. Read the relevant files for context (don't read whole repos — be surgical).
3. Implement the scope above.
4. Verify locally:
   - \`npx tsc --noEmit\` (must be clean)
   - \`npx vitest run\` (must hit the test target)
   - Architecture fitness must stay green
5. Commit with the message format above. Push the branch.
6. Open a PR against \`${BASE#origin/}\` via \`gh pr create\`. Fill the PR template (\`.github/pull_request_template.md\`) fully.${CODEX_SECTION}

## Return shape

Return ONLY:
- PR URL
- Test count (before → after)
- LoC delta (additions / deletions)
- Files changed
- Design decisions (anywhere you diverged from the scope or made a non-obvious call)
- Pushback (anything you'd flag — empty if clean)

No filler. No scope summary. No "I will now..." preamble. Findings + facts only.
EOF
