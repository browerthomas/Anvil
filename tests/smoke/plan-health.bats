#!/usr/bin/env bats
# Smoke tests for /plan-health — per-plan follow-up filing-vs-closing trend gate (non-blocking).
#
# Covers:
#   1. Skill script exists + invocable (frontmatter checked by skill-structure.bats).
#   2. 3-slice fixture where filing > closing × 1.5 for all 3 → flag fires
#      (event appended; gate exits 0 — never blocks).
#   3. 3-slice fixture where one of the 3 has filed ≤ closed × 1.5 → no flag.
#   4. < 3 merged slices → "insufficient" stdout, no flag, no event.
#   5. GH_OFFLINE=1 with no fixture → "skipped (offline)" + no event.
#   6. --dry-run → flag detected, snapshot to stdout, NO event appended.
#   7. /grind step h.5 documents the plan-health auto-invocation contract
#      (pin so a future edit can't silently remove the hook reference).
#   8. zero filed in window → no flag (vacuous truth — total_filed=0).

load ../test_helper

SCRIPT_PATH="$ANVIL_ROOT/skills/plan-health/scripts/check-health.sh"

# --- helpers ------------------------------------------------------------

# Seed a plan with N merged slices, each filing F follow-ups.
# Args: $1 = num slices, $2 = follow-ups per slice (always opens with sequence).
# Plus mkdir docs/plans/test-plan/tasks.md
seed_n_slice_plan() {
  local n=$1 f=$2
  local i j base_h
  mkdir -p "$REPO_DIR/.anvil"
  mkdir -p "$REPO_DIR/docs/plans/test-plan"

  # Build the YAML tasks.md
  {
    echo "# test"
    echo ""
    echo '```yaml'
    echo "slices:"
    for i in $(seq 1 "$n"); do
      printf "  - id: A%d\n" "$i"
      if [ "$i" -eq 1 ]; then
        echo "    depends-on: []"
      else
        printf "    depends-on: [A%d]\n" $((i - 1))
      fi
      echo '    acceptance: ["x"]'
    done
    echo '```'
  } > "$REPO_DIR/docs/plans/test-plan/tasks.md"

  # Build the event log
  events="$REPO_DIR/.anvil/grind-events.jsonl"
  : > "$events"

  # plan-init
  jq -nc '{
    t: "2026-05-01T00:00:00Z",
    ev: "plan-init",
    slice: "",
    data: {plan_path: "docs/plans/test-plan", slices: {}}
  }' >> "$events"

  # Per-slice: in-flight at hour H, F issues filed at H+0.5, merged at H+1
  base_h=10
  for i in $(seq 1 "$n"); do
    local in_h merged_h
    in_h=$((base_h + (i - 1) * 2))
    merged_h=$((in_h + 1))
    jq -nc --arg t "$(printf '2026-05-01T%02d:00:00Z' $in_h)" --arg slice "A$i" \
      '{t: $t, ev: "slice-in-flight", slice: $slice, data: {agent_id: "x", worktree: "/tmp"}}' >> "$events"
    if [ "$f" -gt 0 ]; then
      for j in $(seq 1 "$f"); do
        local issue_n
        issue_n=$((i * 100 + j))
        jq -nc --arg t "$(printf '2026-05-01T%02d:30:00Z' $in_h)" --argjson n "$issue_n" \
          '{t: $t, ev: "issue-filed", slice: "", data: {number: $n}}' >> "$events"
      done
    fi
    jq -nc --arg t "$(printf '2026-05-01T%02d:00:00Z' $merged_h)" --arg slice "A$i" --argjson pr "$i" \
      '{t: $t, ev: "slice-merged", slice: $slice, data: {pr_number: $pr}}' >> "$events"
  done
}

