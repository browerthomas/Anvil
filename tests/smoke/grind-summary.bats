#!/usr/bin/env bats
# Smoke tests for /recap's grind-summary rollup:
#   - Per-slice totals match the synthetic event log.
#   - Multiple agents on one slice sum into a single row.
#   - PR column populated from sibling `slice-pr-opened` events.
#   - Total row sums across all slices.
#   - Orchestrator-side-tokens footer always printed.
#   - Empty / missing event log handled gracefully.
#   - Number formatting (commas + walltime) renders correctly.

load ../test_helper

SUMMARY_SCRIPT="$ANVIL_ROOT/skills/recap/scripts/grind-summary.sh"

setup() {
  setup_fresh_repo
  mkdir -p .anvil
}

# --- empty / missing event log -------------------------------------------

@test "grind-summary: missing event log prints the orchestrator footer + (no event log)" {
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/empty/
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Grind summary: docs/plans/empty/ ==="* ]]
  [[ "$output" == *"no event log"* ]]
  [[ "$output" == *"orchestrator"* ]]
  [[ "$output" == *"/cost"* ]]
}

@test "grind-summary: event log with no agent-completed events prints the friendly notice" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"_doc":"sentinel"}
{"t":"2026-05-15T10:00:00Z","ev":"plan-init","slice":"","data":{"plan_path":"docs/plans/x","slices":{}}}
{"t":"2026-05-15T10:00:01Z","ev":"slice-pending","slice":"S1","data":null}
EOF
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/x
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no agent-completed events recorded)"* ]]
  [[ "$output" == *"/cost"* ]]
}

# --- basic single-slice rollup -------------------------------------------

@test "grind-summary: single agent on single slice renders row + total" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"slice-pr-opened","slice":"B0","data":{"pr_number":949}}
{"t":"2026-05-15T10:01:00Z","ev":"agent-completed","slice":"B0","data":{"agent":"a1","model":"opus","branch":"feat-b0","total_tokens":150200,"tool_uses":88,"duration_ms":734000}}
EOF
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/test
  [ "$status" -eq 0 ]
  [[ "$output" == *"B0"* ]]
  [[ "$output" == *"#949"* ]]
  [[ "$output" == *"150,200"* ]]
  [[ "$output" == *"12m 14s"* ]]
  # Total row must carry the same numbers when there's only one slice.
  [[ "$output" == *"Total"* ]]
  [[ "$output" == *"n=1 agent"* ]]
}

# --- multiple agents on one slice sum into a single row ------------------

@test "grind-summary: two agents on the same slice sum tokens + tools + duration into one row" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"slice-pr-opened","slice":"B2","data":{"pr_number":952}}
{"t":"2026-05-15T10:01:00Z","ev":"agent-completed","slice":"B2","data":{"agent":"a2","total_tokens":180000,"tool_uses":120,"duration_ms":900000}}
{"t":"2026-05-15T10:02:00Z","ev":"agent-completed","slice":"B2","data":{"agent":"a3","total_tokens":22018,"tool_uses":20,"duration_ms":156000}}
EOF
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/test
  [ "$status" -eq 0 ]
  # 180000 + 22018 = 202018 → 202,018
  [[ "$output" == *"202,018"* ]]
  # 120 + 20 = 140
  [[ "$output" == *"140"* ]]
  # 900000 + 156000 = 1056000 ms = 17m 36s
  [[ "$output" == *"17m 36s"* ]]
  # Two-agent count on the trailing line.
  [[ "$output" == *"n=2 agents"* ]]
}

# --- multi-slice rollup matches the issue-#75 reference shape ------------

@test "grind-summary: multi-slice rollup matches reference shape (B0 + B2 from issue #75)" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"slice-pr-opened","slice":"B0","data":{"pr_number":949}}
{"t":"2026-05-15T10:01:00Z","ev":"agent-completed","slice":"B0","data":{"agent":"a1","total_tokens":150200,"tool_uses":88,"duration_ms":734000}}
{"t":"2026-05-15T10:02:00Z","ev":"slice-pr-opened","slice":"B2","data":{"pr_number":952}}
{"t":"2026-05-15T10:03:00Z","ev":"agent-completed","slice":"B2","data":{"agent":"a2","total_tokens":202018,"tool_uses":140,"duration_ms":1056000}}
EOF
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/test
  [ "$status" -eq 0 ]
  [[ "$output" == *"B0"* ]]
  [[ "$output" == *"#949"* ]]
  [[ "$output" == *"150,200"* ]]
  [[ "$output" == *"12m 14s"* ]]
  [[ "$output" == *"B2"* ]]
  [[ "$output" == *"#952"* ]]
  [[ "$output" == *"202,018"* ]]
  [[ "$output" == *"17m 36s"* ]]
  # Total
  [[ "$output" == *"352,218"* ]]    # 150200 + 202018
  [[ "$output" == *"228"* ]]        # 88 + 140
  [[ "$output" == *"n=2 agents"* ]]
}

