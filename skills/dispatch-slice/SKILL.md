---
name: dispatch-slice
description: Use to dispatch a single agent for a single plan slice with consistent briefing. Codifies the agent prompt template (worktree path, deps install reminder, commit format, PR template requirement, default-Opus posture, return shape). Invoke with /dispatch-slice <issue-or-slice-id> "<scope>" or when the operator says "dispatch a slice", "spin up an agent for X", "handle issue #N as a slice".
---

# /dispatch-slice — single-slice agent dispatch with full briefing

The grind loop dispatches many agents. Each needs ~600 words of consistent briefing: worktree path, deps reminder, hard constraints, return shape, default-Opus posture. This skill produces that briefing from minimal args.

## When to invoke

- Operator says "dispatch a slice", "spin up an agent for X", "handle issue #N", or similar.
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

# PR-exists idempotency check (anvil#7)
EXISTING_PR=$(av_existing_pr_for_branch "$BRANCH")
# If non-empty, the agent prompt instructs `gh pr edit <N>` instead of
# `gh pr create` so a previously-failed dispatch attempt doesn't error
# the second time around.
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

**If `git worktree add` fails** (branch already in use by another worktree, target dir already exists, base-branch invalid) OR deps install fails (npm registry timeout, lockfile mismatch, iCloud-evicted node_modules), auto-emit a `gotcha` learning so the next dispatcher sees it:

```bash
# Pseudocode — wrap each failure mode.
case "$failure_kind" in
  "worktree-add-failed-branch-in-use")
    detail="branch '$BRANCH' already in use by another worktree" ;;
  "worktree-add-failed-dir-exists")
    detail="target directory '$WORKTREE_PATH' already exists" ;;
  "worktree-add-failed-base-invalid")
    detail="base '$BASE_BRANCH' could not be resolved (did you fetch?)" ;;
  "deps-install-failed")
    detail="npm install in $WORKTREE_PATH failed — possibly icloud-evicted node_modules or registry timeout" ;;
esac

key="dispatch-fail-${failure_kind}"

bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
  "$key" "gotcha" \
  "Dispatch for slice '$ID' failed: $detail. Operator action needed before re-dispatching." \
  --confidence medium \
  --source /dispatch-slice \
  --slice "$ID" \
  --tag dispatch-fail \
  2>/dev/null || true
```

Soft-fail. The learning emit must not mask the original failure — the dispatch fails loudly and the operator sees the real cause; the JSONL entry is a paper trail.

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

0. **Project constitution** — auto-injected from `.anvil/constitution.md` if present (see below)
1. **Issue context** — link, body summary
2. **Worktree path** — full path
3. **Branch name** — `<branch>`
4. **Scope** — operator-supplied scope paragraph
5. **Required tests** — what the agent must add + target test count
6. **Hard constraints** — defaults below + operator-supplied additions
7. **Recent decisions** — auto-injected from `/learn decisions --affected <slice-id>` if any matching rows exist (see below)
8. **Procedure** — `npm install` if needed, read relevant files, implement, run `tsc --noEmit && vitest run`, commit + push, open PR
9. **Commit message format** — conventional commit (`feat(scope):`, `fix(scope):`, etc) referencing issue #
10. **PR template** — fill `.github/pull_request_template.md` fully (What/Summary/Why/Risks/Testing/Scope/Links)
11. **Return shape** — PR URL, test count, LoC delta, files changed, design decisions, pushback if any

#### Project constitution auto-injection

Before assembling the rest of the prompt, `build-prompt.sh` sources `${ANVIL_ROOT}/shared/lib.sh` and calls `av_load_constitution`, which reads `${PWD}/.anvil/constitution.md` if present. Behaviour:

