#!/usr/bin/env bash
# bin/check-leaks.sh — pre-merge / CI leak grep.
#
# Reads forbidden patterns from .anvil/check-leaks.patterns.txt (per-project,
# gitignored or committed at the project's discretion). The example file ships
# at .anvil/check-leaks.patterns.example.txt as a template; the live file is
# not auto-created.
#
# Pattern shape (one per line, `::` is the field separator):
#   <substring-or-regex> :: <path-glob> :: <exclusion-glob>
# - <substring-or-regex>: extended-regex (grep -E), case-sensitive by default.
# - <path-glob>:          shell glob matched against the file path. Multiple
#                         globs separated by `;`. Examples: `**/*`, `**/*.md`,
#                         `src/**`.
# - <exclusion-glob>:     optional. Multiple globs separated by `;`. A path
#                         matching any exclusion is skipped. Examples:
#                         `skills/**;tests/fixtures/**`.
# Lines starting with `#` are comments. Empty lines ignored.
#
# Hardcoded checks (no config needed):
# - Stale conflict markers: `^<<<<<<<`, `^=======`, `^>>>>>>>`.
#
# Auto-exclusions:
# - Past CHANGELOG entries (markdown headings `## [vN.M.K] - YYYY-MM-DD` or
#   `## [Unreleased] - YYYY-MM-DD`).
# - .git/ contents.
#
# Exit codes:
#   0 → clean (or soft-pass with warning)
#   1 → leak found
#   2 → script crash / dependency missing (fail-closed)
#
# Usage:
#   bin/check-leaks.sh
#
# Override (CI-side): the GitHub workflow honours a `[leak-allow: <reason>]`
# string in the PR body — workflow soft-passes + posts a PR comment. This
# script is unaware of the override; the workflow handles it.

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PATTERNS_FILE="$REPO_ROOT/.anvil/check-leaks.patterns.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# Fail-closed wrapper: any uncaught error inside the body trips this trap and
# the script exits with status 2 so the CI workflow surfaces the crash rather
# than silently soft-passing.
on_err() {
  local rc=$?
  printf "${RED}✗${RESET} check-leaks.sh crashed (exit %d) at line %d\n" "$rc" "${BASH_LINENO[0]}" >&2
  exit 2
}
trap on_err ERR
set -e

# Verify required tools — fail-closed if missing.
for tool in grep awk sort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf "${RED}✗${RESET} required tool missing: %s\n" "$tool" >&2
    exit 2
  fi
done

# ── List of files to scan (tracked + git-aware) ─────────────────────────
# Use `git ls-files` so untracked, ignored, and .git/ contents are excluded.
# Fall back to `find` when not in a git repo (smoke tests don't always have
# one; the test seeds a repo + commits, but defensive fallback is cheap).
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files
  else
    find . -type f -not -path './.git/*' | sed 's|^\./||'
  fi
}

# ── glob → regex (POSIX-compatible) ─────────────────────────────────────
# Translate a shell-style glob to a grep -E regex. Recognises:
#   `**/`  any prefix (zero or more directories, including empty)
#   `**`   any depth of content (zero or more chars)
#   `*`    any sequence within one path segment (no slash)
# Used for both path-globs and exclusion-globs.
#
# Note: the `**/` form is critical — `**/*` must match both `foo.md` AND
# `dir/foo.md`. Treating `**/` as `(.*/|)` (any-depth-prefix-or-empty)
# handles both.
glob_to_regex() {
  local glob="$1"
  # Escape regex metacharacters that don't have glob meaning.
  glob="${glob//./\\.}"
  glob="${glob//+/\\+}"
  glob="${glob//(/\\(}"
  glob="${glob//)/\\)}"
  glob="${glob//\[/\\[}"
  glob="${glob//]/\\]}"
  # `**/` → `(.*/)?` — optional any-depth prefix (handles `**/*.md` matching
  # both `foo.md` and `dir/foo.md`). Placeholder first so later rewrites
  # don't double-process. Use `__DSSLASH__` for the `**/` form.
  glob="${glob//\*\*\//__DSSLASH__}"
  glob="${glob//\*\*/__DOUBLESTAR__}"
  glob="${glob//\*/[^/]*}"
  glob="${glob//__DOUBLESTAR__/.*}"
  glob="${glob//__DSSLASH__/(.*\/)?}"
  printf '^%s$' "$glob"
}

# ── path-glob match: any-of the semicolon-separated globs ───────────────
path_matches_any_glob() {
  local path="$1"
  local globs="$2"
  local IFS=';'
  # Disable pathname expansion before splitting — otherwise `**/*` is
  # globbed against the cwd at array-assignment time.
  local glob_was_off=1
  case $- in *f*) glob_was_off=1;; *) glob_was_off=0; set -f;; esac
  # shellcheck disable=SC2206 — intentional word splitting on the IFS-set value.
  local glist=($globs)
  [ "$glob_was_off" -eq 0 ] && set +f
  local g rx
  for g in "${glist[@]}"; do
    [ -z "$g" ] && continue
    rx=$(glob_to_regex "$g")
    if printf '%s\n' "$path" | grep -qE "$rx"; then
      return 0
    fi
  done
  return 1
}