# --- PR-less slice renders with blank PR column --------------------------

@test "grind-summary: slice with no slice-pr-opened event renders an empty PR column" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"X1","data":{"total_tokens":1000,"tool_uses":5,"duration_ms":5000}}
EOF
  run bash "$SUMMARY_SCRIPT" --plan docs/plans/test
  [ "$status" -eq 0 ]
  [[ "$output" == *"X1"* ]]
  # No "#" should appear adjacent to X1 — the row's PR column is blank.
  ! echo "$output" | grep -E '^X1[[:space:]]+#' >/dev/null
}

# --- orchestrator footer always present ----------------------------------

@test "grind-summary: orchestrator footer line always printed (acceptance of issue #75)" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"S1","data":{"total_tokens":100,"tool_uses":1,"duration_ms":1000}}
EOF
  run bash "$SUMMARY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orchestrator"* ]]
  [[ "$output" == *"/cost"* ]]
  [[ "$output" == *"parent-side tokens"* ]]
}

# --- walltime pretty-print -----------------------------------------------

@test "grind-summary: walltime formatter renders seconds / minutes / hours correctly" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"SEC","data":{"total_tokens":1,"tool_uses":1,"duration_ms":4500}}
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"MIN","data":{"total_tokens":1,"tool_uses":1,"duration_ms":734000}}
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"HRS","data":{"total_tokens":1,"tool_uses":1,"duration_ms":15120000}}
EOF
  run bash "$SUMMARY_SCRIPT"
  [ "$status" -eq 0 ]
  # < 60s → "4.5s"
  [[ "$output" == *"4.5s"* ]]
  # < 1h → "12m 14s"
  [[ "$output" == *"12m 14s"* ]]
  # ≥ 1h → "4h 12m"
  [[ "$output" == *"4h 12m"* ]]
}

# --- thousands separator -------------------------------------------------

@test "grind-summary: thousands separator formats million-scale token totals" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"BIG","data":{"total_tokens":1847221,"tool_uses":1002,"duration_ms":15120000}}
EOF
  run bash "$SUMMARY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1,847,221"* ]]
  [[ "$output" == *"1,002"* ]]
}

# --- --events flag overrides default path --------------------------------

@test "grind-summary: --events <path> reads the named file (not .anvil/)" {
  # Stash events under a custom path; the default .anvil/grind-events.jsonl
  # is intentionally absent.
  mkdir -p /tmp/grind-summary-custom-events
  cat > /tmp/grind-summary-custom-events/log.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"CUSTOM","data":{"total_tokens":42,"tool_uses":1,"duration_ms":1000}}
EOF
  run bash "$SUMMARY_SCRIPT" --events /tmp/grind-summary-custom-events/log.jsonl
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUSTOM"* ]]
  [[ "$output" == *"42"* ]]
  rm -rf /tmp/grind-summary-custom-events
}

# --- null counter values fold as zero (defence-in-depth) -----------------

@test "grind-summary: agent-completed event with null counter fields folds as zero" {
  cat > .anvil/grind-events.jsonl <<'EOF'
{"t":"2026-05-15T10:00:00Z","ev":"agent-completed","slice":"NULL","data":{"agent":"a1","model":"opus","branch":"f","total_tokens":null,"tool_uses":null,"duration_ms":null}}
{"t":"2026-05-15T10:00:01Z","ev":"agent-completed","slice":"NULL","data":{"agent":"a2","total_tokens":100,"tool_uses":2,"duration_ms":3000}}
EOF
  run bash "$SUMMARY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NULL"* ]]
  # null + 100 = 100; null + 2 = 2; null + 3000ms = 3.0s
  [[ "$output" == *"100"* ]]
  [[ "$output" == *"3.0s"* ]] || [[ "$output" == *"3.0 s"* ]]
  # Two agents counted.
  [[ "$output" == *"n=2 agents"* ]]
}
