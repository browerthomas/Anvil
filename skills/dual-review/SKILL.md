---
name: dual-review
description: Use when codex is available + a diff is high-stakes (money / auth / storage / state machine / >500 LoC) and you want both adversarial reviewers firing in parallel before merge. Runs /self-review (Claude) and /codex-review (Codex) concurrently, then emits a single agreement table — Both / Claude only / Codex only — so cross-model agreement signal is visible. Invoke with /dual-review (uncommitted), /dual-review main (vs base), /dual-review <SHA>, /dual-review --pr <N>, or when the operator says "dual review", "both reviewers", "run claude and codex on this".
---

# /dual-review — Claude + Codex in parallel, one synthesized findings table

`/self-review` runs Claude as the adversarial reviewer. `/codex-review` runs OpenAI Codex. Each catches different things — same-family blind spots vs cross-family blind spots. Today operators pick one based on whether codex is rate-limited.

`/dual-review` fires both in parallel, then synthesizes into a single table with a `Source` column:

| Severity | Source | Summary | File:Line | Fix |
|---|---|---|---|---|
| P0 | Both | Missing CSRF check on /admin/refund | web/routes/admin.js:142 | Add `csrfProtection` middleware |
| P1 | Claude only | Unbounded retry loop on Stripe 5xx | core/stripe.js:88 | Cap at 3 attempts with backoff |
| P1 | Codex only | SQL injection via raw `${orderId}` in repo query | src/order/repo.ts:215 | Use prepared statement |

**Cross-model agreement** (Both) is the strongest signal in adversarial review. If two different model families flag the same line, it's almost certainly real. Disagreements (one-only) are blind-spot complements — usually both worth fixing, but the operator gets to make the call.

Source: gstack research (`research/gstack-comparison-2026-05-11.md`). gstack's `/autoplan` runs both by default and synthesizes; anvil today treats them as alternatives. `/dual-review` closes that gap.

## When to invoke

Use `/dual-review` when **all** apply:

- Codex is available (not rate-limited / out).
- Diff touches a high-stakes surface: **payments, auth, storage, state machines, schema migrations, security-critical paths**.
- OR diff is **>500 LoC** (where single-pass review misses scale).
- OR the operator explicitly wants the agreement signal ("is this really clean?").

For everything else (trivial diffs, doc-only changes, code the same agent just wrote and self-reviewed): `/self-review` or `/codex-review` alone are sufficient.

## When NOT to invoke

- **Codex rate-limited / unavailable.** `/dual-review` degrades to `/self-review`-only with a banner warning the operator that this run is strictly weaker signal (no cross-model). If the operator wants only Claude, invoke `/self-review` directly — it's cleaner.
- **Trivial diff.** One-line config tweak, copy edit, doc-only PR. Latency outweighs marginal value.
- **Same author + reviewer.** If Claude just wrote the diff via `/dispatch-slice`, running `/self-review` is mostly redundant — go straight to `/codex-review` (or `/dual-review` if you want both lenses).
- **Already reviewed.** If `/codex-review` or `/self-review` just landed in `.codex-log/` and there's no new diff, re-running both is waste.

## Argument shapes

Same shape as `/self-review` and `/codex-review`. Args before `--` set the diff scope; flags can be mixed in.

| Args | Diff scope |
|---|---|
| (none) | uncommitted (staged + unstaged + untracked) |
| `main` (or any branch name) | current branch's diff vs base branch |
| `<SHA>` | that specific commit |
| `--pr <N>` | fetch PR #N's diff via `gh pr diff <N>` |

Flags:

| Flag | Behavior |
|---|---|
| (default) | One Claude self-review + one Codex review, parallel, synthesized |
| `--multi-critic` | Claude leg becomes `/self-review --multi-critic` (4 critics + synth) + Codex leg unchanged. 6 agents total. Use on highest-stakes diffs. |
| `--no-codex` | Skip Codex even if available — degrades to Claude-only (equivalent to `/self-review`). Useful if codex looks degraded or the operator has reason to suspect cross-family agreement won't help. |
| `--focus "<text>"` | Pass a focus hint to both legs (e.g. `--focus "race conditions in outbox dispatch"`). Both reviewers stay in lane. |

## Procedure

### 1. Confirm we're in a git repo

```bash
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
```

Bail if not.

### 2. Build the diff text

Same logic as the underlying skills — use the arg table above. Capture diff to a temp file so both legs read the same input.

```bash
# uncommitted
git diff HEAD > /tmp/dual-review-diff.patch
git diff --staged >> /tmp/dual-review-diff.patch

# against base
git diff "<base>...HEAD" > /tmp/dual-review-diff.patch

# specific commit
git show "<SHA>" > /tmp/dual-review-diff.patch

# PR
gh pr diff "<N>" > /tmp/dual-review-diff.patch
```

### 3. Cap diff size at 4000 lines

If `wc -l /tmp/dual-review-diff.patch` > 4000, ask the operator to split or pick a focused subset. Reviewing 10k+ lines burns budget without finding more — same rule both underlying skills apply.

### 4. Check codex availability

```bash
if ! command -v codex >/dev/null 2>&1; then
  echo "codex not installed — degrading to /self-review only"
  CODEX_AVAILABLE=false
fi
```

Also surface a quick health check — `codex --version` returning fast is enough. If codex is rate-limited the call inside step 5 will return a quota error; treat that as availability=false and continue with the Claude-only leg.

If `--no-codex` is set, force `CODEX_AVAILABLE=false`.

