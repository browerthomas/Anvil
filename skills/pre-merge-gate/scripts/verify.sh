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
SLICE_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="$2"; shift 2;;
    --base)     BASE="$2"; shift 2;;
    --skip-rebase) SKIP_REBASE=1; shift;;
    --slice)    SLICE_OVERRIDE="$2"; shift 2;;
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

# === Slice context resolution (S3) ===
# Resolve the slice id BEFORE any gate runs. The per-slice checklist is
# enforced post-rebase/tsc/tests/fitness, but the lookup itself is a
# precondition: if we can't find slice context, we refuse to gate. Order:
#   1. --slice <id> arg
#   2. .anvil/dispatched-agents.json exact-match (branch == current branch)
#   3. Hard error (exit before running ANY gate, including global ones).
SLICE_ID=""
PLAN_PATH=""
AGENTS_JSON="$REPO_ROOT/.anvil/dispatched-agents.json"

if [ -n "$SLICE_OVERRIDE" ]; then
  SLICE_ID="$SLICE_OVERRIDE"
fi
if [ -z "$SLICE_ID" ] && [ -f "$AGENTS_JSON" ]; then
  # Collect ALL slice ids whose branch matches; if >1 we hard-fail rather than
  # silently picking the first via `head -1` (silent first-wins masks the
  # collision and runs the wrong slice's checklist).
  _SLICE_MATCHES=$(jq -r --arg b "$BRANCH" \
    'to_entries[] | select(.value.branch == $b) | .key' "$AGENTS_JSON" 2>/dev/null)
  _SLICE_MATCH_COUNT=$(printf '%s' "$_SLICE_MATCHES" | grep -c .)
  if [ "$_SLICE_MATCH_COUNT" -gt 1 ]; then
    _COLLIDING=$(printf '%s' "$_SLICE_MATCHES" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    av_fail "error: ambiguous slice context: branch '$BRANCH' maps to multiple slices: $_COLLIDING"
    if [ "$CLEANUP_WORKTREE" = "1" ]; then
      cd "$REPO_ROOT" 2>/dev/null
      git worktree remove --force "$WORKTREE" 2>/dev/null
    fi
    exit 1
  fi
  SLICE_ID="$_SLICE_MATCHES"
  unset _SLICE_MATCHES _SLICE_MATCH_COUNT _COLLIDING
fi
if [ -z "$SLICE_ID" ]; then
  av_fail "error: no slice context found; pass --slice <id> or run inside /grind"
  if [ "$CLEANUP_WORKTREE" = "1" ]; then
    cd "$REPO_ROOT" 2>/dev/null
    git worktree remove --force "$WORKTREE" 2>/dev/null
  fi
  exit 1
fi
# Resolve plan_path (optional — silent skip downstream if absent).
#
# Two cases:
#  1. SLICE_ID was derived from a branch-match in dispatched-agents.json →
#     fetch plan_path from .[$slice_id].plan_path (same row as the match).
#  2. SLICE_ID was set via --slice override → the operator is asking us to
#     run a DIFFERENT slice of the SAME plan they're already grinding on.
#     The plan_path lives in the row whose branch == current branch, not
#     in the (likely absent) row keyed by the override slice id. Fall back
#     to a branch-match plan_path lookup when the slice-id lookup misses.
if [ -f "$AGENTS_JSON" ]; then
  PLAN_PATH=$(jq -r --arg id "$SLICE_ID" '.[$id].plan_path // empty' "$AGENTS_JSON" 2>/dev/null)
  if [ -z "$PLAN_PATH" ] && [ -n "$SLICE_OVERRIDE" ]; then
    # --slice override: look up plan_path via branch-match instead.
    # ambiguous-branch case is already hard-failed above, so at most one
    # row matches here.
    PLAN_PATH=$(jq -r --arg b "$BRANCH" \
      'to_entries[] | select(.value.branch == $b) | .value.plan_path // empty' \
      "$AGENTS_JSON" 2>/dev/null | head -1)
  fi
  if [ -n "$PLAN_PATH" ] && [ "${PLAN_PATH#/}" = "$PLAN_PATH" ]; then
    PLAN_PATH="$REPO_ROOT/$PLAN_PATH"
  fi
  if [ -n "$PLAN_PATH" ] && [ -d "$PLAN_PATH" ] && [ -f "$PLAN_PATH/tasks.md" ]; then
    PLAN_PATH="$PLAN_PATH/tasks.md"
  fi
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

# 5.5 Per-slice checklist (S3)
# Locate the slice via: --slice override > dispatched-agents.json exact match > error.
# Then parse the plan's checklist via av_parse_slice_checklist and run each item.

# Portable timeout shim — macOS does not ship GNU `timeout` by default.
_av_run_with_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    # Fallback: spawn the command, watch with a sleep, kill on overrun.
    # We must kill the watcher's `sleep` child as well — killing only the
    # watcher subshell leaves its `sleep` running for up to $secs seconds,
    # leaking a zombie `sleep` per checklist item.
    ( "$@" ) & local pid=$!
    ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null ) & local watcher=$!
    wait "$pid" 2>/dev/null; local rc=$?
    # `pkill -P <pid>` kills children of the watcher (the `sleep`), then we
    # kill the watcher itself. Fall back to `kill` alone if pkill is absent.
    if command -v pkill >/dev/null 2>&1; then
      pkill -P "$watcher" 2>/dev/null
    fi
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    return $rc
  fi
}

