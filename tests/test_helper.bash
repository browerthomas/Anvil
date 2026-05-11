#!/usr/bin/env bash
# tests/test_helper.bash — shared setup/teardown for anvil smoke tests.
#
# Sourced via: load test_helper

# ANVIL_ROOT — repository root (the anvil source tree).
ANVIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANVIL_ROOT

FIXTURES_DIR="$ANVIL_ROOT/tests/fixtures"
export FIXTURES_DIR

# Each test gets its own throwaway repo under $BATS_TEST_TMPDIR. Helper sets up
# a fresh git repo (so av_repo_root in shared/lib.sh resolves), cd's into it,
# and exports REPO_DIR. Idempotent — re-calling after the repo already exists
# is a no-op that re-cd's the caller in.
setup_fresh_repo() {
  REPO_DIR="$BATS_TEST_TMPDIR/repo"
  if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    export REPO_DIR
    return 0
  fi
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init -q
  git config user.email "test@anvil.local"
  git config user.name "anvil-test"
  # Initial commit so HEAD resolves.
  : > .gitkeep
  git add .gitkeep
  git commit -q -m "init"
  export REPO_DIR
}

# Same as setup_fresh_repo but pre-populates .anvil/learnings.jsonl with a
# few seed entries — used by /learn search + summary tests.
setup_fresh_repo_with_seed_learnings() {
  setup_fresh_repo
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/learnings.jsonl" <<'EOF'
{"key":"test-flake-vitest","type":"flake","insight":"Vitest sometimes crashes the worker; retry the push.","confidence":"high","source_skill":"/grind","files":[],"tags":["vitest"],"slice_id":null,"prior_count":0,"timestamp":"2026-05-01T10:00:00Z"}
{"key":"test-gotcha-icloud","type":"gotcha","insight":"iCloud-Drive evicts node_modules — use find -delete.","confidence":"medium","source_skill":"/sweep-worktrees","files":["bin/install.sh"],"tags":["icloud"],"slice_id":null,"prior_count":0,"timestamp":"2026-05-02T10:00:00Z"}
{"key":"test-invariant-maxworkers","type":"invariant","insight":"Vitest 4 silently drops forks.maxForks; use top-level maxWorkers.","confidence":"high","source_skill":"manual","files":["vitest.config.js"],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-05-03T10:00:00Z"}
EOF
}

# Assert a glob matches at least one path. Used because [ -f glob/* ] is brittle.
assert_file_glob_matches() {
  local pattern="$1"
  # shellcheck disable=SC2086
  local files=($pattern)
  if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
    echo "no files matched glob: $pattern" >&2
    return 1
  fi
  return 0
}

# Substitute common markdown-block placeholders so `bash -n` can parse the
# block. The skill SKILL.md docs use `<branch-list>` / `<n>` / `<plan-path>`
# etc. — placeholders that aren't valid bash. We rewrite them to underscore
# identifiers before the syntax check.
substitute_md_placeholders() {
  local input="$1" output="$2"
  # Replace <foo-bar> → foo_bar (only when it looks like a placeholder, not real
  # redirection). The heuristic: <word(-|_|word)*> with no surrounding shell
  # operators on the same character.
  sed -E '
    s/<([a-zA-Z][a-zA-Z0-9_/.-]*)>/__\1__/g;
    s/__([a-zA-Z][a-zA-Z0-9_/.-]*)__/PLACEHOLDER_\1/g;
  ' "$input" \
    | sed -E 's/PLACEHOLDER_[a-zA-Z0-9_./-]*/_placeholder_/g' \
    > "$output"
}

# Extract every fenced ```bash block from a markdown file into a single .sh
# file at $2, with placeholders substituted.
extract_md_bash_blocks() {
  local md_file="$1"
  local out_sh="$2"
  awk '
    /^```bash/ { flag=1; next }
    /^```/     { flag=0 }
    flag       { print }
  ' "$md_file" > "$out_sh.raw"
  substitute_md_placeholders "$out_sh.raw" "$out_sh"
  rm -f "$out_sh.raw"
}
