#!/usr/bin/env bats
# Smoke tests for D2 — backward-compat regression suite.
#
# Each B-slice (B1-B4) shipped its own smoke test in-PR. D2's role is the
# AGGREGATION + backward-compat regression slice: a single bats file that
# gates the "pre-sprint fixture must still parse + skills must still produce
# expected output" invariant against `tests/fixtures/sample-events.jsonl`.
#
# Covers:
#   1. /anvil-status — parses the pre-sprint sample-events.jsonl fixture + emits
#      a sensible dashboard (NEXT line + BLOCKED line for the dep-blocked slice).
#   2. /grind --resume — parses the pre-sprint fixture (seeded into a fresh
#      repo + augmented with a slice-merged) + emits a `resume` event.
#   3. Fixture event-type allowlist guard — sample-events.jsonl contains ONLY
#      pre-sprint event types (plan-init, slice-pending, slice-dispatched,
#      slice-reviewed, slice-merged, slice-deferred, plan-revised). The
#      "DO NOT ADD NEW EVENT TYPES" sentinel turned into a programmatic check.
#   4. Cross-skill: /learn decisions + /dispatch-slice — when a relevant
#      decision row exists, the dispatch-slice prompt scaffold includes a
#      "## Recent decisions" section. Aggregates B3 + dispatch-slice contract.
#
# Implementation notes:
#   - These tests DO NOT duplicate per-B-slice smoke coverage (anvil-status,
#     grind-resume, learn-decisions, recap-v2 bats files each ship their own
#     enumerated coverage). They ONLY assert the cross-cutting backward-compat
#     contract — if a future event-vocabulary change creeps in, this file fails
#     loudly.
#   - The fixture allowlist is hard-coded here, not read from a config — that
#     way a config-side bug can't silently widen the allowlist.

load ../test_helper

ANVIL_STATUS_SCRIPT="$ANVIL_ROOT/skills/anvil-status/scripts/build-status.sh"
GRIND_STATE_SCRIPT="$ANVIL_ROOT/skills/grind/scripts/state.sh"
DISPATCH_PROMPT_SCRIPT="$ANVIL_ROOT/skills/dispatch-slice/scripts/build-prompt.sh"
LEARN_ADD_SCRIPT="$ANVIL_ROOT/skills/learn/scripts/learn-add.sh"

# Pre-sprint event-type allowlist. This is the canonical list — sample-events.jsonl
# MUST NOT contain any event type outside this set (the `_doc` JSON sentinel line
# is exempt because it has no `ev` field).
PRE_SPRINT_EVENT_TYPES="plan-init slice-pending slice-dispatched slice-reviewed slice-merged slice-deferred plan-revised"

# --- helpers ------------------------------------------------------------

# Seed the canonical fixture into the test repo's .anvil/grind-events.jsonl.
seed_pre_sprint_fixture() {
  mkdir -p "$REPO_DIR/.anvil"
  cp "$FIXTURES_DIR/sample-events.jsonl" "$REPO_DIR/.anvil/grind-events.jsonl"
}

# Seed a minimal plan.md whose slice ids (S1, S2) match the fixture.
seed_fixture_plan() {
  cat > "$REPO_DIR/plan.md" <<'EOF'
# Fixture-aligned plan

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
}

# --- tests --------------------------------------------------------------

setup() {
  setup_fresh_repo
}

# --- 1. /anvil-status backward-compat -----------------------------------

@test "backward-compat: /anvil-status parses pre-sprint sample-events.jsonl + emits NEXT + BLOCKED dashboard" {
  seed_pre_sprint_fixture
  seed_fixture_plan

  # Sanity: fixture still carries the DO-NOT-ADD-NEW-EVENT-TYPES sentinel.
  run head -1 "$REPO_DIR/.anvil/grind-events.jsonl"
  [[ "$output" == *"DO NOT ADD NEW EVENT TYPES"* ]] || {
    echo "fixture missing backward-compat guard sentinel — re-add it" >&2
    return 1
  }

  run env GH_OFFLINE=1 bash "$ANVIL_STATUS_SCRIPT" "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEXT: S1"* ]] || {
    echo "expected NEXT: S1 (only pending slice with satisfied deps), got: $output" >&2
    return 1
  }
  [[ "$output" == *"BLOCKED: S2"* ]] || {
    echo "expected BLOCKED: S2 (depends on un-merged S1), got: $output" >&2
    return 1
  }
}

# --- 2. /grind --resume backward-compat ---------------------------------

