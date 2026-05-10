# /spec probe questions — used to elicit plan detail

These are the questions /spec asks the operator (via AskUserQuestion) when filling out a plan template. Customise per project.

## 1. Goal probe

**If the operator's intent is < 30 words:**
> What does success look like in plain English? In one paragraph, describe the end state — what changes, what stays, what's measurable about it.

**Validation:** the answer must mention at least one observable property (test passes, deploy works, page loads, metric drops, etc).

## 2. Scope probes

### In-scope
> List 3-7 specific things this plan will deliver. Be specific — "improve auth" is too vague; "add CSRF middleware to v3 routes" is right.

### Out-of-scope (the harder probe)
> Name 3+ things this plan will explicitly NOT do, even if they seem related. The point is to prevent scope creep mid-grind.

**Pushback:** if the operator skips out-of-scope, fire `/codex-confer` with: "Argue against this plan being well-scoped. What's likely to creep in? What's the operator hiding from themselves about effort?" Then surface the response.

## 3. Architecture decisions

For each non-trivial design choice:
> What did you pick? Why this and not the obvious alternative? What did you reject and why?

**Probe pattern:** ask three sub-questions per decision:
- "What's the choice?"
- "What's the alternative you're NOT picking?"
- "Why this over that?"

If only one decision exists, that's fine. If zero — push back: "Are there really no design choices here? Either it's pure mechanical work (skip /spec, just /dispatch-slice) or you haven't thought about it yet."

## 4. Hard constraints

> What inviolable rules apply? Existing project ratchets (no <deprecated-data-shape>

**Default constraints to suggest** (operator approves or rejects each):
- All existing architectural fitness ratchets stay green
- Producer-command-owns-tx pattern intact
- No new env vars unless strictly required
- Test count must increase (no test-deletion to lower the baseline)
- Commit messages follow conventional commits

## 5. Slice decomposition

> How does this decompose into ≤500 LoC chunks? Each chunk should be independently mergeable. Sketch the dependency graph.

**Probe pattern:**
1. "What are the obvious phases?" (e.g. config → types → impl → tests → docs)
2. "Within each phase, what slices are independent (parallel-safe)?"
3. "What slices depend on what?"

**Validation:** if any slice is >800 LoC, push back: "This slice is too big — how could it split?"

## 6. Per-slice acceptance criteria

For each slice:
> What test pins this slice as done? Specifically — what assertion, against what input, expecting what output?

**Probe pattern:**
- "If a future change accidentally regressed this slice's behaviour, what test would catch it?"
- "What's the negative case — when should this code REFUSE to do something?"

If no test can be written: "What's the manual verification? (UI screenshot? Log line? Operator command output?)"

## 7. Operator decision points

> Where in this plan would you want to be ASKED before the orchestrator continues?

**Examples:**
- Before a destructive migration runs
- Before flipping a feature flag in prod
- Before merging a PR that touches billing
- Before deleting a piece of legacy code

For each ASK point:
- "What's the question?"
- "What's the default if you're unreachable for >N hours?" (skip-with-warning, retry, abort)

If the operator says "no decision points needed" — confirm with: "So /grind can run fully autonomous, top-to-bottom? No human checkpoints?"

## 8. Validation checklist

> Once execution finishes, what does the operator need to verify before declaring the plan complete?

This becomes the plan's final checklist — both for /grind to mark slices complete and for the operator to do a final review.

## When to skip /spec

- Single-PR work — just /dispatch-slice.
- Exploration ("see if X is possible") — fire a research agent instead.
- Operator already has a complete plan — just /grind it.
- The "plan" would be 90% of the work — /spec is for thinking, not for hiding implementation in spec.

## Handling drift mid-execution

If the operator changes their mind during /grind (new constraint, scope cut, slice merged externally):

> The plan you signed at <timestamp> said X. The operator now wants Y. Update the plan?
> - yes → re-run validation, re-execute pending slices with new constraints
> - no, just for this slice → patch the slice scope, keep the rest of the plan
> - cancel → halt /grind, leave merged slices in main, operator decides

Never silently change a locked plan. Drift must be explicit.
