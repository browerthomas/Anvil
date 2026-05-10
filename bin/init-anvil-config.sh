#!/usr/bin/env bash
# anvil — bootstrap a repo's .anvil/ directory with starter configs.
#
# Run from inside a git repo. Creates .anvil/ with sample configs you can edit.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo — cd to your project first"; exit 1; }
ANVIL_DIR="$REPO_ROOT/.anvil"

if [ -d "$ANVIL_DIR" ]; then
  av_warn ".anvil/ already exists at $ANVIL_DIR"
  read -r -p "  Overwrite existing files? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    av_info "aborted; nothing changed"
    exit 0
  fi
fi

mkdir -p "$ANVIL_DIR"

cp "$ANVIL_ROOT/skills/pre-merge-gate/templates/forbidden-patterns.example.txt" "$ANVIL_DIR/forbidden-patterns.txt"
av_ok "wrote $ANVIL_DIR/forbidden-patterns.txt"

cp "$ANVIL_ROOT/skills/pre-merge-gate/templates/pre-merge-gate.config.example.json" "$ANVIL_DIR/pre-merge-gate.config.json"
av_ok "wrote $ANVIL_DIR/pre-merge-gate.config.json"

cat > "$ANVIL_DIR/dispatch-defaults.txt" <<'EOF'
# Project-specific hard constraints appended to every /dispatch-slice prompt.
# One per line. Lines starting with # are ignored.
#
# Examples (uncomment + adapt):
#
# Tests must run before commit (no broken-build commits)
# DO NOT bypass the existing CSRF middleware
# DO NOT commit secrets to .env or any tracked file
# Default Opus reasoning unless the slice scope is verifiably trivial
EOF
av_ok "wrote $ANVIL_DIR/dispatch-defaults.txt"

cat > "$ANVIL_DIR/.gitignore" <<'EOF'
# anvil runtime state — not for the repo
grind-state.json
dispatched-agents.json
*.log
EOF
av_ok "wrote $ANVIL_DIR/.gitignore"

cat > "$ANVIL_DIR/README.md" <<'EOF'
# .anvil/

Project-specific configuration consumed by [anvil](https://github.com/browerthomas/Anvil) skills.

| File | Read by | Purpose |
|---|---|---|
| `forbidden-patterns.txt` | `/pre-merge-gate` | Grep patterns + path globs that block merge |
| `pre-merge-gate.config.json` | `/pre-merge-gate` | Rebase target, test baselines, known flakes |
| `dispatch-defaults.txt` | `/dispatch-slice` | Per-project hard constraints appended to every agent prompt |
| `grind-state.json` | `/grind` | Per-plan execution state (auto-managed; gitignored) |
| `dispatched-agents.json` | `/dispatch-slice` | Tracking of in-flight agents (auto-managed; gitignored) |

Edit the static files; let anvil manage the runtime ones.
EOF
av_ok "wrote $ANVIL_DIR/README.md"

echo
av_info "Bootstrap complete. Edit these to suit your project:"
echo "  $ANVIL_DIR/forbidden-patterns.txt"
echo "  $ANVIL_DIR/pre-merge-gate.config.json"
echo "  $ANVIL_DIR/dispatch-defaults.txt"
echo
av_info "Now in Claude Code, try:"
echo "  /pre-merge-gate <pr-number>"
echo "  /dispatch-slice <slice-id> --scope \"...\""
