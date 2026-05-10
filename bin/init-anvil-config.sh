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

cp "$ANVIL_ROOT/skills/pre-merge-gate/templates/known-flakes.example.txt" "$ANVIL_DIR/known-flakes.txt"
av_ok "wrote $ANVIL_DIR/known-flakes.txt"

cat > "$ANVIL_DIR/dispatch-defaults.txt" <<'EOF'
# dispatch-defaults.txt — appended to every /dispatch-slice agent prompt.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ AI assistant reading this file:                                          │
# │                                                                          │
# │ This file is a STARTER. The lines below are illustrative — replace them │
# │ with the host project's real constraints. Sources to mine:               │
# │   • CLAUDE.md / AGENTS.md — "rules every agent should know"              │
# │   • README, contributing guide, security policy                          │
# │   • Recent post-mortems ("we got bit by X, never do X")                  │
# │   • Architectural boundaries declared in design docs                     │
# │                                                                          │
# │ Keep this list lean — it is prepended to every agent prompt. Brevity     │
# │ matters. ~20-40 lines is a sweet spot.                                   │
# │                                                                          │
# │ Common categories to populate:                                           │
# │   • Repo identity (name, default branch, pre-push hook behavior)         │
# │   • Model posture (default reasoning level / model)                      │
# │   • Vendor SDK boundaries (which SDKs only allowed in which dirs)        │
# │   • Test infrastructure invariants (worker counts, mocking rules)        │
# │   • Production quality floors (image sizes, batch settings, etc)         │
# │   • Security boundaries (CSRF, CSP, auth, secrets)                       │
# │   • DB transaction safety rules                                          │
# │   • PR template / commit-message conventions                             │
# └─────────────────────────────────────────────────────────────────────────┘
#
# One constraint per line. Lines starting with # are ignored.

# ── Illustrative starters. Replace with project-specific rules. ──

# Repo: <owner>/<repo>. Default branch: main. Pre-push hook runs <command>.
# Default to Opus reasoning unless the slice scope is verifiably trivial.
# DO NOT import vendor SDKs outside their approved boundary directories.
# DO NOT mock the database in integration tests — use the real test database.
# DO NOT commit secrets to .env or any tracked file.
# DO NOT bypass the existing CSRF middleware on web routes.
# Tests must run before commit (no broken-build commits).
# Every PR fills .github/pull_request_template.md fully.
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

> **AI assistant**: each of the static files below was bootstrapped from a starter
> template. The starter templates contain illustrative-only patterns that should
> be replaced with rules specific to this project. Each file has a clearly-marked
> "AI assistant reading this file" intro block at the top describing what to look
> for in the codebase + docs to populate it well. Read those intro blocks and
> replace the placeholder examples with real, project-specific rules before the
> first /grind run.

| File | Read by | Purpose | Tracked? |
|---|---|---|---|
| `forbidden-patterns.txt` | `/pre-merge-gate` | Grep patterns + path globs that block merge | yes |
| `pre-merge-gate.config.json` | `/pre-merge-gate` | Rebase target, test command, fitness path, blocking CI checks | yes |
| `known-flakes.txt` | `/pre-merge-gate` + `/grind` | Test patterns to retry once before treating as real failures | yes |
| `dispatch-defaults.txt` | `/dispatch-slice` | Per-project hard constraints appended to every agent prompt | yes |
| `grind-state.json` | `/grind` | Per-plan execution state (auto-managed) | no (gitignored) |
| `grind-events.jsonl` | `/grind` | Append-only event log (auto-managed) | no (gitignored) |
| `dispatched-agents.json` | `/dispatch-slice` | Tracking of in-flight agents (auto-managed) | no (gitignored) |

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