### 5. Fire both reviewers in parallel

**This is the load-bearing step.** Both legs must run concurrently — sequential firing defeats the purpose (cross-model agreement is the value, and the operator pays the full latency anyway).

Use the `Agent` tool with `run_in_background: true` to spawn two sub-agents in one tool-call batch:

- **Claude leg** — subagent_type: `general-purpose`, model: `opus`. Prompt: invoke `/self-review` against the diff in `/tmp/dual-review-diff.patch` with the same focus hint. If `--multi-critic` is set on `/dual-review`, the Claude leg gets `--multi-critic` too (so 4 critics + 1 synthesizer in that sub-agent's session).
- **Codex leg** — subagent_type: `general-purpose`, model: `opus` (the sub-agent itself runs in Claude; it shells out to `codex review` via the helper). Prompt: invoke `/codex-review` against the same diff with the same focus hint.

Both sub-agents return a structured findings markdown. Wait for both to complete (the `Monitor` tool can stream the events if the operator wants live progress; otherwise the background-Agent IDs are tracked and the parent waits for both to finish).

**If only the Claude leg ran** (codex unavailable / `--no-codex`): skip step 6 — emit a banner warning and pass the Claude leg's output through directly with the table reduced to `Severity | Summary | File:Line | Fix` (no `Source` column, since there's nothing to compare).

### 6. Spawn a synthesizer sub-agent

Use the `Agent` tool one more time (foreground; we need the output inline) with `templates/synthesizer.md` as the prompt prefix. The synthesizer receives:

- The Claude leg's full findings markdown.
- The Codex leg's full findings markdown.
- The original diff scope description.

It returns a single table in the shape above, plus a verdict block (`AGREE / DISAGREE-ON-SEVERITY / COMPLEMENT-ONLY / CLEAN`).

### 7. Save the merged transcript

```bash
out=".codex-log/$(date +%Y%m%d-%H%M%S)-dual-review.md"
cat > "$out" <<EOF
# /dual-review — $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Diff scope: <args summary>
Diff size: <lines> lines
Multi-critic: <yes|no>
Codex available: <yes|no>

## Claude leg

$(cat <claude-leg-output>)

## Codex leg

$(cat <codex-leg-output>)

## Synthesis

$(cat <synthesizer-output>)
EOF
```

If only the Claude leg ran, omit the Codex leg section and replace synthesis with a "no synthesis — single-source" note.

### 8. Synthesise back to the operator

Print to the operator's terminal:

- Top of the synthesis table (P0/P1 rows first).
- Agreement breakdown: `N findings — A both, B Claude-only, C Codex-only`.
- Verdict line.
- Path to the saved transcript.

If the synthesis verdict is `BLOCK` or there are P0/P1 findings, suggest invoking `/findings-rollup` against the transcript to file P2/P3 and dispatch a fix-up agent.

## Composition

- **Wraps:** `/self-review` + `/codex-review`. Doesn't replace them — they remain invocable standalone.
- **Calls:** the `Agent` tool (3x: 2 parallel reviewers + 1 synthesizer; or 6x with `--multi-critic`).
- **Composes with:** `/findings-rollup` on the output (file P2/P3 issue + dispatch fix-up agent).
- **Used by:** `/grind` can opt into `/dual-review` for slices flagged high-stakes in the plan manifest (`review: dual` per slice). When not specified, `/grind` continues to use the single-reviewer default.

## Codex fallback

If codex is unavailable mid-run (e.g. rate limit fires only inside the Codex sub-agent's call), the parent gets the empty/failed Codex leg back. In that case:

- The Claude leg's output stands alone.
- A banner is printed: `⚠ Codex unavailable; this run is Claude-only — strictly weaker signal. Cross-model agreement was the value-add and it's gone. Treat findings with the same caution as a /self-review-only pass.`
- Save the transcript with `codex_available: false` in the header so the paper trail is honest.

Never silently degrade. The operator made the call to invoke `/dual-review` because they wanted the dual signal — losing one leg has to be visible.

## Trade-offs

- **Latency.** 2 reviewers in parallel + 1 synthesizer ≈ 60-120s wall-clock (vs ~30-60s for one). With `--multi-critic` (6 agents) the Claude leg dominates at ~90s + synth.
- **Agent budget.** 3 agents per default invocation, 6 with `--multi-critic`. Reserve for high-stakes diffs.
- **Subscription budget on Codex.** Codex calls are subscription-billed (ChatGPT, no per-token cost) but rate-limited. Don't fire `/dual-review` on every slice in a grind — pick the slices that touch money / auth / storage / state machines.

## Manual smoke test

To verify `/dual-review` works after install:

1. Make a trivial edit to a file in any repo (e.g. add a comment to a random `.md`).
2. Run `/dual-review` (no args, against the uncommitted edit).
3. Confirm the output includes:
   - A header block showing both legs ran.
   - A synthesis table with the `Source` column (likely `Both: no findings` since the diff is trivial).
   - A saved transcript at `.codex-log/<timestamp>-dual-review.md`.
4. Run `/dual-review --no-codex` against the same edit. Confirm the output reduces to a Claude-only table with the codex-unavailable banner.
5. Optional: introduce a real bug (e.g. an unguarded null dereference) and re-run. Confirm both legs surface it as `Both` in the synthesis table.

If any step fails, check that:
- `codex` is on `PATH` (try `codex --version`).
- The `Agent` tool can dispatch background sub-agents (test in isolation first).
- `.codex-log/` is writable (the underlying skills use the same directory).
