---
name: auto-merge
description: Use to squash-merge a PR + delete branch + wipe worktree + sync main, in one shot. Assumes /pre-merge-gate has already greenlit the PR. Invoke with /auto-merge <pr-number> or when the operator says "merge it", "ship it", "auto-merge that one".
---

# /auto-merge — squash-merge + cleanup in one call

A multi-PR sprint runs this exact sequence per PR — manually it's five steps with footguns at each:

1. `gh pr merge <n> --squash --delete-branch`
2. `find <worktree> -delete` (handle iCloud-evicted node_modules)
3. `find .git/worktrees/<n> -delete` (clear admin)
4. `git branch -D <branch>` (force-delete; squash-merge leaves branch as "unmerged")
5. `git pull origin main` (sync local main)

Each step has a footgun (stale lock files, "branch used by worktree" errors, `rm` hung on cloud-sync-evicted files — iCloud / Dropbox / OneDrive / Google Drive). This skill does it correctly in one call.

## When to invoke

- Operator says "merge it", "ship it", "auto-merge that one".
- `/grind` invokes internally when CI is green + `/pre-merge-gate` returned merge-ready.
- After manual `/codex-review` or `/self-review` returned no findings.

## When NOT to use

- PR has unresolved review comments.
- CI is pending or failed.
- `/pre-merge-gate` returned blocked.
- PR is to a protected branch other than `main` (configure `--target` if needed).

## Args

| Arg | Required | Description |
|---|---|---|
| `<pr-number>` | yes | PR to merge |
| `--strategy <s>` | no | `squash` (default), `merge`, `rebase` |
| `--worktree <path>` | no | Worktree to wipe; auto-derives from PR branch if omitted |
| `--no-pull` | no | Skip the post-merge `git pull` (useful when running in a worktree, not main repo) |

## Procedure

### Step 1: Verify PR is green + mergeable

```bash
state=$(gh pr view <n> --json state,mergeable,mergeStateStatus)
```

Must be: `state=OPEN`, `mergeable=MERGEABLE`, `mergeStateStatus=CLEAN`. If not — abort with a clear message.

CI must be green:

```bash
gh pr checks <n> --json name,bucket | \
  jq -e '. | all(.bucket == "pass" or .bucket == "skipping")'
```

If any check is `pending` or `fail` — abort. Operator must decide.

### Step 2: Capture metadata for cleanup + log

```bash
BRANCH=$(gh pr view <n> --json headRefName --jq '.headRefName')
TITLE=$(gh pr view <n> --json title --jq '.title')
WORKTREE_PATH=${OPT_WORKTREE:-$(git worktree list | awk -v b="$BRANCH" '$3 == "[" b "]" {print $1}')}
```

### Step 3: Squash-merge

```bash
gh pr merge <n> --<strategy> --delete-branch
```

The `--delete-branch` flag deletes both remote and local. **It WILL fail to delete the local branch if a worktree still holds it** — that's expected, we handle in step 4.

### Step 4: Wipe worktree

If worktree exists:

```bash
# Use find -delete (works on iCloud-evicted node_modules; rm -rf hangs)
find "$WORKTREE_PATH" -delete 2>/dev/null
```

Then clear git's worktree admin:

```bash
WORKTREE_NAME=$(basename "$WORKTREE_PATH")
find "$REPO_ROOT/.git/worktrees/$WORKTREE_NAME" -delete 2>/dev/null
git worktree prune
```

### Step 5: Force-delete the local branch

```bash
git -C "$REPO_ROOT" branch -D "$BRANCH" 2>&1
```

Use `-D` (capital). Squash-merges leave branches looking unmerged — `-d` would refuse.

### Step 6: Clear stale lock files

After the dance, git sometimes leaves `.lock` files:

```bash
rm -f "$REPO_ROOT/.git/packed-refs.lock" "$REPO_ROOT/.git/index.lock" "$REPO_ROOT/.git/AUTO_MERGE.lock"
```

### Step 7: Sync local main (unless --no-pull)

```bash
git -C "$REPO_ROOT" checkout main
git -C "$REPO_ROOT" pull origin main
```

### Step 8: Auto-emit a learning when the merge involved a non-trivial rebase

If the merge required `/pre-merge-gate` to rebase the branch (i.e. it wasn't already up-to-date with `origin/main`), the rebase shape itself is worth remembering — especially for stacked-PR work where the *next* slice will face the same dance.

```bash
# Read the rebase-commit count if /pre-merge-gate recorded it.
# (e.g. exported as PRE_MERGE_GATE_REBASE_COMMITS by the caller, or 0 if absent)
rebase_commits="${PRE_MERGE_GATE_REBASE_COMMITS:-0}"

if [ "$rebase_commits" -gt 0 ]; then
  # Slice + plan-slug detection mirrors post-merge-debrief.
  case "$BRANCH" in
    feat-*-S[0-9]*) slice_id=$(echo "$BRANCH" | sed 's/.*-S\([0-9]*\).*/S\1/');;
    fix-[0-9]*)     slice_id=$(echo "$BRANCH" | sed 's/^fix-//');;
    *)              slice_id="";;
  esac

  merge_key="rebase-shape-${BRANCH//\//-}"

  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    "$merge_key" "migration-shape" \
    "PR #${PR_NUMBER} merged after rebase of ${rebase_commits} commits onto origin/main. Branch: ${BRANCH}." \
    --confidence low \
    --source /auto-merge \
    --slice "$slice_id" \
    --tag rebase \
    2>/dev/null || true
fi
```

Confidence is `low` because a single merge isn't yet a pattern — but the `key` shape ensures that if the same plan's later slices all need the same dance, `prior_count` accumulates and `/learn search rebase` surfaces it.

Soft-fail. If `/learn add` errors, the merge has already landed; report continues.

### Step 9: Report

Print:
- ✅ Merged: PR #<n> — <title>
- 🧹 Cleaned: worktree + branch + admin
- 📥 Synced: local main → <new-sha>

## Error handling

| Error | Cause | Fix |
|---|---|---|
| "PR has merge conflicts" | branch out-of-date | Run `/pre-merge-gate <n>` to rebase + retest |
| "branch used by worktree" | step 4 didn't fire correctly | Re-run step 4 manually |
| ".git/packed-refs.lock exists" | stale concurrent git process | Step 6 should clear; retry once |
| `rm`/`find` permission denied | sandboxed shell, or filesystem-level eviction (cloud-sync, encrypted volumes, NFS drop) | Operator runs the wipe manually outside the sandbox |
| "checks pending" | CI not finished | Wait + re-invoke |

## What this saves

Per-PR: ~6 manual commands + ~30s of attention. A 12-PR sprint = 72 commands manually. With this skill: 12 invocations.

## Composition with other skills

- After `/dispatch-slice` agent returns + CI green: `/pre-merge-gate <n>` → if merge-ready: `/auto-merge <n>`.
- `/grind` does this composition automatically per slice.
