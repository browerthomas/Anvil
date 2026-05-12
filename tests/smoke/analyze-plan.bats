#!/usr/bin/env bats
# Smoke tests for /analyze-plan v1 — file-path verification gate.
#
# Each test stages a stub plan layout under $BATS_TEST_TMPDIR and asserts the
# extractor's verdicts + exit code.

load ../test_helper

SCRIPT="$BATS_TEST_DIRNAME/../../skills/analyze-plan/scripts/extract-paths.sh"

setup() {
  setup_fresh_repo
  PLAN_DIR="$REPO_DIR/docs/plans/stub-plan"
  mkdir -p "$PLAN_DIR/specs"
}

# Stage a minimal proposal.md + design.md alongside tasks.md so the plan
# layout looks like a real folder plan. Body is overridable per test.
stage_tasks_md() {
  cat > "$PLAN_DIR/tasks.md" <<'EOF'
# stub-plan — tasks

```yaml
slices:
  - id: S1
    name: Stub slice
    depends-on: []
    files:
      - templates/future.md
    parallelizable: true
    scope: |
      Stub.
    constraints: []
    acceptance: []
```
EOF
  : > "$PLAN_DIR/proposal.md"
  : > "$PLAN_DIR/design.md"
}

@test "analyze-plan reports CONTRADICTED for stale path not in any slice files" {
  stage_tasks_md
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

The plan touches src/foo/bar.ts heavily; preserve the existing behaviour at
src/foo/bar.ts when refactoring.
EOF

  run bash "$SCRIPT" "$PLAN_DIR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CONTRADICTED.*src/foo/bar.ts"
}

@test "analyze-plan reports VERIFIED for existing path" {
  stage_tasks_md
  # shared/lib.sh exists in the anvil checkout — cite it from the plan AND
  # arrange the working tree (current dir = REPO_DIR) to contain a matching
  # file so the existence check passes here without depending on the anvil
  # repo layout from a temp git repo.
  mkdir -p "$REPO_DIR/shared"
  echo "stub" > "$REPO_DIR/shared/lib.sh"

  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

The plan extends shared/lib.sh with a new helper.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERIFIED.*shared/lib.sh"
}

@test "analyze-plan reports EXPECTED-BY-SLICE for forward-looking path in slice files list" {
  stage_tasks_md
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

S1 creates templates/future.md as a scaffold for downstream plans.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "EXPECTED-BY-SLICE.*templates/future.md"
  echo "$output" | grep -vq "CONTRADICTED.*templates/future.md"
}

@test "analyze-plan does not extract angle-bracket placeholder paths" {
  stage_tasks_md
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

Transcript output lands under docs/plans/<slug>.md once /spec finishes.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  # No CONTRADICTED for the angle-bracket placeholder.
  ! echo "$output" | grep -q "docs/plans/<slug>.md"
  ! echo "$output" | grep -q "CONTRADICTED.*slug"
}

@test "analyze-plan reports UNVERIFIABLE for paths inside fenced code blocks" {
  stage_tasks_md
  cat > "$PLAN_DIR/design.md" <<'EOF'
# stub-plan — design

Illustrative invocation:

```bash
bash skills/foo/scripts/example.sh path/to/example.ts
```

End of design.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  echo "$output" | grep -q "UNVERIFIABLE.*path/to/example.ts"
  # Inside a fence → must NOT be CONTRADICTED.
  ! echo "$output" | grep -q "CONTRADICTED.*path/to/example.ts"
}

@test "analyze-plan exits 2 on a path that is not a plan" {
  run bash "$SCRIPT" "$REPO_DIR/does-not-exist"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "is not a plan"
}

@test "analyze-plan extract-paths.sh passes bash -n syntax check" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "analyze-plan exits 0 with a warning when plan has zero verifiable claims" {
  stage_tasks_md
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

This plan is all prose with no factual paths to verify. Operator should still
get a clean exit.
EOF
  # Wipe specs/ so there are no extra .md to scan.
  rm -rf "$PLAN_DIR/specs"

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "extracted 0 verifiable claims"
}

@test "analyze-plan strips leading slash from \${VAR}/path matches (anvil#59 regression)" {
  stage_tasks_md
  # ${VAR}/templates/plan-template.md — the regex would otherwise match starting
  # at the `/` after the closing brace, producing the phantom `/templates/...`.
  # The existence check `[ -e "$WORKING_TREE/$path" ]` then collapses double
  # slashes via path normalisation, producing a misleading VERIFIED if the file
  # happens to exist (or a CONTRADICTED whose path looks absolute and points
  # nowhere obvious if it doesn't).
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

The dispatcher reads from ${VAR}/templates/plan-template.md as part of S1.
The $(fn)/sub/another-template.md form has the same shape.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  # No leading-slash phantom in any verdict row.
  ! echo "$output" | grep -E "^(VERIFIED|CONTRADICTED|EXPECTED-BY-SLICE|UNVERIFIABLE) +/templates/" >/dev/null
  ! echo "$output" | grep -E "^(VERIFIED|CONTRADICTED|EXPECTED-BY-SLICE|UNVERIFIABLE) +/sub/" >/dev/null
  # The corrected (slash-stripped) paths are the ones that should show up — as
  # CONTRADICTED since the files don't exist in the stub working tree.
  echo "$output" | grep -q "CONTRADICTED.*templates/plan-template.md"
  echo "$output" | grep -q "CONTRADICTED.*sub/another-template.md"
}

@test "analyze-plan auto-suppresses .anvil/ runtime state by default (anvil#60 regression)" {
  stage_tasks_md
  cat > "$PLAN_DIR/design.md" <<'EOF'
# stub-plan — design

The skill writes to .anvil/dispatched-prompts/S-test.prompt.md before invoking
Agent. Per-project config lives at .anvil/constitution.md and
.anvil/forbidden-patterns.txt; runtime state is tracked in
.anvil/dispatched-agents.json.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  # None of the .anvil/ paths surface in any verdict bucket.
  ! echo "$output" | grep -q "CONTRADICTED.*\.anvil/"
  ! echo "$output" | grep -q "EXPECTED-BY-SLICE.*\.anvil/"
  ! echo "$output" | grep -q "VERIFIED.*\.anvil/"
  ! echo "$output" | grep -q "UNVERIFIABLE.*\.anvil/"
  # And exit 0 — no CONTRADICTEDs means the gate doesn't block.
  [ "$status" -eq 0 ]
}

@test "analyze-plan auto-suppresses .git/ and node_modules/ paths (anvil#60 regression)" {
  stage_tasks_md
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

Hook stub at .git/hooks/pre-push.sh runs the gate. Build pulls from
node_modules/some-dep/index.js — not source-controlled.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  ! echo "$output" | grep -q "CONTRADICTED.*\.git/"
  ! echo "$output" | grep -q "CONTRADICTED.*node_modules/"
  [ "$status" -eq 0 ]
}

@test "analyze-plan honours per-project .anvil/analyze-plan.ignore globs (anvil#60 regression)" {
  stage_tasks_md
  mkdir -p "$REPO_DIR/.anvil"
  cat > "$REPO_DIR/.anvil/analyze-plan.ignore" <<'EOF'
# Project-local ignores — generated docs go here.
docs/generated/*
EOF
  cat > "$PLAN_DIR/proposal.md" <<'EOF'
# stub-plan — proposal

The generator emits docs/generated/api-ref.md every run.
EOF

  cd "$REPO_DIR"
  run bash "$SCRIPT" "$PLAN_DIR"
  ! echo "$output" | grep -q "CONTRADICTED.*docs/generated/"
  [ "$status" -eq 0 ]
}
