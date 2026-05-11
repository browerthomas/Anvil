#!/usr/bin/env bash
# anvil/recap — build a session recap (v1 visual, v2 structured WHY).
#
# Modes:
#   (no --v2)    — emit the v1 instructions to stdout. The model still owns
#                  the v1 HTML build per skills/recap/SKILL.md.
#   --v2         — emit a v2 markdown recap with TLDR + 4 named sections.
#                  The script:
#                    1. Gathers inputs (event log + plan + PRs + diffs).
#                    2. Renders the prompt template at
#                       skills/recap/templates/why-recap.md.
#                    3. Hands the prompt to a model command if one is
#                       configured (--model-cmd or RECAP_MODEL_CMD env).
#                       Otherwise prints the prompt to stdout and exits 0.
#                    4. Validates the output structure (TLDR first + 4
#                       named sections).
#                    5. Runs CITATION RESOLUTION on the output.
#   --resolve <file> — given an already-generated v2 markdown, validate
#                      structure + citations. Used for testing and for
#                      operators that pipe their own model output through.
#
# Citation vocabulary (sections 3-5 only):
#   path/to/file.ext:N    — file + line, must exist + wc -l >= N
#   #PR_NUMBER            — `gh pr view N` exits 0 (offline: fixture allowlist)
#   <sha>                 — `git cat-file -e <sha>` exits 0
#
# Offline mode (`GH_OFFLINE=1`):
#   - PR citations resolved against $RECAP_PR_ALLOWLIST
#     (default: $REPO_ROOT/.anvil/recap-pr-allowlist.txt, one PR# per line).
#   - SHA citations still resolved via `git cat-file` (always local).
#   - file:N citations still resolved against the working tree.
#
# Exit codes:
#   0 — success (prompt emitted OR markdown structured + citations resolved)
#   1 — structure violation (missing section / wrong sentence count)
#   2 — citation resolution failure (one or more citations don't resolve)
#   3 — input error (bad args, missing files)
#   4 — dependency missing (jq / grep / awk)

set -u

# Resolve ANVIL_ROOT (in order):
#   1. existing env var       — operator override
#   2. anvil-config.sh next to skills/ — post-install (any prefix; copy or symlink)
#   3. env-honoured anvil-config.sh    — $ANVIL_HOME/$CLAUDE_HOME/$HOME/.claude
#   4. relative-path fallback ($SCRIPT_DIR/../../..)  — in-checkout / dev mode
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

# --- Arg parsing --------------------------------------------------------

MODE="v1"                     # v1 | v2 | resolve
PLAN_PATH=""
INPUT_PATH=""                 # for --resolve
OUTPUT_PATH=""                # optional; default stdout
HTML_PATH=""                  # optional; emit styled HTML alongside markdown
GH_REPO=""                    # optional; for citation links (owner/repo)
SINCE=""
UNTIL=""
MODEL_CMD="${RECAP_MODEL_CMD:-}"
PR_ALLOWLIST="${RECAP_PR_ALLOWLIST:-}"
REPO_ROOT_OVERRIDE=""         # for tests to point at a fixture repo
FIXTURE_PR_LIST=""            # offline mode: PRs in window (overrides gh)
FIXTURE_EVENTS=""             # offline mode: events.jsonl (overrides .anvil/)
FIXTURE_DIFF_STATS=""         # offline mode: pre-computed diff stats
FIXTURE_DECISIONS=""          # offline mode: decisions excerpt
SLUG="recap"

while [ $# -gt 0 ]; do
  case "$1" in
    --v2)                MODE="v2"; shift;;
    --resolve)           MODE="resolve"; INPUT_PATH="${2:-}"; shift 2;;
    --plan)              PLAN_PATH="$2"; shift 2;;
    --output|--out|-o)   OUTPUT_PATH="$2"; shift 2;;
    --html)              HTML_PATH="$2"; shift 2;;
    --gh-repo)           GH_REPO="$2"; shift 2;;
    --since)             SINCE="$2"; shift 2;;
    --until)             UNTIL="$2"; shift 2;;
    --model-cmd)         MODEL_CMD="$2"; shift 2;;
    --pr-allowlist)      PR_ALLOWLIST="$2"; shift 2;;
    --repo-root)         REPO_ROOT_OVERRIDE="$2"; shift 2;;
    --fixture-pr-list)   FIXTURE_PR_LIST="$2"; shift 2;;
    --fixture-events)    FIXTURE_EVENTS="$2"; shift 2;;
    --fixture-diff-stats) FIXTURE_DIFF_STATS="$2"; shift 2;;
    --fixture-decisions) FIXTURE_DECISIONS="$2"; shift 2;;
    --slug)              SLUG="$2"; shift 2;;
    -h|--help)
      sed -n '2,40p' "$0"
      exit 0;;
    *) av_fail "unknown arg: $1"; exit 3;;
  esac
