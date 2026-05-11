#!/usr/bin/env bats
# Smoke tests for /findings-rollup scripts.

load ../test_helper

setup() {
  setup_fresh_repo
}

@test "findings-rollup parse-review extracts a valid JSON shape" {
  run bash "$ANVIL_ROOT/skills/findings-rollup/scripts/parse-review.sh" \
    "$FIXTURES_DIR/sample-review.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.p0 and .p1 and .p2 and .p3 and .verdict' >/dev/null
}

@test "findings-rollup parse-review detects BLOCK verdict" {
  run bash "$ANVIL_ROOT/skills/findings-rollup/scripts/parse-review.sh" \
    "$FIXTURES_DIR/sample-review.md"
  [ "$status" -eq 0 ]
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "BLOCK" ]
}

@test "findings-rollup parse-review emits P0 entries when present" {
  run bash "$ANVIL_ROOT/skills/findings-rollup/scripts/parse-review.sh" \
    "$FIXTURES_DIR/sample-review.md"
  [ "$status" -eq 0 ]
  p0_count=$(echo "$output" | jq -r '.p0 | length')
  [ "$p0_count" -gt 0 ]
}

@test "findings-rollup parse-review handles stdin input" {
  run bash -c "cat '$FIXTURES_DIR/sample-review.md' | bash '$ANVIL_ROOT/skills/findings-rollup/scripts/parse-review.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict' >/dev/null
}

@test "findings-rollup dispatch-fixup requires --review and --pr" {
  run bash "$ANVIL_ROOT/skills/findings-rollup/scripts/dispatch-fixup.sh"
  [ "$status" -ne 0 ]
}

@test "findings-rollup dispatch-fixup rejects missing review file" {
  run bash "$ANVIL_ROOT/skills/findings-rollup/scripts/dispatch-fixup.sh" \
    --review /tmp/does-not-exist-$$.md --pr 1
  [ "$status" -ne 0 ]
}
