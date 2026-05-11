#!/usr/bin/env bats
# Smoke tests for /learn (5 scripts: add, search, summary, prune, export).

load ../test_helper

setup() {
  setup_fresh_repo
}

# --- learn add -----------------------------------------------------------

@test "learn add records an entry to .anvil/learnings.jsonl" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    test-key gotcha "smoke-test insight" --source /test --strict
  [ "$status" -eq 0 ]
  [ -f .anvil/learnings.jsonl ]
  grep -q '"key":"test-key"' .anvil/learnings.jsonl
  grep -q '"type":"gotcha"' .anvil/learnings.jsonl
  grep -q '"insight":"smoke-test insight"' .anvil/learnings.jsonl
}

@test "learn add rejects invalid type when --strict" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    test-key bogus-type "x" --strict
  [ "$status" -ne 0 ]
}

@test "learn add rejects invalid key (uppercase) when --strict" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    BAD-KEY gotcha "x" --strict
  [ "$status" -ne 0 ]
}

@test "learn add is idempotent within window (same key + source)" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    dup-key gotcha "first" --source /test --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    dup-key gotcha "first" --source /test --strict
  # Only one line because the second add hits the idempotency window.
  count=$(grep -c '"key":"dup-key"' .anvil/learnings.jsonl)
  [ "$count" -eq 1 ]
}

# --- learn search --------------------------------------------------------

@test "learn search finds an entry by key" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" "test-flake-vitest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-flake-vitest"* ]]
}

@test "learn search emits valid JSON with --json" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" "vitest" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array"' >/dev/null
}

@test "learn search filters by --type" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" "" --type invariant --json
  [ "$status" -eq 0 ]
  # All matched entries must have type=invariant.
  echo "$output" | jq -e 'all(.type == "invariant")' >/dev/null
}

@test "learn search on empty repo returns gracefully" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" "anything"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no learnings recorded"* ]]
}

# --- learn summary -------------------------------------------------------

@test "learn summary prints grouped sections" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-summary.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLAKE"* ]] || [[ "$output" == *"GOTCHA"* ]] || [[ "$output" == *"INVARIANT"* ]]
}

@test "learn summary rejects invalid --since" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-summary.sh" --since "not-a-date"
  [ "$status" -ne 0 ]
}

# --- learn prune --------------------------------------------------------

@test "learn prune --dry-run reports plan without writing" {
  setup_fresh_repo_with_seed_learnings
  before=$(wc -l < .anvil/learnings.jsonl)
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-prune.sh" \
    --before 2030-01-01 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Prune plan"* ]] || [[ "$output" == *"dry-run"* ]]
  # File untouched.
  after=$(wc -l < .anvil/learnings.jsonl)
  [ "$before" -eq "$after" ]
}

@test "learn prune rejects bad --before format" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-prune.sh" --before "2026/01/01" --dry-run
  [ "$status" -ne 0 ]
}

# --- learn export -------------------------------------------------------

@test "learn export emits a markdown header" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-export.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Learnings export"* ]]
}

@test "learn export filters by --min-confidence high" {
  setup_fresh_repo_with_seed_learnings
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-export.sh" --min-confidence high
  [ "$status" -eq 0 ]
  # high-confidence-only output should include the high-confidence seed keys.
  [[ "$output" == *"test-flake-vitest"* ]] || [[ "$output" == *"test-invariant-maxworkers"* ]]
}
