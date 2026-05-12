#!/usr/bin/env bash
# anvil/analyze-plan — verify the file-path claims in a plan against the
# current working tree.
#
# v1 SCOPE: file-path verification ONLY.
# Identifier extraction + numeric-fact verification are deferred to v2
# (see `docs/analyze-plan.md`).
#
# Usage:
#   extract-paths.sh <plan-path>
#
# <plan-path> is either:
#   - a tasks.md file (flat plan layout), OR
#   - a folder containing tasks.md + proposal.md + design.md + specs/
#
# Output (stdout): one verdict per matched path, plus a summary:
#   VERIFIED          <path>  (exists; cited at <plan-file>:<line>)
#   EXPECTED-BY-SLICE <path>  (forward-looking; in slice <id> files: list)
#   CONTRADICTED      <path>  (file does not exist; cited at <plan-file>:<line>)
#   UNVERIFIABLE      <path>  (inside code fence; illustrative; cited at <plan-file>:<line>)
#
# Exit codes:
#   0 — no CONTRADICTED verdicts (everything VERIFIED / EXPECTED-BY-SLICE / UNVERIFIABLE).
#   1 — at least one CONTRADICTED verdict found.
#   2 — usage error / plan path invalid / unreadable file.

set -u

# ---------------------------------------------------------------------------
# Resolve ANVIL_ROOT (same chain as other anvil scripts).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${ANVIL_ROOT:-}" ]; then
  _av_cfg="$SCRIPT_DIR/../../../anvil-config.sh"
  if [ -f "$_av_cfg" ]; then
    # shellcheck source=/dev/null
    . "$_av_cfg"
  fi
  unset _av_cfg
fi
if [ -z "${ANVIL_ROOT:-}" ] && [ -f "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh" ]; then
  # shellcheck source=/dev/null
  . "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh"
fi
if [ -z "${ANVIL_ROOT:-}" ]; then
  ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

# ---------------------------------------------------------------------------
# Arg parsing.
# ---------------------------------------------------------------------------
PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ]; then
  av_fail "/analyze-plan: usage: extract-paths.sh <plan-path>"
  exit 2
fi
if [ ! -e "$PLAN_PATH" ]; then
  av_fail "/analyze-plan: $PLAN_PATH is not a plan (expected a tasks.md or a folder containing one)"
  exit 2
fi

# Resolve plan files: flat (tasks.md) vs folder (proposal.md + design.md + tasks.md + specs/).
PLAN_FILES=()
TASKS_MD=""
PLAN_ROOT=""
if [ -f "$PLAN_PATH" ]; then
  case "$(basename "$PLAN_PATH")" in
    tasks.md)
      TASKS_MD="$PLAN_PATH"
      PLAN_ROOT="$(dirname "$PLAN_PATH")"
      PLAN_FILES+=("$PLAN_PATH")
      ;;
    *)
      # Flat plan in a single .md file — accept it as the tasks file.
      TASKS_MD="$PLAN_PATH"
      PLAN_ROOT="$(dirname "$PLAN_PATH")"
      PLAN_FILES+=("$PLAN_PATH")
      ;;
  esac
elif [ -d "$PLAN_PATH" ]; then
  if [ -f "$PLAN_PATH/tasks.md" ]; then
    TASKS_MD="$PLAN_PATH/tasks.md"
  else
    av_fail "/analyze-plan: $PLAN_PATH is not a plan (expected a tasks.md or a folder containing one)"
    exit 2
  fi
  PLAN_ROOT="$PLAN_PATH"
  # Read every .md under the plan folder (proposal.md, design.md, tasks.md, specs/*.md).
  while IFS= read -r f; do
    PLAN_FILES+=("$f")
  done < <(find "$PLAN_PATH" -type f -name '*.md' 2>/dev/null | sort)
else
  av_fail "/analyze-plan: $PLAN_PATH is not a plan (expected a tasks.md or a folder containing one)"
  exit 2
fi

# Sanity check: at least one readable file.
for f in "${PLAN_FILES[@]}"; do
  if [ ! -r "$f" ]; then
    av_fail "/analyze-plan: cannot read $f: permission denied or not a regular file"
    exit 2
  fi
done

# Pick a working tree to verify against. Prefer the current git repo root if we
# happen to be inside one; otherwise the plan's parent directory's nearest git
# root; otherwise the current PWD. The check is `test -e $WT/$path`.
WORKING_TREE="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$WORKING_TREE" ]; then
  WORKING_TREE="$(git -C "$PLAN_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$WORKING_TREE" ]; then
  WORKING_TREE="$(pwd)"
fi

