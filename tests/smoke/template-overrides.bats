#!/usr/bin/env bats
# Smoke tests for av_resolve_template — the 2-layer template resolver in
# shared/lib.sh. Pins slice S2 acceptance criteria from
# docs/plans/2026-05-12-speckit-gold/specs/s2-template-overrides.md.

load ../test_helper

setup() {
  setup_fresh_repo
  # Source the lib under test. ANVIL_ROOT is exported by test_helper.
  # shellcheck disable=SC1090,SC1091
  source "$ANVIL_ROOT/shared/lib.sh"
}

@test "av_resolve_template returns project override when present" {
  # Drop a stub plan-template.md into the project override slot, cd in,
  # and assert the resolver returns the override path.
  mkdir -p "$REPO_DIR/.anvil/templates/overrides"
  printf 'OVERRIDE_MARKER\n' > "$REPO_DIR/.anvil/templates/overrides/plan-template.md"
  cd "$REPO_DIR"
  run av_resolve_template plan-template.md
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_DIR/.anvil/templates/overrides/plan-template.md" ]
  # And the resolved file contains the marker we wrote — proves first-hit-wins.
  grep -q OVERRIDE_MARKER "$output"
}

@test "av_resolve_template falls back to core default when no override" {
  # Clean cwd, no override. Resolver should return the core path under
  # $(av_anvil_root)/templates/. plan-template.md ships with anvil.
  cd "$REPO_DIR"
  run av_resolve_template plan-template.md
  [ "$status" -eq 0 ]
  local expected="$(av_anvil_root)/templates/plan-template.md"
  [ "$output" = "$expected" ]
  [ -e "$output" ]
}

@test "av_resolve_template refuses path traversal" {
  cd "$REPO_DIR"
  run av_resolve_template ../foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing path traversal"* ]]
}

@test "av_resolve_template refuses leading-slash absolute path" {
  cd "$REPO_DIR"
  run av_resolve_template /etc/passwd
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing path traversal"* ]]
}

@test "av_resolve_template refuses missing argument" {
  cd "$REPO_DIR"
  run av_resolve_template
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing template name"* ]]
}

@test "av_resolve_template refuses name not found anywhere" {
  cd "$REPO_DIR"
  run av_resolve_template nonexistent-template-$$.md
  [ "$status" -ne 0 ]
  # stderr message must list both searched paths so the operator can see
  # exactly where the resolver looked.
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"project:"* ]]
  [[ "$output" == *"core:"* ]]
}

@test "av_resolve_template resolves nested name (folder template file)" {
  # Sanity: folder-layout template files resolve via the same call shape.
  cd "$REPO_DIR"
  run av_resolve_template plan-folder-template/tasks.md
  [ "$status" -eq 0 ]
  [ -e "$output" ]
  [[ "$output" == *"plan-folder-template/tasks.md" ]]
}

@test "shared/lib.sh does not introduce ANVIL_HOME (slice S2 invariant)" {
  # The slice checklist greps for ANVIL_HOME in shared/lib.sh and fails if
  # present. Pin it here so future edits can't silently reintroduce it.
  run grep -n 'ANVIL_HOME' "$ANVIL_ROOT/shared/lib.sh"
  [ "$status" -ne 0 ]
}
