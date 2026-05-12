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

@test "av_resolve_template falls through preset layer to core (preset layer deferred)" {
  # Spec scenario "preset layer deferred": ${HOME}/.anvil/presets/templates/*
  # is documented as a future extension point but MUST NOT be searched in v1.
  # Repoint HOME to a throwaway dir, drop a preset stub, and assert the
  # resolver returns the core path — never the preset path.
  HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.anvil/presets/templates"
  printf 'PRESET\n' > "$HOME/.anvil/presets/templates/plan-template.md"
  cd "$REPO_DIR"  # no project override at $PWD
  run av_resolve_template plan-template.md
  [ "$status" -eq 0 ]
  # Resolved path must NOT be the preset path; must be under av_anvil_root()/templates.
  [[ "$output" != "$HOME/.anvil/presets/templates/plan-template.md" ]]
  [[ "$output" == *"/templates/plan-template.md" ]]
  # And the resolved file content is NOT the preset marker.
  run grep -q '^PRESET$' "$output"
  [ "$status" -ne 0 ]
}

@test "av_resolve_template accepts legitimate filename containing '..' substring" {
  # The earlier `*..*` pattern over-refused any filename containing `..`.
  # The spec wording is "any `..` segment" — a path COMPONENT equal to `..`,
  # not a substring. Drop foo..bar.md as a project override and assert the
  # resolver accepts the name (returns its path).
  mkdir -p "$REPO_DIR/.anvil/templates/overrides"
  printf 'DOUBLEDOT_OK\n' > "$REPO_DIR/.anvil/templates/overrides/foo..bar.md"
  cd "$REPO_DIR"
  run av_resolve_template foo..bar.md
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_DIR/.anvil/templates/overrides/foo..bar.md" ]
}

@test "av_resolve_template refuses override symlink escape" {
  # An operator (or attacker with write access to the override tree) could
  # drop a symlink at .anvil/templates/overrides/<name> pointing at host
  # content. The resolver must refuse rather than hand back a path the
  # caller will then `cat`.
  mkdir -p "$REPO_DIR/.anvil/templates/overrides"
  ln -s /etc/passwd "$REPO_DIR/.anvil/templates/overrides/plan-template.md"
  cd "$REPO_DIR"
  run av_resolve_template plan-template.md
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing override symlink escape"* ]]
}

@test "av_resolve_template resolves when sourced from a foreign repo's git root" {
  # P0 regression: SKILL.md used to source shared/lib.sh from
  # $(git rev-parse --show-toplevel)/shared/lib.sh, which would resolve to
  # the ADOPTING project's git root — where shared/lib.sh does NOT exist.
  # The corrected pattern uses ANVIL_ROOT. Simulate it: create a fake
  # foreign repo, cd in, source ${ANVIL_ROOT}/shared/lib.sh (the real anvil
  # path), and assert av_resolve_template still resolves to a core path
  # under ${ANVIL_ROOT}/templates/.
  local foreign="$BATS_TEST_TMPDIR/foreign-project"
  mkdir -p "$foreign"
  ( cd "$foreign" && git init -q && git config user.email t@t && git config user.name t \
    && : > .gitkeep && git add .gitkeep && git commit -q -m init )
  cd "$foreign"
  # Re-source lib.sh as a SKILL would, but via ANVIL_ROOT (the documented
  # pattern post-fix). ANVIL_ROOT is already exported by test_helper.
  # shellcheck disable=SC1090,SC1091
  source "${ANVIL_ROOT}/shared/lib.sh"
  run av_resolve_template plan-template.md
  [ "$status" -eq 0 ]
  [[ "$output" == "${ANVIL_ROOT}/templates/"* ]]
  [ -e "$output" ]
}
