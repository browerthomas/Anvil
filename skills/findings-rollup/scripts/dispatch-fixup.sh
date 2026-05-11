#!/usr/bin/env bash
# anvil/findings-rollup — assemble the fix-up agent prompt.
#
# Emits the agent prompt to stdout. The caller (skill orchestrator) feeds this
# into the Agent tool. The prompt assumes:
#   - the worktree already exists (PR was opened from it; same branch is being amended)
#   - deps are installed
#   - the review markdown is at the path passed in
#
# Usage:
#   dispatch-fixup.sh \
#     --review <path-to-review.md> \
#     --pr <N> \
#     [--branch <name>] \
#     [--worktree <path>] \
#     [--rollup-issue <N>]
#
# Output: ~600-800 word agent prompt to stdout.

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

REVIEW=""
PR=""
BRANCH=""
WORKTREE=""
ROLLUP_ISSUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --review) REVIEW="$2"; shift 2;;
    --pr) PR="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --worktree) WORKTREE="$2"; shift 2;;
    --rollup-issue) ROLLUP_ISSUE="$2"; shift 2;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

[ -z "$REVIEW" ] && { av_fail "--review required"; exit 1; }
[ -z "$PR" ] && { av_fail "--pr required"; exit 1; }
[ ! -f "$REVIEW" ] && { av_fail "review file not found: $REVIEW"; exit 1; }

# Auto-derive branch from PR if not given
if [ -z "$BRANCH" ]; then
  BRANCH=$(gh pr view "$PR" --json headRefName --jq '.headRefName' 2>/dev/null) || {
    av_fail "could not auto-derive branch — pass --branch"
    exit 1
  }
fi

# Auto-derive worktree from branch if not given
if [ -z "$WORKTREE" ]; then
  WORKTREE=$(git worktree list | awk -v b="$BRANCH" '$NF == "[" b "]" {print $1}' | head -1)
fi

# Read project dispatch-defaults if present
REPO_ROOT=$(av_repo_root) || REPO_ROOT="."
DISPATCH_DEFAULTS_FILE="$REPO_ROOT/.anvil/dispatch-defaults.txt"
PROJECT_CONSTRAINTS=""
if [ -f "$DISPATCH_DEFAULTS_FILE" ]; then
  PROJECT_CONSTRAINTS=$(cat "$DISPATCH_DEFAULTS_FILE")
fi

ROLLUP_LINE=""
if [ -n "$ROLLUP_ISSUE" ]; then
  ROLLUP_LINE="P2/P3 findings are tracked separately in issue #${ROLLUP_ISSUE}; do NOT address them in this fix-up unless trivially adjacent to a P0/P1 fix."
fi

cat <<EOF
You are amending PR [#${PR}](https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pull/${PR}) on branch \`${BRANCH}\` after a multi-critic adversarial review surfaced findings. Your job is to amend the PR with fixes for all P0s and all P1s. ${ROLLUP_LINE}

**Worktree:** \`${WORKTREE}\` (already exists; deps already installed; branch already pushed to origin).

**Synthesis report to read first:** \`${REVIEW}\`. It lists every finding with file:line + suggested fix. **Treat that report as your acceptance contract** — every P0 + P1 in that file must be addressed, with the suggested fix as the default unless you have a substantive reason to diverge.

## Procedure

1. \`cd ${WORKTREE}\` (the worktree). Verify branch is \`${BRANCH}\` and \`git status\` is clean.
2. \`git pull --rebase origin ${BRANCH}\` (in case of any drift).
3. Read the review report fully.
4. Implement fixes — group related items into separate commits if natural (e.g. one commit for "test additions", one for "redaction wire-through"), or one consolidated fix-up commit if you prefer.
5. Verify locally:
   - \`npx vitest run\` (or the project's test runner) — must hit baseline-or-better.
   - \`npm run lint\` (or equivalent) — clean.
   - \`git config core.hooksPath\` — if empty, run lint+test manually before push since the pre-push hook won't fire.
6. Push commits: \`git push origin ${BRANCH}\`.
7. Update PR description with a "Fix-up commit" section linking to the review report and listing each P0/P1 fix with a one-line summary.
8. Comment on PR: \`gh pr comment ${PR} --body "Fix-up landed; addressed N P0s + M P1s. P2/P3 in #${ROLLUP_ISSUE:-<rollup>}."\`

## Hard constraints

EOF

if [ -n "$PROJECT_CONSTRAINTS" ]; then
  echo "$PROJECT_CONSTRAINTS" | sed 's/^/- /'
  echo
fi

cat <<'EOF'
- DO NOT touch unrelated files. The fix-up scope is the P0/P1 list only.
- DO NOT use --no-verify on git push.
- Default Opus reasoning. Quality over token-thrift.
- DO NOT address P2/P3 findings unless they happen to fall out of a P0/P1 fix for free.

## Return shape

Return ONLY:
- New PR commit count (before → after)
- Test count (before → after)
- LoC delta of the fix-up
- Files changed
- Per-finding status: which P0/P1 fixed, which had to be deferred (with reason)
- Any P2/P3 fixes that landed for free
- Pushback (if a fix conflicts with another or the spec is internally contradictory, name it)

No filler.
EOF
