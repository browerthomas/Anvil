#!/usr/bin/env bats
# Smoke tests for per-slice checklists (S3 of speckit-gold).
#
# Covers:
#   - av_parse_slice_checklist parser in shared/lib.sh
#   - /pre-merge-gate verify.sh slice-context lookup
#   - /pre-merge-gate verify.sh checklist execution (shell + grep)
#
# Each test stages a throwaway repo with a minimal plan, a
# .anvil/dispatched-agents.json mapping a branch to a slice id, and a
# current branch matching one of the staged branches. The verify.sh
# script is then invoked and inspected for the right verdict + messages.

load ../test_helper

VERIFY="$ANVIL_ROOT/skills/pre-merge-gate/scripts/verify.sh"

setup() {
  setup_fresh_repo
  # Disable real network calls during tests.
  export GH_OFFLINE=1
  # Source the lib for direct parser tests.
  # shellcheck disable=SC1090,SC1091
  source "$ANVIL_ROOT/shared/lib.sh"
}

# Helper: stage a folder-layout plan with a checklist block.
stage_plan_with_checklist() {
  local plan_dir="$REPO_DIR/docs/plans/p1"
  mkdir -p "$plan_dir"
  cat > "$plan_dir/tasks.md" <<'EOF'
# Test plan — tasks

```yaml
slices:
  - id: SA
    name: Slice with grep absent (should pass)
    files: []
    checklist:
      - kind: grep
        pattern: "TODO_THIS_SHOULD_NOT_EXIST_XYZ"
        in: "src"
        expect: absent
  - id: SB
    name: Slice with grep absent (should fail because pattern is present)
    files: []
    checklist:
      - kind: grep
        pattern: "FORBIDDEN_TOKEN"
        in: "src"
        expect: absent
  - id: SC
    name: Slice with passing shell
    files: []
    checklist:
      - kind: shell
        run: "true"
        expect: pass
        timeout: 10
  - id: SD
    name: Slice without checklist (legacy)
    files: []
  - id: SE
    name: Slice with grep present + count
    files: []
    checklist:
      - kind: grep
        pattern: "marker_unique_string"
        in: "src/onefile.txt"
        expect: present
        count: 1
  - id: SF
    name: Slice with unknown kind
    files: []
    checklist:
      - kind: bogus
        run: "true"
  - id: SG
    name: Slice with invalid grep expect
    files: []
    checklist:
      - kind: grep
        pattern: "x"
        in: "src"
        expect: maybe
  - id: SH
    name: Slice with sleep beyond timeout
    files: []
    checklist:
      - kind: shell
        run: "sleep 10"
        expect: pass
        timeout: 1
```
EOF
  # Seed a src/ dir with two files (one clean, one carrying FORBIDDEN_TOKEN
  # and a marker_unique_string for the present-count test).
  mkdir -p "$REPO_DIR/src"
  printf 'this file is clean\n' > "$REPO_DIR/src/clean.txt"
  printf 'this file has FORBIDDEN_TOKEN inside\n' > "$REPO_DIR/src/dirty.txt"
  printf 'has a marker_unique_string here\n' > "$REPO_DIR/src/onefile.txt"
  # Commit so we have a real worktree-shaped state.
  ( cd "$REPO_DIR" && git add -A && git commit -q -m "seed" )
  echo "$plan_dir"
}

# Helper: stage .anvil/dispatched-agents.json mapping a slice id to current
# branch and plan_path.
stage_dispatched_agents_json() {
  local slice_id="$1" branch="$2" plan_path="$3"
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/dispatched-agents.json" <<EOF
{
  "$slice_id": {
    "agent_id": "stub-agent",
    "worktree": "$REPO_DIR",
    "branch": "$branch",
    "plan_path": "$plan_path",
    "dispatched_at": "2026-05-12T00:00:00Z",
    "scope": "test"
  }
}
EOF
}

# Helper: rename current branch so it matches the mapping in dispatched-agents.json.
checkout_branch() {
  local branch="$1"
  ( cd "$REPO_DIR" && git checkout -q -b "$branch" 2>/dev/null || git checkout -q "$branch" )
}

# Helper: invoke verify.sh from inside the worktree, --skip-rebase to keep
# the test fast (we're not testing rebase here). The harness uses a single
# fresh-repo worktree so we pass --worktree explicitly + --skip-rebase to
# avoid touching origin/main (which doesn't exist in the fixture repo).
invoke_verify() {
  local branch="$1"; shift
  ( cd "$REPO_DIR" && bash "$VERIFY" "$branch" --skip-rebase --worktree "$REPO_DIR" "$@" )
}

# ----------------- Parser tests (av_parse_slice_checklist) -----------------

@test "av_parse_slice_checklist emits structured lines for grep + shell" {
  stage_plan_with_checklist >/dev/null
  run av_parse_slice_checklist "$REPO_DIR/docs/plans/p1/tasks.md" SC
  [ "$status" -eq 0 ]
  [[ "$output" == "shell|true|pass|10" ]]
}

