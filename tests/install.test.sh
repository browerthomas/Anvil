#!/usr/bin/env bash
# tests/install.test.sh — first end-to-end test for anvil's install + preflight.
#
# Verifies the install pipeline against a temp HOME without touching the
# operator's real ~/.claude:
#   1. install.sh --prefix <tmp> --copy --no-preflight runs cleanly
#   2. <tmp>/anvil-config.sh exists + exports ANVIL_ROOT pointing at the checkout
#   3. Every installed skill script syntax-checks (bash -n) cleanly
#   4. Every installed skill script can resolve shared/lib.sh via the config-file path
#   5. preflight.sh --prefix <tmp> exits 0 and reports >= 1 skill installed
#   6. install.sh --prefix <tmp> (symlink mode) also passes preflight
#   7. uninstall.sh --prefix <tmp> removes anvil-config.sh
#
# Run from the anvil checkout root:
#   bash tests/install.test.sh

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# Resolve checkout root (one level up from tests/).
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$TEST_DIR/.." && pwd)"

FAIL=0
pass() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}✗${RESET} %s\n" "$1"; FAIL=$((FAIL + 1)); }

cleanup() {
  if [ -n "${TMP_HOME:-}" ] && [ -d "$TMP_HOME" ]; then
    rm -rf "$TMP_HOME"
  fi
}
trap cleanup EXIT

TMP_HOME=$(mktemp -d)
PREFIX="$TMP_HOME/.claude"

echo
echo "anvil install + preflight test"
echo "  checkout: $ANVIL_ROOT"
echo "  prefix:   $PREFIX"
echo

# -----------------------------------------------------------------------------
# Step 1: install.sh --copy --no-preflight
# -----------------------------------------------------------------------------
echo "Step 1: install.sh --copy --no-preflight --prefix"
if "$ANVIL_ROOT/bin/install.sh" --copy --no-preflight --prefix "$PREFIX" >/dev/null 2>&1; then
  pass "install.sh exited 0"
else
  fail "install.sh exited non-zero"
fi

# -----------------------------------------------------------------------------
# Step 2: anvil-config.sh exists + exports valid ANVIL_ROOT
# -----------------------------------------------------------------------------
echo "Step 2: anvil-config.sh"
CONFIG="$PREFIX/anvil-config.sh"
if [ -f "$CONFIG" ]; then
  pass "$CONFIG exists"
else
  fail "$CONFIG not created"
fi
# Source it in a subshell so it can't taint this test process.
CFG_ANVIL_ROOT=$(
  # shellcheck source=/dev/null
  . "$CONFIG" 2>/dev/null && printf '%s' "${ANVIL_ROOT:-}"
)
if [ "$CFG_ANVIL_ROOT" = "$ANVIL_ROOT" ]; then
  pass "config exports ANVIL_ROOT=$ANVIL_ROOT"
else
  fail "config exports ANVIL_ROOT=$CFG_ANVIL_ROOT (expected $ANVIL_ROOT)"
fi

