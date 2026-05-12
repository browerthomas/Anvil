#!/usr/bin/env bats
# Smoke tests for the project-constitution slot (speckit-gold S1).
# Pins spec scenarios from docs/plans/2026-05-12-speckit-gold/specs/s1-constitution.md.
#
# Covers:
#   - av_load_constitution (shared/lib.sh)
#   - dispatch-slice/scripts/build-prompt.sh constitution prepend + on-disk emission
#   - bin/init-anvil-config.sh scaffold-from-template + non-overwrite

load ../test_helper

# ---------------------------------------------------------------------------
# av_load_constitution unit-shaped tests
# ---------------------------------------------------------------------------

setup() {
  setup_fresh_repo
  # shellcheck disable=SC1090,SC1091
  source "$ANVIL_ROOT/shared/lib.sh"
}

@test "av_load_constitution returns content when .anvil/constitution.md present" {
  mkdir -p "$REPO_DIR/.anvil"
  printf 'TEST_MARKER_CONSTITUTION\nNorth star: ship.\n' > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run av_load_constitution
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_MARKER_CONSTITUTION"* ]]
}

@test "av_load_constitution returns empty when file absent" {
  cd "$REPO_DIR"
  # .anvil/ does not exist at all in a fresh repo.
  run av_load_constitution
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "av_load_constitution returns empty when file is whitespace only" {
  mkdir -p "$REPO_DIR/.anvil"
  printf '   \n\t\n  \n' > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run av_load_constitution
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "av_load_constitution warns on non-UTF-8 and returns empty" {
  mkdir -p "$REPO_DIR/.anvil"
  # \xc3\x28 is a classic invalid UTF-8 sequence — \xc3 expects a continuation
  # byte ≥ 0x80, but 0x28 ('(') is not.
  printf '\xc3\x28 invalid bytes here\n' > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run av_load_constitution
  [ "$status" -eq 0 ]
  [[ "$output" == *"not valid UTF-8"* ]]
  # `output` from `run` concatenates stdout + stderr; assert the actual stdout
  # is empty by capturing it separately.
  local stdout_only
  stdout_only=$(av_load_constitution 2>/dev/null)
  [ -z "$stdout_only" ]
}

# ---------------------------------------------------------------------------
# build-prompt.sh integration tests
# ---------------------------------------------------------------------------

@test "dispatch-slice writes assembled prompt to .anvil/dispatched-prompts/<id>.prompt.md" {
  mkdir -p "$REPO_DIR/.anvil"
  printf 'TEST_MARKER_CONSTITUTION\nNorth star: ship boring software.\n' > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id S-test --scope "smoke"
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.anvil/dispatched-prompts/S-test.prompt.md" ]
  grep -q "## Project constitution" "$REPO_DIR/.anvil/dispatched-prompts/S-test.prompt.md"
  grep -q "TEST_MARKER_CONSTITUTION" "$REPO_DIR/.anvil/dispatched-prompts/S-test.prompt.md"
}

@test "dispatch-slice prompt is unchanged when constitution absent" {
  cd "$REPO_DIR"
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id S-clean --scope "smoke"
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.anvil/dispatched-prompts/S-clean.prompt.md" ]
  # The constitution header must NOT appear in the on-disk prompt when there
  # is no .anvil/constitution.md to source it from.
  run grep -F "## Project constitution" "$REPO_DIR/.anvil/dispatched-prompts/S-clean.prompt.md"
  [ "$status" -ne 0 ]
}

@test "dispatch-slice warns when constitution > 2KB" {
  mkdir -p "$REPO_DIR/.anvil"
  # Generate ~3KB of valid UTF-8 content.
  python3 -c "import sys; sys.stdout.write('a' * 3000 + '\n')" > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id S-big --scope "smoke"
  [ "$status" -eq 0 ]
  # `run` captures stdout + stderr. The 2KB-tier warning text:
  [[ "$output" == *"recommended ≤ 2048"* ]]
}

@test "dispatch-slice second-tier warning when constitution > 8KB" {
  mkdir -p "$REPO_DIR/.anvil"
  python3 -c "import sys; sys.stdout.write('a' * 9000 + '\n')" > "$REPO_DIR/.anvil/constitution.md"
  cd "$REPO_DIR"
  run bash "$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh" \
    --id S-huge --scope "smoke"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bloat every dispatched-agent prompt"* ]]
  # And NOT the lower-tier message (avoid double-warn confusion).
  [[ "$output" != *"recommended ≤ 2048"* ]]
}

# ---------------------------------------------------------------------------
# bin/init-anvil-config.sh scaffolding
# ---------------------------------------------------------------------------

@test "bin/init-anvil-config.sh scaffolds constitution.md on fresh init" {
  cd "$REPO_DIR"
  # Auto-confirm in case .anvil exists (it shouldn't here, but defensive).
  run bash -c "echo y | bash '$ANVIL_ROOT/bin/init-anvil-config.sh'"
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.anvil/constitution.md" ]
  # Content must come from the template — assert one of the template's
  # placeholder section headers is present.
  grep -q "## North star" "$REPO_DIR/.anvil/constitution.md"
  grep -q "## Inviolable principles" "$REPO_DIR/.anvil/constitution.md"
  grep -q "## Out of scope for every slice" "$REPO_DIR/.anvil/constitution.md"
}

@test "bin/init-anvil-config.sh does NOT overwrite existing constitution.md" {
  cd "$REPO_DIR"
  mkdir -p "$REPO_DIR/.anvil"
  printf 'PRE_EXISTING_MARKER\nOperator-authored north star.\n' > "$REPO_DIR/.anvil/constitution.md"
  # init prompts "Overwrite existing files? [y/N]" because .anvil/ exists.
  # We answer 'y' to test that even with overwrite-confirm the constitution
  # itself is preserved (constitution carries operator strategic intent — the
  # non-overwrite guard is dedicated, not gated on the global confirm).
  run bash -c "echo y | bash '$ANVIL_ROOT/bin/init-anvil-config.sh'"
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.anvil/constitution.md" ]
  grep -q "PRE_EXISTING_MARKER" "$REPO_DIR/.anvil/constitution.md"
}
