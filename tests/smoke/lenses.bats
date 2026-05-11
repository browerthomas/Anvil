#!/usr/bin/env bats
# Smoke tests for /lens — all lens files under skills/lens/lenses/.
# Defensive: detects either flat layout (lenses/*.md) OR the namespaced
# layout (lenses/<category>/*.md) without preference.

load ../test_helper

@test "lenses directory exists" {
  [ -d "$ANVIL_ROOT/skills/lens/lenses" ]
}

@test "at least one lens file is present" {
  count=$(find "$ANVIL_ROOT/skills/lens/lenses" -name "*.md" -type f | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

@test "every lens file is non-empty" {
  bad=0
  while IFS= read -r f; do
    if [ ! -s "$f" ]; then
      echo "empty lens: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/lens/lenses" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "every lens file contains the {{project_context}} placeholder" {
  bad=0
  while IFS= read -r f; do
    if ! grep -q "{{project_context}}" "$f"; then
      echo "missing {{project_context}} placeholder: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/lens/lenses" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "no lens file leaks project-private strings (theirownstory / BookGen / agoku64)" {
  bad=0
  while IFS= read -r f; do
    if grep -qiE "theirownstory|BookGen|agoku64" "$f"; then
      echo "project-private string in: $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/lens/lenses" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}

@test "every lens file has a markdown body of reasonable length" {
  # Sanity check that no lens is a one-line stub.
  bad=0
  while IFS= read -r f; do
    chars=$(wc -c < "$f" | tr -d ' ')
    if [ "$chars" -lt 200 ]; then
      echo "lens too short ($chars chars): $f" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills/lens/lenses" -name "*.md" -type f)
  [ "$bad" -eq 0 ]
}