done

# Dependency check (fail-closed).
for tool in jq awk grep; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    av_fail "missing dependency: $tool"
    exit 4
  fi
done

# Repo root resolution. Tests pass --repo-root to point at a fixture dir;
# normal invocation walks up from cwd.
if [ -n "$REPO_ROOT_OVERRIDE" ]; then
  REPO_ROOT="$REPO_ROOT_OVERRIDE"
else
  REPO_ROOT=$(av_repo_root) || REPO_ROOT="$PWD"
fi

# --- v1 mode (backward compat) ------------------------------------------

emit_v1_instructions() {
  cat <<'EOF'
/recap v1 — visual HTML mode.

The script doesn't build the HTML; the model does. Follow the procedure in
skills/recap/SKILL.md:

  1. Gather data (gh pr list / gh issue list / git diff --stat).
  2. Build the HTML at ~/.claude/showme/<YYYYMMDD-HHMMSS>-recap-<slug>.html.
  3. Open + summarize.

For the structured WHY recap, re-run with --v2.
EOF
}

# --- Helpers: input gathering -------------------------------------------

# Render an excerpt of grind-events.jsonl filtered to the window.
collect_events_excerpt() {
  local events_file
  if [ -n "$FIXTURE_EVENTS" ]; then
    events_file="$FIXTURE_EVENTS"
  else
    events_file="$REPO_ROOT/.anvil/grind-events.jsonl"
  fi
  if [ ! -f "$events_file" ]; then
    echo "(no events.jsonl found at $events_file)"
    return 0
  fi
  # If SINCE not provided, take the last 100 events.
  if [ -z "$SINCE" ]; then
    tail -100 "$events_file"
  else
    awk -v since="$SINCE" '{
      # naive: row matches if substring SINCE precedes the "t":"..." stamp.
      # Robust check delegated to jq.
      print
    }' "$events_file" \
      | jq -c "select((.t // \"\") >= \"$SINCE\")"
  fi
}

# PR list. Offline: read from FIXTURE_PR_LIST. Online: `gh pr list --state merged`.
collect_pr_list() {
  if [ -n "$FIXTURE_PR_LIST" ] && [ -f "$FIXTURE_PR_LIST" ]; then
    cat "$FIXTURE_PR_LIST"
    return 0
  fi
  if [ "${GH_OFFLINE:-0}" = "1" ]; then
    echo "(offline mode — no PR list available)"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "(gh CLI missing — no PR list available)"
    return 0
  fi
  local since_arg=""
  if [ -n "$SINCE" ]; then
    since_arg="$SINCE"
  fi
  gh pr list --state merged --base main --limit 30 \
    --json number,title,mergedAt,additions,deletions 2>/dev/null \
    | jq -r --arg since "$since_arg" \
        '.[] | select($since == "" or (.mergedAt >= $since))
        | "#\(.number) | \(.mergedAt[0:10]) | +\(.additions)/-\(.deletions) | \(.title)"' \
    || echo "(gh pr list failed)"
}

# tasks.md excerpt — just take the slice manifest YAML block.
collect_plan_excerpt() {
  if [ -z "$PLAN_PATH" ] || [ ! -e "$PLAN_PATH" ]; then
    echo "(no plan path provided)"
    return 0
  fi
  local tasks_file
  if [ -d "$PLAN_PATH" ]; then
    tasks_file="$PLAN_PATH/tasks.md"
  else
    tasks_file="$PLAN_PATH"
  fi
  if [ ! -f "$tasks_file" ]; then
    echo "(no tasks.md at $tasks_file)"
    return 0
  fi
  head -200 "$tasks_file"
}

# Decisions excerpt from .anvil/learnings.jsonl.
collect_decisions_excerpt() {
  if [ -n "$FIXTURE_DECISIONS" ] && [ -f "$FIXTURE_DECISIONS" ]; then
    cat "$FIXTURE_DECISIONS"
    return 0
  fi
  local learn_file="$REPO_ROOT/.anvil/learnings.jsonl"
  if [ ! -f "$learn_file" ]; then
    echo "(no learnings.jsonl found)"
    return 0
  fi
  jq -c 'select(.type == "decision")' "$learn_file" 2>/dev/null \
    | head -20 \
    || echo "(decisions parse failed)"
}