@test "backward-compat: /grind --resume parses pre-sprint sample-events.jsonl + emits resume event" {
  seed_pre_sprint_fixture
  seed_fixture_plan

  # Need a snapshot for state.sh's resume path (it refreshes snapshot from the
  # event log). state.sh's resume initializes when the log exists; we need to
  # produce a snapshot from the existing events.
  bash "$GRIND_STATE_SCRIPT" snapshot >/dev/null

  # Pre-resume: no resume event in the log.
  pre_count=$(jq -s 'map(select(.ev == "resume")) | length' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$pre_count" -eq 0 ]

  run bash "$GRIND_STATE_SCRIPT" resume "$REPO_DIR/plan.md"
  [ "$status" -eq 0 ]
  # state.sh emits the next-ready slice id on its own stdout line — S1 is the
  # only ready slice in the pre-sprint fixture.
  [[ "$output" == *"S1"* ]] || {
    echo "expected next slice S1 in output, got: $output" >&2
    return 1
  }

  # A resume event was appended.
  post_count=$(jq -s 'map(select(.ev == "resume")) | length' "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$post_count" -eq 1 ]

  # The resume event payload carries plan_path + merged/total counts.
  plan_path=$(jq -rs 'map(select(.ev == "resume")) | last | .data.plan_path' \
    "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$plan_path" = "$REPO_DIR/plan.md" ]
  total=$(jq -rs 'map(select(.ev == "resume")) | last | .data.total_count' \
    "$REPO_DIR/.anvil/grind-events.jsonl")
  [ "$total" = "2" ]
}

# --- 3. Fixture event-type allowlist guard ------------------------------

@test "backward-compat: sample-events.jsonl contains ONLY pre-sprint event types (allowlist guard)" {
  fixture="$FIXTURES_DIR/sample-events.jsonl"
  [ -f "$fixture" ] || {
    echo "fixture not found: $fixture" >&2
    return 1
  }

  # Extract every `ev` field from non-_doc JSON lines.
  # The `_doc` sentinel line has no `ev` field — jq's `.ev // empty` skips it.
  observed_types=$(jq -r '.ev // empty' "$fixture" | sort -u)

  # Compare against the hard-coded allowlist. Any type observed that is not
  # in the allowlist fails the test loudly.
  allowed=$(echo "$PRE_SPRINT_EVENT_TYPES" | tr ' ' '\n' | sort -u)

  unexpected=$(comm -23 <(echo "$observed_types") <(echo "$allowed"))
  if [ -n "$unexpected" ]; then
    echo "fixture contains event types outside the pre-sprint allowlist:" >&2
    echo "$unexpected" >&2
    echo "" >&2
    echo "If you intend to add a new event type, do NOT add it to" >&2
    echo "  tests/fixtures/sample-events.jsonl" >&2
    echo "Add it to a NEW fixture that targets the new vocabulary." >&2
    echo "sample-events.jsonl pins the pre-sprint vocabulary for backward-compat." >&2
    return 1
  fi
}

@test "backward-compat: allowlist guard FAILS when a non-allowlisted event type is injected (self-test)" {
  # Self-test the guard: copy the fixture, inject a fake-event row, then run
  # the same check inline against the copy. The guard must fail loudly.
  fake_fixture="$BATS_TEST_TMPDIR/sample-events-with-fake.jsonl"
  cp "$FIXTURES_DIR/sample-events.jsonl" "$fake_fixture"
  # Append a synthetic event type that is NOT in the allowlist.
  echo '{"t":"2026-05-11T99:99:99Z","ev":"fake-new-event","slice":"X","data":null}' \
    >> "$fake_fixture"

  observed_types=$(jq -r '.ev // empty' "$fake_fixture" | sort -u)
  allowed=$(echo "$PRE_SPRINT_EVENT_TYPES" | tr ' ' '\n' | sort -u)
  unexpected=$(comm -23 <(echo "$observed_types") <(echo "$allowed"))

  # The injected fake-new-event MUST surface in the unexpected list.
  [[ "$unexpected" == *"fake-new-event"* ]] || {
    echo "self-test failed: injected fake-new-event was NOT caught by the guard" >&2
    echo "observed_types: $observed_types" >&2
    echo "unexpected: $unexpected" >&2
    return 1
  }
}

@test "backward-compat: _doc sentinel line is exempt from allowlist (no ev field)" {
  # The first line of the fixture is a JSON _doc with no `ev` field. jq's
  # `.ev // empty` must skip it. Confirm by counting lines vs typed events.
  fixture="$FIXTURES_DIR/sample-events.jsonl"
  total_lines=$(grep -c . "$fixture")
  typed_events=$(jq -r '.ev // empty' "$fixture" | wc -l | tr -d ' ')
  # At least 1 line has no `ev` field (the _doc sentinel).
  [ "$total_lines" -gt "$typed_events" ]

  # The first line is the _doc sentinel — confirm explicitly.
  run head -1 "$fixture"
  [[ "$output" == *"_doc"* ]]
  [[ "$output" == *"DO NOT ADD NEW EVENT TYPES"* ]]
}

# --- 4. Cross-skill: /learn decisions + /dispatch-slice -----------------

@test "cross-skill: /learn decisions + /dispatch-slice — prompt scaffold includes 'Recent decisions' when a relevant row exists" {
  # Log a decision affecting slice S1 (using the same slice id as the fixture).
  run bash "$LEARN_ADD_SCRIPT" \
    --decision-type architecture --affected S1 \
    cross-skill-decision \
    "chose pre-sprint event vocabulary as the backward-compat invariant" \
    --source manual --strict
  [ "$status" -eq 0 ]

  # Build the dispatch-slice prompt for S1.
  run bash "$DISPATCH_PROMPT_SCRIPT" --id S1 --scope "test scope for backward-compat cross-skill"
  [ "$status" -eq 0 ]

  # The prompt scaffold must include the "## Recent decisions" section.
  [[ "$output" == *"## Recent decisions"* ]] || {
    echo "expected '## Recent decisions' section in dispatch-slice prompt, got:" >&2
    echo "$output" >&2
    return 1
  }
  # And the actual decision key from the log.
  [[ "$output" == *"cross-skill-decision"* ]] || {
    echo "expected decision key 'cross-skill-decision' in prompt, got:" >&2
    echo "$output" >&2
    return 1
  }
  # And the decision_type bracket marker.
  [[ "$output" == *"[architecture]"* ]] || {
    echo "expected [architecture] decision-type tag in prompt, got:" >&2
    echo "$output" >&2
    return 1
  }
}