@test "av_parse_slice_checklist silent + rc 0 when no checklist field" {
  stage_plan_with_checklist >/dev/null
  run av_parse_slice_checklist "$REPO_DIR/docs/plans/p1/tasks.md" SD
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "av_parse_slice_checklist rejects unknown kind" {
  stage_plan_with_checklist >/dev/null
  run av_parse_slice_checklist "$REPO_DIR/docs/plans/p1/tasks.md" SF
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown kind 'bogus'"* ]]
}

@test "av_parse_slice_checklist rejects invalid expect for grep" {
  stage_plan_with_checklist >/dev/null
  run av_parse_slice_checklist "$REPO_DIR/docs/plans/p1/tasks.md" SG
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid expect 'maybe'"* ]]
}

@test "av_parse_slice_checklist errors on slice id not found" {
  stage_plan_with_checklist >/dev/null
  run av_parse_slice_checklist "$REPO_DIR/docs/plans/p1/tasks.md" SZZZ
  [ "$status" -ne 0 ]
  [[ "$output" == *"slice id 'SZZZ' not found"* ]]
}

# ----------------- verify.sh: slice resolution + checklist exec ----------

@test "failing grep checklist blocks merge" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SB"
  stage_dispatched_agents_json "SB" "br-SB" "$plan_dir"
  run invoke_verify "br-SB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"FORBIDDEN_TOKEN"* ]]
}

@test "passing shell checklist proceeds to global gates" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SC"
  stage_dispatched_agents_json "SC" "br-SC" "$plan_dir"
  run invoke_verify "br-SC"
  # We expect at least the shell PASS message in the output (verdict
  # depends on global gates which mostly no-op in the fixture).
  [[ "$output" == *"checklist PASS: shell 'true' exit 0"* ]]
}

@test "missing checklist field = legacy behaviour (no warning)" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SD"
  stage_dispatched_agents_json "SD" "br-SD" "$plan_dir"
  run invoke_verify "br-SD"
  # No "checklist FAIL" / "checklist ERROR" lines should surface.
  ! [[ "$output" == *"checklist FAIL"* ]]
  ! [[ "$output" == *"checklist ERROR"* ]]
  # No noisy "no checklist" warning either.
  ! [[ "$output" == *"no checklist"* ]]
}

@test "slice located via dispatched-agents.json exact match" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SA"
  stage_dispatched_agents_json "SA" "br-SA" "$plan_dir"
  run invoke_verify "br-SA"
  # SA's checklist is grep absent for a token that's not in any file → PASS.
  [[ "$output" == *"SA checklist PASS"* ]]
}

@test "--slice arg overrides dispatched-agents.json lookup" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SA"
  # Map current branch to SA in the json, but pass --slice SC to override.
  stage_dispatched_agents_json "SA" "br-SA" "$plan_dir"
  run invoke_verify "br-SA" --slice SC
  # Should run SC's checklist, not SA's.
  [[ "$output" == *"SC checklist PASS: shell 'true' exit 0"* ]]
  ! [[ "$output" == *"SA checklist"* ]]
}

@test "no slice context found errors loudly + global gates did NOT run" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-unmapped"
  # Intentionally do NOT stage dispatched-agents.json for this branch.
  run invoke_verify "br-unmapped"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no slice context found"* ]]
  # Global gates emit "Type-checking" / "Running tests" / "Scanning for
  # forbidden patterns" lines; assert none of those fired.
  ! [[ "$output" == *"Type-checking"* ]]
  ! [[ "$output" == *"Running tests"* ]]
  ! [[ "$output" == *"Scanning for forbidden patterns"* ]]
}

@test "invalid kind: fails loudly via verify.sh" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SF"
  stage_dispatched_agents_json "SF" "br-SF" "$plan_dir"
  run invoke_verify "br-SF"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown kind"* ]] || [[ "$output" == *"bogus"* ]]
}

@test "invalid expect for grep fails loudly via verify.sh" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SG"
  stage_dispatched_agents_json "SG" "br-SG" "$plan_dir"
  run invoke_verify "br-SG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid expect"* ]]
}

@test "count assertion in grep — exact match wins" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SE"
  stage_dispatched_agents_json "SE" "br-SE" "$plan_dir"
  # SE expects exactly 1 match of marker_unique_string in src/onefile.txt
  # (the fixture writes exactly 1 occurrence).
  run invoke_verify "br-SE"
  [[ "$output" == *"SE checklist PASS"* ]]
  # Now mutate the file to have 2 matches and re-run; should fail.
  printf 'second marker_unique_string\n' >> "$REPO_DIR/src/onefile.txt"
  ( cd "$REPO_DIR" && git add -A && git commit -q -m "add second marker" )
  run invoke_verify "br-SE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected exactly 1"* ]] || [[ "$output" == *"checklist FAIL"* ]]
}

@test "shell timeout kills runaway command" {
  plan_dir=$(stage_plan_with_checklist)
  checkout_branch "br-SH"
  stage_dispatched_agents_json "SH" "br-SH" "$plan_dir"
  start=$SECONDS
  run invoke_verify "br-SH"
  elapsed=$(( SECONDS - start ))
  # Should fail with timeout message; should wall-clock under ~5s (1s limit
  # + a generous slack for the shell + global gates).
  [[ "$output" == *"timed out after"* ]] || [[ "$output" == *"timeout"* ]]
  [ "$elapsed" -lt 8 ]
}
