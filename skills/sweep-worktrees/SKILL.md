---
name: sweep-worktrees
description: Use when worktrees / local branches have piled up after a multi-PR sprint and the operator wants them cleaned in one shot. Handles iCloud-evicted node_modules, stale `.git/*.lock` files, `.git/worktrees/*` admin dirs, and force-deletes branches whose PRs are MERGED or CLOSED. Invoke with /sweep-worktrees or when the operator says "clean up the worktrees", "shells are piling up", "kill the stale branches", or similar.
---

# /sweep-worktrees — bulk-cleanup of worktrees + branches

After 10+ PR cycles in a sprint, operators accumulate ~20 worktree directories alongside their main repo and ~30 local branches. Cleanup is fiddly in three predictable ways:

- iCloud-Drive synced `node_modules` directories evict to network, leaving symlink stubs that hang `rm -rf` and `git worktree remove` indefinitely.
- Stale `.git/*.lock` files block branch deletion.
- Git refuses to delete a branch tied to a worktree, even when the worktree is empty.

This skill codifies the cleanup path so it's a single command instead of trial-and-error.

## When to invoke

- Operator says "clean up the worktrees", "shells are piling up", "wipe the merged branches", "tidy the git tree".
- Periodic hygiene at session end after a multi-PR sprint.
- After `git worktree list` shows >5 entries that aren't actively in use.

## Procedure

### Step 1: Classify worktrees

```bash
git worktree list
```

For each non-main worktree, identify the underlying branch + PR state:

```bash
for b in <branch-list>; do
  pr_state=$(gh pr list --state all --head "$b" --json number,state,mergedAt --limit 1 \
    | jq -r '.[0] | "\(.number) \(.state) \(.mergedAt // "-")"')
  printf "%-50s %s\n" "$b" "${pr_state:-NO PR}"
done
```

Outcome buckets:
- **MERGED** → safe to delete worktree + branch.
- **CLOSED** → safe to delete (work was abandoned or superseded).
- **OPEN** → keep (active PR).
- **NO PR** → orphan; check last-commit date with `git log -1 --format=%ci <branch>`. If >7 days old + no obvious reason, propose delete.

### Step 2: Confirm with operator

Before destructive action, AskUserQuestion with the classification:

```
N stale worktree directories detected.
Bulk-delete the M whose PRs are MERGED or CLOSED?
```

Don't proceed without explicit yes.

### Step 3: Wipe worktree contents (parallel)

iCloud-evicted `node_modules` is slow to delete via `rm -rf` because the OS has to re-fetch each evicted file before unlinking. `find -delete` is faster — walks the tree depth-first and never needs to materialize file content.

```bash
for d in <worktree-paths>; do
  find "$d" -delete 2>&1 &
done
wait
```

Expect 30-90 seconds for ~10 worktrees. Don't poll; let it complete.

If a worktree resists deletion (file still has handles, evicted file refuses materialization), `rm -rf` may also fail. Retry once; if still failing, skip + report the path so the operator can investigate.

### Step 4: Clear git's worktree bookkeeping

`git worktree remove --force` won't work on directories that already don't exist; use the bookkeeping cleanup:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
find "$REPO_ROOT/.git/worktrees" -mindepth 1 -delete
git worktree prune -v
```

### Step 5: Clear stale lock files

After bulk worktree operations, git often leaves `.lock` files that block subsequent commands:

```bash
rm -f "$REPO_ROOT/.git/packed-refs.lock" \
      "$REPO_ROOT/.git/index.lock" \
      "$REPO_ROOT/.git/AUTO_MERGE.lock"
```

### Step 6: Force-delete branches

```bash
git -C "$REPO_ROOT" branch -D <branch-list>
```

Use `-D` (capital). Squash-merges leave branches that look unmerged to git but ARE integrated via the squash commit; `-d` would refuse them.

If branch deletion fails with "cannot delete branch X used by worktree at Y": the worktree bookkeeping wasn't cleared (step 4 incomplete). Re-run step 4 + retry.

### Step 7: Sanity check

```bash
git worktree list
git branch | wc -l
```

Report the before/after counts to the operator.

## Error patterns + workarounds

| Symptom | Cause | Fix |
|---|---|---|
| `find -delete` hangs on a single worktree | cloud-sync-evicted `node_modules` symlink storm (iCloud / Dropbox / OneDrive / Google Drive) | Skip that worktree; report path; try again later |
| `git branch -D X` says "used by worktree Y" but Y doesn't exist | `.git/worktrees/Y/` admin dir wasn't cleared | Re-run step 4 |
| `.git/packed-refs.lock` exists | stale concurrent `git` process | `rm -f` the lock |
| `rm -rf` permission denied or hangs | sandboxed shell, or cloud-sync-evicted files | Use `find -delete` instead — skips the OS re-download path |
| `git worktree remove --force` hangs >2 min | cloud-sync `node_modules` content re-fetch | Kill the command; use `find -delete` directly |

## Cadence

Run after every multi-PR sprint (≥5 PRs merged) or weekly on quiet weeks.
