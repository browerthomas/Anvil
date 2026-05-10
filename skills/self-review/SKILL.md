---
name: self-review
description: Use when /codex-review is unavailable (rate-limited / outage / no subscription) and a PR needs adversarial review before merge. Spawns an Opus sub-agent with adversarial prompt template, returns structured findings (P0/P1/P2/P3). Codex-fallback. Invoke with /self-review (uncommitted), /self-review main (against base), /self-review <SHA>, or when the operator says "review the PR yourself" / "without codex" / "second-pair-of-eyes review".
---

# /self-review — adversarial diff review using an Opus sub-agent

When codex is rate-limited or out, this skill substitutes for `/codex-review`. The shape mirrors codex-review's contract:

- Read-only diff inspection
- Adversarial framing (find what's wrong, don't validate)
- Structured P0/P1/P2/P3 findings
- File:line citations on every finding

Trade-off vs codex: same model family (still Claude). The "fresh eyes" cross-model effect of codex doesn't apply. So self-review:
- Catches obvious slips (missed null checks, off-by-one, await-in-tx).
- Catches state-machine + concurrency bugs (Opus is good at these).
- WILL miss: things the original author also missed in the same way (shared model blind spot).

Treat self-review as 70% of codex's value at 0% of codex's per-call cost. Use as fallback, not as primary review when codex is available.

## Argument shapes

| Args | Diff scope |
|---|---|
| (none) | uncommitted changes (staged + unstaged) |
| `main` (or any branch name) | current branch's diff vs base branch |
| `<SHA>` | that specific commit |
| `--pr <N>` | fetch PR #N's diff via `gh pr diff <N>` |

Modes:

| Flag | Behavior |
|---|---|
| (default) | Single-pass adversarial review with the omnibus prompt — fast, catches obvious slips |
| `--multi-critic` | Four parallel critics (correctness, security, test-coverage, architecture) + synthesis pass — slower, dramatically higher catch rate |
| `--critics <list>` | Run a subset (e.g. `--critics correctness,security` for diffs that don't touch test files) |

**When to use multi-critic:** any diff that touches auth, payments, state machines, schema migrations, or that's >500 LoC. The Greptile vs CodeRabbit benchmark (82% catch vs 44%) is mostly explained by multiple specialized lenses + full-codebase context vs one lens + diff-only.

If the operator passes other text (e.g. "focus on auth"), pass it as a custom prompt that augments the default review.

## Multi-critic mode

When `--multi-critic` is set:

1. **Spawn 4 Opus sub-agents in parallel**, each with a different critic prompt from `templates/critics/`:
   - `correctness.md` — logic bugs, race conditions, edge cases
   - `security.md` — auth, injection, CSRF, secrets, sanitization
   - `test-coverage.md` — negative cases, weak assertions, bypassed contracts
   - `architecture.md` — layer boundaries, vendor SDK boundaries, fitness rules

   Each critic gets the same diff text but is told to stay in its lane (skip findings outside its lens).

2. **Wait for all 4 to return.**

3. **Spawn a 5th synthesizer agent** with `templates/synthesizer.md`. It:
   - Deduplicates findings that multiple critics surfaced
   - Re-ranks by severity
   - Identifies cross-critic risk areas (modules surfaced by ≥2 critics)
   - Returns a verdict: `BLOCK | PROCEED-WITH-CAUTION | CLEAN`

4. **Save the full transcript** under `.codex-log/<timestamp>-multi-critic.md` for paper trail.

**Trade-off:** 5x agent cost (4 critics + 1 synthesizer) for ~2x catch rate. Use on high-stakes diffs.

## Procedure

1. **Confirm we're in a git repo.** Bail if not.

2. **Build the diff text** based on args:
   ```bash
   # uncommitted
   git diff HEAD
   git diff --staged
   git ls-files --others --exclude-standard | xargs -I {} cat {}

   # against base branch
   git diff <base>...HEAD

   # specific commit
   git show <SHA>

   # PR
   gh pr diff <N>
   ```

3. **Cap diff size at 4000 lines.** If the diff is bigger, ask the operator to split or pick a focused subset. Self-review on 10k+ lines burns budget without finding more.

4. **Spawn an Opus sub-agent** with the adversarial prompt:

```
You are reviewing a code diff adversarially. Find what's wrong, don't validate.

Diff scope: <args summary>

DIFF:
<diff text>

ADVERSARIAL CONTRACT:

You are looking for bugs, not endorsements. Apply these lenses in order:

1. **Correctness** — does the code do what the commit message claims? Off-by-one, null/undefined misses, type-narrowing bugs, async race conditions, missed edge cases.

2. **State machine + concurrency** — if the diff touches a state machine: are all transitions legal under the contract? If it touches outbox/queue/repo: is the producer-command-owns-tx pattern intact? Are claim_id fences re-checked at the right moments? Is there an await between BEGIN and COMMIT? Does releaseExpiredClaims interact correctly with this change?

3. **Boundary discipline** — does the change respect architectural boundaries? Does it touch <deprecated-data-shape>

4. **Test coverage** — are the new tests pinning the actual contract or just exercising the code path? Are weak assertions used (toContain([200,...,500])) where strong ones would work? Are negative cases covered? Does any test bypass the producer chain in a way that lets a real bug slip through?

5. **Backwards compat** — does the change break any existing caller? Does the diff remove a public field/method/export that other code depends on?

6. **Documentation drift** — does the diff invalidate any claim in CLAUDE.md, the runbook, or other docs? Does it add a new env var without updating .env.example?

OUTPUT FORMAT:

Return findings ONLY. Skip endorsements. For each finding:

- [P0|P1|P2|P3] <one-line summary> — <file>:<line>
  <2-3 sentence explanation>
  <fix suggestion, code if helpful>

Use these severity tiers:
- **P0**: production bug, security issue, or compile/test failure on merge.
- **P1**: real-world failure mode that will fire in production, or significant correctness gap.
- **P2**: design weakness, missing test, or maintainability hit. Not blocking but worth fixing.
- **P3**: nit / cosmetic / cleanup.

If you find NO findings: return literally "No findings." (do not add filler).

Do NOT validate. Do NOT summarize the diff. Do NOT explain what the code does. Just findings.
```

5. **Synthesise the response** for the operator:
   - Filter to real, actionable items.
   - If P0/P1 findings: present prominently with file:line + fix.
   - If only P2/P3: bundle as a follow-up issue suggestion (don't block merge).
   - If "No findings": say so explicitly + give the operator the green light.

6. **Save the review** under `.codex-log/` (same dir as codex-review's logs) with timestamp + scope, so the paper trail is consistent:
   ```bash
   echo "$review" > .codex-log/$(date +%Y%m%d-%H%M%S)-self-review.md
   ```

## When it's worth firing

- Codex is rate-limited or out.
- A PR is mergeable + CI green but you want a sanity check before flipping the merge button.
- Mid-grind, you're about to merge a PR the codex retro will look at later — fire self-review NOW so you don't ship an obvious bug.
- After a refactor that touches a critical surface (auth, payments, state machine, schema).

## When NOT to fire

- Codex is available — use `/codex-review` instead (cross-model is real signal).
- Trivial diffs (one-line config, copy edit, doc-only).
- The agent that wrote the diff already self-reviewed (don't re-review the same model's work twice).

## Cadence

Tonight's session merged 4 PRs without codex review (codex hit limit). Self-review would have caught at least the #1071 backoff×fixture interaction earlier (that bug surfaced 2 PRs later). Use as default fallback.
