---
name: codex-plan
description: Use to ask Codex to write its own implementation plan for a non-trivial task BEFORE the orchestrator executes, then compare the two plans for disagreements. Invoke with /codex-plan "<task description>". Catches scoping mistakes and hidden dependencies that only surface mid-execution. Especially useful before multi-slice work like a generation-pipeline rebuild or schema cutover.
---

# /codex-plan — independent planning second opinion

Wraps `codex exec` with a planning-focused prompt template. Codex returns its own implementation plan; the orchestrator reads it, compares to its own plan, and surfaces the disagreements before either is executed.

## When to use

- About to start a multi-slice or multi-day task and want a sanity check on scope.
- Have a sketch of an approach but haven't pinned down the slicing.
- Already have your own plan and want to know what you're missing.
- A previous slice surprised you mid-execution and you want to scope the next one more carefully.

## When NOT to use

- Trivial single-slice work — over-engineering.
- When you already have a written plan AND have run `/codex-confer` against it — that's a more direct adversarial review.
- When the task is already in progress — too late, just course-correct.

## Procedure

1. **State the goal precisely.** Not "implement the new pipeline" — too vague. Instead: "Lift the order-processing orchestration into the new typed service behind the worker's `process` seam. Processing must be idempotent under worker re-claim. SDK calls go through the existing typed gateway modules. Keep the lift sliceable."

2. **Run the helper:**

```bash
bash "$ANVIL_ROOT/skills/_codex-shared/run-codex.sh" plan exec -- "$(cat <<'EOF'
Write an implementation plan for the task below. Independent of any plan that already exists — don't ask me for context I haven't given.

Goal: [precise goal statement]

Constraints:
[hard requirements — atomicity, test discipline, etc.]

Out of scope:
[what to explicitly NOT touch]

**Exploration budget:** read named files at most twice each. Reserve the majority of your reasoning budget for slicing + synthesis, NOT codebase exploration. If you can't fit the full plan in budget, return the slicing you have rather than continuing to grep.

Response budget: ≤3000 words.

Format your plan as:
1. **Slicing** — propose how to break this into 2-5 PR-sized slices. For each, name what's in / out / which existing modules it touches.
2. **Hidden risks** — what's likely to break or surprise mid-execution. Race conditions, schema migration ordering, test infrastructure gaps, vendor-lock-in.
3. **Open questions** — what would you ask before writing the first line of code.
4. **Recommended first slice** — the smallest piece that proves the boundary contract.

Do NOT write code. The plan is the output.
EOF
)"
```

**Reasoning effort:** leave the helper at its default (`medium`). Override to `high` only for genuinely complex multi-slice plans where the deps are non-obvious — and even then, watch the verbose log: if codex is still grepping after 60s, the prompt is too open-ended.

3. **Compare to your own plan.** This is the actual value — the *delta* between Codex's slicing and yours:
   - **Same slicing** → high confidence the scoping is right.
   - **Different slicing** → at least one of you is wrong about the natural seams. Read both, decide which feels more honest.
   - **Codex flags a risk you didn't** → take it seriously. Write the mitigation into your plan before starting.
   - **Codex misses a risk you flagged** → confirm your risk is real (Codex's silence ≠ "doesn't exist"; verify the constraint).

4. **Update your plan or proceed.** If Codex's plan is materially better, adopt it. If yours is, log the disagreement (commit message or session memory) so the next time the question comes up you remember why you held the line.

## When it's worth firing

Subscription-billed; ~60-120s wall-clock for a multi-slice plan. Worth it for any task where you'd otherwise spend an hour writing the plan yourself — Codex's first draft saves the warm-up cost. Worth it especially for tasks with non-obvious slicing (e.g. anything that touches schema + workers + UI in the same feature).

Skip for one-shot fixes or work where the slicing is obvious from the issue.
