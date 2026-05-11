#!/usr/bin/env bash
# anvil/followup-rollup — group open follow-up issues for a plan by severity + area.
#
# Reads:
#   <plan-path>          — folder (must contain tasks.md) or flat .md file
#   gh issue list ...    — open issues filtered to titles containing the plan slug
#                          (or a --fixture JSON file for tests / offline runs)
#
# Writes: nothing. Stdout only — emits a markdown rollup table.
#
# Output shape:
#   # Follow-up rollup — <plan-slug>
#   **Open follow-ups:** N issues across S slices.
#   ## Severity summary  (table: P0/P1/P2/P3 × count)
#   ## Area breakdown     (sections: correctness / test-coverage / architecture / operability)
#   ## Per-slice tally    (table: slice × severity-counts)
#   ## Consumer suggestions
#
# Usage:
#   build-rollup.sh <plan-path> [--fixture <path>] [--repo <owner/name>]
#
# Environment:
#   GH_OFFLINE=1  — skip gh invocation; emit the empty-fixture placeholder + exit 0.

set -u

# Resolve ANVIL_ROOT (mirrors skills/grind/scripts/state.sh + anvil-status).
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

usage() {
  echo "usage: build-rollup.sh <plan-path> [--fixture <path>] [--repo <owner/name>]" >&2
  echo "  GH_OFFLINE=1 to skip gh invocation" >&2
}

PLAN_PATH=""
FIXTURE=""
REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fixture) FIXTURE="${2:-}"; shift 2;;
    --repo)    REPO="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    -*)        av_fail "unknown arg: $1"; usage; exit 1;;
    *)
      if [ -z "$PLAN_PATH" ]; then
        PLAN_PATH="$1"
      else
        av_fail "unexpected positional arg: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$PLAN_PATH" ]; then
  usage
  exit 1
fi

# ── Resolve plan slug + tasks source ──────────────────────────────────
plan_slug=""
if [ -d "$PLAN_PATH" ]; then
  if [ ! -f "$PLAN_PATH/tasks.md" ]; then
    av_fail "folder plan must contain tasks.md (got: $PLAN_PATH)"
    exit 1
  fi
  # Folder name (strip trailing slash, take basename).
  plan_slug=$(basename "${PLAN_PATH%/}")
elif [ -f "$PLAN_PATH" ]; then
  # Filename stem.
  fname=$(basename "$PLAN_PATH")
  plan_slug="${fname%.md}"
else
  av_fail "plan not found (neither file nor folder): $PLAN_PATH"
  exit 1
fi

# ── Validate fixture if given ──────────────────────────────────────────
if [ -n "$FIXTURE" ]; then
  if [ ! -f "$FIXTURE" ]; then
    av_fail "fixture file not found: $FIXTURE"
    exit 1
  fi
  if ! jq empty "$FIXTURE" 2>/dev/null; then
    av_fail "fixture is not valid JSON: $FIXTURE"
    exit 1
  fi
fi

