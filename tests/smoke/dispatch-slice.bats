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

@test "dispatch-slice SKILL.md Step 4 pseudocode places build-prompt.sh BEFORE Agent({ (anvil#65 ordering ratchet)" {
  # Issue #65: dispatch-slice/SKILL.md claims build-prompt.sh emits the on-disk
  # prompt BEFORE Agent({...}) is invoked. The existing bats tests only assert
  # the on-disk file exists AFTER build-prompt.sh returns — a future refactor
  # that moves the write to a post-Agent hook would pass those tests while
  # silently regressing the operator-visible paper trail. This ratchet pins
  # the documented contract: Step 4's pseudocode (the first fenced code block
  # under "### Step 4") MUST place build-prompt.sh lexically before Agent({.
  local skill_md="$ANVIL_ROOT/skills/dispatch-slice/SKILL.md"
  [ -f "$skill_md" ]
  # Extract the first fenced code block under "### Step 4". Walks Step 4 from
  # the heading, picks up content between the first pair of triple-backtick
  # fences, and emits line numbers so we can compare ordering.
  local step4_pseudocode
  step4_pseudocode=$(awk '
    /^### Step 4/ { in_step=1; fence_seen=0; next }
    in_step && /^### Step / { exit }
    in_step && /^```/ {
      if (fence_seen == 0) { fence_seen=1; next }
      else                 { exit }
    }
    in_step && fence_seen == 1 { print NR "\t" $0 }
  ' "$skill_md")
  [ -n "$step4_pseudocode" ] || { echo "Step 4 has no fenced pseudocode block"; return 1; }
  # First line in the pseudocode that invokes build-prompt.sh.
  local build_prompt_line
  build_prompt_line=$(echo "$step4_pseudocode" | grep -F "build-prompt.sh" | head -n 1 | cut -f1)
  # First line in the pseudocode that invokes Agent({.
  local agent_invoke_line
  agent_invoke_line=$(echo "$step4_pseudocode" | grep -F "Agent({" | head -n 1 | cut -f1)
  # Both must be present in the pseudocode …
  [ -n "$build_prompt_line" ] || { echo "Step 4 pseudocode missing build-prompt.sh invocation"; return 1; }
  [ -n "$agent_invoke_line" ] || { echo "Step 4 pseudocode missing Agent({ invocation";    return 1; }
  # … and build-prompt.sh must come first.
  if [ "$build_prompt_line" -ge "$agent_invoke_line" ]; then
    echo "build-prompt.sh (line $build_prompt_line) must appear BEFORE Agent({ (line $agent_invoke_line) in Step 4 pseudocode"
    return 1
  fi
}
