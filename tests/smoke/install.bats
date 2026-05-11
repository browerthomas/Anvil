#!/usr/bin/env bats
# Smoke test for bin/install.sh — full install against a throwaway HOME.

load ../test_helper

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME"
  export FAKE_HOME
}

@test "install.sh script passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/bin/install.sh"
  [ "$status" -eq 0 ]
}

@test "install.sh --help emits usage" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --help
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "install.sh creates ~/.claude/skills and symlinks every skill" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills" ]
  # Each anvil skill should have a corresponding entry.
  for sk in "$ANVIL_ROOT"/skills/*/; do
    sk_name=$(basename "${sk%/}")
    if [ ! -e "$FAKE_HOME/.claude/skills/$sk_name" ]; then
      echo "missing installed skill: $sk_name" >&2
      return 1
    fi
  done
}

@test "install.sh second run is idempotent (no error)" {
  env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" >/dev/null
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh"
  [ "$status" -eq 0 ]
}

@test "install.sh rejects unknown flag" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --bogus
  [ "$status" -ne 0 ]
}

@test "install.sh --copy mode actually copies (not symlinks)" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --copy
  [ "$status" -eq 0 ]
  # Pick any installed skill and confirm it's a directory, not a symlink.
  for sk in "$FAKE_HOME"/.claude/skills/*/; do
    [ ! -L "${sk%/}" ]
    break
  done
}
