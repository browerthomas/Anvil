#!/usr/bin/env bats
# Smoke tests for /pre-merge-gate/scripts/verify.sh.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "pre-merge-gate verify.sh errors without PR or branch" {
  run bash "$ANVIL_ROOT/skills/pre-merge-gate/scripts/verify.sh"
  [ "$status" -ne 0 ]
}

@test "pre-merge-gate verify.sh rejects unknown flag" {
  run bash "$ANVIL_ROOT/skills/pre-merge-gate/scripts/verify.sh" some-branch --bogus
  # The script may exit non-zero on unknown arg; either ne 0 status or
  # the word "unknown" surfaces somewhere.
  if [ "$status" -ne 0 ]; then
    return 0
  fi
  [[ "$output" == *"unknown"* ]] || [[ "$output" == *"BLOCKED"* ]]
}

@test "pre-merge-gate verify.sh passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/skills/pre-merge-gate/scripts/verify.sh"
  [ "$status" -eq 0 ]
}
