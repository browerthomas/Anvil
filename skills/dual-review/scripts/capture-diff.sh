#!/usr/bin/env bash
# capture-diff.sh — extract the diff text for /dual-review from args, cap size,
# and surface metadata the skill needs for both legs.
#
# Usage:
#   capture-diff.sh [<scope>] [--pr <N>]
#
# Where <scope> is one of:
#   (empty)        → uncommitted (staged + unstaged + untracked)
#   <branch-name>  → current branch's diff vs <branch-name>
#   <SHA>          → that specific commit
#
# --pr <N> overrides scope and fetches PR #N's diff via gh.
#
# Outputs (stdout, machine-parseable):
#   diff_file=/tmp/dual-review-diff-<pid>.patch
#   scope=<one-line description>
#   line_count=<N>
#   too_big=<true|false>      (true if line_count > 4000)
#   codex_available=<true|false>
#
# The diff file is written to /tmp and its path returned. Caller cleans up.

set -euo pipefail

# --- Parse args ---
SCOPE_ARG=""
PR_NUM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR_NUM="${2:?--pr requires a PR number}"
      shift 2
      ;;
    --pr=*)
      PR_NUM="${1#--pr=}"
      shift
      ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [[ -z "$SCOPE_ARG" ]]; then
        SCOPE_ARG="$1"
      else
        echo "unexpected arg: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Confirm git repo ---
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "not a git repo" >&2
  exit 2
fi

# --- Output path ---
diff_file="/tmp/dual-review-diff-$$.patch"
: > "$diff_file"

# --- Build the diff text per scope ---
scope_desc=""

if [[ -n "$PR_NUM" ]]; then
  scope_desc="PR #${PR_NUM}"
  if ! gh pr diff "$PR_NUM" > "$diff_file" 2>/dev/null; then
    echo "failed to fetch PR #${PR_NUM} diff via gh" >&2
    exit 3
  fi
elif [[ -z "$SCOPE_ARG" ]]; then
  scope_desc="uncommitted (staged + unstaged + untracked)"
  git diff HEAD >> "$diff_file" 2>/dev/null || true
  git diff --staged >> "$diff_file" 2>/dev/null || true
  # Untracked files: include their content as a synthetic "new file" patch.
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    {
      echo "diff --git a/${f} b/${f}"
      echo "new file mode 100644"
      echo "--- /dev/null"
      echo "+++ b/${f}"
      sed 's/^/+/' "$f" 2>/dev/null || true
    } >> "$diff_file"
  done < <(git ls-files --others --exclude-standard)
elif git rev-parse --verify "$SCOPE_ARG" >/dev/null 2>&1; then
  # Could be a branch ref or a SHA. Disambiguate: if it resolves to a branch
  # (or remote ref), do `git diff <ref>...HEAD`. Otherwise treat as commit SHA
  # via `git show`.
  if git show-ref --verify --quiet "refs/heads/$SCOPE_ARG" \
     || git show-ref --verify --quiet "refs/remotes/origin/$SCOPE_ARG"; then
    scope_desc="current branch vs ${SCOPE_ARG}"
    git diff "${SCOPE_ARG}...HEAD" > "$diff_file"
  else
    # Likely a commit SHA.
    scope_desc="commit ${SCOPE_ARG}"
    git show "$SCOPE_ARG" > "$diff_file"
  fi
else
  echo "scope arg '${SCOPE_ARG}' does not resolve to a branch or commit" >&2
  exit 4
fi

# --- Size check ---
line_count=$(wc -l < "$diff_file" | tr -d ' ')
too_big="false"
if [[ "$line_count" -gt 4000 ]]; then
  too_big="true"
fi

# --- Codex availability ---
codex_available="false"
if command -v codex >/dev/null 2>&1; then
  # A quick `codex --version` should return fast if codex is installed and the
  # ChatGPT session is alive. We don't probe for rate-limit here because that
  # costs a real call; the underlying /codex-review skill will surface a
  # rate-limit error inline and the parent skill degrades gracefully.
  if codex --version >/dev/null 2>&1; then
    codex_available="true"
  fi
fi

# --- Output metadata ---
echo "diff_file=${diff_file}"
echo "scope=${scope_desc}"
echo "line_count=${line_count}"
echo "too_big=${too_big}"
echo "codex_available=${codex_available}"
