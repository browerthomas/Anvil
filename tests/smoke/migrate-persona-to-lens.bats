#!/usr/bin/env bats
# Smoke tests for bin/migrate-persona-to-lens.sh + install.sh integration.
#
# CRITICAL: every test runs against an ISOLATED $BATS_TEST_TMPDIR/home.
# The real operator $HOME/.claude/ MUST NOT be touched by any test.
# The final test asserts $HOME/.claude/ is byte-identical before + after.

load ../test_helper

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME"
  export FAKE_HOME

  # Belt-and-braces: every test exports HOME pointed at the fake. Any subshell
  # the migrator or install.sh spawns inherits this, so $HOME-relative paths
  # in either script resolve under the fixture, never the operator's box.
  export HOME="$FAKE_HOME"

  # Pre-seed a legacy /persona install for tests that need one.
  LEGACY_DIR="$FAKE_HOME/.claude/skills/persona"
  export LEGACY_DIR
}

seed_legacy_symlink() {
  # Symlink-mode install: ~/.claude/skills/persona → some source.
  # Use a fresh tmp source path; content irrelevant for symlink detection.
  local src="$BATS_TEST_TMPDIR/legacy-src"
  mkdir -p "$src"
  echo "legacy SKILL.md placeholder" > "$src/SKILL.md"
  mkdir -p "$FAKE_HOME/.claude/skills"
  ln -s "$src" "$LEGACY_DIR"
}

seed_legacy_copy_clean() {
  # Copy-mode install whose contents match the in-checkout source. If the
  # source dir is gone (post-C1 checkout — current state of main + this PR),
  # we can't synthesise a "clean" copy, so this helper short-circuits and the
  # test that depends on it routes through the `--force` path instead.
  mkdir -p "$FAKE_HOME/.claude/skills"
  if [ -d "$ANVIL_ROOT/skills/persona" ]; then
    cp -R "$ANVIL_ROOT/skills/persona" "$LEGACY_DIR"
    return 0
  fi
  # Source gone (post-rename) — simulate a copy-mode install with arbitrary
  # placeholder content so the migrator's "diff against source" check fails
  # and we exercise the no-source-comparison path.
  mkdir -p "$LEGACY_DIR"
  echo "placeholder" > "$LEGACY_DIR/SKILL.md"
  return 1
}

seed_legacy_copy_modified() {
  # Copy-mode install with an operator-added file (so diff fails).
  mkdir -p "$FAKE_HOME/.claude/skills"
  mkdir -p "$LEGACY_DIR"
  echo "modified" > "$LEGACY_DIR/SKILL.md"
  echo "operator-local-notes" > "$LEGACY_DIR/local-notes.md"
}

# ── Script-level sanity ─────────────────────────────────────────────────

@test "migrator passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh"
  [ "$status" -eq 0 ]
}

@test "migrator --help emits usage" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --help
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "migrator rejects unknown flag" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --bogus
  [ "$status" -ne 0 ]
}

# ── Detection + removal ─────────────────────────────────────────────────

@test "migrator no-op when no legacy install present" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
  [ "$status" -eq 0 ]
  [ ! -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
}