run_per_slice_checklist() {
  local slice_id="$SLICE_ID"
  local plan_path="$PLAN_PATH"

  if [ -z "$plan_path" ] || [ ! -f "$plan_path" ]; then
    # No plan_path → checklist enforcement is silently skipped (legacy
    # behaviour for plans that pre-date the S3 checklist field). The slice
    # was still resolved successfully — that's the load-bearing assertion.
    return 0
  fi

  # Parse the checklist. Silent absence (no checklist key) → exit 0 + no output.
  # Split stdout (the parser's pipe-delimited checklist lines) from stderr (the
  # parser's error messages). Merging the two (with `2>&1`) caused YAML parser
  # errors to be treated as garbled checklist lines, which then surfaced as
  # confusing "unknown kind 'av_parse_slice_checklist'" failures downstream.
  local checklist_lines parser_err parse_rc stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  av_parse_slice_checklist "$plan_path" "$slice_id" > "$stdout_file" 2> "$stderr_file"
  parse_rc=$?
  checklist_lines=$(cat "$stdout_file")
  parser_err=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
  if [ $parse_rc -ne 0 ]; then
    # Distinguish "slice not found" / "invalid kind" / "invalid expect" — all
    # surface as parser errors. Block merge with the parser's own stderr.
    FAILS+=("$slice_id checklist ERROR: parser failed (rc=$parse_rc): $parser_err")
    return 1
  fi
  if [ -z "$checklist_lines" ]; then
    # Slice exists but has no checklist — legacy silent-absence path.
    return 0
  fi

  # 5. Execute each item.
  local line kind cmd expect timeout pattern in_glob count hits hit_count expanded_glob
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    kind=$(printf '%s' "$line" | cut -d'|' -f1)
    case "$kind" in
      shell)
        cmd=$(printf '%s' "$line" | cut -d'|' -f2)
        expect=$(printf '%s' "$line" | cut -d'|' -f3)
        timeout=$(printf '%s' "$line" | cut -d'|' -f4)
        [ -z "$timeout" ] && timeout=300
        av_info "$slice_id checklist: shell '$cmd' (timeout ${timeout}s)"
        # Run from the worktree so relative paths in the cmd resolve there.
        local rc
        (
          cd "$WORKTREE" || exit 127
          _av_run_with_timeout "$timeout" bash -c "$cmd"
        )
        rc=$?
        # timeout(1) and gtimeout(1) exit 124 on timeout; the fallback path
        # kills the child with SIGTERM (rc 143 = 128 + 15) on overrun.
        if [ "$rc" = "124" ] || [ "$rc" = "143" ]; then
          FAILS+=("$slice_id checklist FAIL: shell '$cmd' timed out after ${timeout}s")
        elif [ "$rc" -eq 0 ]; then
          av_ok "$slice_id checklist PASS: shell '$cmd' exit 0"
        else
          FAILS+=("$slice_id checklist FAIL: shell '$cmd' exit $rc")
        fi
        ;;
      grep)
        pattern=$(printf '%s' "$line" | cut -d'|' -f2)
        in_glob=$(printf '%s' "$line" | cut -d'|' -f3)
        expect=$(printf '%s' "$line" | cut -d'|' -f4)
        count=$(printf '%s' "$line" | cut -d'|' -f5)
        av_info "$slice_id checklist: grep '$pattern' in '$in_glob' expect $expect"
        # Expand the glob from inside the worktree. Use find for portability;
        # `grep -rE` over a literal `**` arg won't work on macOS grep.
        # Convert `dir/**` → `dir`. Otherwise treat as a literal path.
        local search_root
        if [[ "$in_glob" == */** ]]; then
          search_root="$WORKTREE/${in_glob%/**}"
        else
          search_root="$WORKTREE/$in_glob"
        fi
        if [ ! -e "$search_root" ]; then
          FAILS+=("$slice_id checklist FAIL: grep target '$in_glob' does not exist in worktree")
          continue
        fi
        if [ -d "$search_root" ]; then
          hit_count=$(grep -rE --include='*' "$pattern" "$search_root" 2>/dev/null | wc -l | tr -d ' ')
        else
          hit_count=$(grep -cE "$pattern" "$search_root" 2>/dev/null | tr -d ' ')
        fi
        [ -z "$hit_count" ] && hit_count=0
        case "$expect" in
          absent)
            if [ "$hit_count" -gt 0 ]; then
              FAILS+=("$slice_id checklist FAIL: grep pattern '$pattern' present in $in_glob (expected absent; $hit_count match(es))")
            else
              av_ok "$slice_id checklist PASS: grep '$pattern' absent in $in_glob"
            fi
            ;;
          present)
            if [ "$hit_count" -eq 0 ]; then
              FAILS+=("$slice_id checklist FAIL: grep pattern '$pattern' absent in $in_glob (expected present)")
            elif [ -n "$count" ]; then
              # Validate count parses as integer before numeric comparison.
              if ! [[ "$count" =~ ^[0-9]+$ ]]; then
                FAILS+=("$slice_id checklist ERROR: grep count '$count' is not a non-negative integer")
              elif [ "$hit_count" -ne "$count" ]; then
                FAILS+=("$slice_id checklist FAIL: grep pattern '$pattern' found $hit_count match(es) in $in_glob (expected exactly $count)")
              else
                av_ok "$slice_id checklist PASS: grep '$pattern' present in $in_glob ($hit_count match(es))"
              fi
            else
              av_ok "$slice_id checklist PASS: grep '$pattern' present in $in_glob ($hit_count match(es))"
            fi
            ;;
          *)
            FAILS+=("$slice_id checklist ERROR: invalid expect '$expect' for grep (expected: present | absent)")
            ;;
        esac
        ;;
      *)
        FAILS+=("$slice_id checklist ERROR: unknown kind '$kind' (expected: shell | grep)")
        ;;
    esac
  done <<< "$checklist_lines"
}

run_per_slice_checklist || true

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
