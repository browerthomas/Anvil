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
# Portable realpath shim. macOS BSD realpath and GNU realpath differ on
# flag support; fall back to cd + pwd -P (POSIX) when neither works for
# the given path. Returns empty string + non-zero exit on resolution
# failure so the caller can treat that as "refuse".
_av_realpath() {
  local p="$1"
  if [ -z "$p" ]; then
    return 1
  fi
  if command -v realpath >/dev/null 2>&1; then
    local r
    if r="$(realpath "$p" 2>/dev/null)" && [ -n "$r" ]; then
      printf '%s\n' "$r"
      return 0
    fi
  fi
  # POSIX fallback: cd to the parent of the resolved final path and
  # combine with the basename. Works for symlinks whose parent exists.
  local dir base
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  ( cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$base" )
}

av_resolve_template() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "av_resolve_template: missing template name argument" >&2
    return 2
  fi
  # Refuse path traversal BEFORE any filesystem access.
  # - Leading `/` would escape the project/core roots.
  # - Any segment equal to `..` (NOT any `..` substring — `foo..bar.md`
  #   is a legitimate filename) could climb out of the resolved root.
  case "$name" in
    /*)
      echo "av_resolve_template: refusing path traversal in $name (absolute path)" >&2
      return 2
      ;;
  esac
  # Split on `/` and check each component. Localised IFS so we don't
  # leak the change out of the function.
  local _av_old_ifs="$IFS"
  IFS=/
  # shellcheck disable=SC2086
  set -- $name
  IFS="$_av_old_ifs"
  local segment
  for segment in "$@"; do
    if [ "$segment" = ".." ]; then
      echo "av_resolve_template: refusing path traversal in $name (.. segment)" >&2
      return 2
    fi
  done

  local project_layer="${PWD}/.anvil/templates/overrides"
  local core_layer
  core_layer="$(av_anvil_root)/templates"
  local project_path="${project_layer}/${name}"
  local core_path="${core_layer}/${name}"

  local candidate layer_dir
  if [ -e "$project_path" ]; then
    candidate="$project_path"
    layer_dir="$project_layer"
  elif [ -e "$core_path" ]; then
    candidate="$core_path"
    layer_dir="$core_layer"
  else
    echo "av_resolve_template: $name not found (project: $project_path, core: $core_path)" >&2
    return 1
  fi

  # Symlink guard: an operator (or an attacker who can write the override
  # tree) could drop a symlink at the override path pointing at host
  # content (e.g. /etc/passwd). After the layer-hit check, resolve both
  # the candidate and the expected layer dir to their canonical paths
  # and refuse if the candidate escapes the layer.
  local resolved canonical_layer
  resolved="$(_av_realpath "$candidate")"
  canonical_layer="$(cd "$layer_dir" 2>/dev/null && pwd -P)"
  if [ -z "$resolved" ] || [ -z "$canonical_layer" ]; then
    echo "av_resolve_template: refusing override — could not canonicalise '$candidate' or layer '$layer_dir'" >&2
    return 1
  fi
  case "$resolved" in
    "$canonical_layer"/*) ;;  # OK — resolved target is under expected layer
    *)
      echo "av_resolve_template: refusing override symlink escape (resolved '$resolved' outside '$canonical_layer')" >&2
      return 1
      ;;
  esac

  printf '%s\n' "$candidate"
  return 0
}

# --- Constitution loader -------------------------------------------------
# Reads `${PWD}/.anvil/constitution.md` and prints its contents on stdout.
#
# Returns the empty string (exit 0) when:
#   - the file does not exist
#   - the file exists but is empty or whitespace-only
#   - the file contains non-UTF-8 bytes (warning to stderr; graceful skip)
#
# Used by /dispatch-slice to prepend a `## Project constitution` section
# to every assembled agent prompt. See specs/s1-constitution.md.
av_load_constitution() {
  local path="${PWD}/.anvil/constitution.md"
  if [ ! -f "$path" ]; then
    return 0
  fi
  # Empty file → empty return (no warning; absence is normal).
  if [ ! -s "$path" ]; then
    return 0
  fi
  # UTF-8 validation. `iconv -f UTF-8 -t UTF-8` fails on invalid sequences
  # on both BSD (macOS) and GNU systems; fall back to LC_ALL=C grep -P if
  # iconv is missing for some reason.
  if command -v iconv >/dev/null 2>&1; then
    if ! iconv -f UTF-8 -t UTF-8 "$path" >/dev/null 2>&1; then
      printf 'warning: .anvil/constitution.md is not valid UTF-8; skipping prepend\n' >&2
      return 0
    fi
  fi
  # Whitespace-only → empty return. Check by stripping whitespace; if the
  # result is empty, treat as absent.
  local stripped
  stripped="$(tr -d '[:space:]' < "$path")"
  if [ -z "$stripped" ]; then
    return 0
  fi
  cat "$path"
  return 0
}

# --- Agent-completion usage parser ---------------------------------------
# Parses a sub-agent completion-notification body for the `<usage>` block
# and emits the three counters on stdout, one per line, in the order:
#
#   total_tokens
#   tool_uses
#   duration_ms
#
# Returns 0 if a usage block was found and at least one counter parsed,
# 1 if no usage block / no counters could be extracted. The dispatcher
# soft-fails on a non-zero return — missing counters must never block a
# slice (older runtimes + manual dispatches don't carry the block).
#
# Accepted shapes (whichever the runtime emits — all parsed best-effort):
#   <usage>
#     total_tokens: 278901
#     tool_uses:    171
#     duration_ms:  1478669
#   </usage>
#
#   <usage total_tokens="278901" tool_uses="171" duration_ms="1478669" />
#
#   <usage>{"total_tokens": 278901, "tool_uses": 171, "duration_ms": 1478669}</usage>
#
# Unknown fields are ignored; missing fields render as the empty string
# (the writer turns empty → JSON null). All counter values must be
# non-negative integers; non-numeric tokens are dropped so a stray label
# can't smuggle a string into the event log.
av_parse_agent_usage() {
  local input="$1"
  if [ -z "$input" ] || [ ! -f "$input" ]; then
    return 1
  fi
  # Extract the first <usage>...</usage> body. Tolerant of:
  #   - block form (open + body + close on separate lines)
  #   - inline form (single line)
  #   - self-closing (<usage ... />)
  local body
  body=$(awk '
    BEGIN { capture=0; out="" }
    {
      line=$0
      if (capture == 0) {
        if (match(line, /<usage[^>]*\/>/)) {
          # Self-closing — capture the attribute slice between < and />.
          s = substr(line, RSTART, RLENGTH)
          sub(/^<usage[[:space:]]*/, "", s)
          sub(/[[:space:]]*\/>$/, "", s)
          out = out " " s
          exit
        }
        if (match(line, /<usage[^>]*>/)) {
          # Opening tag — keep anything after the `>` on this line.
          rest = substr(line, RSTART + RLENGTH)
          # Inline close on same line?
          ci = index(rest, "</usage>")
          if (ci > 0) {
            out = out " " substr(rest, 1, ci - 1)
            exit
          } else {
            out = out " " rest
            capture = 1
            next
          }
        }
      } else {
        ci = index(line, "</usage>")
        if (ci > 0) {
          out = out " " substr(line, 1, ci - 1)
          exit
        }
        out = out " " line
      }
    }
    END { print out }
  ' "$input")
  if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    return 1
  fi
  # Extract the three counters. Strategy:
  #   1. Strip JSON braces / quotes / commas — turns `{"total_tokens": 200}`
  #      into ` total_tokens: 200 `, same shape as the block form.
  #   2. Walk `key: value` and `key="value"` pairs via grep -oE.
  local norm
  norm=$(printf '%s' "$body" \
    | tr -d '{}",' \
    | sed -E 's/=/: /g')
  local total tool dur
  total=$(printf '%s' "$norm" | grep -oE 'total_tokens[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+$' || true)
  tool=$(printf '%s' "$norm"  | grep -oE 'tool_uses[[:space:]]*:[[:space:]]*[0-9]+'    | head -1 | grep -oE '[0-9]+$' || true)
  dur=$(printf '%s' "$norm"   | grep -oE 'duration_ms[[:space:]]*:[[:space:]]*[0-9]+'  | head -1 | grep -oE '[0-9]+$' || true)
  # Fail if none of the three resolved — that's "block was there but unparseable".
  if [ -z "$total" ] && [ -z "$tool" ] && [ -z "$dur" ]; then
    return 1
  fi
  printf '%s\n%s\n%s\n' "$total" "$tool" "$dur"
  return 0
}