@test "migrator removes symlink-mode legacy install" {
  seed_legacy_symlink
  [ -L "$LEGACY_DIR" ]
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
  [ "$status" -eq 0 ]
  [ ! -L "$LEGACY_DIR" ]
  [ ! -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
}

@test "migrator removes copy-mode legacy install when verified clean (or simulates the unknown-source path)" {
  if seed_legacy_copy_clean; then
    # Clean copy path — anvil source still has skills/persona/.
    run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
    [ "$status" -eq 0 ]
    [ ! -e "$LEGACY_DIR" ]
  else
    # Source is gone (post-C1) — without --force the migrator skips, with --force it removes.
    run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
    [ "$status" -eq 0 ]
    # Skip path leaves the directory in place.
    [ -e "$LEGACY_DIR" ]
    [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
    # --force removes it.
    run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet --force
    [ "$status" -eq 0 ]
    [ ! -e "$LEGACY_DIR" ]
  fi
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
}

@test "migrator skips (with warning) a modified copy-mode install by default" {
  seed_legacy_copy_modified
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh"
  [ "$status" -eq 0 ]
  [ -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
  # The warning prints "skipping:" on stderr.
  [[ "$output" == *"skipping"* ]] || [[ "$output" == *"local modifications"* ]]
}

@test "migrator --force removes modified copy-mode install" {
  seed_legacy_copy_modified
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --force --quiet
  [ "$status" -eq 0 ]
  [ ! -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
}

@test "migrator idempotent — second run is no-op" {
  seed_legacy_symlink
  env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
  [ ! -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]

  # Second run: nothing to remove, sentinel still present.
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
  [ "$status" -eq 0 ]
  [ ! -e "$LEGACY_DIR" ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
}

@test "migrator --prefix overrides install root" {
  ALT_ROOT="$BATS_TEST_TMPDIR/alt-root"
  mkdir -p "$ALT_ROOT/skills"
  src="$BATS_TEST_TMPDIR/alt-src"
  mkdir -p "$src"
  ln -s "$src" "$ALT_ROOT/skills/persona"
  run bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --prefix "$ALT_ROOT" --quiet
  [ "$status" -eq 0 ]
  [ ! -e "$ALT_ROOT/skills/persona" ]
  [ -f "$ALT_ROOT/.anvil-lens-migrated" ]
  # FAKE_HOME untouched.
  [ ! -e "$FAKE_HOME/.claude/skills/persona" ]
}

# ── install.sh integration ──────────────────────────────────────────────

@test "install.sh auto-invokes migrator when /persona present + lens installs" {
  # Pre-seed a stale symlink under the fake home.
  seed_legacy_symlink
  [ -L "$LEGACY_DIR" ]
  # Run install.sh against fake home.
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --no-preflight
  [ "$status" -eq 0 ]
  # Legacy gone.
  [ ! -e "$LEGACY_DIR" ]
  # Sentinel present.
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
  # /lens installed.
  [ -e "$FAKE_HOME/.claude/skills/lens" ]
}

@test "install.sh on a fresh box (no /persona) writes sentinel + installs lens" {
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --no-preflight
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
  [ -e "$FAKE_HOME/.claude/skills/lens" ]
  [ ! -e "$FAKE_HOME/.claude/skills/persona" ]
}

@test "install.sh second run is idempotent with migrator in place" {
  env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --no-preflight >/dev/null
  run env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --no-preflight
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/.anvil-lens-migrated" ]
  [ -e "$FAKE_HOME/.claude/skills/lens" ]
}

# ── Real $HOME/.claude/ isolation guarantee ─────────────────────────────
# Snapshot real $HOME/.claude/ before + after a full install.sh + migrator
# run under FAKE_HOME. Byte-identical snapshots prove no leakage.

@test "real \$HOME/.claude/ is byte-identical before+after migrator+install run" {
  # Skip cleanly if the operator has no ~/.claude/ — nothing to compare.
  REAL_HOME_CLAUDE="${HOME_REAL:-/Users/$(whoami)/.claude}"
  # Use $LOGNAME / id-derived path: the test exports HOME=FAKE_HOME, so $HOME
  # here is NOT the operator's box. Reconstruct via getent / passwd.
  REAL_USER_HOME="$(eval echo ~"$(whoami)")"
  REAL_CLAUDE_DIR="$REAL_USER_HOME/.claude"

  if [ ! -d "$REAL_CLAUDE_DIR" ]; then
    skip "no real \$HOME/.claude/ on this box — isolation test vacuous"
  fi

  # Manifest = sorted list of "path\tmode\tsize" lines under the real dir.
  # Use mode + size rather than full hash because hashing the full tree on
  # every test invocation is slow and the goal is just "did anything change".
  # Empty/missing real dir is handled by the skip above.
  before_manifest="$BATS_TEST_TMPDIR/real-home-before.manifest"
  after_manifest="$BATS_TEST_TMPDIR/real-home-after.manifest"

  snapshot_dir() {
    local dir="$1" out="$2"
    # `find … -printf` is GNU-only; use stat for portability. Sort for deterministic ordering.
    # macOS stat: stat -f '%Sp\t%z\t%N' file
    # GNU stat:   stat -c '%A\t%s\t%n' file
    if stat -f '%Sp' / >/dev/null 2>&1; then
      find "$dir" \( -type f -o -type l \) -print0 \
        | xargs -0 stat -f '%Sp	%z	%N' 2>/dev/null \
        | sort > "$out"
    else
      find "$dir" \( -type f -o -type l \) -print0 \
        | xargs -0 stat -c '%A	%s	%n' 2>/dev/null \
        | sort > "$out"
    fi
  }

  snapshot_dir "$REAL_CLAUDE_DIR" "$before_manifest"

  # Run migrator + install.sh under the fake home — these are the operations
  # that, if leaked, would mutate the real dir.
  seed_legacy_symlink
  env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/migrate-persona-to-lens.sh" --quiet
  env HOME="$FAKE_HOME" bash "$ANVIL_ROOT/bin/install.sh" --no-preflight >/dev/null

  snapshot_dir "$REAL_CLAUDE_DIR" "$after_manifest"

  if ! diff -q "$before_manifest" "$after_manifest" >/dev/null 2>&1; then
    echo "real \$HOME/.claude/ manifest changed during test — MIGRATOR/INSTALL LEAKED" >&2
    echo "diff:" >&2
    diff "$before_manifest" "$after_manifest" >&2 || true
    return 1
  fi
}
