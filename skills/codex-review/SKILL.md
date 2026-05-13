---
name: codex-review
description: Use to get a cross-model second opinion on a diff via OpenAI Codex CLI. Invoke with /codex-review (uncommitted), /codex-review main (against base branch), or /codex-review <SHA> (specific commit). Useful before opening a PR, before merging, or after a refactor — Codex catches things the orchestrator misses, especially structural issues and missed edge cases.
---

# /codex-review — cross-model code review

Wraps `codex review` with the same defaults the rest of the codex-* skills use: read-only sandbox, clean final answer, full call logged under `.codex-log/`.

## Usage

The args after `/codex-review` decide which diff Codex reviews:

| Args | Diff scope |
|---|---|
| (none) | `--uncommitted` — staged + unstaged + untracked changes |
| `main` (or any branch) | `--base main` — current branch's diff vs the base |
| `<SHA>` | `--commit <SHA>` — that specific commit |

If the operator passes other text (e.g. "focus on auth"), pass it as a custom prompt that augments the default review.

## Procedure

1. **Confirm we're in a git repo** — if not, ask the operator to confirm or skip.
2. **Pick the codex args** from the table above based on `$ARGUMENTS`.
3. **Run the helper** — it handles output capture + logging:

```bash
# Example: review uncommitted changes
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" review review --uncommitted

# Example: review against main
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" review review --base main

# Example: review a specific commit
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" review review --commit abc1234

# Example: review uncommitted with a custom focus
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" review review --uncommitted -- "Focus on race conditions and idempotency."
```

4. **Read Codex's output and synthesise.** Don't just dump it back to the operator — Codex's reviews are often verbose and include points you've already considered. Filter to:
   - **Real issues** worth acting on (with file:line refs)
   - **Disagreements** between Codex and your prior reasoning (highlight these — that's where the cross-model value is)
   - **Followups** the operator should know about even if not blocking
5. **Decide whether to act.** If Codex flags something genuine, propose a fix. If you disagree with Codex, say so explicitly and explain why — don't just defer because Codex said it.

## When it's worth firing

The operator runs Codex on a ChatGPT subscription, so calls are subscription-billed (no per-token cost). The bottleneck is wall-clock — a typical `codex review` is 30-90s and the operator has to wait for the synthesis. Fire it when the wait is worth it:

- Pre-merge of a multi-file feature slice
- After a refactor that touches a critical surface (auth, payments, state machine, schema)
- When you have a nagging doubt and want a sanity check
- When you want a structural opinion that a unit-test pass wouldn't surface

Skip it for trivial changes (one-line config tweaks, doc-only PRs, copy edits) — the latency outweighs the marginal value.