# --- Per-slice checklist parser (S3) ---
# Parses the `checklist:` field for a single slice in a plan's YAML manifest.
# Emits one line per checklist item in a structured pipe-delimited format:
#   shell|<run>|<expect>|<timeout>
#   grep|<pattern>|<in>|<expect>|<count>
# Empty fields are emitted as the empty string. The `count` field is empty
# when unset for grep items. `timeout` defaults to 300 (seconds) for shell
# items when not specified.
#
# Usage: av_parse_slice_checklist <plan-path> <slice-id>
#
# Behaviour:
#   - Missing plan file              → exit 2, stderr error
#   - Missing argument(s)            → exit 2, stderr error
#   - Slice id not found             → exit 1, stderr error
#   - No `checklist:` key on slice   → exit 0, silent (legacy)
#   - Empty `checklist: []` list     → exit 0, silent (legacy)
#   - Unknown `kind:` value          → exit 1, stderr error
#   - Invalid `expect:` for grep     → exit 1, stderr error
#
# The plan-path argument is the file containing the YAML slice manifest in a
# ```yaml ... ``` fenced block (either a flat plan file or `tasks.md` from a
# folder-layout plan). Re-uses the existing yq-or-python3-with-pyyaml pattern
# already in use by skills/spec/scripts/validate.sh and skills/grind/scripts/
# state.sh — same dependency surface, no new external tools.
av_parse_slice_checklist() {
  local plan_path="$1"
  local slice_id="$2"
  if [ -z "$plan_path" ] || [ -z "$slice_id" ]; then
    echo "av_parse_slice_checklist: usage: av_parse_slice_checklist <plan-path> <slice-id>" >&2
    return 2
  fi
  if [ ! -f "$plan_path" ]; then
    echo "av_parse_slice_checklist: plan file not found: $plan_path" >&2
    return 2
  fi
  # jq is a hard dependency — explicit precheck so a missing jq doesn't get
  # surfaced as a misleading "could not parse slices YAML" message later.
  if ! command -v jq >/dev/null 2>&1; then
    echo "av_parse_slice_checklist: need jq (hard dependency)" >&2
    return 2
  fi

  # 1. Extract the YAML slice manifest from the first ```yaml ... ``` fence.
  local yaml
  yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){exit}; next} flag {print}' "$plan_path")
  if [ -z "$yaml" ] || ! echo "$yaml" | grep -q "slices:"; then
    echo "av_parse_slice_checklist: no slices YAML manifest found in $plan_path" >&2
    return 1
  fi

  # 2. Convert YAML to JSON via yq (preferred) or python3+pyyaml (fallback).
  local slices_json=""
  if command -v yq >/dev/null 2>&1; then
    slices_json=$(printf '%s\n' "$yaml" | yq -o=json 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    slices_json=$(printf '%s\n' "$yaml" | python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin)))' 2>/dev/null)
  else
    echo "av_parse_slice_checklist: need yq or python3+pyyaml to parse YAML" >&2
    return 2
  fi
  if [ -z "$slices_json" ] || ! echo "$slices_json" | jq -e '.slices' >/dev/null 2>&1; then
    echo "av_parse_slice_checklist: could not parse slices YAML (check syntax)" >&2
    return 1
  fi

  # 3. Find the requested slice by id.
  local slice_json
  slice_json=$(echo "$slices_json" | jq --arg id "$slice_id" '.slices[] | select(.id == $id)')
  if [ -z "$slice_json" ]; then
    echo "av_parse_slice_checklist: slice id '$slice_id' not found in $plan_path" >&2
    return 1
  fi

  # 4. Missing or empty checklist → silent legacy behaviour.
  local has_checklist
  has_checklist=$(echo "$slice_json" | jq 'has("checklist") and (.checklist // [] | length > 0)')
  if [ "$has_checklist" != "true" ]; then
    return 0
  fi

  # 5. Walk each checklist item.
  local items_count idx item kind run expect timeout pattern in_glob count
  items_count=$(echo "$slice_json" | jq '.checklist | length')
  idx=0
  while [ "$idx" -lt "$items_count" ]; do
    item=$(echo "$slice_json" | jq -c ".checklist[$idx]")
    kind=$(echo "$item" | jq -r '.kind // ""')
    case "$kind" in
      shell)
        run=$(echo "$item" | jq -r '.run // ""')
        expect=$(echo "$item" | jq -r '.expect // "pass"')
        timeout=$(echo "$item" | jq -r '.timeout // 300')
        printf 'shell|%s|%s|%s\n' "$run" "$expect" "$timeout"
        ;;
      grep)
        pattern=$(echo "$item" | jq -r '.pattern // ""')
        in_glob=$(echo "$item" | jq -r '.in // ""')
        expect=$(echo "$item" | jq -r '.expect // ""')
        if [ "$expect" != "present" ] && [ "$expect" != "absent" ]; then
          echo "av_parse_slice_checklist: invalid expect '$expect' for grep (expected: present | absent) in slice '$slice_id'" >&2
          return 1
        fi
        count=$(echo "$item" | jq -r '.count // ""')
        printf 'grep|%s|%s|%s|%s\n' "$pattern" "$in_glob" "$expect" "$count"
        ;;
      "")
        echo "av_parse_slice_checklist: checklist item $idx in slice '$slice_id' is missing 'kind'" >&2
        return 1
        ;;
      *)
        echo "av_parse_slice_checklist: unknown kind '$kind' (expected: shell | grep) in slice '$slice_id'" >&2
        return 1
        ;;
    esac
    idx=$((idx + 1))
  done
  return 0
}

