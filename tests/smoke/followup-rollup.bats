#!/usr/bin/env bats
# Smoke tests for /followup-rollup — consolidates open follow-up issues for a
# multi-slice plan into a markdown rollup grouped by severity + area.
#
# Covers:
#   1. Zero matching issues — outputs the friendly "no follow-ups" placeholder
#      + the prefix-enforcement gap note.
#   2. One follow-up per slice (3 slices, 3 issues) — output groups them under
#      per-slice tally AND severity summary.
#   3. Issues without the [<plan>-<slice> followup] prefix → excluded from
#      every section of the rollup.
#   4. Severity grouping — label, title-token, body-marker, fallback all
#      bucket correctly (synthesised fixture covers all four routes).
#   5. Area grouping — label-driven AND title-keyword-heuristic both resolve
#      to the correct bucket.

load ../test_helper

SCRIPT_PATH="$ANVIL_ROOT/skills/followup-rollup/scripts/build-rollup.sh"

# --- helpers ------------------------------------------------------------

# Drop a folder-plan fixture (tasks.md only) into the test repo's docs/plans/.
# Uses a controllable slug name so the title-prefix regex stays predictable.
seed_folder_plan() {
  local slug="${1:-test-plan}"
  mkdir -p "$REPO_DIR/docs/plans/$slug"
  cat > "$REPO_DIR/docs/plans/$slug/tasks.md" <<'EOF'
# Test plan — tasks

```yaml
slices:
  - id: S1
    name: first
    depends-on: []
    acceptance:
      - "Test: S1 lands"
  - id: S2
    name: second
    depends-on:
      - S1
    acceptance:
      - "Test: S2 lands after S1"
  - id: S3
    name: third
    depends-on:
      - S2
    acceptance:
      - "Test: S3 lands after S2"
```
EOF
}

