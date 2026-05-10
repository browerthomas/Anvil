---
name: findings-rollup
description: Use after /self-review or /codex-review produces a multi-finding report to (a) file P2/P3 findings as a single rollup issue with checkboxes, and (b) dispatch a fix-up agent against the same PR/branch with the P0/P1 list as its acceptance contract. Closes the manual sequence "synthesize findings → file rollup issue → write fix-up brief → dispatch agent." Invoke with /findings-rollup <path-to-review-md> [--pr <N>] or when the operator says "act on the review", "file the followups", "dispatch the fix-up".
---

# /findings-rollup — file P2/P3 + dispatch fix-up agent from a review report

After `/self-review --multi-critic` or `/codex-review` lands findings in `.codex-log/<timestamp>-<kind>.md`, the operator runs the same 5-step sequence every time:

1. Skim the synthesis verdict.
2. Bundle P2/P3 findings into one rollup issue with checkboxes (because filing each as its own issue is noise).
3. Write a fix-up agent brief that lists the P0/P1 findings as the contract, references the synthesis report path, and inherits the worktree + branch from the original PR.
4. Dispatch the fix-up agent.
5. Comment on the PR linking the rollup issue + fix-up agent ID.

This skill compresses that to one invocation.

## When to invoke

- Operator says "act on the review", "file the followups", "fix-up agent", "dispatch the fix-up", "rollup the findings".
- `/grind` invokes internally after `/self-review --multi-critic` returns BLOCK or PROCEED-WITH-CAUTION.
- After any review pass that produces ≥3 findings or any P0/P1.

## When NOT to use

- Review verdict is CLEAN (no findings) — nothing to file or fix.
- Review surfaced a single P2/P3 — file it as a regular issue, no rollup needed.
- The findings are aesthetic / nit-level — operator should decide on impact, not auto-rollup.

## Args

| Arg | Required | Description |
|---|---|---|
| `<review-path>` | yes | Path to `.codex-log/<ts>-multi-critic.md` (or any review markdown with P0/P1/P2/P3 sections) |
| `--pr <N>` | yes | PR number the review was against |
| `--branch <name>` | no | Worktree branch (auto-derived from PR if omitted) |
| `--skip-fixup` | no | File P2/P3 only; don't dispatch fix-up agent (use when operator wants to handle P0/P1 manually) |
| `--skip-rollup` | no | Dispatch fix-up only; don't file P2/P3 issue (use when P2/P3 are clearly speculative and not worth tracking) |
| `--label <list>` | no | Comma-separated labels for the rollup issue (default: `p2,tech-debt`) |

## Procedure

### Step 1: Parse the review report

Extract the four severity sections from the markdown. Look for headings like `## P0 findings`, `## P1 findings`, `## P2 findings`, `## P3 findings` (or the equivalent shapes the synthesizer emits — `templates/synthesizer.md` is the canonical shape).

For each finding, capture:
- Severity (`P0|P1|P2|P3`)
- Summary (one-line)
- File:line citation
- Explanation (2-3 sentences)
- Suggested fix
- Tagged critics (if multi-critic synthesis)

### Step 2: Decide the action plan

| Found | Rollup issue | Fix-up agent |
|---|---|---|
| P0 only | no | yes |
| P1 only | no | yes |
| P0/P1 + P2/P3 | yes (P2/P3) | yes (P0/P1) |
| P2/P3 only | yes | no |
| nothing | no | no — exit "no findings" |

`--skip-rollup` and `--skip-fixup` override the matrix.

### Step 3: File the rollup issue (if applicable)

Use `templates/rollup-issue.md` as the body template. Variables filled:
- `{{review-path}}` — relative path to the review markdown
- `{{pr-number}}` — the PR the review was against
- `{{p2-list}}` — checkbox list of P2 findings
- `{{p3-list}}` — checkbox list of P3 findings
- `{{cross-critic-areas}}` — if synthesizer surfaced any (P2/P3-relevant only)

Title format: `[<severity>/<category-rollup>] <plan-or-pr-slug> review followups (#<pr-or-issue>)`. Pick the highest severity present in P2/P3 (so all-P2 → "[P2 rollup]", mixed → "[P2/P3 rollup]").

Run `gh issue create --repo <owner>/<repo> --title "..." --body-file <tmpfile> [--label <each>]`. Capture the new issue number.

### Step 4: Dispatch the fix-up agent (if applicable)

Use `scripts/dispatch-fixup.sh` to assemble the prompt. The fix-up agent gets:
- Worktree path (auto-derived from branch via `git worktree list`)
- Reference to the review markdown
- The P0/P1 list verbatim as its acceptance contract
- Reference to the rollup issue number (so the agent knows P2/P3 are tracked)
- Default-Opus posture
- Project-specific `.anvil/dispatch-defaults.txt` (appended)

Dispatch via the `Agent` tool with `subagent_type: general-purpose`, `model: opus`, `run_in_background: true`. Capture the agent ID.

### Step 5: Comment on the PR

```bash
gh pr comment <pr-number> --body "$(cat <<EOF
Multi-critic review landed: \`<review-path>\`.

**Rollup issue:** #<rollup-issue-number> (<count> P2/P3 items tracked).
**Fix-up agent dispatched** for <count> P0/P1 items. Will amend this PR.

Verdict was: <BLOCK | PROCEED-WITH-CAUTION>.
EOF
)"
```

If `--skip-rollup` or `--skip-fixup` was set, omit the missing line.

### Step 6: Update the event log (if a /grind plan is active)

If `.anvil/grind-events.jsonl` exists in the repo root, append a `findings-rolled-up` event:

```json
{"t": "<iso>", "ev": "findings-rolled-up", "slice": "<slice-id-or-null>", "data": {"review_path": "...", "pr": <N>, "rollup_issue": <M>, "fixup_agent_id": "..."}}
```

The `slice` is auto-derived from the PR's branch name pattern (`fix-<id>` / `feat-<plan>-S<N>` → `S<N>`) if it matches; otherwise null.

## Output

```
=== /findings-rollup ===
Review: .codex-log/20260510-S1-multi-critic.md
PR: #1080 — feat(http-client) slice S1

P0/P1 fix-up: agent a67cf5bffae1fd2e0 dispatched (3 P0s, 12 P1s)
P2/P3 rollup: issue #1081 filed (10 P2s, 6 P3s, labels: p2,tech-debt)
PR comment: posted

Event logged.
```

## Composition

- After `/self-review --multi-critic` or `/codex-review` returns findings.
- Composes: `gh issue create`, the `Agent` tool, `gh pr comment`, `state.sh decision` if grind is active.
- The fix-up agent runs in background; `/grind` watches for completion and continues the per-slice cycle.

## Configuration

Per-project tuning lives in `.anvil/findings-rollup.config.json` (optional). Shape:

```json
{
  "labels": ["p2", "tech-debt"],
  "issue_title_format": "[{{severity_rollup}}] {{slug}} review followups (#{{pr}})",
  "fixup_agent_model": "opus",
  "skip_rollup_if_only_p3": false
}
```

If absent: skill uses the defaults above. The label list MUST exist on the repo (`gh label list`); if not, skill warns + omits the labels rather than failing.
