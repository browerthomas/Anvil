#!/usr/bin/env bats
# Smoke test for /codex-review — markdown-only skill that depends on the
# external Codex CLI. We can't fire a real review (would call OpenAI), so
# the smoke test only asserts that the SKILL.md exists + is non-empty +
# parses any bash blocks under it.

load ../test_helper

@test "codex-review SKILL.md exists and is non-empty" {
  [ -s "$ANVIL_ROOT/skills/codex-review/SKILL.md" ] || skip "codex-review SKILL.md not present"
}

@test "codex-review markdown bash blocks parse" {
  local sk="$ANVIL_ROOT/skills/codex-review/SKILL.md"
  [ -f "$sk" ] || skip "codex-review SKILL.md not present"
  local out="$BATS_TEST_TMPDIR/extracted.sh"
  extract_md_bash_blocks "$sk" "$out"
  [ -s "$out" ] || skip "no bash blocks in codex-review SKILL.md"
  run bash -n "$out"
  [ "$status" -eq 0 ]
}
