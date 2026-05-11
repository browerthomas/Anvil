#!/usr/bin/env bash
# anvil/pre-merge-gate — concrete verification script.
#
# Usage:
#   verify.sh <pr-number-or-branch> [--worktree <path>] [--base <branch>] [--skip-rebase] [--strict]
#
# Returns:
#   0 → MERGE-READY
#   1 → BLOCKED (specific failure printed to stderr)
#   2 → YELLOW FLAGS (warnings, --strict treats as blocked)

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

PR_OR_BRANCH="${1:-}"
shift || true
if [ -z "$PR_OR_BRANCH" ]; then
  av_fail "usage: verify.sh <pr-number-or-branch> [opts]"
  exit 1
fi

WORKTREE=""
BASE=""
SKIP_REBASE=0
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="$2"; shift 2;;
    --base)     BASE="$2"; shift 2;;
    --skip-rebase) SKIP_REBASE=1; shift;;
    --strict)   STRICT=1; shift;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

# Resolve repo + config
REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }
CONFIG="$REPO_ROOT/.anvil/pre-merge-gate.config.json"
PATTERNS_FILE="$REPO_ROOT/.anvil/forbidden-patterns.txt"

# Defaults from config (fall through to skill defaults if config absent)
get_cfg() {
  if [ -f "$CONFIG" ]; then
    jq -r "$1 // empty" "$CONFIG" 2>/dev/null
  fi
}
[ -z "$BASE" ] && BASE=$(get_cfg '.rebaseAgainst')
[ -z "$BASE" ] && BASE=$(av_default_base_branch)

# Resolve branch + worktree
if [[ "$PR_OR_BRANCH" =~ ^[0-9]+$ ]]; then
  BRANCH=$(av_pr_branch "$PR_OR_BRANCH")
  PR="$PR_OR_BRANCH"
else
  BRANCH="$PR_OR_BRANCH"
  PR=""
fi

[ -z "$WORKTREE" ] && WORKTREE=$(av_worktree_for_branch "$BRANCH")
if [ -z "$WORKTREE" ]; then
  WORKTREE="/tmp/anvil-merge-gate-$$"
  git fetch origin "$BRANCH" 2>/dev/null
  git worktree add "$WORKTREE" "origin/$BRANCH" 2>/dev/null
  CLEANUP_WORKTREE=1
else
  CLEANUP_WORKTREE=0
fi

# === GATES ===
FAILS=()
WARNS=()

# 1. Rebase
if [ "$SKIP_REBASE" -eq 0 ]; then
  av_info "Rebasing $BRANCH against $BASE..."
  cd "$WORKTREE"
  git fetch origin "${BASE#origin/}" 2>/dev/null
  if ! git rebase "$BASE" 2>&1 | tail -5; then
    git rebase --abort 2>/dev/null
    FAILS+=("rebase: conflicts against $BASE")
  else
    av_ok "rebase clean"
  fi
fi

# 2. Type check (find tsconfig.json sites)
if [ "$(get_cfg '.typecheck.enabled')" != "false" ]; then
  for tsc_dir in $(find "$WORKTREE" -maxdepth 3 -name "tsconfig.json" -not -path "*/node_modules/*" 2>/dev/null); do
    pkg=$(dirname "$tsc_dir")
    av_info "Type-checking $pkg..."
    if (cd "$pkg" && npx --no-install tsc --noEmit 2>&1 | tail -10) | grep -q "error TS"; then
      FAILS+=("typecheck: errors in $pkg")
    else
      av_ok "tsc clean: $pkg"
    fi
  done
fi

# 3. Tests
if [ "$(get_cfg '.tests.enabled')" != "false" ]; then
  TEST_CMD=$(get_cfg '.tests.command')
  [ -z "$TEST_CMD" ] && TEST_CMD="npx vitest run"
  for vc in $(find "$WORKTREE" -maxdepth 3 -name "vitest.config.*" -not -path "*/node_modules/*" 2>/dev/null); do
    pkg=$(dirname "$vc")
    av_info "Running tests in $pkg..."
    OUT=$(cd "$pkg" && $TEST_CMD 2>&1 | tail -5)
    if echo "$OUT" | grep -qE "Tests +[0-9]+ passed"; then
      COUNT=$(echo "$OUT" | grep -oE "Tests +[0-9]+ passed" | head -1 | grep -oE "[0-9]+")
      av_ok "tests: $COUNT passing in $pkg"
    else
      FAILS+=("tests: failed or unparseable in $pkg")
    fi
  done
