---
name: codex-check
description: Use to ask Codex a narrow factual yes/no/unsure question about the codebase, with structured output for unambiguous verdict. Invoke with /codex-check "<specific claim>". Forces Codex to commit to a verdict and explain the evidence — useful for "does this code actually do X?" type questions where you want a binding answer, not a hedge.
---

# /codex-check — narrow factual verification

Wraps `codex exec` with `--output-schema` so Codex MUST return a structured `{ verdict, evidence, caveats }` payload. Forces commitment.

## When to use

- "Does this code actually handle race condition X?" — yes/no with file:line evidence.
- "Is this idempotent under retry?" — yes/no with the specific guard / lack thereof.
- "Does the legacy do Y the way I think it does?" — fact-check before lifting.
- "Did my refactor preserve behaviour Z?" — pre-merge sanity check.

## When NOT to use

- Open-ended "what should we do?" questions — use `/codex-confer`.
- Diff review — use `/codex-review`.
- Anything where you'd accept a "maybe" answer — `/codex-check` forces a verdict, so it's wrong if the question is genuinely ambiguous.

## Procedure

1. **Frame the question as a binary claim.** "X handles Y under condition Z" — Codex returns yes/no/unsure with evidence.
2. **Set up the output schema.** Write a tight JSON Schema to a temp file:

```bash
cat >/tmp/codex-check-schema.json <<'JSON'
{
  "type": "object",
  "required": ["verdict", "evidence"],
  "properties": {
    "verdict":   { "type": "string", "enum": ["yes", "no", "unsure"] },
    "evidence":  { "type": "string", "description": "file:line refs and the specific code that supports the verdict" },
    "caveats":   { "type": "string", "description": "what could change the verdict — race conditions, environment-specific behaviour, untested paths" },
    "confidence":{ "type": "string", "enum": ["high", "medium", "low"] }
  }
}
JSON
```

3. **Run the helper with the schema:**

```bash
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" check exec --output-schema /tmp/codex-check-schema.json -- "$(cat <<'EOF'
Verify this claim against the actual code. Commit to a verdict — don't hedge.

Claim: [the specific claim, e.g. "OrderService.refund atomically revokes share + download tokens in the same SQLite transaction as the state flip"]

Return JSON matching the provided schema. The evidence field MUST cite specific files:lines.
EOF
)"
```

4. **Parse the JSON and act.** The helper returns the JSON as the final answer. Read the verdict + evidence:
   - **yes** with high confidence + evidence cited → claim verified, move on.
   - **no** → either fix the bug or update your mental model.
   - **unsure** → either the question was genuinely ambiguous (fix the question) or Codex hit something it couldn't determine (read the caveats).

## When it's worth firing

`/codex-check` is the fastest of the codex-* skills — the schema constraint makes the answer short and the question is narrow. Subscription-billed; the bottleneck is wall-clock (~20-40s).

Fire whenever you'd otherwise be guessing or hand-waving. The structured verdict is binding — that's the point.
