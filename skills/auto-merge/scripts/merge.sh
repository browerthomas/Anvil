#!/usr/bin/env bash
# anvil/auto-merge — squash-merge + cleanup + sync, in one shot.
#
# Usage:
#   merge.sh <pr-number> [--strategy squash|merge|rebase] [--worktree <path>] [--no-pull]
#
# Returns:
#   0 → merged + cleaned + main synced
#   1 → blocked (specific reason printed to stderr)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

PR="${1:-}"
shift || true
if ! [[ "$PR" =~ ^[0-9]+$ ]]; then
  av_fail "usage: merge.sh <pr-number> [opts]"
  exit 1
fi

STRATEGY="squash"
WORKTREE=""
PULL_MAIN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --strategy) STRATEGY="$2"; shift 2;;
    --worktree) WORKTREE="$2"; shift 2;;
    --no-pull)  PULL_MAIN=0; shift;;
    *) av_fail "unknown arg: $1"; exit 1;;
  esac
done

REPO_ROOT=$(av_repo_root) || { av_fail "not in a git repo"; exit 1; }

# 1. Verify PR is mergeable
av_info "Checking PR #$PR state..."
PR_STATE=$(av_pr_state "$PR")
read -r STATE MERGEABLE MERGESTATE <<< "$PR_STATE"

if [ "$STATE" != "OPEN" ]; then
  av_fail "PR #$PR is not OPEN (state: $STATE)"
  exit 1
fi
if [ "$MERGEABLE" != "MERGEABLE" ] && [ "$MERGEABLE" != "UNKNOWN" ]; then
  av_fail "PR #$PR is not mergeable (mergeable: $MERGEABLE, state: $MERGESTATE)"
  exit 1
fi

# 2. Verify CI green
av_info "Checking CI status..."
if ! av_pr_checks_all_pass "$PR"; then
  av_pr_checks_summary "$PR" | awk '$1 != "pass" && $1 != "skipping"' | while read -r line; do
    av_warn "  $line"
  done
  av_fail "PR #$PR CI not all green; aborting"
  exit 1
fi
av_ok "CI green"

# 3. Capture metadata
BRANCH=$(av_pr_branch "$PR")
TITLE=$(gh pr view "$PR" --json title --jq '.title' 2>/dev/null)
[ -z "$WORKTREE" ] && WORKTREE=$(av_worktree_for_branch "$BRANCH")

# 4. Squash-merge
av_info "Merging PR #$PR (--$STRATEGY)..."
if ! gh pr merge "$PR" "--$STRATEGY" --delete-branch 2>&1 | tail -3; then
  # gh pr merge often fails the LOCAL branch deletion when a worktree holds it.
  # That's fine — we'll handle it below.
  :
fi

# Confirm merge happened (retry once for race)
sleep 1
POST_STATE=$(gh pr view "$PR" --json state --jq '.state')
if [ "$POST_STATE" != "MERGED" ]; then
  av_fail "PR #$PR did not enter MERGED state (got: $POST_STATE)"
  exit 1
fi
av_ok "merged"

# 5. Wipe worktree
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  av_info "Wiping worktree $WORKTREE..."
  if av_safe_wipe_dir "$WORKTREE"; then
    av_ok "worktree wiped"
  else
    av_warn "worktree partially cleaned (likely cloud-sync evicted: iCloud / Dropbox / OneDrive); continuing"
  fi

  # Clear git's bookkeeping for this worktree
  WT_NAME=$(basename "$WORKTREE")
  WT_ADMIN="$REPO_ROOT/.git/worktrees/$WT_NAME"
  [ -d "$WT_ADMIN" ] && find "$WT_ADMIN" -mindepth 0 -delete 2>/dev/null
  git -C "$REPO_ROOT" worktree prune 2>/dev/null
fi

# 6. Clear stale lock files
av_clear_git_locks
av_ok "git locks cleared"

# 7. Force-delete the local branch
if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  if git -C "$REPO_ROOT" branch -D "$BRANCH" 2>&1 | tail -1; then
    av_ok "branch deleted"
  else
    av_warn "could not delete local branch $BRANCH (still in use?)"
  fi
fi

# 8. Sync main
if [ "$PULL_MAIN" -eq 1 ]; then
  av_info "Syncing local main..."
  CURRENT=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  if [ "$CURRENT" != "main" ]; then
    git -C "$REPO_ROOT" checkout main 2>&1 | tail -1
  fi
  git -C "$REPO_ROOT" pull origin main 2>&1 | tail -3
  av_ok "main synced"
fi

# === REPORT ===
echo
printf "${AV_GREEN}✅ Merged: PR #%s — %s${AV_RESET}\n" "$PR" "$TITLE"
printf "${AV_GREEN}🧹 Cleaned: worktree + branch + admin${AV_RESET}\n"
[ "$PULL_MAIN" -eq 1 ] && printf "${AV_GREEN}📥 Synced: local main${AV_RESET}\n"
exit 0
