---
name: config-bootstrap
description: Use once per project that adopts anvil to populate `.anvil/forbidden-patterns.txt` + `.anvil/dispatch-defaults.txt` + `.anvil/known-flakes.txt` from the project's existing context docs (CLAUDE.md / AGENTS.md / README / post-mortems). Closes the "AI assistant manually populates each starter template" step. Invoke with /config-bootstrap [--from-doc <path>] or when the operator says "populate the .anvil/ configs", "bootstrap from CLAUDE.md", "fill in the rules from our docs".
---

# /config-bootstrap — derive `.anvil/` configs from the project's context docs

`bin/init-anvil-config.sh` writes starter templates with placeholders and "AI assistant: replace these" intros. This skill is what the AI assistant runs to do the populate step.

For each `.anvil/` config file, scan the project's context docs (CLAUDE.md, AGENTS.md, README.md, `docs/post-mortems/*.md`, `docs/audits/*.md`) for rules that match the file's purpose, then write them into the file.

## When to invoke

- Operator just ran `bin/init-anvil-config.sh` for a fresh project — the placeholder examples need replacing with real rules.
- Operator says "populate the .anvil/ configs", "bootstrap from CLAUDE.md", "derive the rules from our docs".
- Adopting anvil on a new repo — this is the second-step companion to `init-anvil-config.sh`.

## When NOT to use

- `.anvil/` already has populated, project-specific rules — this would overwrite them. Use `/refine-plan` or manual edits instead.
- Project has no context docs — there's nothing to derive from. Operator has to write rules from scratch.
- The operator wants different rules from what the docs imply — manual edit is faster.

## Args

| Arg | Required | Description |
|---|---|---|
| `--from-doc <path>` | no | Specific doc to derive from (default: scan CLAUDE.md, AGENTS.md, README.md, docs/post-mortems/*.md, docs/audits/*.md) |
| `--target <file>` | no | One of `forbidden-patterns`, `dispatch-defaults`, `known-flakes`, `all` (default: `all`) |
| `--dry-run` | no | Print proposed updates as a diff without writing |
| `--merge` | no | Merge with existing rules instead of replacing (default: replace placeholders only; preserve real rules) |

## Procedure

### Step 1: Inventory the source docs

```bash
docs=()
[ -f CLAUDE.md ] && docs+=(CLAUDE.md)
[ -f AGENTS.md ] && docs+=(AGENTS.md)
[ -f README.md ] && docs+=(README.md)
docs+=( $(ls docs/post-mortems/*.md docs/audits/*.md 2>/dev/null) )
```

### Step 2: Extract rules per target file

For `forbidden-patterns.txt`:
- Look for "DO NOT", "must not", "never use", "do not import", "deprecated", "deleted in", "removed in"
- Extract the named pattern (`@vendor/sdk`, `core/<module>`, `console.log`, `--no-verify`)
- Extract the path scope (e.g. "outside src/model/", "in production code")
- Format as `<regex> :: <path-glob> :: <exclusion-glob> :: <comment>` per the file's existing format

For `dispatch-defaults.txt`:
- Look for "always", "every PR must", "default", "tests must", "commit message format"
- Extract the imperative form
- One constraint per line

For `known-flakes.txt`:
- Look for "flake", "flaky", "retry once", "known race", "intermittent"
- Extract the test name pattern
- One regex per line

### Step 3: Diff against existing file content

If the file currently contains only the AI-assistant-intro + placeholder examples (i.e. the `init-anvil-config.sh` output unchanged), replace fully.

If it has real rules already, append the new rules (with `--merge`) or warn (default).

### Step 4: Write the files

Preserve the existing AI-assistant-intro block at the top of each file. Replace the placeholder section with the derived rules.

### Step 5: Output a summary

```
=== /config-bootstrap ===
Source docs: CLAUDE.md, docs/post-mortems/2026-04-27-paid-api-incident.md, docs/audits/2026-04-28-v2-quality-audit.md

forbidden-patterns.txt: 18 rules derived (Phase 8 ModelGateway boundary, LOCK-1 provider boundary, deleted modules core/claude.js + core/gemini.js, V3 ESM scope, BEGIN-IMMEDIATE-await trap, hardcoded vendor secrets, console.log in production, --no-verify)
dispatch-defaults.txt: 14 constraints derived (vendor SDK boundary, test-infra invariants, production quality floor, security boundaries, V3 ESM scope, DB transaction safety, no-auto-retry billing safety)
known-flakes.txt: 5 patterns derived (worker-crash flake, regenerate-credit-race, Stripe sandbox, Lulu sandbox, screenshot-diff)

Review the files; edit by hand if any derived rule is too tight or too loose.
```

### Step 6: Suggest follow-up

After bootstrap, recommend the operator:
1. Open the generated files; sanity-check the derived rules.
2. Run `npx vitest run test/architecture/fitness.test.js` (or equivalent) — if anvil's pre-merge gate is wired, the new rules apply immediately.
3. Run `bin/preflight.sh` to verify the broader environment.

## Composition

- Pairs with `bin/init-anvil-config.sh` — that writes the placeholder templates; this fills them in.
- The output is consumed by `/pre-merge-gate` (forbidden-patterns + known-flakes) and `/dispatch-slice` (dispatch-defaults).
