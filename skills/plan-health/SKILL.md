---
name: plan-health
description: Use to compute a per-plan follow-up filing-vs-closing ratio over a sliding 3-slice window and surface a non-blocking warning when filing outpaces closing. Reads `.anvil/grind-events.jsonl` + `gh issue list` for follow-up open/close timestamps. Auto-invoked by `/grind` step h.5 (post-merge); writes a `plan-health-degraded` event + comments on the most-recent open PR. Never pauses `/grind` dispatch. Invoke with /plan-health <plan-path> or when the operator says "is the plan healthy", "are follow-ups piling up", "what's our debt trend".
---

# /plan-health — per-plan follow-up filing-vs-closing trend gate (non-blocking)

A multi-slice plan that files 6 follow-ups per slice and closes 1 is drifting into a backlog the cleanup slices can't catch up on. The signal exists in `.anvil/grind-events.jsonl` (issue-filed events) + the `gh issue` close state — but nobody folds it into a trend.

`/plan-health <plan-path>` computes a per-slice metric (open-follow-ups-filed-this-slice ÷ follow-ups-closed-this-slice) over the most recent 3 slices and flags when filing > closing × 1.5 for 3 consecutive slices.

**Non-blocking by design.** When the gate fires it (a) appends one `plan-health-degraded` event to `.anvil/grind-events.jsonl` for audit + later trend analysis, and (b) posts a metric snapshot comment on the most-recent open PR. It never pauses `/grind` dispatch. Operator override is not needed because the gate never blocks.

Auto-invoked from `/grind` step h.5 (post-merge, before the loop moves to the next slice). Also runnable standalone.

## When to invoke

- Operator says "is the plan healthy", "are follow-ups piling up", "what's our debt trend", "should we add a cleanup phase".
- Auto-invoked by `/grind` after each slice's `slice-merged` event (step h.5).
- Mid-grind, manually, when the operator suspects backlog drift.
- Before deciding whether to add a P-phase (cleanup) to a plan that's already mid-flight.

## When NOT to use

- For the rollup of WHICH follow-ups exist — use `/followup-rollup` (D4). This skill answers "is the trend bad", not "what are the open issues".
- For a per-PR review — use `/codex-review` or `/self-review`.
- When `gh` is unavailable AND the operator wants real numbers — the skill degrades gracefully to "skipped (offline)" but the open/close ratio numbers won't be accurate.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to plan markdown (flat) OR plan folder (must contain `tasks.md`). |
| `--pr <number>` | no | Override the PR number for the comment target. Default: auto-derive from the most-recent open PR in the plan's event log. |
| `--fixture <path>` | no | Use a local JSON file of issues instead of `gh issue list`. Shape: `[{number, state, closedAt}, ...]`. Used by smoke tests + offline runs. |
| `--repo <owner/name>` | no | Override the gh repo (default: auto-derive from `git remote get-url origin`). |
| `--dry-run` | no | Print the metric snapshot to stdout. Do NOT append the event. Do NOT post the PR comment. |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `GH_OFFLINE` | `0` | When `1`, skip `gh` invocation entirely. The skill emits a "skipped (offline)" line + exits 0. No event appended, no PR comment posted. |

## The metric

For each slice in the plan:

- **Filed-this-slice** — issues whose `issue-filed` event sits between this slice's `slice-in-flight` event timestamp and its `slice-merged` event timestamp.
- **Closed-this-slice** — of those same filed issues, the subset that closed (per `gh issue view`) before the slice's `slice-merged` event.

The slice is **degraded** when `filed > closed × 1.5` (i.e. the filing rate outpaces the closing rate by 1.5×).

