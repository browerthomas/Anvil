#!/usr/bin/env bats
# Smoke tests: every SKILL.md's bash fenced blocks pass `bash -n` after
# common placeholder substitution. Covers all 16 skills (whether or not
# they have a script too — bash blocks are part of the procedure docs).

load ../test_helper

setup() {
  setup_fresh_repo
}

# Helper used by each test to syntax-check a skill's bash blocks.
check_md_bash() {
  local sk_name="$1"
  local sk_md="$ANVIL_ROOT/skills/$sk_name/SKILL.md"
  if [ ! -f "$sk_md" ]; then
    skip "$sk_name SKILL.md not present"
  fi
  local out_sh="$BATS_TEST_TMPDIR/${sk_name//\//_}.sh"
  extract_md_bash_blocks "$sk_md" "$out_sh"
  if [ ! -s "$out_sh" ]; then
    skip "$sk_name SKILL.md has no bash blocks"
  fi
  bash -n "$out_sh"
}

@test "auto-merge SKILL.md bash blocks parse" {
  check_md_bash auto-merge
}

@test "config-bootstrap SKILL.md bash blocks parse" {
  check_md_bash config-bootstrap
}

@test "dispatch-slice SKILL.md bash blocks parse" {
  check_md_bash dispatch-slice
}

@test "dual-review SKILL.md bash blocks parse" {
  check_md_bash dual-review
}

@test "findings-rollup SKILL.md bash blocks parse" {
  check_md_bash findings-rollup
}

@test "grind SKILL.md bash blocks parse" {
  check_md_bash grind
}

@test "issue-to-spec SKILL.md bash blocks parse" {
  check_md_bash issue-to-spec
}

@test "learn SKILL.md bash blocks parse" {
  check_md_bash learn
}

@test "persona SKILL.md bash blocks parse" {
  check_md_bash persona
}

@test "post-merge-debrief SKILL.md bash blocks parse" {
  check_md_bash post-merge-debrief
}

@test "pre-merge-gate SKILL.md bash blocks parse" {
  check_md_bash pre-merge-gate
}

@test "recap SKILL.md bash blocks parse" {
  check_md_bash recap
}

@test "refine-plan SKILL.md bash blocks parse" {
  check_md_bash refine-plan
}

@test "self-review SKILL.md bash blocks parse" {
  check_md_bash self-review
}

@test "spec SKILL.md bash blocks parse" {
  check_md_bash spec
}

@test "sweep-worktrees SKILL.md bash blocks parse" {
  check_md_bash sweep-worktrees
}
