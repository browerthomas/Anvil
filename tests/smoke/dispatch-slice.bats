#!/usr/bin/env bats
# Smoke tests for /dispatch-slice/scripts/build-prompt.sh.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "dispatch-slice build-prompt requires --id and --scope" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh"
  [ "$status" -ne 0 ]
}

@test "dispatch-slice build-prompt emits prompt with required sections" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id smoke-1 \
    --scope "Implement the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Worktree"* ]]
  [[ "$output" == *"Scope"* ]]
  [[ "$output" == *"Hard constraints"* ]]
  [[ "$output" == *"Procedure"* ]]
  [[ "$output" == *"Return shape"* ]]
}

@test "dispatch-slice build-prompt embeds the scope text" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id smoke-2 \
    --scope "Sentinel scope marker xyzzy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sentinel scope marker xyzzy"* ]]
}

@test "dispatch-slice build-prompt embeds the slice id" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id slice-uniq-42 \
    --scope "x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"slice-uniq-42"* ]]
}

@test "dispatch-slice build-prompt with --issue references the issue number" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id smoke-3 \
    --scope "x" \
    --issue 999
  [ "$status" -eq 0 ]
  [[ "$output" == *"#999"* ]]
}

@test "dispatch-slice build-prompt with --no-codex omits the codex review section" {
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id smoke-4 --scope "x" --no-codex
  [ "$status" -eq 0 ]
  # The codex section title is "## Review" — absent when --no-codex is passed.
  [[ "$output" != *"## Review"* ]]
}
