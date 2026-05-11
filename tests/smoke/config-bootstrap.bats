#!/usr/bin/env bats
# Smoke tests for /config-bootstrap/scripts/derive-rules.sh.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "config-bootstrap derive-rules emits TSV from fixture context doc" {
  run bash "$ANVIL_ROOT/skills/config-bootstrap/scripts/derive-rules.sh" \
    "$FIXTURES_DIR/sample-context-doc.md"
  [ "$status" -eq 0 ]
  # Output is non-empty.
  [ -n "$output" ]
}

@test "config-bootstrap derive-rules captures forbidden-pattern lines" {
  run bash "$ANVIL_ROOT/skills/config-bootstrap/scripts/derive-rules.sh" \
    "$FIXTURES_DIR/sample-context-doc.md"
  [ "$status" -eq 0 ]
  # The fixture has "DO NOT commit `.env`" — derive should classify as forbidden.
  echo "$output" | grep -q "^forbidden	"
}

@test "config-bootstrap derive-rules captures dispatch lines" {
  run bash "$ANVIL_ROOT/skills/config-bootstrap/scripts/derive-rules.sh" \
    "$FIXTURES_DIR/sample-context-doc.md"
  [ "$status" -eq 0 ]
  # The fixture has "Every PR must..." and "Always run...".
  echo "$output" | grep -q "^dispatch	"
}

@test "config-bootstrap derive-rules captures flake lines" {
  run bash "$ANVIL_ROOT/skills/config-bootstrap/scripts/derive-rules.sh" \
    "$FIXTURES_DIR/sample-context-doc.md"
  [ "$status" -eq 0 ]
  # The fixture has "chronic" and "intermittent".
  echo "$output" | grep -q "^flake	"
}

@test "config-bootstrap derive-rules accepts stdin input" {
  run bash -c "printf 'Never use --no-verify.\nDO NOT commit .env files.\n' | bash '$ANVIL_ROOT/skills/config-bootstrap/scripts/derive-rules.sh'"
  # Output may be empty or matched — just confirm no crash on stdin path.
  [ "$status" -eq 0 ]
}
