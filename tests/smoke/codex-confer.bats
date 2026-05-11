#!/usr/bin/env bats
# Smoke test for /codex-confer — markdown-only, depends on Codex CLI.

load ../test_helper

@test "codex-confer SKILL.md exists and is non-empty" {
  [ -s "$ANVIL_ROOT/skills/codex-confer/SKILL.md" ] || skip "codex-confer SKILL.md not present"
}

@test "codex-confer markdown bash blocks parse" {
  local sk="$ANVIL_ROOT/skills/codex-confer/SKILL.md"
  [ -f "$sk" ] || skip "codex-confer SKILL.md not present"
  local out="$BATS_TEST_TMPDIR/extracted.sh"
  extract_md_bash_blocks "$sk" "$out"
  [ -s "$out" ] || skip "no bash blocks in codex-confer SKILL.md"
  run bash -n "$out"
  [ "$status" -eq 0 ]
}
