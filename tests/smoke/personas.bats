#!/usr/bin/env bats
# Smoke tests for /persona — all persona files under skills/persona/personas/.
# Defensive: detects either flat layout (personas/*.md) OR the future namespaced
# layout (personas/<category>/*.md) without preference.

load ../test_helper

@test "personas directory exists" {
  [ -d "$ANVIL_ROOT/skills/persona/personas" ]
}

@test "at least one persona file is present" {
  count=$(find "$ANVIL_ROOT/skills/persona/personas" -name "*.md" -type f | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

@test "every persona file is non-empty" {
  bad=0
  while IFS= read -r f; do
    if [ ! -s "$f" ]; then
      echo "empty persona: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/persona/personas" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "every persona file contains the {{project_context}} placeholder" {
  bad=0
  while IFS= read -r f; do
    if ! grep -q "{{project_context}}" "$f"; then
      echo "missing {{project_context}} placeholder: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/persona/personas" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "no persona file leaks project-private strings (theirownstory / BookGen / agoku64)" {
  bad=0
  while IFS= read -r f; do
    if grep -qiE "theirownstory|BookGen|agoku64" "$f"; then
      echo "project-private string in: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/persona/personas" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "every persona file has a markdown body of reasonable length" {
  # Sanity check that no persona is a one-line stub.
  bad=0
  while IFS= read -r f; do
    chars=$(wc -c < "$f" | tr -d ' ')
    if [ "$chars" -lt 200 ]; then
      echo "persona too short ($chars chars): $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/persona/personas" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}
