---
name: post-merge-debrief
description: Use after a single PR squash-merges to bundle (verify-merge + sweep-this-worktree + mark-merged-in-event-log + pull-main + auto-dispatch-next-slice-if-deps-met). Compresses 5 manual steps into one call. Useful when an operator merges a PR outside of /grind and wants the standard cleanup. Invoke with /post-merge-debrief <pr-number> or when the operator says "debrief that merge", "wrap up after the merge", "what's next after merging".
---

# /post-merge-debrief — single-PR cleanup + next-slice dispatch in one call

After any squash-merge, an operator runs the same five steps:

1. Verify the merge actually landed.
2. Sweep the worktree for that branch.
3. If a `/grind` plan is active: mark the slice merged in `.anvil/grind-events.jsonl`.
4. Pull main locally.
5. If the next dependent slice is now ready: dispatch its agent.

`/grind` does this internally. This skill is the standalone version for when the operator merged outside of `/grind` (one-off PR, manual `gh pr merge`, GitHub-UI merge).

## When to invoke

- Operator merged a PR via `gh pr merge` or the GitHub UI and wants the standard cleanup.
- After `/auto-merge` if a plan is in flight and the operator wants the next slice dispatched without re-entering `/grind`.
- Cron-style call after every merge in a multi-slice plan.

## When NOT to use

- The merge was reverted — clean up via git, not this skill.
- The PR isn't part of an active plan and the operator doesn't want a worktree wipe (some operators keep worktrees for follow-up cleanup).
- The plan is intentionally paused mid-grind — auto-dispatching the next slice would resume it without operator approval.

## Args

| Arg | Required | Description |
|---|---|---|
| `<pr-number>` | yes | PR that just merged |
| `--no-dispatch` | no | Don't dispatch the next slice even if ready (default: auto-dispatch if there's a plan + the next slice has all deps met) |
| `--no-sweep` | no | Don't wipe the worktree (default: sweep) |
| `--plan <path>` | no | Path to active plan (auto-detected from `.anvil/grind-events.jsonl` if omitted) |

## Procedure

### Step 1: Verify the merge

```bash
state=$(gh pr view <pr> --json state,mergedAt,mergeCommit --jq '{state, mergedAt, sha: .mergeCommit.oid}')
```

Must be: `state=MERGED`, `mergedAt` is a recent timestamp, `mergeCommit.sha` is set. If not — abort with a clear message.

### Step 2: Capture metadata

```bash
BRANCH=$(gh pr view <pr> --json headRefName --jq '.headRefName')
WORKTREE_PATH=$(git worktree list | awk -v b="$BRANCH" '$NF == "[" b "]" {print $1}')
```

### Step 3: Mark merged in event log (if plan active)

If `.anvil/grind-events.jsonl` exists, derive the slice ID from the branch name:
- `feat-<plan>-S<N>` → slice ID `S<N>`
- `fix-<id>` → slice ID `<id>`
- Otherwise → no slice match; skip event log update.

```bash
bash <anvil-root>/skills/grind/scripts/state.sh mark <slice> merged
bash <anvil-root>/skills/grind/scripts/state.sh set-pr <slice> <pr>
```

### Step 4: Sweep the worktree (unless --no-sweep)

```bash
find "$WORKTREE_PATH" -delete 2>/dev/null
WORKTREE_NAME=$(basename "$WORKTREE_PATH")
find "$REPO_ROOT/.git/worktrees/$WORKTREE_NAME" -delete 2>/dev/null
git worktree prune
git -C "$REPO_ROOT" branch -D "$BRANCH" 2>&1
```

### Step 5: Sync local main

```bash
git -C "$REPO_ROOT" checkout main
git -C "$REPO_ROOT" pull origin main
```

### Step 6: Check next slice (unless --no-dispatch)

If a plan is active:

```bash
NEXT=$(bash <anvil-root>/skills/grind/scripts/state.sh next)
```

If `NEXT` is empty (no slices left) → output "Plan complete; consider running /recap."

If `NEXT` is set → check whether it's safe to auto-dispatch:
- All `depends-on` slices are merged
- The next slice doesn't have an `operator-decision.ask` (or has one with `default: approve`)

If safe: invoke `/dispatch-slice <NEXT>` to fire the agent. If unsafe (operator decision pending): print the ASK + tell operator to invoke `/grind` to resume.

### Step 7: Output summary

```
=== /post-merge-debrief ===
✅ Merged: PR #<N> — <title> (sha <short-sha>)
🧹 Cleaned: worktree + branch + admin
📥 Synced: local main → <new-sha>
🔄 Marked S<N> → merged in event log
🚀 Dispatched: S<N+1> (agent <id>) | OR Plan complete | OR Operator decision required
```

## Composition

- Composes: `gh pr view`, `find -delete`, `git worktree prune`, `git pull`, `state.sh`, `/dispatch-slice`.
- Subset of `/grind`'s per-slice loop (the post-merge half).
- Pairs with `/auto-merge` — they're the two halves of a "land + advance" cycle outside of `/grind`.
