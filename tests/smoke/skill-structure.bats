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

# Four-way skill-count consistency — closes anvil#24.
#
# The drift that motivated this assertion: docs/index.html had two stale
# references ("thirteen", "installed 14 skills") that survived three skills
# landing because no automated check tied prose to ground truth. Now we
# enforce all four legs of the consistency relationship in one test:
#
#   1. count(README skill mentions matching `(\d+)\s+skills\b`) == landing
#      `data-skill-count` attribute(s) == plugin.json.skills.length
#   2. every plugin.json.skills entry resolves to skills/<name>/SKILL.md
#   3. every skills/*/SKILL.md dir is referenced in plugin.json
#   4. no stale numeric skill-counts hide elsewhere in README or landing
#
# Pinned selectors:
#   README → `(\d+)\s+skills\b` regex (first match wins; current anchor is
#     "17 skills" in the Skills section header)
#   Landing → `data-skill-count="N"` HTML attribute (one per visible region:
#     the credibility badge + the disclosure summary)
@test "four-way skill-count consistency (README, landing, plugin.json, skills/ dir)" {
  plugin_count=$(jq '.skills | length' "$ANVIL_ROOT/.claude-plugin/plugin.json")
  dir_count=$(find "$ANVIL_ROOT/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')

  # Rule 3: every plugin.json skills entry resolves to a SKILL.md on disk.
  while IFS= read -r entry; do
    skill_md="$ANVIL_ROOT/$entry/SKILL.md"
    if [ ! -f "$skill_md" ]; then
      echo "plugin.json references missing SKILL.md: $skill_md" >&2
      return 1
    fi
  done < <(jq -r '.skills[]' "$ANVIL_ROOT/.claude-plugin/plugin.json")

  # Rule 4: every skills/*/SKILL.md is referenced in plugin.json.
  bad=0
  for skill_dir in "$ANVIL_ROOT"/skills/*/; do
    name=$(basename "${skill_dir%/}")
    if ! jq -e --arg n "skills/$name" '.skills | index($n)' \
         "$ANVIL_ROOT/.claude-plugin/plugin.json" >/dev/null; then
      echo "orphan skill dir not in plugin.json: skills/$name" >&2
      bad=$((bad+1))
    fi
  done
  [ "$bad" -eq 0 ]

  # Belt-and-braces: dir count and plugin.json count must agree before we
  # cross-check prose.
  if [ "$plugin_count" -ne "$dir_count" ]; then
    echo "plugin.json count ($plugin_count) != skills/ dir count ($dir_count)" >&2
    return 1
  fi

  # README pin: first `(\d+) skills` mention.
  readme_count=$(grep -oE '\b[0-9]+ skills\b' "$ANVIL_ROOT/README.md" \
                   | head -1 | grep -oE '^[0-9]+')
  if [ -z "$readme_count" ]; then
    echo "README.md missing pinned skill-count anchor matching '(\\d+) skills\\b'" >&2
    return 1
  fi
  if [ "$readme_count" -ne "$plugin_count" ]; then
    echo "README skill count ($readme_count) != plugin.json count ($plugin_count)" >&2
    return 1
  fi

  # Landing pin: every `data-skill-count="N"` attribute. At least one must
  # exist; all values must equal plugin_count. Use a portable while-read loop
  # rather than `mapfile`, which isn't available on every bats host.
  landing_count_total=0
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    landing_count_total=$((landing_count_total + 1))
    if [ "$v" -ne "$plugin_count" ]; then
      echo "docs/index.html data-skill-count=$v != plugin.json count ($plugin_count)" >&2
      return 1
    fi
  done < <(grep -oE 'data-skill-count="[0-9]+"' "$ANVIL_ROOT/docs/index.html" \
             | grep -oE '[0-9]+')
  if [ "$landing_count_total" -eq 0 ]; then
    echo "docs/index.html missing pinned data-skill-count attribute" >&2
    return 1
  fi

  # Rule 4 cross-check: NO stale digit-form skill counts hide elsewhere.
  # Any `\d+ skills\b` reference (case-insensitive) in README or landing must
  # equal $plugin_count. Catches "installed 16 skills" / "all 14 skills" /
  # "Show all 13 skills" drift the way anvil#24 originally specified.
  for f in "$ANVIL_ROOT/README.md" "$ANVIL_ROOT/docs/index.html"; do
    while IFS=: read -r line_no match_content; do
      [ -z "$line_no" ] && continue
      n=$(echo "$match_content" | grep -oE '[0-9]+ skills\b' | head -1 \
            | grep -oE '^[0-9]+')
      [ -z "$n" ] && continue
      if [ "$n" -ne "$plugin_count" ]; then
        echo "stale skill-count in $f:$line_no — found '$n skills', expected '$plugin_count skills'" >&2
        echo "  context: ${match_content:0:120}" >&2
        return 1
      fi
    done < <(grep -niE '\b[0-9]+ skills\b' "$f" || true)
  done

  # Same for word-form references — current canonical word matches plugin_count.
  # Map plugin_count → its English word so we can detect stale words. Only
  # word-forms that explicitly refer to *skills* are checked (e.g. "Sixteen
  # skills" or "all sixteen" inside the skills section). Unrelated copy that
  # happens to use "seventeen" elsewhere is intentionally not policed.
  case "$plugin_count" in
    13) word="thirteen" ;;
    14) word="fourteen" ;;
    15) word="fifteen"  ;;
    16) word="sixteen"  ;;
    17) word="seventeen";;
    18) word="eighteen" ;;
    19) word="nineteen" ;;
    20) word="twenty"   ;;
    *)  word="" ;;  # outside the tracked range; skip word-form check
  esac
  if [ -n "$word" ]; then
    # Match the stale word-forms ONLY in skill-related contexts:
    #   - "<word> skills"
    #   - "all <word>" (covers "Adopt one skill, or all sixteen.")
    stale_alt='thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty'
    skill_word_re="\\b($stale_alt)\\b[[:space:]]+skills\\b|\\ball[[:space:]]+($stale_alt)\\b"
    for f in "$ANVIL_ROOT/README.md" "$ANVIL_ROOT/docs/index.html"; do
      while IFS=: read -r line_no match_content; do
        [ -z "$line_no" ] && continue
        hit=$(echo "$match_content" | grep -oiE "($stale_alt)" | head -1 \
                | tr '[:upper:]' '[:lower:]')
        [ -z "$hit" ] && continue
        if [ "$hit" != "$word" ]; then
          echo "stale word-form skill-count in $f:$line_no — found '$hit', expected '$word'" >&2
          echo "  context: ${match_content:0:120}" >&2
          return 1
        fi
      done < <(grep -niE "$skill_word_re" "$f" || true)
    done
  fi
}