# Diff stats per slice-merged event.
collect_diff_stats() {
  if [ -n "$FIXTURE_DIFF_STATS" ] && [ -f "$FIXTURE_DIFF_STATS" ]; then
    cat "$FIXTURE_DIFF_STATS"
    return 0
  fi
  if [ "${GH_OFFLINE:-0}" = "1" ]; then
    echo "(offline mode — diff stats unavailable)"
    return 0
  fi
  # Use the events excerpt to find merged shas; ask git diff --stat per sha.
  local events_file
  if [ -n "$FIXTURE_EVENTS" ]; then
    events_file="$FIXTURE_EVENTS"
  else
    events_file="$REPO_ROOT/.anvil/grind-events.jsonl"
  fi
  if [ ! -f "$events_file" ]; then
    echo "(no events.jsonl)"
    return 0
  fi
  # Best-effort. Extract slice + PR number per slice-merged event.
  jq -r 'select(.ev == "slice-merged") | "\(.slice) #\(.data.pr // "?")"' \
    "$events_file" 2>/dev/null | head -10 \
    || echo "(could not parse slice-merged events)"
}

# --- Helpers: template render -------------------------------------------

render_prompt() {
  local template="$ANVIL_ROOT/skills/recap/templates/why-recap.md"
  if [ ! -f "$template" ]; then
    av_fail "template missing at $template"
    exit 3
  fi

  # Spool each multi-line input to a tmp file. awk reads them via getline
  # in BEGIN — that path handles newlines cleanly (passing newline-bearing
  # strings via `-v` triggers an "awk: newline in string" error).
  local tmpdir
  tmpdir=$(mktemp -d -t anvil-recap.XXXXXX)
  trap 'rm -rf "$tmpdir"' RETURN
  collect_events_excerpt    > "$tmpdir/events.txt"
  collect_pr_list           > "$tmpdir/prs.txt"
  collect_plan_excerpt      > "$tmpdir/plan.txt"
  collect_decisions_excerpt > "$tmpdir/decisions.txt"
  collect_diff_stats        > "$tmpdir/diffs.txt"

  local events_path
  if [ -n "$FIXTURE_EVENTS" ]; then
    events_path="$FIXTURE_EVENTS"
  else
    events_path="$REPO_ROOT/.anvil/grind-events.jsonl"
  fi
  local events_count pr_count commit_count
  # `grep -c` returns 1 on zero matches, which trips `set -e` flavoured callers
  # and corrupts the count. Use awk for an always-zero-on-empty path.
  events_count=$(awk 'NF{n++} END{print n+0}' "$tmpdir/events.txt")
  pr_count=$(awk '/^#/{n++} END{print n+0}' "$tmpdir/prs.txt")
  commit_count=$(awk 'NF{n++} END{print n+0}' "$tmpdir/diffs.txt")

  # awk template renderer: scalar substitutions inline, multi-line markers
  # ({{events_excerpt}}, {{pr_list}}, etc.) replaced by reading the spool
  # file at substitution time. This avoids awk's newline-in-string limit.
  awk -v plan="$PLAN_PATH" \
      -v since="$SINCE" \
      -v until_="$UNTIL" \
      -v events_count="$events_count" \
      -v events_path="$events_path" \
      -v pr_count="$pr_count" \
      -v commit_count="$commit_count" \
      -v slug="$SLUG" \
      -v events_file="$tmpdir/events.txt" \
      -v prs_file="$tmpdir/prs.txt" \
      -v plan_file="$tmpdir/plan.txt" \
      -v decisions_file="$tmpdir/decisions.txt" \
      -v diffs_file="$tmpdir/diffs.txt" \
  '
  function load_file(p,    ln, blob) {
    blob = ""
    while ((getline ln < p) > 0) {
      blob = blob ln "\n"
    }
    close(p)
    sub(/\n$/, "", blob)
    return blob
  }
  BEGIN {
    events_blob    = load_file(events_file)
    prs_blob       = load_file(prs_file)
    plan_blob      = load_file(plan_file)
    decisions_blob = load_file(decisions_file)
    diffs_blob     = load_file(diffs_file)
  }
  {
    # Scalar substitutions first.
    gsub(/\{\{plan_path\}\}/, plan)
    gsub(/\{\{since\}\}/, since)
    gsub(/\{\{until\}\}/, until_)
    gsub(/\{\{events_count\}\}/, events_count)
    gsub(/\{\{events_path\}\}/, events_path)
    gsub(/\{\{pr_count\}\}/, pr_count)
    gsub(/\{\{commit_count\}\}/, commit_count)
    gsub(/\{\{slug\}\}/, slug)
    # If a line is exactly a multi-line placeholder, replace with the blob.
    # This avoids needing gsub() with newline-bearing replacement strings.
    if ($0 == "{{events_excerpt}}")    { print events_blob;    next }
    if ($0 == "{{pr_list}}")           { print prs_blob;       next }
    if ($0 == "{{plan_excerpt}}")      { print plan_blob;      next }
    if ($0 == "{{decisions_excerpt}}") { print decisions_blob; next }
    if ($0 == "{{diff_stats}}")        { print diffs_blob;     next }
    print
  }' "$template"
}

