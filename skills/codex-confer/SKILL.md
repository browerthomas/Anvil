---
name: codex-confer
description: Use to get an adversarial cross-model opinion on a design, scoping, or approach question via OpenAI Codex CLI. Invoke with /codex-confer "<question>". Codex is prompted to push back, find weaknesses, and name trade-offs you might be hiding from yourself — not to validate. Use when you're about to commit to an approach and want a second pair of eyes from a different model family.
---

# /codex-confer — adversarial design consultation

Wraps `codex exec` with an adversarial prompt template. The point is **disagreement**, not validation.

## When to use

- You've designed an approach and want a sanity check before implementing.
- You're scoping a slice and want to know what you're under-thinking.
- You're stuck between two approaches and want a tiebreaker that won't just defer to your framing.

## When NOT to use

- For factual lookups ("what does this code do?") — use `/codex-check` or just read the code.
- For diff review — use `/codex-review`.
- For trivial questions — just decide and move on.

## Procedure

1. **Frame the question for adversarial input.** Don't ask "is this a good idea?" — Codex will tend to agree. Instead, ask:
   - "What's wrong with this approach? What am I not seeing?"
   - "Argue against doing X. What's the strongest case for the alternative?"
   - "What corner case does this design miss?"
2. **Bundle relevant context.** Codex starts cold — give it file paths or paste the design sketch. Don't paste 1000 lines; the helper passes through to `codex exec` which can read files itself.
3. **Run the helper:**

```bash
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" confer exec -- "$(cat <<'EOF'
You are reviewing a design decision adversarially. Push back. Find what's weak. Name the trade-offs the proposer is hiding from themselves. Do NOT default to agreement.

**Exploration budget:** read each referenced file ONCE. Do NOT re-grep the codebase to verify upstream claims — the context provided IS your input, not a starting point for re-investigation. Reserve the majority of your reasoning budget for synthesis, not exploration. If you run out of budget mid-thought, return what you have rather than continuing to explore.

Context: [your context here, or file paths Codex should read]

Question: [the actual question]

Response budget: ≤2000 words. Skip categories that have no findings — do not pad.

Format your reply as:
1. Strongest counter-argument
2. Specific risks with concrete failure modes
3. Verdict — does the approach hold up, with what changes

End your response with exactly one of these lines on its own:
`VERDICT: APPROVED` — design holds up; no P0/P1 findings worth blocking on.
`VERDICT: REVISE` — found P0/P1 issues that should be addressed before proceeding.

This makes the response machine-parseable for iteration loops without losing the nuance above.
EOF
)"
```

**Reasoning effort:** leave the helper at its default (`medium`). Do NOT override to `high` unless you have evidence the question genuinely needs it — high reasoning + many context files burns the budget on exploration loops and you get an empty response. The retry-on-empty fallback in the helper will drop to `low` if codex returns nothing, but it's better not to need the fallback.

4. **Synthesise the response.** Apply the same filter as `/codex-review`:
   - Did Codex find a real weakness?
   - Did it disagree with your reasoning, and is the disagreement substantive?
   - If Codex says "yes this is fine," consider whether the prompt was too leading and the answer is therefore weak signal.
5. **Decide.** Either course-correct based on the pushback, or hold your line and explain why Codex's pushback doesn't apply (which is also useful — you'll have refined the reasoning).

## When it's worth firing

Subscription-billed (no per-call cost), but each run is 30-90s wall-clock plus your synthesis time. The ceiling that matters: don't fire `/codex-confer` more than 2-3× on the same question. Disagreement loops with diminishing returns are a smell — at that point, write the decision down, name the trade-off you're accepting, and move on.
