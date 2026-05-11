#!/usr/bin/env bats
# Smoke tests for /issue-to-spec/scripts/verify-issue.sh.
# Real run requires `gh` + a real issue; smoke tests only confirm argument
# validation works.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "issue-to-spec verify-issue errors without --issue" {
  run bash "$ANVIL_ROOT/skills/issue-to-spec/scripts/verify-issue.sh"
  [ "$status" -ne 0 ]
}

@test "issue-to-spec verify-issue rejects unknown flag" {
  run bash "$ANVIL_ROOT/skills/issue-to-spec/scripts/verify-issue.sh" --bogus 1
  [ "$status" -ne 0 ]
}

@test "issue-to-spec script passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/skills/issue-to-spec/scripts/verify-issue.sh"
  [ "$status" -eq 0 ]
}