The plan is **flagged** when the most recent 3 consecutive merged slices are each degraded. The 3-slice sliding window damps single-slice noise (one slice with 6 P3 follow-ups and zero closures doesn't trip the gate; three slices in a row each filing 6 and closing 0 does).

### Worked example

| Slice | Filed | Closed | Ratio | Degraded? |
|---|---|---|---|---|
| A1 | 4 | 0 | inf | yes |
| A2 | 5 | 1 | 5.0 | yes |
| A3 | 3 | 0 | inf | yes |
| A4 | 2 | 2 | 1.0 | no |

After A3 merges, the most recent 3 slices (A1+A2+A3) are all degraded → flag fires → `plan-health-degraded` event appended + PR comment posted.
After A4 merges, the most recent 3 slices (A2+A3+A4) include one healthy slice → no flag.

## Output

### Stdout (always)

A compact human-readable snapshot:

```
plan-health: <plan-slug>
  window: <slice-3>, <slice-2>, <slice-1>
  filed:   N, N, N
  closed:  N, N, N
  ratio:   r1, r2, r3
  flagged: yes/no (criterion: 3 consecutive slices with filed > closed × 1.5)
```

### `plan-health-degraded` event (on flag, unless `--dry-run`)

Appended to `.anvil/grind-events.jsonl`:

```json
{"t":"<iso>","ev":"plan-health-degraded","slice":"<latest-merged-slice>","data":{"window":["A1","A2","A3"],"filed":[4,5,3],"closed":[0,1,0],"ratios":[null,5.0,null],"plan_slug":"<slug>"}}
```

The slice id is the most-recently-merged slice (the slice that just triggered the post-merge h.5 hook).

### PR comment (on flag, unless `--dry-run` or `--pr` omitted with no derivable PR)

Posted via `gh pr comment <pr-number> --body "..."`. Body:

```
**plan-health: degraded** — _<slug>_

The most recent 3 merged slices each filed more follow-ups than they closed by 1.5× or more.

| Slice | Filed | Closed | Ratio |
|---|---|---|---|
| <slice-3> | N | N | r |
| <slice-2> | N | N | r |
| <slice-1> | N | N | r |

Non-blocking — this PR is unaffected. Consider whether the plan needs a cleanup slice before launching the next phase.
```

## When the gate does NOT fire

- Fewer than 3 merged slices exist in the event log (insufficient signal — never flag on initial sprint slices).
- Any one of the last 3 slices is healthy (ratio in band).
- Total filed across the 3-slice window is zero (vacuous truth — nothing to flag).
- `GH_OFFLINE=1` is set (the close counts are unknowable; skill exits 0 with a "skipped (offline)" line).

## Auto-invocation from /grind

`/grind` step h.5 (the half-step between h "sync + log" and step 4 "periodic check-in") calls this skill after each `slice-merged` event has been appended. The hook is wired into `skills/grind/SKILL.md`'s procedure section. Failure modes:

- Plan-health crashes → caught + logged; the parent `/grind` continues unaffected (gate is best-effort).
- gh rate-limited → skipped; no event appended.
- No PR derivable → event still appended (audit-only), PR comment skipped.

## Composition

Reads:
- `.anvil/grind-events.jsonl` — for `issue-filed`, `slice-in-flight`, `slice-merged`, `slice-pr-opened` events.
- The plan's `tasks.md` (or flat `.md`) — to read slice order.
- `gh issue list` — to fetch close states of the filed issues. `--fixture` for offline / test.

Writes:
- `.anvil/grind-events.jsonl` — one `plan-health-degraded` event when flagged (and not `--dry-run`).
- Most-recent-open-PR — one comment when flagged + a PR is derivable (and not `--dry-run`).

## Pairs with

- `/anvil-status` (B1) — for the current "what's next" state of the plan.
- `/followup-rollup` (D4) — for the WHO+WHAT view of open follow-ups.
- `/learn-promote` (this slice, D5) — for promoting durable learnings into MEMORY.md.

## Smoke tests

`tests/smoke/plan-health.bats` covers:

1. Skill exists + frontmatter validates against `skills/*/SKILL.md` structure (caught by `skill-structure.bats`).
2. Three-slice fixture where filing > closing × 1.5 for all 3 → flag fires (event appended + PR comment via mock `gh`).
3. Three-slice fixture where one of the 3 has filed ≤ closed × 1.5 → no flag.
4. `GH_OFFLINE=1` → skipped (no event, no comment).
5. `--dry-run` → snapshot to stdout, no event, no comment.
6. `/grind` step h.5 auto-invocation contract — `skills/grind/SKILL.md` mentions step h.5 with the plan-health hook (documentation pin).
