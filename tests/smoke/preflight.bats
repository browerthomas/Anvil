#!/usr/bin/env bats
# Smoke test for bin/preflight.sh — prerequisite check.

load ../test_helper

@test "preflight.sh script passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/bin/preflight.sh"
  [ "$status" -eq 0 ]
}

@test "preflight.sh runs and reports a summary line" {
  # Exit code may be 0 (clean) or 1 (missing required tools). Either way
  # the script must reach the end and print the summary.
  run env HOME="$BATS_TEST_TMPDIR/home" bash "$ANVIL_ROOT/bin/preflight.sh"
  # Status: 0 if all required passed, 1 if anything missing.
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" == *"REQUIRED tools"* ]]
  [[ "$output" == *"OPTIONAL tools"* ]]
}

@test "preflight.sh covers all required-tool checks" {
  run env HOME="$BATS_TEST_TMPDIR/home" bash "$ANVIL_ROOT/bin/preflight.sh"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  # Mentions each required tool by name.
  [[ "$output" == *"git"* ]]
  [[ "$output" == *"GitHub CLI"* ]] || [[ "$output" == *"gh"* ]]
  [[ "$output" == *"Node"* ]]
  [[ "$output" == *"npm"* ]]
  [[ "$output" == *"jq"* ]]
}
