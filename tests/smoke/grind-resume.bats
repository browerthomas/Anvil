#!/usr/bin/env bats
# Smoke tests for /grind --resume — auto-derive resume point from event log.
#
# Covers (per tasks.md acceptance bullets):
#   1. --resume against a 3-slice plan where slice 1 is merged skips slice 1
#      + dispatches slice 2 (state.sh resume → state.sh next == S2).
#   2. --from <slice-id> still works (deprecation path tested via grind.bats
#      mark+next chain — backward compat preserved because state.sh next is
#      the same code path; this test asserts mark + next chain unchanged).
#   3. --resume twice appends 2 resume events but does not re-dispatch
#      already-merged slices.
#   4. --resume rejects a plan path that does not exist (exit non-zero).
#   5. Concurrent --resume (file lock on grind-events.jsonl.lock) — second
#      invocation prints warning + exits 0 without dispatching.
#   6. Plan with one slice marked `deferred` (failed) → --resume retries it
#      (deferred slice gets re-pended; failed != merged).
#
# Implementation notes:
#   - Tests exercise state.sh resume directly. /grind's wrapper is markdown +
#     instructions for Claude; the actual state mutation lives in state.sh.
#   - Mock dispatch: we never fire agents in tests; we assert state.sh's
#     resume output (next-slice id + event-log shape).

load ../test_helper

SCRIPT_PATH="$ANVIL_ROOT/skills/grind/scripts/state.sh"

# --- helpers ------------------------------------------------------------

# Drop a 3-slice plan into the test repo (S1 → S2 → S3 dependency chain).
seed_3slice_plan() {
  cat > "$REPO_DIR/plan.md" <<'EOF'
# 3-slice fixture
```yaml
slices:
  - id: S1
    depends-on: []
    acceptance: ["x"]
  - id: S2
    depends-on: [S1]
    acceptance: ["y"]
  - id: S3
    depends-on: [S2]
    acceptance: ["z"]
```
EOF
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

@test "grind resume against 3-slice plan with S1 merged dispatches S2" {
  seed_3slice_plan
  bash "$SCRIPT_PATH" init "$REPO_DIR/plan.md" >/dev/null
  bash "$SCRIPT_PATH" mark S1 merged >/dev/null

  run bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  # state.sh resume echoes the next-ready slice id on its own line.
  [[ "$output" == *"S2"* ]]
  # Confirm via the topo-sort that S2 is also next.
  next=$(bash "$SCRIPT_PATH" next)
  [ "$next" = "S2" ]
}

@test "grind --from path: mark + next chain still works (deprecation alias preserved)" {
  # --from is the deprecated alias. /grind's flag-parser is markdown; the
  # underlying chain mark+next is what --from used. This test asserts the
  # chain is unchanged (backward-compat for any existing operator scripts).
  seed_3slice_plan
  bash "$SCRIPT_PATH" init "$REPO_DIR/plan.md" >/dev/null
  bash "$SCRIPT_PATH" mark S1 merged >/dev/null

  # next should pick S2 (S1 is merged → S2's dep is satisfied)
  run bash "$SCRIPT_PATH" next
  [ "$status" -eq 0 ]
  [ "$output" = "S2" ]
}

@test "grind resume twice appends 2 resume events without re-dispatching merged slices" {
  seed_3slice_plan
  bash "$SCRIPT_PATH" init "$REPO_DIR/plan.md" >/dev/null
  bash "$SCRIPT_PATH" mark S1 merged >/dev/null

  bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md" >/dev/null
  bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md" >/dev/null

  # Two resume events appended.
  resume_count=$(jq -s 'map(select(.ev == "resume")) | length' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$resume_count" -eq 2 ]

  # S1 still merged (not re-pended).
  s1_status=$(jq -r '.slices.S1.status' "$REPO_DIR/.anvil/grind-snapshot.json")
  [ "$s1_status" = "merged" ]
}

@test "grind resume rejects a plan path that does not exist" {
  run bash "$SCRIPT_PATH" resume "$REPO_DIR/nonexistent-plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan not found"* ]]
}

@test "grind resume — concurrent invocation hits file lock + exits 0 with warning" {
  seed_3slice_plan
  bash "$SCRIPT_PATH" init "$REPO_DIR/plan.md" >/dev/null

  # Simulate another in-flight --resume by pre-creating the lock dir.
  mkdir "$REPO_DIR/.anvil/grind-events.jsonl.lock"

  run bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"another /grind --resume is in flight"* ]] || {
    echo "expected lock-held warning, got: $output" >&2
    return 1
  }

  # No resume event was appended (lock prevented mutation).
  resume_count=$(jq -s 'map(select(.ev == "resume")) | length' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$resume_count" -eq 0 ]

  # Clean up the synthetic lock so any later teardown doesn't trip on it.
  rm -rf "$REPO_DIR/.anvil/grind-events.jsonl.lock"
}

@test "grind resume retries a deferred (failed) slice — failed != merged" {
  seed_3slice_plan
  bash "$SCRIPT_PATH" init "$REPO_DIR/plan.md" >/dev/null
  # Mark S1 deferred (failed CI / blocked PR / etc.). S1 should be retried
  # on resume — i.e. status reverts to pending so next picks it.
  bash "$SCRIPT_PATH" mark S1 deferred "synthetic CI failure" >/dev/null

  # Sanity: before resume, S1 is deferred.
  status_before=$(jq -r '.slices.S1.status' "$REPO_DIR/.anvil/grind-snapshot.json")
  [ "$status_before" = "deferred" ]

  run bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  # The next-ready slice is S1 (retry path).
  [[ "$output" == *"S1"* ]]

  # After resume, S1 is back to pending.
  status_after=$(jq -r '.slices.S1.status' "$REPO_DIR/.anvil/grind-snapshot.json")
  [ "$status_after" = "pending" ]

  # The resume event records resumed_from=S1.
  resumed_from=$(jq -rs 'map(select(.ev == "resume")) | last | .data.resumed_from' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$resumed_from" = "S1" ]
}

@test "grind resume initializes the event log if it does not exist" {
  # No prior init — resume should bootstrap the event log.
  seed_3slice_plan

  [ ! -f "$REPO_DIR/.anvil/grind-events.jsonl" ]

  run bash "$SCRIPT_PATH" resume "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.anvil/grind-events.jsonl" ]

  # fresh_init flag is set on the resume event.
  fresh=$(jq -rs 'map(select(.ev == "resume")) | last | .data.fresh_init' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$fresh" = "true" ]
}

@test "grind resume passes bash -n syntax check" {
  run bash -n "$SCRIPT_PATH"
  [ "$status" -eq 0 ]
}
