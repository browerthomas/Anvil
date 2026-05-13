---
name: codex-debug
description: Use to feed a stack trace, error message, or test failure to Codex with relevant code, asking it to find the bug. Invoke with /codex-debug "<error or symptom>". Codex's fresh eyes are cheap when you've been staring at a bug for >15 minutes — different model family, different blind spots.
---

# /codex-debug — fresh-eyes bug hunt

Wraps `codex exec` with a debugging-focused prompt template. Codex gets the symptom + repro context and goes hunting in the codebase.

## When to use

- You've been stuck on a bug for >15 min and want a fresh pair of eyes.
- A test is failing in a way that doesn't match your mental model of the code.
- A production error trace lands in the inbox and you don't immediately see the cause.
- You suspect a race / ordering / atomicity bug but can't isolate it.

## When NOT to use

- The first 15 minutes of a bug — you usually know more than Codex does at that point.
- Trivial bugs you've already root-caused — just fix it.
- Symptoms without a repro or trace — give Codex something to bite on.

## Procedure

1. **Gather the evidence.** Codex needs:
   - The error message / stack trace / failing test output
   - The expected behaviour (what SHOULD happen)
   - One or two file paths where you suspect the bug lives, OR a confirmation that you have no suspect (Codex will hunt)
   - Any recent changes that might have introduced the regression

2. **Run the helper:**

```bash
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" debug exec -- "$(cat <<'EOF'
You are debugging a bug. Find the root cause, not just a symptom-suppressor.

Symptom:
[paste error / failing test output]

Expected behaviour:
[what should happen]

Suspected file(s):
[file paths or "no suspect — please hunt"]

Recent changes that might be relevant:
[recent commit messages, refactors, or "unknown"]

Find the bug. Cite the specific file:line that's wrong. If the fix is non-obvious, suggest it but flag the trade-offs. If it's a Heisenbug (timing / ordering / environment), say so explicitly so I don't go chasing a phantom.
EOF
)"
```

3. **Synthesise.** Apply standard cross-model filtering:
   - Did Codex find the actual bug, or a plausible-looking but wrong cause? Verify before acting.
   - Cite the file:line, then read the code yourself before you patch.
   - If Codex says "Heisenbug" or "I can't tell from static analysis," that's a signal to add observability (logs / asserts) rather than guess at a fix.

4. **If Codex's diagnosis matches your suspicion** — bug confirmed, write the fix. If it diverges — read both candidates carefully, decide which is the real bug, document the disagreement in the commit message if you went with one over the other.

## When it's worth firing

Subscription-billed; ~30-60s wall-clock. The ceiling is "are you 80% sure where the bug is?" — if yes, just fix it. If no, fire `/codex-debug`.

Don't fire it on a stack trace from third-party code (Codex doesn't know your repo's vendor pins). Don't fire it on a test that's flaky for known infra reasons (e.g. CI worker contention) — fix the infra instead.
