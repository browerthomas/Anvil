#!/usr/bin/env bats
# Smoke tests for /grind/scripts/state.sh — append-only event log + snapshot.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "grind state.sh errors without subcommand" {
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh"
  [ "$status" -ne 0 ]
}

@test "grind state.sh init creates events file + snapshot from a valid plan" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [ -f .anvil/grind-events.jsonl ]
  [ -f .anvil/grind-snapshot.json ]
  # Each line is valid JSON.
  jq -c . .anvil/grind-events.jsonl >/dev/null
}

@test "grind state.sh init records 2 slices from the fixture" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  count=$(jq '.slices | length' .anvil/grind-snapshot.json)
  [ "$count" -eq 2 ]
}

@test "grind state.sh next picks the first ready slice" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" next
  [ "$status" -eq 0 ]
  # A1 has no dependencies; should be the next slice.
  [ "$output" = "A1" ]
}

@test "grind state.sh ready lists slices with deps satisfied" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" ready
  [ "$status" -eq 0 ]
  # Only A1 is ready (A2 depends on A1).
  [[ "$output" == *"A1"* ]]
  [[ "$output" != *"A2"* ]]
}

@test "grind state.sh mark transitions a slice to merged" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 merged
  [ "$status" -eq 0 ]
  status_a1=$(jq -r '.slices.A1.status' .anvil/grind-snapshot.json)
  [ "$status_a1" = "merged" ]
}

@test "grind state.sh status emits a readable summary" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Slices"* ]]
  [[ "$output" == *"A1"* ]]
  [[ "$output" == *"A2"* ]]
}

@test "grind state.sh trace prints event lines" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" trace
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan-init"* ]]
}

@test "grind state.sh init rejects a plan with no YAML manifest" {
  echo "# no manifest" > "$REPO_DIR/empty.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/empty.md"
  [ "$status" -ne 0 ]
}

# --- Token / cost event-data fields ------------------------------------

@test "grind state.sh mark in-flight accepts --tokens-in / --tokens-out / --cost-usd" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 in-flight \
    --tokens-in 1234 --tokens-out 567 --cost-usd 0.0123
  [ "$status" -eq 0 ]
  # Event written with the three fields.
  ev=$(grep '"slice":"A1"' .anvil/grind-events.jsonl | grep 'in-flight' | tail -1)
  echo "$ev" | jq -e '.data.tokens_in == 1234' >/dev/null
  echo "$ev" | jq -e '.data.tokens_out == 567' >/dev/null
  echo "$ev" | jq -e '.data.cost_usd == 0.0123' >/dev/null
  # Snapshot fold carries them on the slice + rolls them up.
  jq -e '.slices.A1.tokens_in  == 1234'   .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.tokens_out == 567'    .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.cost_usd   == 0.0123' .anvil/grind-snapshot.json >/dev/null
  jq -e '.cost_total_usd  == 0.0123'      .anvil/grind-snapshot.json >/dev/null
  jq -e '.tokens_in_total  == 1234'       .anvil/grind-snapshot.json >/dev/null
  jq -e '.tokens_out_total == 567'        .anvil/grind-snapshot.json >/dev/null
}

@test "grind state.sh set-pr accepts token/cost flags" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" set-pr A1 99 \
    --tokens-in 100 --tokens-out 50 --cost-usd 0.001
  [ "$status" -eq 0 ]
  ev=$(grep '"ev":"slice-pr-opened"' .anvil/grind-events.jsonl | tail -1)
  echo "$ev" | jq -e '.data.pr_number == 99' >/dev/null
  echo "$ev" | jq -e '.data.cost_usd  == 0.001' >/dev/null
}

@test "grind state.sh mark merged accumulates token/cost across multiple events" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 in-flight \
    --tokens-in 100 --tokens-out 50 --cost-usd 0.005 >/dev/null
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" set-pr A1 50 \
    --tokens-in 200 --cost-usd 0.010 >/dev/null
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 merged \
    --pr 50 --tests-delta 7 --tokens-out 100 --cost-usd 0.003 >/dev/null
  # 100+200 in, 50+100 out, 0.005+0.010+0.003 cost = 0.018
  jq -e '.slices.A1.tokens_in  == 300'    .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.tokens_out == 150'    .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.cost_usd   == 0.018'  .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.tests_delta == 7'     .anvil/grind-snapshot.json >/dev/null
  jq -e '.slices.A1.pr == 50'             .anvil/grind-snapshot.json >/dev/null
}

@test "grind state.sh mark rejects unknown flag" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 in-flight --bogus 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]] || [[ "$output" == *"bogus"* ]]
}

@test "grind state.sh set-pr rejects unknown flag" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  run bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" set-pr A1 42 --bogus 1
  [ "$status" -ne 0 ]
}

@test "grind state.sh mark preserves backward-compat positional reason arg" {
  cp "$FIXTURES_DIR/valid-plan.md" "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/plan.md"
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark A1 deferred "rate limited" >/dev/null
  ev=$(grep '"ev":"slice-deferred"' .anvil/grind-events.jsonl | tail -1)
  echo "$ev" | jq -e '.data.reason == "rate limited"' >/dev/null
}
