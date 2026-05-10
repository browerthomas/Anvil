#!/usr/bin/env bash
# anvil install — symlink (default) or copy each skill into ~/.claude/skills/

set -eu

ANVIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

MODE="symlink"
if [ "${1:-}" = "--copy" ]; then
  MODE="copy"
fi

echo
printf "${GREEN}anvil install (%s mode)${RESET}\n" "$MODE"
echo "  source: $ANVIL_ROOT/skills/"
echo "  target: $SKILLS_DIR/"
echo

mkdir -p "$SKILLS_DIR"

INSTALLED=0
SKIPPED=0
REPLACED=0

for skill_dir in "$ANVIL_ROOT"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  target="$SKILLS_DIR/$skill_name"

  # Detect existing
  if [ -L "$target" ] || [ -e "$target" ]; then
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$skill_dir" ]; then
      printf "  ${YELLOW}~${RESET} %s already symlinked to anvil, skipping\n" "$skill_name"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    printf "  ${YELLOW}~${RESET} %s exists — replacing\n" "$skill_name"
    rm -rf "$target"
    REPLACED=$((REPLACED + 1))
  fi

  # Install
  if [ "$MODE" = "symlink" ]; then
    ln -s "${skill_dir%/}" "$target"
  else
    cp -R "${skill_dir%/}" "$target"
  fi
  printf "  ${GREEN}+${RESET} %s\n" "$skill_name"
  INSTALLED=$((INSTALLED + 1))
done

echo
printf "${GREEN}installed${RESET} %d (%d new, %d replaced, %d already-installed)\n" \
  "$((INSTALLED + SKIPPED))" "$((INSTALLED - REPLACED))" "$REPLACED" "$SKIPPED"
echo
echo "Skills are now active in your Claude Code session."
echo
if [ "$MODE" = "symlink" ]; then
  echo "Edits to ${ANVIL_ROOT}/skills/<name>/SKILL.md are LIVE immediately."
else
  echo "(Copy mode: re-run install.sh --copy to push edits.)"
fi
echo
echo "Try one:"
echo "  /sweep-worktrees    # cleanup pile-up"
echo "  /self-review        # adversarial diff review"
echo "  /recap              # visual session report"