# ── Resolve repo (only needed when fetching live) ─────────────────────
if [ -z "$FIXTURE" ] && [ "${GH_OFFLINE:-0}" != "1" ]; then
  if [ -z "$REPO" ]; then
    # Derive from git remote.
    origin=$(git remote get-url origin 2>/dev/null || echo "")
    # Patterns: git@github.com:owner/repo.git  OR  https://github.com/owner/repo(.git)
    if [[ "$origin" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
  fi
fi

# ── Fetch issues ──────────────────────────────────────────────────────
# `issues_json` is the raw array of {number,title,labels,body,url}.
issues_json="[]"

emit_empty_placeholder() {
  local reason="$1"
  cat <<EOF
# Follow-up rollup — $plan_slug

**Open follow-ups:** 0 — $reason

> Note: the title-prefix contract \`[<plan-slug>-<slice> followup]\` is not
> currently enforced by \`/findings-rollup\` or \`/grind\`. If you expected
> follow-ups here, either (a) there are genuinely none, or (b) the upstream
> filing path uses a different title format. To close the gap, retrofit the
> prefix into the issue-filing call in \`skills/grind/templates/grind-loop.md\` +
> \`skills/findings-rollup/SKILL.md\`.
EOF
}

if [ -n "$FIXTURE" ]; then
  issues_json=$(cat "$FIXTURE")
elif [ "${GH_OFFLINE:-0}" = "1" ]; then
  emit_empty_placeholder "no issues fetched (GH_OFFLINE=1)"
  exit 0
else
  # Live gh fetch.
  if ! command -v gh >/dev/null 2>&1; then
    emit_empty_placeholder "no issues fetched (gh not on PATH)"
    exit 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    emit_empty_placeholder "no issues fetched (gh not authenticated)"
    exit 0
  fi
  if [ -z "$REPO" ]; then
    av_fail "could not derive repo from origin remote; pass --repo <owner/name>"
    exit 1
  fi
  # Search for the plan slug in the issue title — narrows the result set
  # before client-side regex filtering.
  issues_json=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --limit 200 \
    --search "$plan_slug in:title" \
    --json number,title,labels,body,url 2>/dev/null || echo "[]")
fi

# ── Filter to titles matching `[<plan-slug>-<slice> followup]` ────────
# jq extracts:
#   - number, title, url, body
#   - slice_id    (from the title-prefix capture group)
#   - severity    (label > title-token > body-marker > "P3" fallback)
#   - area        (label > title-keyword heuristic > "correctness" fallback)
#
# Severity priority order:
#   1. label p0/p1/p2/p3 (case-insensitive)
#   2. title token [P0]/[P1]/[P2]/[P3]
#   3. body line "**Severity:** Pn" (case-insensitive)
#   4. "P3"
#
# Area priority order:
#   1. label test-coverage / correctness / architecture / operability
#   2. title-keyword heuristic (see SKILL.md for the substring list)
#   3. "correctness"

matched=$(echo "$issues_json" | jq --arg slug "$plan_slug" '
  # Severity derivation. Precedence:
  #   1. label p0/p1/p2/p3 (case-insensitive)
  #   2. title token [P0]/[P1]/[P2]/[P3]
  #   3. body line "**Severity:** Pn" (case-insensitive)
  #   4. "P3" (fallback)
  #
  # NOTE: every // arm is FULLY parenthesised. capture() emits an empty
  # stream on no match — we wrap it in `(... // empty)` so // chaining
  # treats "no match" as "advance to next alternative".
  def derive_severity:
    (
      (
        ((.labels // []) | map(.name // "" | ascii_downcase)
                         | map(select(. == "p0" or . == "p1" or . == "p2" or . == "p3"))
                         | first)
      )
      //
      (
        ((.title // "") | (capture("\\[(?<s>P[0-3])\\]") | .s) // empty) | ascii_downcase
      )
      //
      (
        ((.body // "") | split("\n") | map(ascii_downcase)
                                      | map(select(test("^\\s*\\*\\*severity:\\*\\*\\s*p[0-3]")))
                                      | first
                                      | if . == null then empty
                                        else (capture("p(?<n>[0-3])") | "p" + .n)
                                        end)
      )
      //
      "p3"
    )
    | ascii_upcase;

  # Area derivation. Precedence:
  #   1. label test-coverage / correctness / architecture / operability
  #   2. title-keyword heuristic (case-insensitive substrings) — applied to
  #      the title body only, AFTER stripping the leading
  #      `[<plan>-<slice> followup]` prefix. Without that strip, plan slugs
  #      containing heuristic keywords (e.g. a plan literally named test-plan,
  #      OR a real one whose slug shares a substring like logs-pipeline /
  #      race-fix / refactor-X) would always match the corresponding
  #      bucket and trample every other classification.
  #   3. "correctness" (fallback)
  def derive_area:
    (
      (
        ((.labels // []) | map(.name // "" | ascii_downcase)
                         | map(select(. == "test-coverage" or . == "correctness" or . == "architecture" or . == "operability"))
                         | first)
      )
      //
      (
        (((.title // "") | sub("^\\[[^\\]]*\\]\\s*"; "")) | ascii_downcase) as $t
        | if   ($t | test("test|coverage|flaky|fixture|smoke")) then "test-coverage"
          elif ($t | test("bug|incorrect|wrong|broken|regression|race")) then "correctness"
          elif ($t | test("refactor|extract|interface|layer|coupling|boundary")) then "architecture"
          elif ($t | test("log|metric|observability|runbook|alert|dashboard")) then "operability"
          else empty end
      )
      //
      "correctness"
    );

  # The prefix regex captures the slice id. Anchored at title start; case
  # sensitive on "followup" because /findings-rollup uses that exact spelling.
  ("^\\[" + $slug + "-(?<slice>[A-Za-z0-9._-]+) followup\\]") as $pat
  | map(
      . as $i
      | (($i.title // "") | (capture($pat) | .slice) // empty) as $slice_id
      | select($slice_id != null and $slice_id != "")
      | {
          number: $i.number,
          title:  $i.title,
          url:    $i.url,
          slice:  $slice_id,
          severity: ($i | derive_severity),
          area:     ($i | derive_area)
        }
    )
')

# Sanity: jq above must always produce a JSON array. If the upstream JSON was
# malformed (gh hiccup), emit the empty placeholder rather than crashing.
if ! echo "$matched" | jq -e 'type == "array"' >/dev/null 2>&1; then
  emit_empty_placeholder "issue fetch returned malformed JSON"
  exit 0
fi

count=$(echo "$matched" | jq 'length')

if [ "$count" -eq 0 ]; then
  emit_empty_placeholder "no issues match the \`[$plan_slug-<slice> followup]\` title prefix"
  exit 0
fi

# ── Aggregate for rendering ──────────────────────────────────────────
# Slice count.
slice_count=$(echo "$matched" | jq -r '[.[] .slice] | unique | length')

# Severity counts.
p0=$(echo "$matched" | jq '[.[] | select(.severity == "P0")] | length')
p1=$(echo "$matched" | jq '[.[] | select(.severity == "P1")] | length')
p2=$(echo "$matched" | jq '[.[] | select(.severity == "P2")] | length')
p3=$(echo "$matched" | jq '[.[] | select(.severity == "P3")] | length')

# Source label for the header.
if [ -n "$FIXTURE" ]; then
  source_label="fixture \`$FIXTURE\`"
else
  source_label="\`gh issue list\` against \`$REPO\`"
fi

# ── Emit the markdown rollup ─────────────────────────────────────────
cat <<EOF
# Follow-up rollup — $plan_slug

**Open follow-ups:** $count issues across $slice_count slices.
**Source:** $source_label.

## Severity summary

| Severity | Count | Suggested consuming slice |
|---|---|---|
| P0 | $p0 | next merge gate |
| P1 | $p1 | next cleanup phase |
| P2 | $p2 | cleanup phase |
| P3 | $p3 | nice-to-have / backlog |
EOF

echo
echo "## Area breakdown"

# Order matters — the bucket-priority order from SKILL.md:
# correctness > operability > test-coverage > architecture
for area in correctness operability test-coverage architecture; do
  area_items=$(echo "$matched" | jq -c --arg a "$area" '[.[] | select(.area == $a)]')
  area_count=$(echo "$area_items" | jq 'length')
  [ "$area_count" -eq 0 ] && continue
  echo
  echo "### $area ($area_count)"
  echo "$area_items" | jq -r '.[] | "- #\(.number) — \(.title) (\(.severity), slice \(.slice))"'
done

# Per-slice tally — alphabetical for stable test output.
echo
echo "## Per-slice tally"
echo
echo "| Slice | P0 | P1 | P2 | P3 | Total |"
echo "|---|---|---|---|---|---|"

# Build per-slice rows via jq for atomicity.
echo "$matched" | jq -r '
  group_by(.slice) | sort_by(.[0].slice) | .[] |
  {
    slice: .[0].slice,
    p0: ([.[] | select(.severity == "P0")] | length),
    p1: ([.[] | select(.severity == "P1")] | length),
    p2: ([.[] | select(.severity == "P2")] | length),
    p3: ([.[] | select(.severity == "P3")] | length),
    total: length
  } |
  "| \(.slice) | \(.p0) | \(.p1) | \(.p2) | \(.p3) | \(.total) |"
'

# Consumer suggestions — drop / bundle / backlog.
echo
echo "## Consumer suggestions"

p0p1=$(echo "$matched" | jq -c '[.[] | select(.severity == "P0" or .severity == "P1")]')
p0p1_count=$(echo "$p0p1" | jq 'length')
p2_items=$(echo "$matched" | jq -c '[.[] | select(.severity == "P2")]')
p3_items=$(echo "$matched" | jq -c '[.[] | select(.severity == "P3")]')

echo
echo "- **Drop into the next cleanup slice (P0 + P1, $p0p1_count items):**"
if [ "$p0p1_count" -eq 0 ]; then
  echo "  - _none_"
else
  echo "$p0p1" | jq -r '.[] | "  - #\(.number) — \(.title)"'
fi

p2_count=$(echo "$p2_items" | jq 'length')
echo "- **Bundle into a P2 rollup issue ($p2_count items):**"
if [ "$p2_count" -eq 0 ]; then
  echo "  - _none_"
else
  echo "$p2_items" | jq -r '.[] | "  - #\(.number) — \(.title)"'
fi

p3_count=$(echo "$p3_items" | jq 'length')
echo "- **Backlog / nice-to-have (P3, $p3_count items):**"
if [ "$p3_count" -eq 0 ]; then
  echo "  - _none_"
else
  echo "$p3_items" | jq -r '.[] | "  - #\(.number) — \(.title)"'
fi