# Write a JSON fixture array of issues to a tmp file + echo the path.
write_fixture() {
  local path="$BATS_TEST_TMPDIR/issues-$$.json"
  echo "$1" > "$path"
  echo "$path"
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

# ── 1. Zero matching issues ───────────────────────────────────────────
@test "followup-rollup: zero issues prints friendly placeholder + gap note" {
  seed_folder_plan "test-plan"
  fixture=$(write_fixture '[]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" --fixture "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Open follow-ups:** 0"* ]]
  [[ "$output" == *"no issues match"* ]]
  # The gap-note one-liner about /findings-rollup / /grind must appear.
  [[ "$output" == *"/findings-rollup"* ]]
  [[ "$output" == *"/grind"* ]]
}

# ── 2. One follow-up per slice — 3 slices, 3 issues ────────────────────
@test "followup-rollup: 3 issues across 3 slices groups by slice + severity" {
  seed_folder_plan "test-plan"
  fixture=$(write_fixture '[
    {"number":101,"url":"https://x/101","title":"[test-plan-S1 followup] missing test coverage for foo","body":"","labels":[{"name":"p2"},{"name":"test-coverage"}]},
    {"number":102,"url":"https://x/102","title":"[test-plan-S2 followup] race condition in bar","body":"","labels":[{"name":"p1"},{"name":"correctness"}]},
    {"number":103,"url":"https://x/103","title":"[test-plan-S3 followup] missing observability dashboard","body":"","labels":[{"name":"p3"},{"name":"operability"}]}
  ]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" --fixture "$fixture"
  [ "$status" -eq 0 ]
  # Header reflects the totals.
  [[ "$output" == *"Open follow-ups:** 3 issues across 3 slices"* ]]
  # Each issue appears in the area breakdown.
  [[ "$output" == *"#101"* ]]
  [[ "$output" == *"#102"* ]]
  [[ "$output" == *"#103"* ]]
  # Per-slice tally has a row per slice.
  [[ "$output" == *"| S1 |"* ]]
  [[ "$output" == *"| S2 |"* ]]
  [[ "$output" == *"| S3 |"* ]]
}

# ── 3. Issues without the prefix are excluded ──────────────────────────
@test "followup-rollup: issues without [<plan>-<slice> followup] prefix are excluded" {
  seed_folder_plan "test-plan"
  fixture=$(write_fixture '[
    {"number":200,"url":"https://x/200","title":"[test-plan-S1 followup] valid one","body":"","labels":[{"name":"p2"}]},
    {"number":201,"url":"https://x/201","title":"unrelated bug report","body":"","labels":[]},
    {"number":202,"url":"https://x/202","title":"[other-plan-X1 followup] from a different plan","body":"","labels":[{"name":"p1"}]},
    {"number":203,"url":"https://x/203","title":"test-plan but no followup prefix","body":"","labels":[]},
    {"number":204,"url":"https://x/204","title":"[P2] test-plan-S1 followup — wrong shape","body":"","labels":[]}
  ]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" --fixture "$fixture"
  [ "$status" -eq 0 ]
  # Only the one valid issue counts.
  [[ "$output" == *"Open follow-ups:** 1 issues across 1 slices"* ]]
  [[ "$output" == *"#200"* ]]
  # Excluded issues must NOT appear in the rollup.
  ! [[ "$output" == *"#201"* ]] || return 1
  ! [[ "$output" == *"#202"* ]] || return 1
  ! [[ "$output" == *"#203"* ]] || return 1
  ! [[ "$output" == *"#204"* ]] || return 1
}

# ── 4. Severity grouping — label, title-token, body-marker, fallback ──
@test "followup-rollup: severity grouping derives from labels, title tokens, body markers, and falls back to P3" {
  seed_folder_plan "test-plan"
  # 4 issues, each exercising a different severity-resolution route:
  #   #301 → label p0
  #   #302 → title token [P1]
  #   #303 → body marker "**Severity:** P2"
  #   #304 → no signal → fallback P3
  fixture=$(write_fixture '[
    {"number":301,"url":"https://x/301","title":"[test-plan-S1 followup] label-driven severity","body":"","labels":[{"name":"p0"}]},
    {"number":302,"url":"https://x/302","title":"[test-plan-S1 followup] [P1] title-token severity","body":"","labels":[]},
    {"number":303,"url":"https://x/303","title":"[test-plan-S1 followup] body-marker severity","body":"Some intro\n**Severity:** P2\nMore body.","labels":[]},
    {"number":304,"url":"https://x/304","title":"[test-plan-S1 followup] no severity signal at all","body":"","labels":[]}
  ]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" --fixture "$fixture"
  [ "$status" -eq 0 ]
  # Severity table shows exactly 1 in each bucket.
  [[ "$output" == *"| P0 | 1 |"* ]]
  [[ "$output" == *"| P1 | 1 |"* ]]
  [[ "$output" == *"| P2 | 1 |"* ]]
  [[ "$output" == *"| P3 | 1 |"* ]]
  # Per-slice tally for S1 has 1/1/1/1 + total 4.
  [[ "$output" == *"| S1 | 1 | 1 | 1 | 1 | 4 |"* ]]
}

# ── 5. Area grouping — label vs title-keyword heuristic ─────────────────
@test "followup-rollup: area grouping resolves via labels AND title-keyword heuristic" {
  seed_folder_plan "test-plan"
  # 8 issues exercising both routes:
  #   label route:        #401(test-coverage) #402(correctness) #403(architecture) #404(operability)
  #   heuristic route:    #405(test→test-coverage) #406(broken→correctness)
  #                       #407(refactor→architecture) #408(metric→operability)
  fixture=$(write_fixture '[
    {"number":401,"url":"https://x/401","title":"[test-plan-S1 followup] zzz","body":"","labels":[{"name":"test-coverage"},{"name":"p2"}]},
    {"number":402,"url":"https://x/402","title":"[test-plan-S1 followup] zzz","body":"","labels":[{"name":"correctness"},{"name":"p2"}]},
    {"number":403,"url":"https://x/403","title":"[test-plan-S1 followup] zzz","body":"","labels":[{"name":"architecture"},{"name":"p2"}]},
    {"number":404,"url":"https://x/404","title":"[test-plan-S1 followup] zzz","body":"","labels":[{"name":"operability"},{"name":"p2"}]},
    {"number":405,"url":"https://x/405","title":"[test-plan-S2 followup] missing test fixture coverage","body":"","labels":[{"name":"p2"}]},
    {"number":406,"url":"https://x/406","title":"[test-plan-S2 followup] broken pagination on listing","body":"","labels":[{"name":"p2"}]},
    {"number":407,"url":"https://x/407","title":"[test-plan-S2 followup] refactor cross-layer coupling","body":"","labels":[{"name":"p2"}]},
    {"number":408,"url":"https://x/408","title":"[test-plan-S2 followup] add metric for runbook signal","body":"","labels":[{"name":"p2"}]}
  ]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan" --fixture "$fixture"
  [ "$status" -eq 0 ]
  # Each area bucket has count 2 (one label-route + one heuristic-route).
  [[ "$output" == *"### test-coverage (2)"* ]]
  [[ "$output" == *"### correctness (2)"* ]]
  [[ "$output" == *"### architecture (2)"* ]]
  [[ "$output" == *"### operability (2)"* ]]
  # Spot-check: #405 (heuristic test-coverage) appears under test-coverage,
  # #401 (label test-coverage) also.
  [[ "$output" == *"#401"* ]]
  [[ "$output" == *"#405"* ]]
  # And neither route landed something in the wrong area: confirm exact
  # mapping by checking the per-slice tally totals.
  [[ "$output" == *"| S1 | 0 | 0 | 4 | 0 | 4 |"* ]]
  [[ "$output" == *"| S2 | 0 | 0 | 4 | 0 | 4 |"* ]]
}

# ── Bonus: flat-file plan layout works too ───────────────────────────
@test "followup-rollup: accepts flat-file plan layout (.md)" {
  cat > "$REPO_DIR/flat-plan.md" <<'EOF'
# Flat-file plan

```yaml
slices:
  - id: F1
    name: only
    depends-on: []
    acceptance:
      - "x"
```
EOF
  fixture=$(write_fixture '[
    {"number":500,"url":"https://x/500","title":"[flat-plan-F1 followup] a thing","body":"","labels":[{"name":"p1"}]}
  ]')

  run bash "$SCRIPT_PATH" "$REPO_DIR/flat-plan.md" --fixture "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Follow-up rollup — flat-plan"* ]]
  [[ "$output" == *"#500"* ]]
}

# ── Bonus: GH_OFFLINE=1 short-circuits to the empty placeholder ──────
@test "followup-rollup: GH_OFFLINE=1 emits empty placeholder without invoking gh" {
  seed_folder_plan "test-plan"

  # Sentinel gh stub — if invoked, writes to a flag file.
  sentinel="$BATS_TEST_TMPDIR/gh-called.flag"
  mkdir -p "$BATS_TEST_TMPDIR/gh-stub"
  cat > "$BATS_TEST_TMPDIR/gh-stub/gh" <<EOF
#!/usr/bin/env bash
echo invoked > "$sentinel"
EOF
  chmod +x "$BATS_TEST_TMPDIR/gh-stub/gh"

  run env GH_OFFLINE=1 PATH="$BATS_TEST_TMPDIR/gh-stub:$PATH" bash "$SCRIPT_PATH" "$REPO_DIR/docs/plans/test-plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Open follow-ups:** 0"* ]]
  [[ "$output" == *"GH_OFFLINE=1"* ]]
  if [ -f "$sentinel" ]; then
    echo "gh was invoked despite GH_OFFLINE=1" >&2
    return 1
  fi
}
