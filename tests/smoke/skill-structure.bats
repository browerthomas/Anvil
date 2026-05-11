#!/usr/bin/env bats
# Structural smoke tests across every SKILL.md — frontmatter present, name +
# description fields populated, no project-private references. Catches a class
# of regressions where someone edits a SKILL.md and accidentally drops the
# Claude Code skill manifest header.

load ../test_helper

@test "every skill has a SKILL.md" {
  bad=0
  for sk in "$ANVIL_ROOT"/skills/*/; do
    if [ ! -f "${sk}SKILL.md" ]; then
      echo "missing SKILL.md: $sk" >&2
      bad=$((bad+1))
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every SKILL.md opens with YAML frontmatter" {
  bad=0
  for sk in "$ANVIL_ROOT"/skills/*/; do
    if [ -f "${sk}SKILL.md" ]; then
      first=$(head -1 "${sk}SKILL.md")
      if [ "$first" != "---" ]; then
        echo "no frontmatter: ${sk}SKILL.md (first line: $first)" >&2
        bad=$((bad+1))
      fi
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every SKILL.md frontmatter has a name field matching the directory" {
  bad=0
  for sk in "$ANVIL_ROOT"/skills/*/; do
    name=$(basename "${sk%/}")
    if [ -f "${sk}SKILL.md" ]; then
      decl=$(awk '/^---$/{c++; next} c==1' "${sk}SKILL.md" | grep -E '^name:' | head -1 | sed -E 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'")
      if [ "$decl" != "$name" ]; then
        echo "frontmatter name='$decl' does not match dir '$name'" >&2
        bad=$((bad+1))
      fi
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every SKILL.md frontmatter has a non-empty description" {
  bad=0
  for sk in "$ANVIL_ROOT"/skills/*/; do
    if [ -f "${sk}SKILL.md" ]; then
      desc=$(awk '/^---$/{c++; next} c==1' "${sk}SKILL.md" | grep -E '^description:' | head -1)
      if [ -z "$desc" ]; then
        echo "missing description: ${sk}SKILL.md" >&2
        bad=$((bad+1))
      fi
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "no SKILL.md references project-private strings" {
  bad=0
  for sk in "$ANVIL_ROOT"/skills/*/; do
    if [ -f "${sk}SKILL.md" ]; then
      if grep -qiE "theirownstory|BookGen|agoku64" "${sk}SKILL.md"; then
        echo "project-private string in: ${sk}SKILL.md" >&2
        bad=$((bad+1))
      fi
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every script under skills/*/scripts/ passes bash -n" {
  bad=0
  while IFS= read -r sh; do
    if ! bash -n "$sh" 2>/dev/null; then
      echo "syntax error in: $sh" >&2
      bash -n "$sh" 2>&1 | head -3 >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills" -path "*/scripts/*" -name "*.sh" -type f)
  [ "$bad" -eq 0 ]
}

@test "no script references project-private strings" {
  bad=0
  while IFS= read -r sh; do
    if grep -qiE "theirownstory|BookGen|agoku64" "$sh"; then
      echo "project-private string in: $sh" >&2
      bad=$((bad+1))
    fi
  done < <(find "$ANVIL_ROOT/skills" -path "*/scripts/*" -name "*.sh" -type f)
  [ "$bad" -eq 0 ]
}

@test "shared/lib.sh passes bash -n" {
  run bash -n "$ANVIL_ROOT/shared/lib.sh"
  [ "$status" -eq 0 ]
}

@test "shared/lib.sh does not reference project-private strings" {
  run grep -iE "theirownstory|BookGen|agoku64" "$ANVIL_ROOT/shared/lib.sh"
  [ "$status" -ne 0 ]
}

@test "every script under bin/ passes bash -n" {
  bad=0
  for sh in "$ANVIL_ROOT/bin"/*.sh; do
    if ! bash -n "$sh" 2>/dev/null; then
      echo "syntax error in: $sh" >&2
      bad=$((bad+1))
    fi
  done
  [ "$bad" -eq 0 ]
}