# ── CHANGELOG past-entry auto-exclusion ─────────────────────────────────
# We exclude lines INSIDE a past CHANGELOG release block. Anything between
# `## [vN.M.K] - YYYY-MM-DD` (or `## [Unreleased] - YYYY-MM-DD`) headings and
# the next `## [` or EOF is treated as historical, so project codenames that
# legitimately appear in old release notes don't fail the check.
#
# The grep below over CHANGELOG.md gets a "past-entry line range" map; the
# scan loop later uses it to skip those line numbers in CHANGELOG.md only.
build_changelog_exclusion_lines() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    /^## \[v?[0-9]+\.[0-9]+\.[0-9]+[^]]*\] - [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
      in_past = 1
      print NR
      next
    }
    /^## \[/ {
      if (in_past) {
        in_past = 0
      }
      next
    }
    in_past {
      print NR
    }
  ' "$file"
}

# ── Hardcoded conflict-marker scan ──────────────────────────────────────
# Runs against EVERY tracked file (no per-project config required).
scan_conflict_markers() {
  local found=0
  local file line content
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ -f "$file" ] || continue
    # Skip self (this file documents conflict-marker patterns).
    case "$file" in
      bin/check-leaks.sh) continue;;
    esac
    # grep -n returns "LINENO:CONTENT" for matches.
    while IFS=: read -r line content; do
      [ -z "$line" ] && continue
      printf "${RED}✗${RESET} conflict marker in %s:%s — %s\n" \
        "$file" "$line" "${content:0:60}" >&2
      found=1
    done < <(grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$file" 2>/dev/null || true)
  done < <(list_files)
  return $found
}

# ── Per-project pattern scan ────────────────────────────────────────────
# Each pattern line: <substring-or-regex> :: <path-glob> :: <exclusion-glob>
scan_project_patterns() {
  local found=0
  if [ ! -f "$PATTERNS_FILE" ]; then
    printf "${YELLOW}~${RESET} %s missing — soft-pass with warning (project-specific patterns not scanned)\n" \
      "$PATTERNS_FILE" >&2
    return 0
  fi

  # Build CHANGELOG exclusion once.
  local cl_excl_file=""
  if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
    cl_excl_file=$(mktemp)
    build_changelog_exclusion_lines "$REPO_ROOT/CHANGELOG.md" > "$cl_excl_file"
  fi

  local pattern path_glob exclusion_glob line_no
  while IFS= read -r raw_line; do
    # Strip CR (Windows line endings) + trim.
    raw_line="${raw_line%$'\r'}"
    raw_line="${raw_line#"${raw_line%%[![:space:]]*}"}"
    raw_line="${raw_line%"${raw_line##*[![:space:]]}"}"
    [ -z "$raw_line" ] && continue
    case "$raw_line" in '#'*) continue;; esac

    # Split on the literal `::` delimiter (NOT `:` — bash `IFS='::'` would do
    # that). awk -F'::' handles it correctly.
    pattern=$(printf '%s\n' "$raw_line" | awk -F'::' '{print $1}' | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')
    path_glob=$(printf '%s\n' "$raw_line" | awk -F'::' '{print $2}' | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')
    exclusion_glob=$(printf '%s\n' "$raw_line" | awk -F'::' '{print $3}' | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')

    # Default path-glob = match everything if unspecified.
    [ -z "$path_glob" ] && path_glob='**/*'

    # Iterate files, match path-glob, run pattern grep.
    local file
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      [ -f "$file" ] || continue
      # Skip self.
      case "$file" in
        bin/check-leaks.sh|.anvil/check-leaks.patterns*.txt) continue;;
      esac
      path_matches_any_glob "$file" "$path_glob" || continue
      if [ -n "$exclusion_glob" ]; then
        path_matches_any_glob "$file" "$exclusion_glob" && continue
      fi
      # Grep with extended regex.
      while IFS=: read -r line_no match_content; do
        [ -z "$line_no" ] && continue
        # CHANGELOG past-entry suppression.
        if [ "$file" = "CHANGELOG.md" ] && [ -n "$cl_excl_file" ]; then
          if grep -qxF "$line_no" "$cl_excl_file"; then
            continue
          fi
        fi
        printf "${RED}✗${RESET} forbidden pattern '%s' in %s:%s — %s\n" \
          "$pattern" "$file" "$line_no" "${match_content:0:80}" >&2
        found=1
      done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
    done < <(list_files)
  done < "$PATTERNS_FILE"

  [ -n "$cl_excl_file" ] && rm -f "$cl_excl_file"
  return $found
}

# ── Main ────────────────────────────────────────────────────────────────
echo
printf "${GREEN}check-leaks.sh${RESET}\n"
echo "Scanning for forbidden patterns + conflict markers..."
echo

# Disable -e + ERR trap around scan calls so we can capture their return
# codes (1 = leak found is informational, not a crash). The ERR trap still
# fires under `set +e` because bash invokes it before suppression.
trap - ERR
set +e
scan_conflict_markers
cm_rc=$?
scan_project_patterns
pp_rc=$?
set -e
trap on_err ERR

if [ "$cm_rc" -ne 0 ]; then
  echo
  printf "${RED}OVERALL: ✗ CONFLICT MARKERS FOUND${RESET} — these cannot be overridden\n" >&2
  exit 3
fi
if [ "$pp_rc" -ne 0 ]; then
  echo
  printf "${RED}OVERALL: ✗ PATTERN LEAKS FOUND${RESET} — fix above (or override via PR body)\n" >&2
  exit 1
fi

echo
printf "${GREEN}OVERALL: ✓ CLEAN${RESET}\n"
exit 0
