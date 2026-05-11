#!/usr/bin/env bats
# Smoke tests for /recap v2 (B4):
#   - Structured WHY mode emits TLDR first + 4 named sections after.
#   - TLDR has exactly 4 sentences.
#   - Sections 3-5 require a citation per bullet.
#   - Citation resolution fails on hallucinated #PRs.
#   - Citation resolution fails on file:line where line > file length.
#   - GH_OFFLINE=1 mode resolves PR citations against the allowlist fixture.
#   - v1 mode preserved (no --v2 prints v1 instructions).

load ../test_helper

BUILD_RECAP="$ANVIL_ROOT/skills/recap/scripts/build-recap.sh"
RECAP_FX="$ANVIL_ROOT/tests/fixtures/recap-v2"

setup() {
  setup_fresh_repo
  # Seed the repo with a known file so file:N citations against it resolve.
  printf 'line 1\nline 2\nline 3\n' > README.md
  git add README.md
  git commit -q -m "seed README"
}

# --- v1 backward-compat ----------------------------------------------------

@test "v1 mode (no --v2) prints v1 instructions and exits 0" {
  run bash "$BUILD_RECAP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1"* ]]
  [[ "$output" == *"--v2"* ]]
}

# --- v2 structure ----------------------------------------------------------

@test "v2 prompt mode (no --model-cmd) emits the prompt and exits 0" {
  # Copy the fixture events into a working .anvil/ so v2 can find them.
  mkdir -p .anvil
  cp "$RECAP_FX/events.jsonl" .anvil/grind-events.jsonl
  run bash "$BUILD_RECAP" --v2 --slug fixture-sprint
  [ "$status" -eq 0 ]
  [[ "$output" == *"## TLDR"* ]]
  [[ "$output" == *"## What shipped"* ]]
  [[ "$output" == *"## What assumptions changed"* ]]
  [[ "$output" == *"## What architectural drift"* ]]
  [[ "$output" == *"## What residual risk"* ]]
}

# --- Acceptance criterion #1: TLDR first + 4 named sections after ---------

@test "resolve mode: good recap fixture has TLDR first followed by 4 named sections" {
  cp "$RECAP_FX/good-recap.md" recap.md
  # First non-title heading must be ## TLDR.
  first_h2=$(grep -E '^## ' recap.md | head -1)
  [ "$first_h2" = "## TLDR" ]
  # All 4 named sections must appear, in order.
  run grep -E '^## ' recap.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"## TLDR"* ]]
  [[ "$output" == *"## What shipped"* ]]
  [[ "$output" == *"## What assumptions changed"* ]]
  [[ "$output" == *"## What architectural drift"* ]]
  [[ "$output" == *"## What residual risk"* ]]
}

@test "resolve mode: good recap fixture passes structure + citation validation" {
  cp "$RECAP_FX/good-recap.md" recap.md
  run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  # The good fixture cites #1010-#1012 (in allowlist) + README.md:1 (exists).
  # GH_OFFLINE forces allowlist path and skips gh.
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 0 ]
}

# --- Acceptance criterion #2: TLDR has exactly 4 sentences ----------------

@test "resolve mode: TLDR sentence count must be exactly 4" {
  # The good fixture should pass.
  cp "$RECAP_FX/good-recap.md" recap.md
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 0 ]
}

@test "resolve mode: TLDR with 1 sentence fails structure check" {
  cp "$RECAP_FX/bad-recap-tldr-count.md" recap.md
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TLDR"* ]] || [[ "$output" == *"4 sentences"* ]]
}

# --- Acceptance criterion #3: every bullet in 3-5 has a citation ----------

