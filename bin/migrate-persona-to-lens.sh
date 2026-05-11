#!/usr/bin/env bash
# bin/migrate-persona-to-lens.sh — one-shot migrator for the /persona → /lens
# hard rename (Phase C, sprint docs/plans/2026-05-11-positioning-and-state-product).
#
# Detects an existing legacy install at $INSTALL_ROOT/skills/persona/ (symlink
# OR copy) and removes it so install.sh can install $INSTALL_ROOT/skills/lens/
# cleanly. Writes a sentinel $INSTALL_ROOT/.anvil-lens-migrated so install.sh
# can short-circuit on subsequent runs.
#
# Usage:
#   bin/migrate-persona-to-lens.sh                # default: detect + remove
#   bin/migrate-persona-to-lens.sh --force        # remove even if local mods present
#   bin/migrate-persona-to-lens.sh --prefix <dir> # override install root (tests)
#   bin/migrate-persona-to-lens.sh --quiet        # suppress informational output
#   bin/migrate-persona-to-lens.sh --help
#
# Install-root resolution (mirrors install.sh):
#   --prefix flag > ANVIL_HOME > CLAUDE_HOME > $HOME/.claude
#
# Behaviour:
#   - Symlink mode (`-L` test): just rm the symlink.
#   - Copy mode (real dir): if --force not given, warn + skip; sentinel still
#     written so install.sh doesn't loop. Operator decides whether to inspect
#     + re-run with --force.
#   - Idempotent: a second invocation finds no persona dir, just refreshes the
#     sentinel and exits 0.
#
# Exit codes:
#   0 — migration applied, skipped cleanly (no install present), or skipped
#       with local-mod warning (sentinel still written).
#   1 — unknown flag / arg parse error.
#   2 — internal error (filesystem, permissions, etc.).

set -eu

ANVIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}"

FORCE=0
QUIET=0

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

log() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '%b\n' "$*"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift;;
    --quiet) QUIET=1; shift;;
    --prefix) INSTALL_ROOT="$2"; shift 2;;
    --help|-h)
      sed -n '2,32p' "$0" | sed 's/^# \?//'
      exit 0;;
    *) printf "${RED}unknown arg:${RESET} %s\n" "$1" >&2; exit 1;;
  esac
done

SKILLS_DIR="${INSTALL_ROOT}/skills"
LEGACY_DIR="${SKILLS_DIR}/persona"
SENTINEL="${INSTALL_ROOT}/.anvil-lens-migrated"

log
log "${GREEN}migrate-persona-to-lens${RESET}"
log "  install root: ${INSTALL_ROOT}"
log "  legacy path:  ${LEGACY_DIR}"
log

# Ensure install root exists so we can write the sentinel even on a fresh box.
mkdir -p "$INSTALL_ROOT"

# ── Detect legacy install ───────────────────────────────────────────────
# Use -L OR -e separately — `-L` catches a broken symlink that points at a
# now-deleted source; `-e` catches a real dir.
if [ ! -L "$LEGACY_DIR" ] && [ ! -e "$LEGACY_DIR" ]; then
  log "  ${GREEN}no legacy /persona install found — nothing to migrate${RESET}"
  # Refresh sentinel (idempotent re-run).
  : > "$SENTINEL"
  log "  ${GREEN}+${RESET} sentinel: $SENTINEL"
  log
  exit 0
fi

# ── Symlink mode ────────────────────────────────────────────────────────
if [ -L "$LEGACY_DIR" ]; then
  link_target="$(readlink "$LEGACY_DIR" 2>/dev/null || true)"
  log "  ${YELLOW}~${RESET} symlink-mode install detected (→ ${link_target:-unknown})"
  rm -f "$LEGACY_DIR"
  log "  ${GREEN}-${RESET} removed symlink: $LEGACY_DIR"
  : > "$SENTINEL"
  log "  ${GREEN}+${RESET} sentinel: $SENTINEL"
  log
  exit 0
fi

# ── Copy mode ───────────────────────────────────────────────────────────
# Real directory — could be a clean copy (safe to remove) or have local
# operator modifications (warn + skip unless --force).
#
# Heuristic for "has local modifications":
#   - Compare against the in-checkout source at $ANVIL_ROOT/skills/persona/.
#     Pre-C1 anvil checkouts had that path; post-C1 they don't.
#   - If the source exists and `diff -rq` shows no differences → clean copy.
#   - If the source exists and diff reports differences → local mods.
#   - If the source is gone (post-C1 checkout) → we can't compare. Treat as
#     "potentially modified" and require --force to be conservative. Operator
#     who knows their install is clean passes --force; operator who's unsure
#     inspects manually.
if [ -d "$LEGACY_DIR" ]; then
  log "  ${YELLOW}~${RESET} copy-mode install detected"
  SOURCE_REF="$ANVIL_ROOT/skills/persona"
  CLEAN=0
  if [ -d "$SOURCE_REF" ]; then
    # diff -rq is silent on equal trees, prints per-file when differing.
    if diff -rq "$LEGACY_DIR" "$SOURCE_REF" >/dev/null 2>&1; then
      CLEAN=1
    fi
  fi

  if [ "$CLEAN" -eq 1 ]; then
    rm -rf "$LEGACY_DIR"
    log "  ${GREEN}-${RESET} removed copy (verified clean vs source): $LEGACY_DIR"
    : > "$SENTINEL"
    log "  ${GREEN}+${RESET} sentinel: $SENTINEL"
    log
    exit 0
  fi

  # Local mods OR source-not-available comparison.
  if [ "$FORCE" -eq 1 ]; then
    rm -rf "$LEGACY_DIR"
    log "  ${YELLOW}!${RESET} --force given; removed copy: $LEGACY_DIR" >&2
    : > "$SENTINEL"
    log "  ${GREEN}+${RESET} sentinel: $SENTINEL"
    log
    exit 0
  fi

  # Skip path — still write sentinel so install.sh doesn't re-invoke us in a
  # loop. Operator can re-run with --force after inspecting.
  printf "${YELLOW}!${RESET} skipping: %s appears to have local modifications.\n" "$LEGACY_DIR" >&2
  printf "  Inspect: ls -la %s\n" "$LEGACY_DIR" >&2
  printf "  Remove anyway: %s --force\n" "$0" >&2
  : > "$SENTINEL"
  log "  ${GREEN}+${RESET} sentinel: $SENTINEL (install.sh will not re-invoke migrator)"
  log
  exit 0
fi

# Should be unreachable — defensive.
printf "${RED}✗${RESET} unexpected file type at %s — manual inspection required\n" "$LEGACY_DIR" >&2
exit 2
