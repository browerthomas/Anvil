# Spec: /persona → /lens hard rename contract

> The rename touches a public-facing skill name. Operator's local install will break briefly during the cutover. This spec pins what must work post-merge + what migration is acceptable.

---

## Contract

After Phase C merges:

1. **`/lens <name> "<scope>"`** is the canonical invocation. All docs, smoke tests, CI use this form.
2. **`/persona <name> "<scope>"`** no longer exists as a skill. The directory is gone; the SKILL.md is gone; the resolver script is gone.
3. **Operator's local install** is in a broken state until they run `bin/install.sh` post-merge. `bin/install.sh` auto-invokes the migrator + cleans the old `/persona` install + installs `/lens`.
4. **17 lens content files** (saas/systems/generic) keep their content unchanged. Only the wrapping dir (personas → lenses) + the skill name change. Operator's memory files referencing the lens names (e.g. `systems/sre-incident-responder`) continue to resolve.
5. **No alias** to `/persona`. The intent is a clean break.

---

## What the migrator does

`bin/migrate-persona-to-lens.sh`:

```bash
# 1. Detect old install (symlink or copy)
if [ -L "$HOME/.claude/skills/persona" ] || [ -d "$HOME/.claude/skills/persona" ]; then
  # 2. Check for local modifications
  if [ -d "$HOME/.claude/skills/persona" ] && [ ! -L "$HOME/.claude/skills/persona" ]; then
    # Copy mode: check for diffs vs the original
    if diff -r "$HOME/.claude/skills/persona" "$ANVIL_ROOT/skills/persona-archived-for-migrator" 2>/dev/null; then
      # No local changes; safe to remove
      rm -rf "$HOME/.claude/skills/persona"
    else
      # Local changes; warn + skip
      echo "Skipping migration: ~/.claude/skills/persona has local changes. Use --force to remove anyway."
      [ "$1" != "--force" ] && exit 0
      rm -rf "$HOME/.claude/skills/persona"
    fi
  else
    # Symlink mode: just remove the symlink
    rm -f "$HOME/.claude/skills/persona"
  fi
fi

# 3. Touch a sentinel so install.sh knows this ran
touch "$HOME/.claude/.anvil-lens-migrated"
```

`bin/install.sh` checks for `$HOME/.claude/.anvil-lens-migrated` + runs the migrator if absent.

---

## Failure modes

**Operator forgets to run bin/install.sh post-merge.**
- Symptom: `/persona <name>` fails (skill not found). `/lens <name>` also fails (not yet installed).
- Recovery: operator runs `bin/install.sh`; both symptoms resolve.

**Operator has local modifications to ~/.claude/skills/persona/**
- Symptom: migrator skips by default with a warning.
- Recovery: operator inspects the changes, either commits upstream OR runs `bin/install.sh --force`.

**Operator's MEMORY.md references `/persona <name>`** (their own past sessions)
- Past memory entries are historical. They don't break anything; they just won't be invocable as-is anymore. New sessions use `/lens`. Operator can leave the past entries or update them — operator choice.

---

## Smoke test

`tests/smoke/lens.bats` (renamed from `tests/smoke/personas.bats`):

```bash
@test "/lens systems/sre-incident-responder resolves" {
  run bash "$ANVIL_ROOT/skills/lens/scripts/resolve-lens.sh" systems/sre-incident-responder
  [ "$status" -eq 0 ]
  [[ "$output" == *"P1 page at 3 a.m."* ]]
}

@test "/lens privacy-lawyer (bare name) resolves via cross-category lookup" {
  run bash "$ANVIL_ROOT/skills/lens/scripts/resolve-lens.sh" privacy-lawyer
  [ "$status" -eq 0 ]
}

@test "skills/persona/ no longer exists" {
  [ ! -d "$ANVIL_ROOT/skills/persona" ]
}

@test "bin/install.sh runs the migrator on fresh install" {
  setup_temp_home
  HOME="$TEMP_HOME" bash "$ANVIL_ROOT/bin/install.sh"
  [ -f "$TEMP_HOME/.claude/.anvil-lens-migrated" ]
  [ -e "$TEMP_HOME/.claude/skills/lens" ]
  [ ! -e "$TEMP_HOME/.claude/skills/persona" ]
}
```

---

## What does NOT change

- The 17 lens content files (saas/systems/generic). All prompts unchanged.
- The lens-resolution shape (bare-name lookup, ambiguity error, deprecation shim for `oncall-3am` → `systems/sre-incident-responder`).
- The `{{project_context}}` placeholder + the `.anvil/persona-context.md` → `.anvil/lens-context.md` is RENAMED but the content is preserved.
- The user-facing semantic: "wrap /self-review with a hard-coded role prefix."
