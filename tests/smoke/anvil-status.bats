#!/usr/bin/env bats
# Smoke tests for /anvil-status — read-only text dashboard of plan state.
#
# Covers:
#   1. Dashboard prints NEXT: as the first non-blank line (folder-plan fixture).
#   2. GH_OFFLINE=1 emits the dashboard without invoking gh.
#   3. Pre-sprint sample-events.jsonl fixture parses + emits sensible output
#      (backward-compat guard — DO NOT add new event types to the fixture).
#   4. Blocked-node detection — when a dep is in `deferred` (failed) status,
#      the dependent slice appears under BLOCKED with the failing dep cited.
#   5. Cumulative test-delta footer equals the sum of per-slice tests_delta
#      values in the event log.

load ../test_helper

SCRIPT_PATH="$ANVIL_ROOT/skills/anvil-status/scripts/build-status.sh"

# --- helpers ------------------------------------------------------------

# Drop a folder-plan fixture (tasks.md only) into the test repo's docs/plans/.
seed_folder_plan() {
  mkdir -p "$REPO_DIR/docs/plans/test-plan"
  cp "$FIXTURES_DIR/folder-plan/tasks.md" "$REPO_DIR/docs/plans/test-plan/tasks.md"
}

# Init the grind event log against the folder plan.
init_event_log() {
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" init "$REPO_DIR/docs/plans/test-plan" >/dev/null
}

# Return the first non-blank line of multi-line input.
first_nonblank_line() {
  awk 'NF { print; exit }' <<< "$1"
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

@test "anvil-status NEXT: is the first non-blank line against folder-plan fixture" {
  seed_folder_plan
  init_event_log
  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  first=$(first_nonblank_line "$output")
  [[ "$first" == NEXT:* ]] || {
    echo "expected first non-blank line to start with NEXT:, got: $first" >&2
    return 1
  }
}

@test "anvil-status GH_OFFLINE=1 emits dashboard without invoking gh" {
  seed_folder_plan
  init_event_log

  # Sentinel + a PATH that excludes gh — even if gh-the-binary exists, the
  # script must not invoke it under GH_OFFLINE=1. The sentinel script also
  # confirms (a) the script never tried to call gh because the sentinel was
  # never written.
  sentinel="$BATS_TEST_TMPDIR/gh-called.flag"
  mkdir -p "$BATS_TEST_TMPDIR/gh-stub"
  cat > "$BATS_TEST_TMPDIR/gh-stub/gh" <<EOF
#!/usr/bin/env bash
echo invoked > "$sentinel"
EOF
  chmod +x "$BATS_TEST_TMPDIR/gh-stub/gh"

  run env GH_OFFLINE=1 PATH="$BATS_TEST_TMPDIR/gh-stub:$PATH" bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEXT:"* ]]
  if [ -f "$sentinel" ]; then
    echo "gh was invoked despite GH_OFFLINE=1" >&2
    return 1
  fi
}

@test "anvil-status parses pre-sprint sample-events.jsonl fixture (backward-compat guard)" {
  # Seed the fixture as-is into the test repo. The DO-NOT-ADD-NEW-EVENT-TYPES
  # sentinel at the top of the fixture is a JSON _doc line — the script must
  # tolerate it.
  mkdir -p "$REPO_DIR/.anvil"
  cp "$FIXTURES_DIR/sample-events.jsonl" "$REPO_DIR/.anvil/grind-events.jsonl"

  # Build a minimal plan matching the slice ids in the fixture (S1, S2).
  cat > "$REPO_DIR/plan.md" <<'EOF'
# Fixture plan

```yaml
slices:
  - id: S1
    depends-on: []
    acceptance: ["x"]
  - id: S2
    depends-on: [S1]
    acceptance: ["y"]
```
EOF

  # Confirm the fixture STILL contains the no-new-event-types guard.
  run head -1 "$REPO_DIR/.anvil/grind-events.jsonl"
  [[ "$output" == *"DO NOT ADD NEW EVENT TYPES"* ]] || {
    echo "fixture missing backward-compat guard — re-add it" >&2
    return 1
  }

  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEXT: S1"* ]]
  [[ "$output" == *"BLOCKED: S2"* ]]
}

@test "anvil-status BLOCKED cites the failing dep when a dep is in failed status" {
  seed_folder_plan
  init_event_log
  # Mark F1 (the dep) as deferred — F2 depends on F1, so F2 should surface
  # as BLOCKED with F1 cited under (failed: ...).
  bash "$ANVIL_ROOT/skills/grind/scripts/state.sh" mark F1 deferred "synthetic failure" >/dev/null

  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKED: F2"* ]]
  [[ "$output" == *"failed: F1"* ]] || {
    echo "expected BLOCKED line to cite failed: F1, got: $output" >&2
    return 1
  }
}

@test "anvil-status cumulative test-delta footer matches sum of per-slice deltas" {
  seed_folder_plan
  init_event_log

  # Append two synthetic slice-merged events with explicit tests_delta values.
  # Use jq -nc to keep the JSON well-formed.
  jq -nc \
    --arg t1 "2026-05-11T11:00:00Z" \
    '{t:$t1, ev:"slice-merged", slice:"F1", data:{pr_number: 100, tests_delta: 17}}' \
    >> "$REPO_DIR/.anvil/grind-events.jsonl"
  jq -nc \
    --arg t2 "2026-05-11T11:05:00Z" \
    '{t:$t2, ev:"slice-merged", slice:"F2", data:{pr_number: 101, tests_delta: 8}}' \
    >> "$REPO_DIR/.anvil/grind-events.jsonl"

  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  # 17 + 8 = 25 cumulative across 2 slices.
  [[ "$output" == *"Tests: +25 cumulative (Δ across 2 slices)"* ]] || {
    echo "expected test-delta footer = +25 across 2 slices, got: $output" >&2
    return 1
  }
}

@test "anvil-status emits friendly no-op when event log is missing" {
  # No .anvil/ at all — script should print the placeholder NEXT: line + footer
  # without erroring out.
  echo "# stub" > "$REPO_DIR/plan.md"
  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"event log empty"* ]]
  [[ "$output" == *"Tests:"* ]]
}

@test "anvil-status emits non-zero status only on usage error" {
  run bash "$SCRIPT_PATH"
  [ "$status" -ne 0 ]
}

@test "anvil-status passes bash -n syntax check" {
  run bash -n "$SCRIPT_PATH"
  [ "$status" -eq 0 ]
}
