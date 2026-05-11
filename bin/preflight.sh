#!/usr/bin/env bash
# anvil preflight — verifies prerequisites + (post-install) verifies skills work.
#
# Usage:
#   preflight.sh                       # pre-install + post-install if anvil-config.sh present
#   preflight.sh --prefix <dir>        # override install root (default: $HOME/.claude)
#                                      # also honoured via ANVIL_INSTALL_ROOT, ANVIL_HOME, CLAUDE_HOME env vars
#   preflight.sh --skills-only         # skip the tool/version/auth checks, only run skill smoke
#   preflight.sh --no-skills           # skip the post-install skill smoke section
#
# Exit codes:
#   0 → clean (or warnings only)
#   1 → at least one hard failure

set -u

# Resolve install root early so the skill-smoke section knows where to look.
# Precedence: --prefix > ANVIL_INSTALL_ROOT > ANVIL_HOME > CLAUDE_HOME > $HOME/.claude
INSTALL_ROOT="${ANVIL_INSTALL_ROOT:-${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}}"
SKILLS_ONLY=0
NO_SKILLS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) INSTALL_ROOT="$2"; shift 2;;
    --skills-only) SKILLS_ONLY=1; shift;;
    --no-skills) NO_SKILLS=1; shift;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# \?//'
      exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Skill-smoke counters (tracked separately so the summary can break them out).
SKILL_TOTAL=0
SKILL_OK=0
SKILL_FAIL=0
SKILLS_INSTALLED=0

