#!/usr/bin/env bats
# Smoke tests for /learn decision-type ergonomics (B3):
#   - learn-add.sh --decision-type <dt> --affected <slice> writes type:decision rows
#   - learn-search.sh decisions filters to type:decision rows only
#   - learn-search.sh <q> (no filter) returns rows of any type
#   - --affected accepts repeatable + comma-separated forms
#   - decision rows respect existing idempotency window
#   - /dispatch-slice prompt template renders "Recent decisions:" when relevant rows exist

load ../test_helper

setup() {
  setup_fresh_repo
}

# --- learn add --decision-type ------------------------------------------

@test "add decision row with --decision-type architecture writes type:decision to learnings.jsonl" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    chose-redis-over-postgres-listen \
    "retry semantics under worker restart cleaner with redis pub/sub" \
    --source manual --strict
  [ "$status" -eq 0 ]
  [ -f .anvil/learnings.jsonl ]
  # Single line, type=decision.
  count=$(jq -c 'select(.key == "chose-redis-over-postgres-listen")' .anvil/learnings.jsonl | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  jq -e 'select(.key == "chose-redis-over-postgres-listen")
    | (.type == "decision") and (.decision_type == "architecture")' \
    .anvil/learnings.jsonl >/dev/null
}

@test "add decision row rejects invalid --decision-type when --strict" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type bogus-dt --affected B1 \
    bad-key "ignored insight" --strict
  [ "$status" -ne 0 ]
}

@test "add row rejects --decision-type on non-decision type" {
  # 3-positional form with explicit type=flake + --decision-type should fail under --strict.
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    mixed-key flake "this is a flake, not a decision" \
    --decision-type architecture --strict
  [ "$status" -ne 0 ]
}

@test "add row rejects --affected on non-decision type" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    mixed-key flake "this is a flake" \
    --affected B1 --strict
  [ "$status" -ne 0 ]
}

# --- --affected slice id storage ----------------------------------------

@test "--affected B1 stores the slice id in the row" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    single-slice-decision "test insight" --strict
  jq -e 'select(.key == "single-slice-decision") | .affected_slices == ["B1"]' \
    .anvil/learnings.jsonl >/dev/null
}

@test "--affected B1,B2 stores both slice ids (comma-separated)" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type scope --affected B1,B2 \
    multi-slice-decision "test insight" --strict
  jq -e 'select(.key == "multi-slice-decision") | .affected_slices == ["B1","B2"]' \
    .anvil/learnings.jsonl >/dev/null
}

@test "--affected B1 --affected B2 stores both slice ids (repeatable)" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type scope --affected B1 --affected B2 \
    repeat-slice-decision "test insight" --strict
  jq -e 'select(.key == "repeat-slice-decision") | .affected_slices == ["B1","B2"]' \
    .anvil/learnings.jsonl >/dev/null
}

@test "--affected accepts whitespace around commas" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type scope --affected "B1, B2 , B3" \
    whitespace-decision "test insight" --strict
  jq -e 'select(.key == "whitespace-decision") | .affected_slices == ["B1","B2","B3"]' \
    .anvil/learnings.jsonl >/dev/null
}

# --- /learn decisions subcommand ----------------------------------------

@test "/learn decisions filters to type:decision rows only" {
  # Mixed: 1 decision, 1 flake, 1 gotcha — verify decisions returns only 1.
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    mixed-decision-row "an architecture decision" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    flake-row flake "an unrelated flake" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    gotcha-row gotcha "an unrelated gotcha" --strict

  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions --json
  [ "$status" -eq 0 ]
  # All matched entries must have type=decision.
  echo "$output" | jq -e 'length == 1 and all(.type == "decision")' >/dev/null
  echo "$output" | jq -e '.[0].key == "mixed-decision-row"' >/dev/null
}

@test "/learn decisions equivalent to learn-search.sh --type decision" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type scope --affected B2 \
    explicit-type-filter "test insight" --strict

  out_subcmd=$(bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions --json)
  out_flag=$(bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" "" --type decision --json)
  [ "$out_subcmd" = "$out_flag" ]
}

