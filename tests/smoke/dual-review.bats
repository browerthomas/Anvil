#!/usr/bin/env bats
# Smoke tests for /dual-review/scripts/capture-diff.sh.
# Full skill depends on Codex CLI + Claude sub-agent; we only smoke-test the
# diff-capture helper.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "dual-review capture-diff --help emits usage" {
  run bash "$ANVIL_ROOT/skills/dual-review/scripts/capture-diff.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"capture"* ]] || [[ "$output" == *"dual-review"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "dual-review capture-diff in a clean repo emits empty patch metadata" {
  run bash "$ANVIL_ROOT/skills/dual-review/scripts/capture-diff.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff_file="* ]]
  [[ "$output" == *"scope="* ]]
  [[ "$output" == *"line_count="* ]]
  [[ "$output" == *"too_big="* ]]
  [[ "$output" == *"codex_available="* ]]
}

@test "dual-review capture-diff captures untracked file content" {
  echo "smoke marker xyzzy" > smoke.txt
  run bash "$ANVIL_ROOT/skills/dual-review/scripts/capture-diff.sh"
  [ "$status" -eq 0 ]
  diff_file=$(echo "$output" | grep ^diff_file= | cut -d= -f2)
  [ -f "$diff_file" ]
  grep -q "smoke marker xyzzy" "$diff_file"
  rm -f "$diff_file"
}

@test "dual-review capture-diff errors when scope arg is unresolvable" {
  run bash "$ANVIL_ROOT/skills/dual-review/scripts/capture-diff.sh" not-a-branch-or-sha
  [ "$status" -ne 0 ]
}
