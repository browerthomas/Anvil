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

# PR-exists idempotency check (anvil#7): if an open PR already exists
# on this branch (e.g. from a previous failed dispatch attempt), embed
# the PR number so the agent updates the existing one instead of trying
# `gh pr create` and getting a "PR already exists" error.
EXISTING_PR=""
if command -v gh >/dev/null 2>&1; then
  EXISTING_PR=$(av_existing_pr_for_branch "$BRANCH")
fi

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

# Inject "Recent decisions:" section by querying /learn decisions for any
# type:decision rows whose affected_slices contains this slice id. Soft-fail
# if the call errors — the dispatch must not block on a missing learnings file
# or a transient jq failure.
DECISIONS_JSON=""
if [ -f "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" ] && [ -n "$ID" ]; then
  DECISIONS_JSON=$(bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" \
    decisions --affected "$ID" --json --limit 20 2>/dev/null || true)
fi

if [ -n "$DECISIONS_JSON" ] && [ "$DECISIONS_JSON" != "[]" ]; then
  # Render one bullet per decision: [<decision_type>] <key> — <insight>
  DECISIONS_BULLETS=$(echo "$DECISIONS_JSON" | jq -r '
    .[] |
    "- [" + (.decision_type // "decision") + "] " + .key + " — " + .insight
  ' 2>/dev/null || true)
  if [ -n "$DECISIONS_BULLETS" ]; then
    echo
    echo "## Recent decisions"
    echo
    echo "These design decisions (logged via \`/learn add --decision-type ...\`) affect this slice. Treat them as binding constraints unless your scope explicitly reverses them."
    echo
    echo "$DECISIONS_BULLETS"
  fi
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
6. ${EXISTING_PR:+**PR #${EXISTING_PR} already exists on this branch (from a previous dispatch attempt).** Run \`gh pr edit ${EXISTING_PR} --body "<new body>"\` to update it. Do NOT run \`gh pr create\`. Fill the PR template fully.}${EXISTING_PR:-Open a PR against \`${BASE#origin/}\` via \`gh pr create\`. Fill the PR template (\`.github/pull_request_template.md\`) fully.}${CODEX_SECTION}

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
