#!/usr/bin/env bats
# Smoke tests for /learn-promote — draft a MEMORY.md-pasteable markdown chunk
# of high-confidence learnings recorded since a given date.
#
# Covers:
#   1. --since <date> emits markdown headers + bullets.
#   2. --min-confidence high (default) excludes medium + low confidence rows.
#   3. --min-confidence medium widens to include medium rows.
#   4. Decisions appear FIRST in the output (most-durable type-order).
#   5. Old entries (before --since) are excluded.
#   6. Empty match emits a friendly "no learnings match" footer.
#   7. --type filter narrows to a single type.
#   8. Affected slice ids included in the bullet for decision rows.

load ../test_helper

SCRIPT_PATH="$ANVIL_ROOT/skills/learn/scripts/learn-promote.sh"

# --- helpers ------------------------------------------------------------

# Seed learnings with a mix of types + confidences + dates.
seed_diverse_learnings() {
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/learnings.jsonl" <<'EOF'
{"key":"decision-redis","type":"decision","insight":"Use redis for queue retries","confidence":"high","source_skill":"manual","files":[],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-05-08T10:00:00Z","decision_type":"architecture","affected_slices":["B1","B2"]}
{"key":"flake-vitest-crash","type":"flake","insight":"Vitest worker crash under CPU contention","confidence":"high","source_skill":"/grind","files":[],"tags":[],"slice_id":null,"prior_count":2,"timestamp":"2026-05-09T10:00:00Z"}
{"key":"med-conf-row","type":"gotcha","insight":"medium confidence - excluded by high default","confidence":"medium","source_skill":"manual","files":[],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-05-09T11:00:00Z"}
{"key":"low-conf-row","type":"gotcha","insight":"low confidence - always excluded","confidence":"low","source_skill":"manual","files":[],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-05-09T12:00:00Z"}
{"key":"old-decision","type":"decision","insight":"too old","confidence":"high","source_skill":"manual","files":[],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-04-01T10:00:00Z","decision_type":"architecture"}
{"key":"recent-invariant","type":"invariant","insight":"recent high-confidence invariant","confidence":"high","source_skill":"manual","files":["vitest.config.js"],"tags":[],"slice_id":null,"prior_count":0,"timestamp":"2026-05-10T10:00:00Z"}
EOF
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

@test "learn-promote script exists + is executable" {
  [ -f "$SCRIPT_PATH" ]
  [ -x "$SCRIPT_PATH" ]
}

@test "learn-promote --since 2026-05-01 emits markdown chunk" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Learnings promote"* ]]
  [[ "$output" == *"Pasteable bullet"* ]]
}

@test "learn-promote defaults to --min-confidence high (excludes medium + low)" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  # High-confidence rows included.
  [[ "$output" == *"decision-redis"* ]]
  [[ "$output" == *"flake-vitest-crash"* ]]
  [[ "$output" == *"recent-invariant"* ]]
  # Medium + low excluded.
  [[ "$output" != *"med-conf-row"* ]]
  [[ "$output" != *"low-conf-row"* ]]
}

@test "learn-promote --min-confidence medium widens to include medium rows" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01 --min-confidence medium
  [ "$status" -eq 0 ]
  [[ "$output" == *"med-conf-row"* ]]
  # Low still excluded.
  [[ "$output" != *"low-conf-row"* ]]
}

@test "learn-promote --min-confidence low includes all confidences" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01 --min-confidence low
  [ "$status" -eq 0 ]
  [[ "$output" == *"low-conf-row"* ]]
  [[ "$output" == *"med-conf-row"* ]]
  [[ "$output" == *"decision-redis"* ]]
}

@test "learn-promote rejects invalid --min-confidence" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01 --min-confidence wishful
  [ "$status" -ne 0 ]
}

@test "learn-promote excludes entries older than --since" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  # old-decision is dated 2026-04-01 → must be excluded.
  [[ "$output" != *"old-decision"* ]]
}

@test "learn-promote includes old entries when --since is permissive" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-01-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"old-decision"* ]]
}

@test "learn-promote requires --since" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH"
  [ "$status" -ne 0 ]
}

@test "learn-promote rejects malformed --since (not YYYY-MM-DD)" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since "yesterday"
  [ "$status" -ne 0 ]
}

@test "learn-promote orders decisions FIRST in the output" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]

  # Extract the position of the type headers — decision must come before flake/invariant.
  decision_pos=$(echo "$output" | grep -n '^## DECISIONS' | head -1 | cut -d: -f1)
  flake_pos=$(echo "$output" | grep -n '^## FLAKES' | head -1 | cut -d: -f1)
  invariant_pos=$(echo "$output" | grep -n '^## INVARIANTS' | head -1 | cut -d: -f1)

  [ -n "$decision_pos" ]
  [ -n "$flake_pos" ]
  [ -n "$invariant_pos" ]
  [ "$decision_pos" -lt "$invariant_pos" ]
  [ "$invariant_pos" -lt "$flake_pos" ]
}

@test "learn-promote emits 'no learnings match' footer on empty match" {
  # Empty learnings.jsonl → no match.
  mkdir -p "$REPO_DIR/.anvil"
  : > "$REPO_DIR/.anvil/learnings.jsonl"

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"No learnings match"* ]]
}

@test "learn-promote --type filter narrows to a single type" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01 --type decision
  [ "$status" -eq 0 ]
  [[ "$output" == *"decision-redis"* ]]
  [[ "$output" != *"flake-vitest-crash"* ]]
  [[ "$output" != *"recent-invariant"* ]]
}

@test "learn-promote includes affected slice ids for decision rows" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  # decision-redis has affected_slices: [B1, B2]
  [[ "$output" == *"affects: B1, B2"* ]]
}

@test "learn-promote emits a Pasteable bullet line per entry" {
  seed_diverse_learnings

  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  # Every kept entry has a "Pasteable bullet" line shaped as the operator expects.
  count=$(echo "$output" | grep -c "Pasteable bullet")
  # 3 high-confidence post-2026-05-01 entries: decision-redis, flake-vitest-crash, recent-invariant.
  [ "$count" -eq 3 ]
}

@test "learn-promote handles missing learnings.jsonl gracefully" {
  # No .anvil/learnings.jsonl at all.
  run bash "$SCRIPT_PATH" --since 2026-05-01
  [ "$status" -eq 0 ]
  # Friendly info on stderr; no markdown chunk to emit.
  [[ "$output" == *"no learnings"* ]] || [[ "${stderr:-}" == *"no learnings"* ]] || \
    [[ "${output}${stderr:-}" == *"nothing"* ]] || [[ -z "$output" ]]
}