@test "/learn decisions returns nothing on empty repo" {
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions
  [ "$status" -eq 0 ]
  [[ "$output" == *"no learnings recorded"* ]]
}

@test "/learn decisions filters by --affected slice id" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    decision-for-b1 "B1 only" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B2 \
    decision-for-b2 "B2 only" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type scope --affected B1,B3 \
    decision-for-b1-and-b3 "B1 and B3" --strict

  # --affected B1 should match decision-for-b1 + decision-for-b1-and-b3 (2 rows).
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions --affected B1 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2' >/dev/null
  keys=$(echo "$output" | jq -r '.[].key' | sort | tr '\n' ',')
  [ "$keys" = "decision-for-b1,decision-for-b1-and-b3," ]
}

# --- learn search returns decisions too ---------------------------------

@test "/learn search redis returns rows of any type matching the query (including decisions)" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    chose-redis-architecture \
    "retry semantics under worker restart cleaner with redis pub/sub" \
    --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    other-tag gotcha "an unrelated tag" --strict

  # Substring "redis" should match the decision via insight content.
  run bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" redis --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1 and .[0].key == "chose-redis-architecture"' >/dev/null
}

# --- combined smoke: decision + flake + gotcha three-row test -----------

@test "write 3 rows (decision + flake + gotcha): /learn decisions returns 1; /learn search returns all 3" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    triple-test-decision "decision row" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    triple-test-flake flake "flake row" --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    triple-test-gotcha gotcha "gotcha row" --strict

  # /learn decisions → 1
  dec_count=$(bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" decisions --json \
    | jq 'length')
  [ "$dec_count" -eq 1 ]

  # /learn search "row" → 3 (substring "row" appears in all 3 insights)
  total_count=$(bash "$ANVIL_ROOT/skills/learn/scripts/learn-search.sh" row --json \
    | jq 'length')
  [ "$total_count" -eq 3 ]
}

# --- idempotency window for decision rows -------------------------------

@test "decision rows respect existing idempotency window (same key+source within window)" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    idem-decision "first" --source /test --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    idem-decision "first" --source /test --strict

  count=$(jq -c 'select(.key == "idem-decision")' .anvil/learnings.jsonl | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "decision rows skip idempotency when --idempotency-window 0" {
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    no-idem-decision "first" --source /test --idempotency-window 0 --strict
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    no-idem-decision "second" --source /test --idempotency-window 0 --strict

  count=$(jq -c 'select(.key == "no-idem-decision")' .anvil/learnings.jsonl | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

# --- /dispatch-slice prompt template injection --------------------------

@test "/dispatch-slice template renders 'Recent decisions:' section when relevant rows exist" {
  # Log a decision affecting slice B1.
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B1 \
    dispatch-injected-decision \
    "retry semantics under worker restart cleaner with redis pub/sub" \
    --strict

  # Build the prompt for slice B1.
  prompt=$(bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id B1 --scope "test scope for B1 dispatch")

  # The prompt must contain "## Recent decisions" + the decision bullet.
  echo "$prompt" | grep -q "## Recent decisions"
  echo "$prompt" | grep -q "architecture"
  echo "$prompt" | grep -q "dispatch-injected-decision"
}

@test "/dispatch-slice template omits 'Recent decisions:' when no matching rows" {
  # Log a decision affecting B2 but dispatch B1 — no match.
  bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
    --decision-type architecture --affected B2 \
    decision-for-b2-only "B2 only" --strict

  prompt=$(bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id B1 --scope "test scope")

  # The "Recent decisions" section must NOT appear.
  ! echo "$prompt" | grep -q "## Recent decisions"
}

@test "/dispatch-slice template omits 'Recent decisions:' when learnings.jsonl missing" {
  # Fresh repo, no decisions logged. Dispatch B1.
  prompt=$(bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id B1 --scope "test scope")

  # The "Recent decisions" section must NOT appear, and the build must succeed.
  ! echo "$prompt" | grep -q "## Recent decisions"
  echo "$prompt" | grep -q "## Scope"
}