check_required() {
  local name="$1"
  local cmd="$2"
  local hint="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} %s found (%s)\n" "$name" "$(command -v "$cmd")"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${RED}✗${RESET} %s missing — %s\n" "$name" "${hint:-install $cmd}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_optional() {
  local name="$1"
  local cmd="$2"
  local hint="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} %s found (%s)\n" "$name" "$(command -v "$cmd")"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${YELLOW}~${RESET} %s missing (optional) — %s\n" "$name" "${hint:-skill will use fallback}"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

check_version() {
  local name="$1"
  local cmd="$2"
  local minver="$3"
  local actual
  actual=$($cmd 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  if [ -z "$actual" ]; then
    printf "  ${YELLOW}~${RESET} %s version unknown\n" "$name"
    WARN_COUNT=$((WARN_COUNT + 1))
    return
  fi
  if printf '%s\n%s\n' "$minver" "$actual" | sort -V -C 2>/dev/null; then
    printf "  ${GREEN}✓${RESET} %s %s (≥%s required)\n" "$name" "$actual" "$minver"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${YELLOW}~${RESET} %s %s — older than recommended %s\n" "$name" "$actual" "$minver"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

echo
printf "${GREEN}anvil preflight${RESET}\n"
echo "Checking prerequisites for the orchestration framework..."
echo

if [ "$SKILLS_ONLY" = "0" ]; then
echo "REQUIRED tools:"
check_required "git" "git"
check_required "GitHub CLI" "gh" "https://cli.github.com — needed for PR + issue automation"
check_required "Node.js" "node" "https://nodejs.org — needed for tsc/vitest in skills"
check_required "npm" "npm"
check_required "jq" "jq" "brew install jq (macOS) / apt install jq (linux)"
echo

echo "OPTIONAL tools:"
check_optional "Codex CLI" "codex" "/self-review is the fallback when codex is unavailable"
check_optional "Bun" "bun" "speeds up some skills if present"
echo

echo "VERSION checks:"
if command -v node >/dev/null 2>&1; then
  check_version "Node.js" "node --version" "20.0.0"
fi
if command -v git >/dev/null 2>&1; then
  check_version "git" "git --version" "2.40.0"
fi
echo

echo "AUTHENTICATION checks:"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} gh authenticated\n"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${RED}✗${RESET} gh not authenticated — run: gh auth login\n"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi
echo

echo "FILESYSTEM checks:"
SKILLS_DIR="${INSTALL_ROOT}/skills"
if [ -d "$SKILLS_DIR" ]; then
  if [ -w "$SKILLS_DIR" ]; then
    printf "  ${GREEN}✓${RESET} %s exists and is writable\n" "$SKILLS_DIR"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${RED}✗${RESET} %s is not writable\n" "$SKILLS_DIR"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  printf "  ${YELLOW}~${RESET} %s does not exist — install will create it\n" "$SKILLS_DIR"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# macOS: verify find -delete works (needed by /sweep-worktrees)
if [ "$(uname)" = "Darwin" ]; then
  TMPDIR=$(mktemp -d)
  mkdir -p "$TMPDIR/probe"
  if find "$TMPDIR/probe" -delete 2>/dev/null; then
    printf "  ${GREEN}✓${RESET} find -delete works (required by /sweep-worktrees)\n"
    OK_COUNT=$((OK_COUNT + 1))
  else
    printf "  ${RED}✗${RESET} find -delete failed (sandbox / permission issue)\n"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  rm -rf "$TMPDIR"
fi
echo
fi  # end SKILLS_ONLY guard

# ============================================================
# Post-install: verify the skills we just installed actually work.
# ============================================================
# Skipped only when --no-skills is passed.  Runs whenever anvil-config.sh
# exists at the install root (i.e. install.sh has been run).
CONFIG_FILE="${INSTALL_ROOT}/anvil-config.sh"
SKILLS_DIR="${INSTALL_ROOT}/skills"

if [ "$NO_SKILLS" = "0" ] && [ -f "$CONFIG_FILE" ]; then
  echo "POST-INSTALL: anvil-config.sh"
  # Source it in a subshell so a broken config doesn't poison preflight.
  CFG_ANVIL_ROOT=$(
    # shellcheck source=/dev/null
    . "$CONFIG_FILE" 2>/dev/null && printf '%s' "${ANVIL_ROOT:-}"
  )
  if [ -z "$CFG_ANVIL_ROOT" ]; then
    printf "  ${RED}✗${RESET} %s did not set ANVIL_ROOT\n" "$CONFIG_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ ! -d "$CFG_ANVIL_ROOT" ]; then
    printf "  ${RED}✗${RESET} ANVIL_ROOT=%s does not exist (anvil checkout moved?)\n" "$CFG_ANVIL_ROOT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ ! -f "$CFG_ANVIL_ROOT/shared/lib.sh" ]; then
    printf "  ${RED}✗${RESET} shared/lib.sh missing at %s\n" "$CFG_ANVIL_ROOT/shared/lib.sh"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf "  ${GREEN}✓${RESET} ANVIL_ROOT resolves to %s\n" "$CFG_ANVIL_ROOT"
    printf "  ${GREEN}✓${RESET} shared/lib.sh present (%s)\n" "$CFG_ANVIL_ROOT/shared/lib.sh"
    # Try sourcing lib.sh in a subshell — catches syntax errors.
    if ( # shellcheck source=/dev/null
         . "$CFG_ANVIL_ROOT/shared/lib.sh" ) >/dev/null 2>&1; then
      printf "  ${GREEN}✓${RESET} shared/lib.sh sources cleanly\n"
      OK_COUNT=$((OK_COUNT + 3))
    else
      printf "  ${RED}✗${RESET} shared/lib.sh failed to source\n"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
  echo

  echo "POST-INSTALL: skill scripts (syntax + smoke)"
  if [ ! -d "$SKILLS_DIR" ]; then
    printf "  ${YELLOW}~${RESET} %s does not exist — nothing to verify\n" "$SKILLS_DIR"
    WARN_COUNT=$((WARN_COUNT + 1))
  else
    # Iterate installed skills (each is a directory or symlink to one).
    for skill_dir in "$SKILLS_DIR"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "${skill_dir%/}")
      # Only count skills that look like ours (have a SKILL.md).
      [ -f "$skill_dir/SKILL.md" ] || continue
      SKILLS_INSTALLED=$((SKILLS_INSTALLED + 1))

      scripts_dir="${skill_dir%/}/scripts"
      [ -d "$scripts_dir" ] || continue

      for script in "$scripts_dir"/*.sh; do
        [ -f "$script" ] || continue
        SKILL_TOTAL=$((SKILL_TOTAL + 1))
        # Syntax check (bash -n) is the universal floor — every script must
        # parse without error.  This is what catches the original #19 bug:
        # a script that won't even source shared/lib.sh fails here.
        if bash -n "$script" 2>/dev/null; then
          # Bonus: actually invoke with no args to confirm the
          # ANVIL_ROOT resolution + lib.sh source path works at runtime.
          # Most of our scripts print a "usage:" message on no-args and exit
          # non-zero — that's still a SUCCESSFUL smoke since the ANVIL_ROOT
          # resolution and lib.sh sourcing happened before the usage exit.
          # We treat any exit code as a syntax-pass; only a stderr containing
          # "lib.sh" or "ANVIL_ROOT" is a real failure.
          # Export ANVIL_HOME=INSTALL_ROOT so scripts resolved via symlink find
          # the anvil-config.sh at the install root (not the checkout target).
          smoke_stderr=$(ANVIL_HOME="$INSTALL_ROOT" bash "$script" </dev/null 2>&1 >/dev/null || true)
          if echo "$smoke_stderr" | grep -qE 'shared/lib\.sh|ANVIL_ROOT.*unbound|No such file' 2>/dev/null; then
            printf "  ${RED}✗${RESET} %s/%s — failed to locate shared/lib.sh\n" \
              "$skill_name" "$(basename "$script" .sh)"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            SKILL_FAIL=$((SKILL_FAIL + 1))
          else
            printf "  ${GREEN}✓${RESET} %s/%s\n" "$skill_name" "$(basename "$script" .sh)"
            OK_COUNT=$((OK_COUNT + 1))
            SKILL_OK=$((SKILL_OK + 1))
          fi
        else
          printf "  ${RED}✗${RESET} %s/%s — syntax error (bash -n)\n" \
            "$skill_name" "$(basename "$script" .sh)"
          FAIL_COUNT=$((FAIL_COUNT + 1))
          SKILL_FAIL=$((SKILL_FAIL + 1))
        fi
      done
    done

    if [ "$SKILL_TOTAL" -eq 0 ]; then
      printf "  ${YELLOW}~${RESET} no skill helper scripts found in %s\n" "$SKILLS_DIR"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  fi
  echo
elif [ "$NO_SKILLS" = "0" ]; then
  echo "POST-INSTALL: skipped"
  printf "  ${YELLOW}~${RESET} %s not found — run install.sh first to enable skill smoke checks\n" "$CONFIG_FILE"
  echo
  WARN_COUNT=$((WARN_COUNT + 1))
fi

echo "=== Preflight summary ==="
if [ "$SKILLS_ONLY" = "0" ]; then
  printf "  ok: %d   warnings: %d   failures: %d\n" "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
fi
if [ -f "$CONFIG_FILE" ] && [ "$NO_SKILLS" = "0" ]; then
  printf "  Skills installed: %d\n" "$SKILLS_INSTALLED"
  printf "  Skill scripts:    %d of %d passed\n" "$SKILL_OK" "$SKILL_TOTAL"
fi
echo

if [ "$FAIL_COUNT" -gt 0 ]; then
  printf "${RED}OVERALL: ✗ ISSUES${RESET} — fix above before invoking /grind\n"
  exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
  printf "${YELLOW}OVERALL: ~ READY with warnings${RESET} — install will work; some skills may have reduced functionality\n"
  exit 0
else
  printf "${GREEN}OVERALL: ✓ READY${RESET}\n"
  exit 0
fi