@test "resolve mode: every bullet under 'What assumptions changed' has a citation" {
  cp "$RECAP_FX/good-recap.md" recap.md
  # Extract the section body.
  body=$(awk '
    /^## What assumptions changed[[:space:]]*$/ {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' recap.md)
  # Every bullet line must contain a citation form.
  bad=0
  while IFS= read -r bullet; do
    [ -z "$bullet" ] && continue
    # Match `#N` OR `path:N` OR <sha>
    if ! echo "$bullet" | grep -qE '(\#[0-9]+|[A-Za-z0-9_./-]+:[0-9]+|<[0-9a-f]{7,40}>|[0-9a-f]{7,40})'; then
      echo "no-citation bullet: $bullet"
      bad=$((bad+1))
    fi
  done < <(echo "$body" | grep -E '^[[:space:]]*[-*][[:space:]]')
  [ "$bad" -eq 0 ]
}

@test "resolve mode: every bullet under 'What architectural drift' has a citation" {
  cp "$RECAP_FX/good-recap.md" recap.md
  body=$(awk '
    /^## What architectural drift[[:space:]]*$/ {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' recap.md)
  bad=0
  while IFS= read -r bullet; do
    [ -z "$bullet" ] && continue
    if ! echo "$bullet" | grep -qE '(\#[0-9]+|[A-Za-z0-9_./-]+:[0-9]+|<[0-9a-f]{7,40}>|[0-9a-f]{7,40})'; then
      bad=$((bad+1))
    fi
  done < <(echo "$body" | grep -E '^[[:space:]]*[-*][[:space:]]')
  [ "$bad" -eq 0 ]
}

@test "resolve mode: every bullet under 'What residual risk' has a citation" {
  cp "$RECAP_FX/good-recap.md" recap.md
  body=$(awk '
    /^## What residual risk[[:space:]]*$/ {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' recap.md)
  bad=0
  while IFS= read -r bullet; do
    [ -z "$bullet" ] && continue
    if ! echo "$bullet" | grep -qE '(\#[0-9]+|[A-Za-z0-9_./-]+:[0-9]+|<[0-9a-f]{7,40}>|[0-9a-f]{7,40})'; then
      bad=$((bad+1))
    fi
  done < <(echo "$body" | grep -E '^[[:space:]]*[-*][[:space:]]')
  [ "$bad" -eq 0 ]
}

# --- Acceptance criterion #4: hallucinated #9999 fails ---------------------

@test "resolve mode: hallucinated #9999 against 5-PR fixture allowlist FAILS" {
  cp "$RECAP_FX/bad-recap-hallucinated-pr.md" recap.md
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"9999"* ]]
}

# --- Acceptance criterion #5: file:line with too-high line FAILS ----------

@test "resolve mode: README.md:999999 against a 3-line README FAILS" {
  cp "$RECAP_FX/bad-recap-file-line.md" recap.md
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"999999"* ]] || [[ "$output" == *"line"* ]]
}

# --- Acceptance criterion #6: GH_OFFLINE=1 mode passes against allowlist --

@test "resolve mode: GH_OFFLINE=1 passes when all PRs are in the allowlist" {
  cp "$RECAP_FX/good-recap.md" recap.md
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 0 ]
}

@test "resolve mode: GH_OFFLINE=1 FAILS when a PR is missing from allowlist" {
  # Build a recap that cites a PR not in the allowlist.
  cat > recap.md <<'EOF'
# Recap — fixture-sprint

## TLDR

Three slices shipped under the fixture plan with two assumption shifts captured. One assumption shifted around event-log shape after the first slice merged. Architectural drift introduced an additional indirection layer in the resolver. Residual risk lives in the offline mode fallback for PR resolution.

## What shipped

- S1 — slice-1 lifted.

## What assumptions changed

- We assumed event-log shape was append-only (#7777).

## What architectural drift

- Resolver script grew a third branch (#7778).

## What residual risk

- Offline mode (#7779).
EOF
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --resolve recap.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt"
  [ "$status" -eq 2 ]
}

# --- v2 build with --model-cmd integration --------------------------------

@test "v2 with --model-cmd: model command echoes the good fixture and structure + citations validate" {
  # Mock model: ignore stdin and emit the good-recap fixture body.
  good_recap="$RECAP_FX/good-recap.md"
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --v2 \
    --plan "$RECAP_FX" \
    --output /tmp/recap-v2-out.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt" \
    --model-cmd "cat $good_recap"
  [ "$status" -eq 0 ]
  [ -f /tmp/recap-v2-out.md ]
  # Cleanup.
  rm -f /tmp/recap-v2-out.md
}

@test "v2 with --model-cmd that emits hallucinated #9999 — build FAILS" {
  bad_recap="$RECAP_FX/bad-recap-hallucinated-pr.md"
  GH_OFFLINE=1 run bash "$BUILD_RECAP" --v2 \
    --plan "$RECAP_FX" \
    --output /tmp/recap-v2-bad.md \
    --pr-allowlist "$RECAP_FX/pr-allowlist.txt" \
    --model-cmd "cat $bad_recap"
  [ "$status" -eq 2 ]
  rm -f /tmp/recap-v2-bad.md
}

# --- argument handling -----------------------------------------------------

@test "--resolve without a file path exits 3" {
  run bash "$BUILD_RECAP" --resolve /nonexistent/path.md
  [ "$status" -eq 3 ]
}

@test "unknown flag exits 3" {
  run bash "$BUILD_RECAP" --not-a-real-flag
  [ "$status" -eq 3 ]
}
