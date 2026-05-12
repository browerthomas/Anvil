#!/usr/bin/env bash
# shared/lib.sh — common helpers used across anvil skills.
# Source via: source "$(dirname "${BASH_SOURCE[0]}")/../../shared/lib.sh"

# --- Color codes (terminal-safe) ---
AV_GREEN='\033[0;32m'
AV_YELLOW='\033[0;33m'
AV_RED='\033[0;31m'
AV_BLUE='\033[0;34m'
AV_RESET='\033[0m'

# --- Logging helpers ---
av_info()  { printf "${AV_BLUE}[anvil]${AV_RESET} %s\n" "$*"; }
av_ok()    { printf "${AV_GREEN}✓${AV_RESET} %s\n" "$*"; }
av_warn()  { printf "${AV_YELLOW}~${AV_RESET} %s\n" "$*"; }
av_fail()  { printf "${AV_RED}✗${AV_RESET} %s\n" "$*" >&2; }

# --- Repo introspection ---
av_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}
av_repo_name() {
  basename "$(av_repo_root)"
}
av_default_base_branch() {
  # Honour `main` if present, else `master`, else origin/HEAD
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "origin/main"
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "origin/master"
  else
    git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@'
  fi
}

# --- Worktree management ---
av_worktree_path_for() {
  # Default worktree path for a given slice id.
  # /Users/foo/Desktop/myrepo + slice 1064 -> /Users/foo/Desktop/myrepo-1064
  local slice_id="$1"
  local repo_root parent_dir repo_name
  repo_root=$(av_repo_root) || return 1
  parent_dir=$(dirname "$repo_root")
  repo_name=$(basename "$repo_root")
  echo "${parent_dir}/${repo_name}-${slice_id}"
}

av_worktree_for_branch() {
  # Returns the path of the worktree currently checked out on a branch, or empty.
  local branch="$1"
  git worktree list | awk -v b="[${branch}]" '$3 == b {print $1; exit}'
}

av_install_deps_in_worktree() {
  # Run npm install in every package.json directory (excludes node_modules).
  local wt="$1"
  local pkg
  for pkg in $(find "$wt" -maxdepth 2 -name "package.json" -not -path "*/node_modules/*" 2>/dev/null); do
    (cd "$(dirname "$pkg")" && npm install --no-audit --no-fund 2>&1 | tail -3) &
  done
  wait
}

# --- File deletion (cloud-sync-friendly) ---
# `rm -rf` hangs on cloud-sync-evicted files (iCloud Drive, Dropbox,
# OneDrive, Google Drive Backup-and-Sync) because the OS tries to
# re-download the stub before unlinking. `find -delete` skips the
# download path and unlinks the entries directly. Same trick covers
# some sandboxed shells where the higher-permission `rm` path is denied.
av_safe_wipe_dir() {
  # Wipe a directory using find -delete (faster + cloud-sync-safe).
  # Falls back to rm -rf if find -delete fails.
  local target="$1"
  if [ ! -d "$target" ]; then
    return 0
  fi
  find "$target" -delete 2>/dev/null || rm -rf "$target" 2>/dev/null
  if [ -d "$target" ]; then
    av_warn "could not fully wipe $target (may have cloud-sync-evicted files — iCloud / Dropbox / OneDrive / Google Drive)"
    return 1
  fi
}

# --- Git lock cleanup ---
av_clear_git_locks() {
  local repo_root
  repo_root=$(av_repo_root) || return 1
  rm -f "$repo_root/.git/packed-refs.lock" \
        "$repo_root/.git/index.lock" \
        "$repo_root/.git/AUTO_MERGE.lock" \
        2>/dev/null
}

# --- PR introspection ---
av_pr_state() {
  # Echoes "STATE MERGEABLE MERGESTATE" for a given PR
  gh pr view "$1" --json state,mergeable,mergeStateStatus 2>/dev/null \
    | jq -r '"\(.state) \(.mergeable) \(.mergeStateStatus)"'
}

av_pr_branch() {
  gh pr view "$1" --json headRefName 2>/dev/null | jq -r '.headRefName'
}

av_existing_pr_for_branch() {
  # Returns the PR number for a given branch (open or draft), or empty.
  # Pass branch name as $1. If multiple, returns the first (most recent).
  # Returns empty + exit 0 if no PR found.
  local branch="$1"
  [ -z "$branch" ] && return 0
  gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null
}

av_pr_checks_summary() {
  # Echoes per-check status, one per line: "<bucket> <name>"
  gh pr checks "$1" --json name,bucket 2>/dev/null \
    | jq -r '.[] | "\(.bucket) \(.name)"'
}

av_pr_checks_all_pass() {
  # Returns 0 if all checks are pass or skipping.
  local pr="$1"
  local bad
  bad=$(av_pr_checks_summary "$pr" | awk '$1 != "pass" && $1 != "skipping" {print}')
  [ -z "$bad" ]
}

# --- Plan introspection ---
av_plan_extract_yaml() {
  # Extracts the YAML slice manifest from a markdown plan.
  # Looks for ```yaml ... ``` fence with `slices:` key.
  awk '/^```yaml/{flag=1; next} /^```/{flag=0} flag && /slices:/{print_block=1} print_block && flag {print}' "$1"
}

# --- Time helpers ---
av_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}
av_slug_now() {
  date +"%Y%m%d-%H%M%S"
}

# --- Path discovery ---
av_anvil_root() {
  # Resolves the anvil repo root from a sourced library path.
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# --- Template resolution (2-layer: project override -> core default) ---
# Resolves a template name through a 2-layer hierarchy. First hit wins.
#   Layer 1 (project override): ${PWD}/.anvil/templates/overrides/<name>
#   Layer 2 (core default):     $(av_anvil_root)/templates/<name>
#
# Prints the absolute path of the resolved template on stdout, exits 0.
# Refuses path traversal (`..` segments or a leading `/` in <name>) before
# any filesystem access. Refuses missing argument. Refuses name-not-found
# with a stderr message listing both searched paths.
#
# Reuses av_anvil_root() and the canonical ANVIL_ROOT install-root concept.
# (Do not introduce alternate install-root variables here — other names in
# bin/ are already overloaded for different meanings; see
# docs/template-overrides.md.)
av_resolve_template() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "av_resolve_template: missing template name argument" >&2
    return 2
  fi
  # Refuse path traversal BEFORE any filesystem access.
  # - Leading `/` would escape the project/core roots.
  # - Any `..` segment could climb out of the resolved root.
  # - Backslash defends against odd shell-quoted inputs.
  case "$name" in
    /*|*..*|*$'\\'*)
      echo "av_resolve_template: refusing path traversal in $name" >&2
      return 2
      ;;
  esac

  local project_path="${PWD}/.anvil/templates/overrides/${name}"
  local core_path
  core_path="$(av_anvil_root)/templates/${name}"

  if [ -e "$project_path" ]; then
    # Absolute path already (PWD is absolute on POSIX shells).
    printf '%s\n' "$project_path"
    return 0
  fi
  if [ -e "$core_path" ]; then
    printf '%s\n' "$core_path"
    return 0
  fi
  echo "av_resolve_template: $name not found (project: $project_path, core: $core_path)" >&2
  return 1
}
