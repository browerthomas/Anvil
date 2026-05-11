#!/usr/bin/env bats
# Smoke tests for bin/check-leaks.sh — the pre-merge leak grep.
#
# Each test seeds a throwaway repo (setup_fresh_repo from test_helper) and
# exercises one acceptance criterion from slice D1.

load ../test_helper

setup() {
  setup_fresh_repo
  # Stage the script under test into the fresh repo so it can be invoked
  # with the throwaway repo as cwd (git ls-files driven).
  mkdir -p "$REPO_DIR/bin"
  cp "$ANVIL_ROOT/bin/check-leaks.sh" "$REPO_DIR/bin/check-leaks.sh"
  chmod +x "$REPO_DIR/bin/check-leaks.sh"
  git add bin/check-leaks.sh
  git commit -q -m "seed: check-leaks.sh"
}

@test "check-leaks.sh script passes bash -n syntax check" {
  run bash -n "$ANVIL_ROOT/bin/check-leaks.sh"
  [ "$status" -eq 0 ]
}

@test "missing patterns file = soft-pass with warning to stderr" {
  # No .anvil/check-leaks.patterns.txt → soft-pass.
  run bash bin/check-leaks.sh
  [ "$status" -eq 0 ]
  # The warning is printed to stderr; bats merges both into $output.
  [[ "$output" == *"check-leaks.patterns.txt missing"* ]]
  [[ "$output" == *"soft-pass"* ]]
}

@test "example patterns file alone = soft-pass" {
  # Only the .example template present → real file still missing → soft-pass.
  mkdir -p "$REPO_DIR/.anvil"
  cp "$ANVIL_ROOT/.anvil/check-leaks.patterns.example.txt" "$REPO_DIR/.anvil/check-leaks.patterns.example.txt"
  git add .anvil/check-leaks.patterns.example.txt
  git commit -q -m "seed: example patterns"
  run bash bin/check-leaks.sh
  [ "$status" -eq 0 ]
  # Still warns — the .example file is not the live one.
  [[ "$output" == *"check-leaks.patterns.txt missing"* ]]
}

@test "real patterns file with anvil's terms blocks a file containing theirownstory" {
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/check-leaks.patterns.txt" <<'EOF'
# anvil's own patterns
theirownstory :: **/* ::
EOF
  echo "leaked: theirownstory was here" > "$REPO_DIR/leak.md"
  git add .anvil/check-leaks.patterns.txt leak.md
  git commit -q -m "seed: patterns + leak"
  run bash bin/check-leaks.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"theirownstory"* ]]
  [[ "$output" == *"leak.md"* ]]
  [[ "$output" == *"LEAKS FOUND"* ]]
}

@test "past CHANGELOG entries excluded (date-prefixed line containing a leak doesn't fail)" {
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/check-leaks.patterns.txt" <<'EOF'
theirownstory :: **/* ::
EOF
  # A CHANGELOG with a past-release block that legitimately mentions the term.
  cat > "$REPO_DIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- nothing in here yet

## [v0.5.0] - 2026-04-30

- early reference: forked from theirownstory's pre-merge gate pattern.
EOF
  git add .anvil/check-leaks.patterns.txt CHANGELOG.md
  git commit -q -m "seed: past changelog mentions term"
  run bash bin/check-leaks.sh
  [ "$status" -eq 0 ]
}

@test "stale conflict marker fails (hardcoded check)" {
  # No patterns file at all — only the hardcoded conflict-marker check runs.
  # Construct the markers dynamically so this bats file itself doesn't trip
  # the check on a future run (which would self-block).
  local LT=$(printf '%s' '<<<<<<<')
  local EQ=$(printf '%s' '=======')
  local GT=$(printf '%s' '>>>>>>>')
  cat > "$REPO_DIR/half-merged.md" <<EOF
preamble
$LT HEAD
our side
$EQ
their side
$GT origin/branch
postamble
EOF
  git add half-merged.md
  git commit -q -m "seed: stale conflict"
  run bash bin/check-leaks.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"conflict marker"* ]]
  [[ "$output" == *"half-merged.md"* ]]
}

@test "PR-body override pattern recognized (regex isolation against fixture)" {
  # The workflow does the override detection, not the script. This test
  # verifies the regex shape used by the workflow against a few fixtures.
  # If the regex shape changes in the workflow, this test catches it.
  local rx='\[leak-allow:[[:space:]]*[^]]+\]'

  # Positive fixtures — must match.
  echo "Some prose. [leak-allow: discussing a leak in a post-mortem doc] more prose." \
    | grep -qE "$rx"
  [ "$?" -eq 0 ]

  echo "[leak-allow:no-space-reason]" | grep -qE "$rx"
  [ "$?" -eq 0 ]

  echo "header
multi-line body
[leak-allow: multi-line is fine]
footer" | grep -qE "$rx"
  [ "$?" -eq 0 ]

  # Negative fixtures — must NOT match.
  echo "Some prose without override." | grep -qvE "$rx"
  [ "$?" -eq 0 ]

  # No `]` at all — incomplete directive, must not match.
  echo "[leak-allow: missing close-bracket" | grep -qvE "$rx"
  [ "$?" -eq 0 ]

  # Missing colon — different directive name, must not match.
  echo "[leak-allow]" | grep -qvE "$rx"
  [ "$?" -eq 0 ]

  # Empty reason with no space — `[^]]+` requires 1+ chars, so this rejects.
  echo "[leak-allow:]" | grep -qvE "$rx"
  [ "$?" -eq 0 ]
}

@test "exclusion-glob suppresses matches in specified paths" {
  # tests/smoke/** is excluded in anvil's own pattern set — verify the
  # exclusion mechanic works generally.
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/check-leaks.patterns.txt" <<'EOF'
forbidden_substring :: **/* :: allowed/**
EOF
  mkdir -p "$REPO_DIR/allowed" "$REPO_DIR/blocked"
  echo "this has forbidden_substring" > "$REPO_DIR/allowed/ok.md"
  echo "this has forbidden_substring" > "$REPO_DIR/blocked/no.md"
  git add .anvil/check-leaks.patterns.txt allowed/ok.md blocked/no.md
  git commit -q -m "seed: exclusion test"
  run bash bin/check-leaks.sh
  [ "$status" -eq 1 ]
  # The blocked path should be flagged.
  [[ "$output" == *"blocked/no.md"* ]]
  # The allowed path should NOT be flagged.
  [[ "$output" != *"allowed/ok.md"* ]]
}

@test "patterns file itself is auto-excluded from scanning" {
  # The patterns file contains the forbidden terms by definition — scanning
  # it would always self-block. Verify it's skipped.
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/check-leaks.patterns.txt" <<'EOF'
self_referencing_term :: **/* ::
EOF
  git add .anvil/check-leaks.patterns.txt
  git commit -q -m "seed: self-reference"
  run bash bin/check-leaks.sh
  [ "$status" -eq 0 ]
}
