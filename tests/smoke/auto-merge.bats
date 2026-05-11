#!/usr/bin/env bats
# Smoke tests for /auto-merge/scripts/merge.sh. Full merge flow requires
# gh + an open PR; here we only assert argument validation + syntax.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "auto-merge merge.sh errors without PR number" {
  run bash "$ANVIL_ROOT/skills/auto-merge/scripts/merge.sh"
  [ "$status" -ne 0 ]
}

@test "auto-merge merge.sh errors on non-numeric PR arg" {
  run bash "$ANVIL_ROOT/skills/auto-merge/scripts/merge.sh" not-a-number
  [ "$status" -ne 0 ]
}

@test "auto-merge merge.sh script passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/skills/auto-merge/scripts/merge.sh"
  [ "$status" -eq 0 ]
}
