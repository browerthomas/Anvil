#!/usr/bin/env bash
# anvil preflight — verifies prerequisites before install.

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

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
SKILLS_DIR="${HOME}/.claude/skills"
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

echo "===================="
printf "  ${GREEN}%d ok${RESET}, ${YELLOW}%d warnings${RESET}, ${RED}%d failures${RESET}\n" "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
echo "===================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  printf "${RED}preflight FAILED${RESET} — fix the items above before running install.sh\n"
  exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
  echo
  printf "${YELLOW}preflight passed with warnings${RESET} — install.sh will work, some skills may have reduced functionality\n"
  exit 0
else
  echo
  printf "${GREEN}preflight clean${RESET} — ready to install\n"
  echo "Next: ~/Desktop/anvil/bin/install.sh"
  exit 0
fi