# Write a fixture marking ALL issues as OPEN (zero closures).
fixture_all_open() {
  local out="$1" n=$2 f=$3
  local issues=()
  if [ "$f" -gt 0 ]; then
    for i in $(seq 1 "$n"); do
      for j in $(seq 1 "$f"); do
        issues+=("{\"number\": $((i * 100 + j)), \"state\": \"OPEN\", \"closedAt\": null}")
      done
    done
  fi
  if [ ${#issues[@]} -eq 0 ]; then
    echo "[]" > "$out"
  else
    echo "[$(IFS=,; echo "${issues[*]}")]" | jq '.' > "$out"
  fi
}

# Write a fixture closing the FIRST slice's issues (so first slice is healthy).
fixture_first_slice_closed() {
  local out="$1" n=$2 f=$3
  local issues=()
  if [ "$f" -gt 0 ]; then
    for i in $(seq 1 "$n"); do
      for j in $(seq 1 "$f"); do
        local num=$((i * 100 + j))
        if [ "$i" -eq 1 ]; then
          # Closed by the slice's merged_at (hour 11)
          issues+=("{\"number\": $num, \"state\": \"CLOSED\", \"closedAt\": \"2026-05-01T10:45:00Z\"}")
        else
          issues+=("{\"number\": $num, \"state\": \"OPEN\", \"closedAt\": null}")
        fi
      done
    done
  fi
  if [ ${#issues[@]} -eq 0 ]; then
    echo "[]" > "$out"
  else
    echo "[$(IFS=,; echo "${issues[*]}")]" | jq '.' > "$out"
  fi
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

@test "plan-health script exists + is executable" {
  [ -f "$SCRIPT_PATH" ]
  [ -x "$SCRIPT_PATH" ]
}

@test "plan-health SKILL.md exists with frontmatter" {
  [ -f "$ANVIL_ROOT/skills/plan-health/SKILL.md" ]
  head -1 "$ANVIL_ROOT/skills/plan-health/SKILL.md" | grep -q '^---$'
}

@test "plan-health flags when 3 consecutive slices file > closed × 1.5" {
  # 3 slices, 4 issues each, zero closures → all 3 slices degraded.
  seed_n_slice_plan 3 4
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 3 4

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flagged: yes"* ]]

  # Event appended.
  grep -q '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl"
}

@test "plan-health does NOT flag when one of 3 slices is healthy" {
  # 3 slices, 4 issues each, first slice closes all 4 → first slice healthy.
  seed_n_slice_plan 3 4
  fixture_first_slice_closed "$REPO_DIR/.anvil/issues.json" 3 4

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flagged: no"* ]]

  # No event appended.
  ! grep -q '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl"
}

@test "plan-health emits 'insufficient' when fewer than 3 merged slices" {
  seed_n_slice_plan 2 4
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 2 4

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"insufficient"* ]]
  [[ "$output" == *"flagged: no"* ]]

  # No event appended.
  ! grep -q '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl"
}

@test "plan-health GH_OFFLINE=1 with no fixture → skipped (offline)" {
  seed_n_slice_plan 3 4

  run env GH_OFFLINE=1 bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (offline"* ]]

  # No event appended.
  ! grep -q '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl"
}

@test "plan-health --dry-run detects flag but does NOT append event" {
  seed_n_slice_plan 3 4
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 3 4

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"flagged: yes"* ]]
  [[ "$output" == *"dry-run"* ]]

  # No event appended even though flag fired.
  ! grep -q '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl"
}

@test "plan-health vacuous: zero filed in window → no flag" {
  # 3 slices but ZERO follow-ups → vacuous truth, never flag.
  seed_n_slice_plan 3 0
  echo "[]" > "$REPO_DIR/.anvil/issues.json"

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flagged: no"* ]]
}

@test "plan-health exits 0 even when flag fires (non-blocking contract)" {
  seed_n_slice_plan 3 4
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 3 4

  bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json" >/dev/null
  [ $? -eq 0 ]
}

@test "/grind SKILL.md documents step h.5 plan-health auto-invocation" {
  # Pin the documented integration. If a future edit removes step h.5 the
  # auto-invocation contract is broken without a test failure to flag it.
  grep -q "h\.5" "$ANVIL_ROOT/skills/grind/SKILL.md"
  grep -q "plan-health" "$ANVIL_ROOT/skills/grind/SKILL.md"
  grep -qi "non-blocking" "$ANVIL_ROOT/skills/grind/SKILL.md"
}

@test "plan-health event payload includes window, filed, closed, ratios, plan_slug" {
  seed_n_slice_plan 3 4
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 3 4

  bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" \
    --fixture "$REPO_DIR/.anvil/issues.json" >/dev/null

  ev=$(grep '"ev":"plan-health-degraded"' "$REPO_DIR/.anvil/grind-events.jsonl" | tail -1)
  echo "$ev" | jq -e '.data | has("window") and has("filed") and has("closed") and has("ratios") and has("plan_slug")' >/dev/null
  # Sanity: latest slice is A3 (newest merged).
  echo "$ev" | jq -e '.slice == "A3"' >/dev/null
  # Plan slug derived from folder name.
  echo "$ev" | jq -e '.data.plan_slug == "test-plan"' >/dev/null
}

@test "plan-health rejects missing plan path" {
  run bash "$SCRIPT_PATH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]] || [[ "${stderr:-}" == *"usage"* ]]
}

@test "plan-health rejects non-existent plan path" {
  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/does-not-exist"
  [ "$status" -ne 0 ]
}

@test "plan-health handles flat .md plan layout (uses filename stem)" {
  # Flat plan layout: docs/plans/my-flat.md, not a folder.
  seed_n_slice_plan 3 4
  # Replace the folder layout with a flat layout.
  rm -rf "$REPO_DIR/docs/plans/test-plan"
  mkdir -p "$REPO_DIR/docs/plans"
  cat > "$REPO_DIR/docs/plans/my-flat.md" <<'EOF'
# Flat plan

```yaml
slices:
  - id: A1
    depends-on: []
    acceptance: ["x"]
  - id: A2
    depends-on: [A1]
    acceptance: ["y"]
  - id: A3
    depends-on: [A2]
    acceptance: ["z"]
```
EOF
  fixture_all_open "$REPO_DIR/.anvil/issues.json" 3 4

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/my-flat.md" \
    --fixture "$REPO_DIR/.anvil/issues.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan-health: my-flat"* ]]
}
