---
name: dispatch-slice
description: Use to dispatch a single agent for a single plan slice with consistent briefing. Codifies the agent prompt template (worktree path, deps install reminder, commit format, PR template requirement, default-Opus posture, return shape). Invoke with /dispatch-slice <issue-or-slice-id> "<scope>" or when the operator says "dispatch a slice", "spin up an agent for X", "handle issue #N as a slice".
---

# /dispatch-slice — single-slice agent dispatch with full briefing

The grind loop dispatches many agents. Each needs ~600 words of consistent briefing: worktree path, deps reminder, hard constraints, return shape, default-Opus posture. This skill produces that briefing from minimal args.

## When to invoke

- Operator says "dispatch a slice", "spin up an agent for X", "handle issue #N", "dispatch #1064", or similar.
- `/grind` invokes this internally for each slice in a plan.
- Manually for one-off agent work that benefits from the consistent shape.

## Args

| Arg | Required | Description |
|---|---|---|
| `<id>` | yes | Slice ID (e.g. `slice-A1`, issue # like `1064`, ad-hoc name `fix-csrf`) |
| `--scope "<text>"` | yes | One-paragraph description of what the agent must do |
| `--branch <name>` | no | Branch name (defaults to `fix-<id>` or `feat-<id>` based on title) |
| `--worktree <path>` | no | Worktree path (defaults to `<repo-parent>/<repo-name>-<id>`) |
| `--base <branch>` | no | Base branch (defaults to `origin/main`) |
| `--constraints "<text>"` | no | Hard constraints in addition to default boilerplate |
| `--tests "<target>"` | no | Test count target (e.g. "965+") |
| `--no-codex` | no | Skip codex-review reminder in agent prompt (set when codex is rate-limited) |

## Procedure

### Step 1: Resolve defaults

```bash
# Repo root + name
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
PARENT_DIR=$(dirname "$REPO_ROOT")

# Defaults
BRANCH="fix-${ID}"
WORKTREE_PATH="${PARENT_DIR}/${REPO_NAME}-${ID}"
BASE_BRANCH="origin/main"
```

### Step 2: Create worktree + install deps

```bash
git worktree add -B "$BRANCH" "$WORKTREE_PATH" "$BASE_BRANCH"

# Install deps (package-by-package; some repos have nested package.json)
for pkg in $(find "$WORKTREE_PATH" -maxdepth 2 -name "package.json" -not -path "*/node_modules/*"); do
  (cd "$(dirname "$pkg")" && npm install --no-audit --no-fund) &
done
wait
```

Run deps install in BACKGROUND so the agent dispatch doesn't block waiting.

### Step 3: Build the agent prompt

Use the canonical template at `templates/agent-prompt.md` (relative to this skill dir). Variables in `{{ ... }}` are filled from the args. Helpers from `shared/lib.sh`:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../../shared/lib.sh"
worktree=$(av_worktree_path_for "$slice_id")
base=$(av_default_base_branch)
git worktree add -B "$branch" "$worktree" "$base"
av_install_deps_in_worktree "$worktree" &  # background
```

Standard sections in the prompt (per template):

1. **Issue context** — link, body summary
2. **Worktree path** — full path
3. **Branch name** — `<branch>`
4. **Scope** — operator-supplied scope paragraph
5. **Required tests** — what the agent must add + target test count
6. **Hard constraints** — defaults below + operator-supplied additions
7. **Procedure** — `npm install` if needed, read relevant files, implement, run `tsc --noEmit && vitest run`, commit + push, open PR
8. **Commit message format** — conventional commit (`feat(scope):`, `fix(scope):`, etc) referencing issue #
9. **PR template** — fill `.github/pull_request_template.md` fully (What/Summary/Why/Risks/Testing/Scope/Links)
10. **Return shape** — PR URL, test count, LoC delta, files changed, design decisions, pushback if any

Default hard constraints (always include):

```
- DO NOT touch unrelated files. NO comments-only changes outside this slice.
- DO NOT add new env vars unless strictly required.
- All architectural fitness ratchets in <FITNESS_TEST_PATH> must stay green.
- Tests target: <TEST_TARGET>+ passing (current baseline: <TEST_BASELINE>).
- Commit message format: <COMMIT_PREFIX>(<scope>): <imperative summary> [#<issue>]
- Default Opus reasoning. Quality over token-thrift.
```

Project-specific constraints come from `.anvil/dispatch-defaults.txt` (one constraint per line; appended to the boilerplate). If the file doesn't exist, only the defaults above apply.

Codex reminder (omit if `--no-codex`):

```
After implementation, run `/codex-review` (cross-model review). If codex is rate-limited, the orchestrator will run `/self-review` post-merge for paper-trail.
```

### Step 4: Dispatch via Agent tool

```
Agent({
  description: "<id> <one-line>",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "<assembled prompt>",
  run_in_background: true
})
```

Default to background. Operator can foreground if a single agent is the only thing in flight.

### Step 5: Record + return the agent ID + summary

Append a row to `.anvil/dispatched-agents.json` (auto-create if missing) so `/grind` can track in-flight work:

```json
{
  "<slice-id>": {
    "agent_id": "<agent-id>",
    "worktree": "<worktree-path>",
    "branch": "<branch-name>",
    "dispatched_at": "<iso-timestamp>",
    "scope": "<one-line summary>"
  }
}
```

Print to operator:
- Worktree path
- Branch name
- Agent ID (background reference)
- Estimated time (small ≤500 LoC = ~5min; medium ≤1500 LoC = ~10-15min; large ≤3000 LoC = ~20-30min)
- "I'll notify when it completes"

## What the agent should know about the framework

Embed in every dispatch prompt: a one-paragraph note that the framework expects:
- Self-verified tsc + vitest pass before commit
- PR opened with full template
- Pushback documented in the return summary
- LoC delta + test count delta in return summary

This makes the return shape consistent so the orchestrator can parse it.

## When this skill SAVES time

Tonight's session: ~15 agent dispatches. Each ~600 word prompt manually written + adapted. With this skill: 3-line invocation + skill emits the full prompt. Saves token cost, reduces brief variance, eliminates "did I forget the return shape?" bugs.

## When NOT to use

- Trivial single-line edits (do them yourself — agent dispatch overhead exceeds the work).
- Operator-pace decisions (deploys, cleanups that need real-time eyes).
- When the task is "investigate" not "implement" — use a research agent template instead (separate skill).