fi

# 4. Architecture fitness
FITNESS_PATH=$(get_cfg '.fitness.testPath')
if [ -n "$FITNESS_PATH" ] && [ -f "$WORKTREE/$FITNESS_PATH" ]; then
  av_info "Running architecture fitness ratchets..."
  if (cd "$WORKTREE" && npx vitest run "$FITNESS_PATH" 2>&1 | tail -5) | grep -qE "Tests +[0-9]+ passed"; then
    av_ok "fitness: all ratchets green"
  else
    FAILS+=("fitness: ratchet violations")
  fi
fi

# 5. Forbidden patterns
if [ -f "$PATTERNS_FILE" ]; then
  av_info "Scanning for forbidden patterns..."
  while IFS= read -r line; do
    # Skip empty + comment lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Parse: pattern :: path-glob :: exclusion-glob (optional) :: comment
    pattern=$(echo "$line" | cut -d':' -f1 | sed 's/[[:space:]]*$//')
    path_glob=$(echo "$line" | cut -d':' -f4)
    excl_glob=$(echo "$line" | cut -d':' -f7)

    if [ -z "$pattern" ] || [ -z "$path_glob" ]; then continue; fi

    # Build find expression
    FIND_ARGS=()
    IFS=';' read -ra PATHS <<< "$path_glob"
    for p in "${PATHS[@]}"; do
      FIND_ARGS+=("-path" "$WORKTREE/${p// /}" "-o")
    done
    unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]'

    EXCL_ARGS=()
    if [ -n "$excl_glob" ]; then
      IFS=';' read -ra EXCLS <<< "$excl_glob"
      for e in "${EXCLS[@]}"; do
        EXCL_ARGS+=("-not" "-path" "$WORKTREE/${e// /}")
      done
    fi

    HITS=$(find "$WORKTREE" "${FIND_ARGS[@]}" -type f "${EXCL_ARGS[@]}" 2>/dev/null \
      | xargs grep -lE "$pattern" 2>/dev/null | head -5)

    if [ -n "$HITS" ]; then
      FAILS+=("forbidden pattern '$pattern' found in: $(echo "$HITS" | tr '\n' ' ')")
    fi
  done < "$PATTERNS_FILE"
  av_ok "forbidden patterns: scan complete"
fi

# 6. CI check (if PR specified)
if [ -n "$PR" ]; then
  av_info "Verifying GH PR #$PR CI..."
  CI_STATE=$(gh pr checks "$PR" --json bucket 2>/dev/null | jq -r '[.[] | select(.bucket != "pass" and .bucket != "skipping")] | length')
  if [ "$CI_STATE" = "0" ]; then
    av_ok "CI: all checks pass or skipping"
  else
    PENDING=$(gh pr checks "$PR" --json name,bucket | jq -r '.[] | select(.bucket=="pending") | .name')
    FAILED=$(gh pr checks "$PR" --json name,bucket | jq -r '.[] | select(.bucket=="fail") | .name')
    [ -n "$FAILED" ] && FAILS+=("CI: failed checks: $FAILED")
    [ -n "$PENDING" ] && WARNS+=("CI: pending checks: $PENDING")
  fi
fi

# Cleanup tmp worktree
if [ "$CLEANUP_WORKTREE" -eq 1 ]; then
  cd "$REPO_ROOT"
  git worktree remove --force "$WORKTREE" 2>/dev/null
fi

# === VERDICT ===
echo
echo "===================="
if [ "${#FAILS[@]}" -gt 0 ]; then
  printf "${AV_RED}🔴 BLOCKED${AV_RESET}\n"
  for f in "${FAILS[@]}"; do
    printf "  ${AV_RED}✗${AV_RESET} %s\n" "$f"
  done
  exit 1
fi
if [ "${#WARNS[@]}" -gt 0 ]; then
  printf "${AV_YELLOW}🟡 YELLOW FLAGS${AV_RESET}\n"
  for w in "${WARNS[@]}"; do
    printf "  ${AV_YELLOW}~${AV_RESET} %s\n" "$w"
  done
  if [ "$STRICT" -eq 1 ]; then exit 1; fi
  exit 2
fi
printf "${AV_GREEN}🟢 MERGE-READY${AV_RESET}\n"
exit 0