- File present + non-empty + valid UTF-8 → contents prepended as a `## Project constitution` section at the top of the prompt (before scope, before hard constraints).
- File absent OR empty OR whitespace-only → no section emitted, prompt is byte-identical to the pre-S1 shape.
- File contains non-UTF-8 bytes → `av_load_constitution` warns to stderr (`warning: .anvil/constitution.md is not valid UTF-8; skipping prepend`) and returns empty; dispatch continues with the legacy brief shape (graceful degradation, not a hard fail).
- File > 2048 bytes → stderr warning `warning: .anvil/constitution.md is N bytes (recommended ≤ 2048)`; dispatch proceeds.
- File > 8192 bytes → stderr warning `warning: .anvil/constitution.md is N bytes — this will bloat every dispatched-agent prompt`; dispatch proceeds.

The constitution slot is for **project ethos** — north star, inviolable principles, things explicitly out of scope. NOT mechanical config (use `.anvil/dispatch-defaults.txt` for that). The scaffolded template at `templates/constitution-template.md` is dropped into `.anvil/constitution.md` by `bin/init-anvil-config.sh` on first init (it is NOT touched by `/config-bootstrap` — auto-synthesis was rejected in adversarial review).

#### On-disk prompt emission (load-bearing)

`build-prompt.sh` writes the full assembled prompt to `.anvil/dispatched-prompts/<slice-id>.prompt.md` **before** the Agent tool is invoked. Hard fail if the directory cannot be created or the file cannot be written: `error: cannot write to .anvil/dispatched-prompts/: <reason>`. Without the on-disk emission the constitution prepend (and the rest of the brief shape) is not testable from bats; the directory is auto-created and gitignored (it is runtime state, not source). The Agent tool caller MUST run `build-prompt.sh` first; the resulting prompt is on stdout AND on disk.

#### Recent decisions auto-injection

Before assembling the prompt, query `/learn` for any `type:decision` rows whose `affected_slices` array contains the dispatching slice id:

```bash
bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions \
  --affected "$ID" --json 2>/dev/null
```

If the call returns a non-empty array, render a "## Recent decisions" section into the prompt — one bullet per row with `decision_type`, `key`, and `insight`. Example agent-visible output:

```
## Recent decisions

These design decisions (logged via `/learn add --decision-type ...`) affect this slice. Treat them as binding constraints unless your scope explicitly reverses them.

- [architecture] chose-redis-over-postgres-listen — retry semantics under worker restart cleaner with redis pub/sub; trade-off documented in design.md
- [scope] no-new-state-files — extending /learn instead of adding /decide skill; same .anvil/learnings.jsonl with type:decision
```

If `/learn decisions` returns empty (no matching decisions), the section is omitted entirely — no empty "Recent decisions: (none)" noise. The injection is read-only on `.anvil/learnings.jsonl`. Soft-fail: if the call errors, the dispatch continues without the section.

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

Append a row to `.anvil/dispatched-agents.json` (auto-create if missing) so `/grind` can track in-flight work AND `/pre-merge-gate` can locate the slice + plan for per-slice checklist enforcement (see `skills/pre-merge-gate/SKILL.md` Step 6.5):

```json
{
  "<slice-id>": {
    "agent_id": "<agent-id>",
    "worktree": "<worktree-path>",
    "branch": "<branch-name>",
    "plan_path": "<absolute-or-repo-relative path to the plan file or folder>",
    "dispatched_at": "<iso-timestamp>",
    "scope": "<one-line summary>"
  }
}
```

The `branch` field is the exact-match key `/pre-merge-gate` looks up. The `plan_path` field points at either the flat plan markdown OR the folder-layout `tasks.md` so `av_parse_slice_checklist` can find the slice manifest.

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

A typical multi-slice sprint dispatches 8-15 agents. Each needs ~600 words of consistent briefing — manually written and adapted, that's significant token spend and a steady source of "did I forget the return shape?" bugs. With this skill: 3-line invocation + skill emits the full prompt.

## When NOT to use

- Trivial single-line edits (do them yourself — agent dispatch overhead exceeds the work).
- Operator-pace decisions (deploys, cleanups that need real-time eyes).
- When the task is "investigate" not "implement" — use a research agent template instead (separate skill).