# ---------------------------------------------------------------------------
# Build FORWARD_PATHS: union of every `files:` entry across all slices in the
# plan's tasks.md YAML manifest. Simple line-walker (no yq dependency).
#
# Grammar we accept (matches templates/plan-folder-template/tasks.md):
#   files:
#     - shared/lib.sh
#     - skills/spec/SKILL.md
# ---------------------------------------------------------------------------
FORWARD_PATHS_FILE="$(mktemp -t anvil-analyze-paths.XXXXXX)"
trap 'rm -f "$FORWARD_PATHS_FILE" "${FORWARD_PATHS_FILE}.matches" "${FORWARD_PATHS_FILE}.report"' EXIT

awk '
  /^[[:space:]]*files:[[:space:]]*$/ { in_files=1; next }
  in_files {
    if (match($0, /^[[:space:]]*-[[:space:]]*/)) {
      # Strip the leading "- " and any inline trailing comment / whitespace.
      line = substr($0, RSTART + RLENGTH)
      sub(/[[:space:]]*#.*$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      # Trim surrounding quotes/backticks.
      gsub(/^["\x27`]+|["\x27`]+$/, "", line)
      if (line != "") print line
      next
    }
    # End of files: block — first non-list-item line.
    if ($0 !~ /^[[:space:]]*$/) in_files=0
  }
' "$TASKS_MD" | sort -u > "$FORWARD_PATHS_FILE"

# Build a slice-id lookup for each forward path (best-effort).
slice_for_path() {
  local target="$1"
  awk -v target="$target" '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "")
      gsub(/[[:space:]"]/, "")
      cur_id=$0
      in_files=0
      next
    }
    /^[[:space:]]*files:[[:space:]]*$/ { in_files=1; next }
    in_files {
      if (match($0, /^[[:space:]]*-[[:space:]]*/)) {
        line = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]*#.*$/, "", line)
        sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
        gsub(/^["\x27`]+|["\x27`]+$/, "", line)
        if (line == target) { print cur_id; exit }
        next
      }
      if ($0 !~ /^[[:space:]]*$/) in_files=0
    }
  ' "$TASKS_MD"
}

# ---------------------------------------------------------------------------
# Path-claim extraction.
#
# Conservative regex (sed/grep ERE):
#   - Must contain at least one "/" — a token without a slash is not a path.
#   - Must end in one of: .ts .js .sh .md .json .yml .yaml .bash .py .txt .bats
#   - Must NOT contain `<` `>` `{` `}` placeholders, nor a YYYY-MM-DD date.
#
# We also track "is this match inside a fenced code block?" via a per-file
# line-aware pass so we can flag those as UNVERIFIABLE.
#
# Output of the extract pass (per match):
#   <plan-file>\t<line>\t<in_fence:0|1>\t<path>
# ---------------------------------------------------------------------------

# Conservative path regex. Passed via -v to awk (string-to-regex conversion);
# `\\.` here = literal `\.` in awk = literal `.` (NOT any-char), required to
# avoid false positives like `.transcripts` matching `.tra` + any + `ts`.
# We strip leading `./` and surrounding `` ` `` / `"` / `'` in the post-filter.
PATH_RE='([a-zA-Z0-9_./-]+/)+[a-zA-Z0-9_.-]+\\.(ts|js|sh|md|json|yml|yaml|bash|py|txt|bats)'

extract_one_file() {
  local file="$1"
  awk -v file="$file" -v re="$PATH_RE" '
    BEGIN { in_fence = 0 }
    {
      # Track fenced-code-block state. ``` toggles. Tilde fences not handled
      # (rare in our plans).
      if ($0 ~ /^[[:space:]]*```/) { in_fence = !in_fence; next }
      line = $0
      # Strip out URL-form occurrences ("http(s)://...") before matching so
      # we do not emit them as paths.
      gsub(/https?:\/\/[^[:space:]]+/, " ", line)
      # Iterate matches on the line.
      tmp = line
      while (match(tmp, re)) {
        m = substr(tmp, RSTART, RLENGTH)
        # Reject placeholder tokens before emitting.
        if (m ~ /[<>{}]/)                       { tmp = substr(tmp, RSTART + RLENGTH); continue }
        if (m ~ /[0-9]{4}-[0-9]{2}-[0-9]{2}/)   { tmp = substr(tmp, RSTART + RLENGTH); continue }
        # Strip leading ./
        sub(/^\.\//, "", m)
        # Skip if the path collapsed to empty (defensive).
        if (m == "") { tmp = substr(tmp, RSTART + RLENGTH); continue }
        printf("%s\t%d\t%d\t%s\n", file, NR, in_fence, m)
        tmp = substr(tmp, RSTART + RLENGTH)
      }
    }
  ' "$file"
}

> "${FORWARD_PATHS_FILE}.matches"
for f in "${PLAN_FILES[@]}"; do
  extract_one_file "$f" >> "${FORWARD_PATHS_FILE}.matches"
done

# ---------------------------------------------------------------------------
# Verdict pass.
# ---------------------------------------------------------------------------
verified=0
expected=0
contradicted=0
unverifiable=0
contradicted_lines_file="${FORWARD_PATHS_FILE}.contradicted"
verified_lines_file="${FORWARD_PATHS_FILE}.verified"
expected_lines_file="${FORWARD_PATHS_FILE}.expected"
unverifiable_lines_file="${FORWARD_PATHS_FILE}.unverifiable"
: > "$contradicted_lines_file"
: > "$verified_lines_file"
: > "$expected_lines_file"
: > "$unverifiable_lines_file"

# Deduplicate (file:line:path) so the same line emitting two regex matches
# doesn't double-count.
sort -u "${FORWARD_PATHS_FILE}.matches" -o "${FORWARD_PATHS_FILE}.matches"

while IFS=$'\t' read -r plan_file plan_line in_fence path; do
  [ -z "$path" ] && continue
  cite="$(realpath --relative-to="$(pwd)" "$plan_file" 2>/dev/null || echo "$plan_file"):$plan_line"
  if [ "$in_fence" = "1" ]; then
    unverifiable=$((unverifiable + 1))
    printf 'UNVERIFIABLE      %s  (inside code fence; illustrative; cited at %s)\n' \
      "$path" "$cite" >> "$unverifiable_lines_file"
    continue
  fi
  # Existence check: prefer relative to WORKING_TREE; fall back to absolute or
  # plan-root-relative (some plans cite a path with a working-tree-rooted
  # prefix like `docs/...` which only resolves under WORKING_TREE).
  if [ -e "$WORKING_TREE/$path" ] || [ -e "$path" ]; then
    verified=$((verified + 1))
    printf 'VERIFIED          %s  (exists; cited at %s)\n' "$path" "$cite" >> "$verified_lines_file"
    continue
  fi
  # Forward-looking: is the path in the union of slice `files:` lists?
  if grep -Fxq "$path" "$FORWARD_PATHS_FILE"; then
    sid="$(slice_for_path "$path")"
    [ -z "$sid" ] && sid="?"
    expected=$((expected + 1))
    printf 'EXPECTED-BY-SLICE %s  (forward-looking; in slice %s files: list)\n' \
      "$path" "$sid" >> "$expected_lines_file"
    continue
  fi
  # Drift.
  contradicted=$((contradicted + 1))
  printf 'CONTRADICTED      %s  (file does not exist; cited at %s)\n' \
    "$path" "$cite" >> "$contradicted_lines_file"
done < "${FORWARD_PATHS_FILE}.matches"

total=$((verified + expected + contradicted + unverifiable))

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
{
  printf '/analyze-plan v1 — file-path verification\n'
  printf 'plan: %s\n' "$PLAN_PATH"
  printf 'working-tree: %s\n' "$WORKING_TREE"
  printf '\n'
  # "No signal" = nothing extractable at all OR every match was inside a code
  # fence (e.g. tasks.md's slice manifest yaml block emits UNVERIFIABLE-only).
  verifiable=$((verified + expected + contradicted))
  if [ "$verifiable" -eq 0 ]; then
    printf 'warning: extracted 0 verifiable claims — analyze-plan provides no signal for this plan\n'
  fi
  if [ -s "$verified_lines_file" ];     then sort -u "$verified_lines_file"; fi
  if [ -s "$expected_lines_file" ];     then sort -u "$expected_lines_file"; fi
  if [ -s "$unverifiable_lines_file" ]; then sort -u "$unverifiable_lines_file"; fi
  if [ -s "$contradicted_lines_file" ]; then sort -u "$contradicted_lines_file"; fi
  printf '\n'
  printf 'summary: VERIFIED=%d  EXPECTED-BY-SLICE=%d  UNVERIFIABLE=%d  CONTRADICTED=%d\n' \
    "$verified" "$expected" "$unverifiable" "$contradicted"
  if [ "$contradicted" -gt 0 ]; then
    printf '\n'
    printf 'CONTRADICTED claims (drift — re-run /refine-plan or /grind --skip-analyze):\n'
    sort -u "$contradicted_lines_file" | sed 's/^/  /'
  fi
}

if [ "$contradicted" -gt 0 ]; then
  exit 1
fi
exit 0