# --- Helpers: structure validation --------------------------------------

# Required sections, in order. Section 1 (TLDR) MUST be first non-title
# heading. The order of sections 2-5 is also locked.
REQUIRED_SECTIONS=(
  "## TLDR"
  "## What shipped"
  "## What assumptions changed"
  "## What architectural drift"
  "## What residual risk"
)

validate_structure() {
  local file="$1"
  if [ ! -f "$file" ]; then
    av_fail "validate_structure: file not found: $file"
    return 1
  fi
  # Each required heading present?
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -Fxq "$section" "$file"; then
      av_fail "missing section: $section"
      return 1
    fi
  done
  # Order: pull all `## ` lines and assert REQUIRED_SECTIONS is a prefix of them.
  local actual
  actual=$(grep -E '^## ' "$file")
  local i=0
  while IFS= read -r line; do
    if [ $i -ge ${#REQUIRED_SECTIONS[@]} ]; then break; fi
    if [ "$line" != "${REQUIRED_SECTIONS[$i]}" ]; then
      av_fail "section order wrong: expected '${REQUIRED_SECTIONS[$i]}' at position $((i+1)), got '$line'"
      return 1
    fi
    i=$((i+1))
  done <<< "$actual"
  if [ $i -lt ${#REQUIRED_SECTIONS[@]} ]; then
    av_fail "section order short — found $i of ${#REQUIRED_SECTIONS[@]} required sections in order"
    return 1
  fi
  # TLDR must contain exactly 4 sentences. Real recaps mention names + common
  # abbreviations + decision-record stanzas + version numbers. Strategy:
  #   1. Strip well-known abbreviation periods (Mr., Dr., e.g., i.e., vs., etc.,
  #      v1., decision_type:) — common patterns that would otherwise inflate
  #      the sentence count.
  #   2. Treat a sentence terminator as `.`/`!`/`?` followed by whitespace+
  #      capital letter OR end-of-input.
  local tldr_body
  tldr_body=$(awk '
    /^## TLDR[[:space:]]*$/ {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' "$file")
  local sentence_count
  # POSIX `\b` is not portable across sed implementations (BSD sed doesn't
  # honour it inside -E). Anchor abbreviations via "preceded by start-of-line
  # or non-letter, followed by `.` + whitespace" to be cross-platform safe.
  sentence_count=$(printf '%s' "$tldr_body" \
    | tr '\n' ' ' \
    | sed -E '
        s/(^|[^A-Za-z])(Mr|Mrs|Ms|Dr|Inc|Co|Ltd|St|Jr|Sr|Prof|Capt|Sgt)\.[[:space:]]/\1\2 /g
        s/(^|[^A-Za-z])(e|i)\.(g|e)\.[[:space:]]/\1\2\3 /g
        s/(^|[^A-Za-z])(vs|etc|cf|al|approx|min|max|pp|vol|ed|eds|fig|figs|no|nos)\.[[:space:]]/\1\2 /g
        s/(^|[^A-Za-z])v([0-9]+)\.([0-9]+)?\.?[[:space:]]/\1v\2_\3 /g
      ' \
    | grep -oE '[.!?]+([[:space:]]+[A-Z]|[[:space:]]*$)' \
    | wc -l \
    | tr -d ' ')
  if [ "$sentence_count" -ne 4 ]; then
    av_fail "TLDR must contain exactly 4 sentences (one per WHY section); found $sentence_count"
    return 1
  fi
  return 0
}

# --- Helpers: citation extraction + resolution --------------------------

# Extract every citation candidate from sections 3-5 of $1. Emits one citation
# per line, with a leading tag indicating form: FILE|PR|SHA.
extract_citations() {
  local file="$1"
  # Pull body of sections 3, 4, 5.
  awk '
    /^## What assumptions changed[[:space:]]*$/ {flag=1; next}
    /^## What architectural drift[[:space:]]*$/ {flag=1; next}
    /^## What residual risk[[:space:]]*$/      {flag=1; next}
    /^## / && flag                              {flag=0}
    flag                                        {print}
  ' "$file" \
  | tr '\n' ' ' \
  | grep -oE '(\#[0-9]+|[A-Za-z0-9_.\/-]+:[0-9]+|<[0-9a-f]{7,40}>|[0-9a-f]{7,40}\b)' \
  | awk '
    /^#[0-9]+$/                                   { print "PR|" $0; next }
    /^[A-Za-z0-9_.\/-]+:[0-9]+$/                  {
      # Reject URL-shaped fragments — schemes like `http:` / `https:` / `git:`
      # have `://` shape but the leading scheme strips and this regex matches
      # the trailing segment. Defense-in-depth: drop any candidate containing
      # `://` upstream OR starting with `//`.
      if ($0 ~ /^\/\// || $0 ~ /:\/\//) {
        print "URL|" $0; next
      }
      print "FILE|" $0; next
    }
    /^<[0-9a-f]{7,40}>$/                          { gsub(/[<>]/, "", $0); print "SHA|" $0; next }
    /^[0-9a-f]{7,40}$/                            {
      # Naked SHA only counts if it is at least 7 hex chars AND not all numeric.
      if ($0 !~ /^[0-9]+$/) { print "SHA|" $0 }
      next
    }
  '
}

# Count bullets in a section and assert each non-empty bullet line has at least
# one citation matching one of the three forms.
validate_section_citations() {
  local file="$1"
  local section="$2"
  local body
  body=$(awk -v s="$section" '
    $0 == s {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' "$file")
  # Iterate bullet lines (start with `- ` or `* `, after trim).
  local bad=0
  local bullets
  bullets=$(printf '%s\n' "$body" | grep -E '^[[:space:]]*[-*][[:space:]]' || true)
  if [ -z "$bullets" ]; then
    # Section can be empty (no claims) — that's fine.
    return 0
  fi
  while IFS= read -r bullet; do
    # A citation regex: `#N`, `path:N`, `<sha>`, or naked sha.
    if ! printf '%s\n' "$bullet" \
      | grep -qE '(\#[0-9]+|[A-Za-z0-9_.\/-]+:[0-9]+|<[0-9a-f]{7,40}>|[0-9a-f]{7,40})'; then
      av_fail "no citation in bullet under '$section': $bullet"
      bad=$((bad+1))
    fi
  done <<< "$bullets"
  return $bad
}

# Resolve a single citation. Echoes "ok" or "bad: <reason>" to stdout.
resolve_citation() {
  local kind="$1"
  local cite="$2"
  case "$kind" in
    PR)
      local n="${cite#\#}"
      # Always check fixture allowlist first if provided.
      local allow="$PR_ALLOWLIST"
      if [ -z "$allow" ]; then
        allow="$REPO_ROOT/.anvil/recap-pr-allowlist.txt"
      fi
      if [ -f "$allow" ] && grep -qFx "$n" "$allow"; then
        echo "ok"
        return 0
      fi
      if [ "${GH_OFFLINE:-0}" = "1" ]; then
        echo "bad: PR $cite not in allowlist (offline mode)"
        return 1
      fi
      if ! command -v gh >/dev/null 2>&1; then
        echo "bad: PR $cite — no allowlist hit + gh CLI missing"
        return 1
      fi
      if gh pr view "$n" --json number >/dev/null 2>&1; then
        echo "ok"
        return 0
      fi
      echo "bad: PR $cite — gh pr view failed"
      return 1
      ;;
    FILE)
      local path="${cite%:*}"
      local line="${cite##*:}"
      # Resolve relative to REPO_ROOT if not absolute.
      if [ "${path:0:1}" != "/" ]; then
        path="$REPO_ROOT/$path"
      fi
      if [ ! -f "$path" ]; then
        echo "bad: file $cite — path does not exist"
        return 1
      fi
      local n
      n=$(wc -l < "$path" | tr -d ' ')
      if [ "$n" -lt "$line" ]; then
        echo "bad: file $cite — file has $n lines, citation references line $line"
        return 1
      fi
      echo "ok"
      return 0
      ;;
    SHA)
      # Validate SHA against the repo (or override).
      if ( cd "$REPO_ROOT" && git cat-file -e "$cite" 2>/dev/null ); then
        echo "ok"
        return 0
      fi
      echo "bad: SHA $cite — not in git object store"
      return 1
      ;;
    URL)
      echo "bad: unrecognised URL-shaped citation: $cite (use file:line, #PR, or commit SHA)"
      return 1
      ;;
    *)
      echo "bad: unknown citation kind: $kind"
      return 1
      ;;
  esac
}

# Run citation resolution over a v2 markdown file. Returns 0 if every citation
# resolves OR there are no citations. Returns 2 on any unresolved citation.
resolve_citations() {
  local file="$1"
  # First, assert every bullet in sections 3-5 has at least one citation.
  local missing=0
  validate_section_citations "$file" "## What assumptions changed" || missing=$((missing + $?))
  validate_section_citations "$file" "## What architectural drift" || missing=$((missing + $?))
  validate_section_citations "$file" "## What residual risk"       || missing=$((missing + $?))
  if [ "$missing" -ne 0 ]; then
    return 2
  fi
  # Then resolve each citation. extract_citations emits one per line as KIND|CITE.
  local cites
  cites=$(extract_citations "$file" | sort -u || true)
  if [ -z "$cites" ]; then
    # No citations at all. That's fine ONLY if no bullets exist in 3-5
    # (already enforced above). Treat empty as pass.
    return 0
  fi
  local fail=0
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    local kind="${row%%|*}"
    local cite="${row#*|}"
    local result
    result=$(resolve_citation "$kind" "$cite") || fail=$((fail+1))
    if [ "$result" != "ok" ]; then
      av_fail "$result"
      fail=$((fail+1))
    fi
  done <<< "$cites"
  if [ "$fail" -ne 0 ]; then
    return 2
  fi
  return 0
}

# --- v2 build orchestrator ----------------------------------------------

build_v2() {
  # Step 1: render the prompt template.
  local prompt
  prompt=$(render_prompt)

  # If no model command is configured, emit the prompt + exit 0. The operator
  # can hand the prompt to a model out-of-band.
  if [ -z "$MODEL_CMD" ]; then
    if [ -n "$OUTPUT_PATH" ]; then
      printf '%s\n' "$prompt" > "$OUTPUT_PATH"
    else
      printf '%s\n' "$prompt"
    fi
    av_info "no --model-cmd / RECAP_MODEL_CMD set — prompt emitted; run the model out-of-band and pipe its output back via --resolve <file>."
    return 0
  fi

  # Step 2: pipe the prompt into the model command. The command is expected to
  # consume the prompt on stdin and emit the markdown recap on stdout.
  local recap_md_path
  if [ -n "$OUTPUT_PATH" ]; then
    recap_md_path="$OUTPUT_PATH"
  else
    recap_md_path="$(mktemp -t anvil-recap.XXXXXX).md"
  fi
  if ! printf '%s\n' "$prompt" | bash -c "$MODEL_CMD" > "$recap_md_path"; then
    av_fail "model command failed: $MODEL_CMD"
    return 3
  fi

  # Step 3: validate structure.
  if ! validate_structure "$recap_md_path"; then
    av_fail "v2 recap structure invalid — see errors above. Output kept at: $recap_md_path"
    return 1
  fi

  # Step 4: resolve citations.
  local rc
  resolve_citations "$recap_md_path"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    av_fail "citation resolution failed — see errors above. Output kept at: $recap_md_path"
    return 2
  fi

  av_ok "v2 recap written to $recap_md_path"
  if [ -n "$HTML_PATH" ]; then
    render_html "$recap_md_path" "$HTML_PATH" || {
      av_warn "html render failed (recap markdown still at $recap_md_path)"
    }
  fi
  if [ -z "$OUTPUT_PATH" ]; then
    cat "$recap_md_path"
  fi
  return 0
}

build_resolve() {
  if [ -z "$INPUT_PATH" ] || [ ! -f "$INPUT_PATH" ]; then
    av_fail "--resolve requires a path to an existing markdown file"
    exit 3
  fi
  if ! validate_structure "$INPUT_PATH"; then
    exit 1
  fi
  local rc
  resolve_citations "$INPUT_PATH"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    exit 2
  fi
  if [ -n "$HTML_PATH" ]; then
    render_html "$INPUT_PATH" "$HTML_PATH" || {
      av_warn "html render failed (recap markdown still at $INPUT_PATH)"
      exit 2
    }
    av_ok "html rendered to $HTML_PATH"
  fi
  av_ok "structure + citations resolved for $INPUT_PATH"
}

# --- HTML render ---------------------------------------------------------
#
# render_html <validated-md> <output-html>
#
# Reads a v2 markdown file (assumed validated + cited) + emits a self-
# contained styled HTML page using templates/v2-html-shell.html. The
# styling is dark-theme by default with a light-mode media query. Pulls
# the per-section bodies + TLDR sentences + converts citations to colored
# pills (file:line / #PR / sha).
#
# Citation pills become anchor tags when:
#   - file:line — link to `<path>#L<N>` if `$GH_REPO` is set (e.g.
#     owner/repo); otherwise unlinked badge.
#   - #PR       — link to https://github.com/$GH_REPO/pull/<N> if set.
#   - sha       — link to https://github.com/$GH_REPO/commit/<sha> if set.

render_html() {
  local md="$1"
  local out="$2"
  local tpl="$SCRIPT_DIR/../templates/v2-html-shell.html"
  if [ ! -f "$tpl" ]; then
    av_fail "html template missing: $tpl"
    return 1
  fi

  # Pull TLDR body + each section body separately.
  local tldr_raw
  tldr_raw=$(awk '
    /^## TLDR[[:space:]]*$/ {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' "$md")

  # Convert TLDR into <li> rows, one per sentence. Strategy: strip abbreviation
  # periods to a sentinel, then split on sentence-terminator + space + capital.
  local tldr_items
  tldr_items=$(printf '%s' "$tldr_raw" \
    | tr '\n' ' ' \
    | sed -E '
        s/(^|[^A-Za-z])(Mr|Mrs|Ms|Dr|Inc|Co|Ltd|St|Jr|Sr|Prof|Capt|Sgt)\.[[:space:]]/\1\2ZZZABBR /g
        s/(^|[^A-Za-z])(e|i)\.(g|e)\.[[:space:]]/\1\2\3ZZZABBR /g
        s/(^|[^A-Za-z])(vs|etc|cf|al|approx|min|max|pp|vol|ed|eds|fig|figs|no|nos)\.[[:space:]]/\1\2ZZZABBR /g
        s/(^|[^A-Za-z])v([0-9]+)\.([0-9]+)?\.?[[:space:]]/\1v\2_\3ZZZABBR /g
        s/([.!?]+)[[:space:]]+([A-Z])/\1__BREAK__\2/g
      ' \
    | tr '\n' ' ' \
    | awk 'BEGIN{RS="__BREAK__"} NF{
        s=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        gsub(/ZZZABBR/, ".", s)
        if (length(s) > 0) printf "    <li>%s</li>\n", s
      }')

  # Section bodies. Convert each to HTML by:
  #   - bullets `- foo` → <li>foo</li>
  #   - non-empty non-bullet line → <p>line</p>
  #   - inline `code` → <code>code</code>
  #   - citations matching #N | path:N | sha → <a class="cite-..."> pills
  local shipped_body assumptions_body drift_body risk_body
  shipped_body=$(section_to_html "$md" "## What shipped")
  assumptions_body=$(section_to_html "$md" "## What assumptions changed")
  drift_body=$(section_to_html "$md" "## What architectural drift")
  risk_body=$(section_to_html "$md" "## What residual risk")

  # Header fields.
  local title subtitle generated_at plan_display
  title=$(head -1 "$md" | sed -E 's/^#[[:space:]]+//' | sed -E 's/[&<>]/_/g')
  [ -z "$title" ] && title="Sprint recap"
  subtitle="Structured WHY — v2"
  generated_at=$(date -u +"%Y-%m-%d %H:%MZ")
  plan_display="${PLAN_PATH:-(unspecified plan)}"
  plan_display=$(printf '%s' "$plan_display" | sed -E 's/[&<>]/_/g')

  # Multi-line substitution via tmpfiles + awk getline. -v can't carry
  # newline-bearing strings on POSIX awk; tmpfile-per-block is the
  # cross-platform way to splice them in safely.
  local tldr_f shipped_f assumptions_f drift_f risk_f
  tldr_f=$(mktemp -t anvil-recap-tldr.XXXXXX)
  shipped_f=$(mktemp -t anvil-recap-shipped.XXXXXX)
  assumptions_f=$(mktemp -t anvil-recap-assumptions.XXXXXX)
  drift_f=$(mktemp -t anvil-recap-drift.XXXXXX)
  risk_f=$(mktemp -t anvil-recap-risk.XXXXXX)
  printf '%s\n' "$tldr_items" > "$tldr_f"
  printf '%s\n' "$shipped_body" > "$shipped_f"
  printf '%s\n' "$assumptions_body" > "$assumptions_f"
  printf '%s\n' "$drift_body" > "$drift_f"
  printf '%s\n' "$risk_body" > "$risk_f"

  awk \
    -v title="$title" \
    -v subtitle="$subtitle" \
    -v generated_at="$generated_at" \
    -v plan_path="$plan_display" \
    -v tldr_f="$tldr_f" \
    -v shipped_f="$shipped_f" \
    -v assumptions_f="$assumptions_f" \
    -v drift_f="$drift_f" \
    -v risk_f="$risk_f" \
    '
    function inject(path,    line) {
      while ((getline line < path) > 0) print line
      close(path)
    }
    {
      line = $0
      gsub(/\{\{title\}\}/, title, line)
      gsub(/\{\{subtitle\}\}/, subtitle, line)
      gsub(/\{\{generated_at\}\}/, generated_at, line)
      gsub(/\{\{plan_path\}\}/, plan_path, line)
      if (line ~ /\{\{tldr_items\}\}/)        { inject(tldr_f); next }
      if (line ~ /\{\{shipped_body\}\}/)      { inject(shipped_f); next }
      if (line ~ /\{\{assumptions_body\}\}/)  { inject(assumptions_f); next }
      if (line ~ /\{\{drift_body\}\}/)        { inject(drift_f); next }
      if (line ~ /\{\{risk_body\}\}/)         { inject(risk_f); next }
      print line
    }
  ' "$tpl" > "$out"

  rm -f "$tldr_f" "$shipped_f" "$assumptions_f" "$drift_f" "$risk_f"
}

# section_to_html <md-file> <section-heading>
# Emits HTML body for one section. Bullets → <ul><li>; non-bullet lines drop
# (recaps are bullet-shaped); inline code → <code>; citations → pills.
section_to_html() {
  local md="$1"
  local section="$2"
  local body
  body=$(awk -v s="$section" '
    $0 == s {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' "$md")
  if [ -z "$body" ]; then
    printf '  <p style="color:var(--text-3);font-style:italic;">(no entries)</p>\n'
    return 0
  fi
  # Filter to bullet lines only, then transform.
  local html
  html=$(printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*[-*][[:space:]]' \
    | sed -E '
        s/^[[:space:]]*[-*][[:space:]]+//
        s/&/\&amp;/g
        s/</\&lt;/g
        s/>/\&gt;/g
        s/`([^`]+)`/<code>\1<\/code>/g
      ' \
    | citations_to_pills \
    | awk 'NF { printf "    <li>%s</li>\n", $0 }')
  if [ -z "$html" ]; then
    printf '  <p style="color:var(--text-3);font-style:italic;">(no entries)</p>\n'
  else
    printf '  <ul>\n%s  </ul>\n' "$html"
  fi
}

# citations_to_pills — stdin filter that converts citation tokens to pill anchors.
# Honors $GH_REPO for link targets when set.
citations_to_pills() {
  # BSD sed -E doesn't honour \b — anchor file:N citations via "preceded by
  # start-of-line or non-path-char". Use separate -e expressions because
  # BSD sed's handling of multi-line -E scripts is finicky.
  local repo="${GH_REPO:-anvil/anvil}"
  sed -E \
    -e "s|#([0-9]+)|<a class='cite cite-pr' href='https://github.com/${repo}/pull/\\1'>#\\1</a>|g" \
    -e "s|<([0-9a-f]{7,40})>|<a class='cite cite-sha' href='https://github.com/${repo}/commit/\\1'>\\1</a>|g" \
    -e "s|(^\|[^A-Za-z0-9._/-])([A-Za-z0-9_./-]+\\.[A-Za-z]+):([0-9]+)|\\1<a class='cite cite-file' href='\\2#L\\3'>\\2:\\3</a>|g"
}

# --- main ---------------------------------------------------------------

case "$MODE" in
  v1)      emit_v1_instructions; exit 0;;
  v2)      build_v2; exit $?;;
  resolve) build_resolve; exit $?;;
  *)       av_fail "internal error: unknown mode '$MODE'"; exit 3;;
esac