# -----------------------------------------------------------------------------
# Step 3: syntax-check every installed skill script
# -----------------------------------------------------------------------------
echo "Step 3: skill-script syntax (bash -n)"
SYNTAX_OK=0
SYNTAX_TOTAL=0
for skill_dir in "$PREFIX"/skills/*/; do
  [ -d "$skill_dir/scripts" ] || continue
  for script in "$skill_dir/scripts"/*.sh; do
    [ -f "$script" ] || continue
    SYNTAX_TOTAL=$((SYNTAX_TOTAL + 1))
    if bash -n "$script" 2>/dev/null; then
      SYNTAX_OK=$((SYNTAX_OK + 1))
    else
      fail "syntax error: $script"
    fi
  done
done
if [ "$SYNTAX_OK" = "$SYNTAX_TOTAL" ] && [ "$SYNTAX_TOTAL" -gt 0 ]; then
  pass "$SYNTAX_OK / $SYNTAX_TOTAL scripts parse cleanly"
elif [ "$SYNTAX_TOTAL" -eq 0 ]; then
  fail "no skill scripts found at $PREFIX/skills/*/scripts/*.sh"
fi

# -----------------------------------------------------------------------------
# Step 4: pick representative scripts, smoke-test ANVIL_ROOT resolution
# -----------------------------------------------------------------------------
echo "Step 4: shared/lib.sh resolution post-install"
SMOKE_SCRIPTS=(
  "$PREFIX/skills/learn/scripts/learn-add.sh"
  "$PREFIX/skills/pre-merge-gate/scripts/verify.sh"
  "$PREFIX/skills/auto-merge/scripts/merge.sh"
)
for script in "${SMOKE_SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    fail "smoke target missing: $script"
    continue
  fi
  smoke_stderr=$(bash "$script" </dev/null 2>&1 >/dev/null || true)
  # The bug being prevented: stderr mentions shared/lib.sh: No such file
  if echo "$smoke_stderr" | grep -qE 'shared/lib\.sh.*No such file|ANVIL_ROOT.*unbound'; then
    fail "$(basename "$script"): shared/lib.sh resolution failed"
    echo "    stderr: $smoke_stderr" >&2
  else
    pass "$(basename "$script"): resolved shared/lib.sh"
  fi
done

# -----------------------------------------------------------------------------
# Step 5: preflight.sh --prefix exits 0
# -----------------------------------------------------------------------------
echo "Step 5: preflight.sh --prefix"
if "$ANVIL_ROOT/bin/preflight.sh" --prefix "$PREFIX" >/tmp/anvil-preflight-out 2>&1; then
  pass "preflight.sh exited 0"
else
  # Some operators have a missing optional tool (bun) — preflight returns 0
  # with warnings.  A non-zero return here is a real failure.
  fail "preflight.sh exited non-zero"
  cat /tmp/anvil-preflight-out >&2 || true
fi
if grep -q "Skills installed:" /tmp/anvil-preflight-out 2>/dev/null; then
  pass "preflight reports skill count"
else
  fail "preflight did not report skill count"
fi
rm -f /tmp/anvil-preflight-out

# -----------------------------------------------------------------------------
# Step 6: install symlink mode + preflight still passes
# -----------------------------------------------------------------------------
echo "Step 6: install.sh (symlink) + preflight"
# Wipe + re-install in default symlink mode.
rm -rf "$PREFIX/skills" "$PREFIX/anvil-config.sh"
if "$ANVIL_ROOT/bin/install.sh" --no-preflight --prefix "$PREFIX" >/dev/null 2>&1; then
  pass "install.sh (symlink) exited 0"
else
  fail "install.sh (symlink) exited non-zero"
fi
if "$ANVIL_ROOT/bin/preflight.sh" --prefix "$PREFIX" >/dev/null 2>&1; then
  pass "preflight after symlink install exited 0"
else
  fail "preflight after symlink install exited non-zero"
fi

# -----------------------------------------------------------------------------
# Step 7: uninstall removes anvil-config.sh
# -----------------------------------------------------------------------------
echo "Step 7: uninstall.sh removes anvil-config.sh"
if "$ANVIL_ROOT/bin/uninstall.sh" --prefix "$PREFIX" >/dev/null 2>&1; then
  pass "uninstall.sh exited 0"
else
  fail "uninstall.sh exited non-zero"
fi
if [ ! -f "$CONFIG" ]; then
  pass "$CONFIG was removed"
else
  fail "$CONFIG still exists after uninstall"
fi

# -----------------------------------------------------------------------------
echo
if [ "$FAIL" -gt 0 ]; then
  printf "${RED}FAIL${RESET} — %d check(s) did not pass\n" "$FAIL"
  exit 1
fi
printf "${GREEN}PASS${RESET} — install + preflight pipeline clean\n"
exit 0
