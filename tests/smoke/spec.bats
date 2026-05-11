#!/usr/bin/env bats
# Smoke tests for /spec/scripts/validate.sh.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "spec validate accepts a valid flat-file plan" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh" \
    "$FIXTURES_DIR/valid-plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLAN VALIDATES"* ]] || [[ "$output" == *"plan validates"* ]]
}

@test "spec validate accepts a folder-layout plan" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh" \
    "$FIXTURES_DIR/folder-plan"
  # Folder plan may surface warnings (no decision shapes etc.); accept 0 or 2.
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "spec validate rejects an invalid plan" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh" \
    "$FIXTURES_DIR/invalid-plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"error"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "spec validate emits a non-empty verdict block" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh" \
    "$FIXTURES_DIR/valid-plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan validation"* ]]
}

@test "spec validate errors on missing plan path" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh"
  [ "$status" -ne 0 ]
}

@test "spec validate errors on nonexistent plan path" {
  run bash "$ANVIL_ROOT/skills/spec/scripts/validate.sh" \
    "/tmp/never-existed-$$.md"
  [ "$status" -ne 0 ]
}
