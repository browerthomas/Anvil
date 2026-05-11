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
