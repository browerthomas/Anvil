#!/usr/bin/env bash
# anvil uninstall — removes anvil skills + anvil-config.sh from $HOME/.claude/
# (or the install root selected via --prefix / ANVIL_HOME / CLAUDE_HOME).

set -eu

ANVIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}"

# Parse args (--prefix kept symmetric with install.sh)
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) INSTALL_ROOT="$2"; shift 2;;
    --help|-h)
      echo "Usage: uninstall.sh [--prefix <dir>]"
      exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

SKILLS_DIR="${INSTALL_ROOT}/skills"
CONFIG_FILE="${INSTALL_ROOT}/anvil-config.sh"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo
printf "${GREEN}anvil uninstall${RESET}\n"
echo "  removing skills installed from: $ANVIL_ROOT/skills/"
echo "  target: $SKILLS_DIR/"
echo

REMOVED=0
KEPT=0

for skill_dir in "$ANVIL_ROOT"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "${skill_dir%/}" ] || [ "$(readlink "$target")" = "$skill_dir" ]; then
      rm "$target"
      printf "  ${GREEN}-${RESET} %s (symlink removed)\n" "$skill_name"
      REMOVED=$((REMOVED + 1))
    else
      printf "  ${YELLOW}~${RESET} %s symlinked elsewhere, keeping\n" "$skill_name"
      KEPT=$((KEPT + 1))
    fi
  elif [ -d "$target" ]; then
    # Copy-mode install. Confirm anvil-origin via SKILL.md content match.
    if [ -f "$target/SKILL.md" ] && [ -f "$skill_dir/SKILL.md" ] && cmp -s "$target/SKILL.md" "$skill_dir/SKILL.md"; then
      rm -rf "$target"
      printf "  ${GREEN}-${RESET} %s (copy removed)\n" "$skill_name"
      REMOVED=$((REMOVED + 1))
    else
      printf "  ${YELLOW}~${RESET} %s exists but does not match anvil, keeping\n" "$skill_name"
      KEPT=$((KEPT + 1))
    fi
  fi
done

echo
printf "${GREEN}removed${RESET} %d, kept %d non-anvil skills\n" "$REMOVED" "$KEPT"

# Remove the anvil-config.sh that install.sh wrote.
if [ -f "$CONFIG_FILE" ]; then
  rm -f "$CONFIG_FILE"
  printf "  ${GREEN}-${RESET} %s (config removed)\n" "$CONFIG_FILE"
fi
