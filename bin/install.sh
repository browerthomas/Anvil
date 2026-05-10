#!/usr/bin/env bash
# anvil install — symlink (default) or copy each skill into ~/.claude/skills/
#
# Usage:
#   install.sh                      # all 8 skills (meta-bundle, default)
#   install.sh --copy               # copy mode, all 8 skills
#   install.sh --group <name>       # install just one group: core | pr | orchestrator
#   install.sh --group core --copy  # copy mode, just one group

set -eu

ANVIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

MODE="symlink"
GROUP=""

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE="copy"; shift;;
    --group) GROUP="$2"; shift 2;;
    --help|-h)
      sed -n '2,9p' "$0" | sed 's/^# \?//'
      exit 0;;
    *) printf "${RED}unknown arg:${RESET} %s\n" "$1" >&2; exit 1;;
  esac
done

# Resolve which skills to install based on group
if [ -n "$GROUP" ]; then
  GROUP_MANIFEST="$ANVIL_ROOT/groups/$GROUP/.claude-plugin/plugin.json"
  if [ ! -f "$GROUP_MANIFEST" ]; then
    printf "${RED}group not found:${RESET} %s\n" "$GROUP" >&2
    echo "  available: core, pr, orchestrator" >&2
    exit 1
  fi
  # Extract skill paths from group manifest, resolve relative paths
  if ! command -v jq >/dev/null 2>&1; then
    printf "${RED}error:${RESET} jq required to install by group\n" >&2
    exit 1
  fi
  SKILL_DIRS=()
  while IFS= read -r rel_path; do
    abs_path=$(cd "$ANVIL_ROOT/groups/$GROUP/.claude-plugin" && cd "$(dirname "$rel_path")" && pwd)/$(basename "$rel_path")
    SKILL_DIRS+=("$abs_path/")
  done < <(jq -r '.skills[]' "$GROUP_MANIFEST")
  GROUP_LABEL="anvil-$GROUP"
else
  # Default: install everything via top-level manifest
  SKILL_DIRS=("$ANVIL_ROOT"/skills/*/)
  GROUP_LABEL="anvil (full bundle)"
fi

echo
printf "${GREEN}%s install (%s mode)${RESET}\n" "$GROUP_LABEL" "$MODE"
echo "  source: $ANVIL_ROOT/skills/"
echo "  target: $SKILLS_DIR/"
echo

mkdir -p "$SKILLS_DIR"

INSTALLED=0
SKIPPED=0
REPLACED=0

for skill_dir in "${SKILL_DIRS[@]}"; do
  skill_name=$(basename "${skill_dir%/}")
  target="$SKILLS_DIR/$skill_name"

  # Detect existing
  if [ -L "$target" ] || [ -e "$target" ]; then
    canonical_source="${skill_dir%/}"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$canonical_source" ]; then
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
case "$GROUP" in
  core)
    echo "Try one of these (anvil-core):"
    echo "  /sweep-worktrees    # cleanup pile-up"
    echo "  /self-review        # adversarial diff review"
    echo "  /recap              # visual session report"
    ;;
  pr)
    echo "Try the per-PR cycle (anvil-pr):"
    echo "  /dispatch-slice <id> --scope \"...\"   # spin up agent in worktree"
    echo "  /pre-merge-gate <pr>                  # rebase + tsc + tests + fitness + grep"
    echo "  /auto-merge <pr>                      # squash + cleanup + sync"
    ;;
  orchestrator)
    echo "Try the orchestrator (anvil-orchestrator):"
    echo "  /spec \"<intent>\"                      # interactive plan capture"
    echo "  /grind docs/plans/<slug>.md           # end-to-end execution"
    ;;
  *)
    echo "Try one:"
    echo "  /sweep-worktrees   # everyday helper"
    echo "  /spec \"<intent>\"   # interactive plan capture"
    echo "  /grind <plan>      # end-to-end orchestrator"
    ;;
esac
