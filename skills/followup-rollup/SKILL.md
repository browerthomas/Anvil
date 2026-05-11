---
name: followup-rollup
description: Use to consolidate open follow-up issues filed during a multi-slice plan into a single markdown rollup table — grouped by severity (P0/P1/P2/P3) + area (test-coverage / correctness / architecture / operability) — with a suggested consuming slice per cluster. Walks open issues whose title carries the `[<plan>-<slice> followup]` prefix. Pasteable into a planning doc. Read-only. Invoke with /followup-rollup <plan-path> or when the operator says "rollup the followups", "what's the cumulative debt", "what should the D-slices clean up", "consolidate the open followups".
---

# /followup-rollup — group deferred-slice follow-ups by severity + area

A typical multi-slice plan fires 5-7 follow-up issues per slice. After 8-10 slices that's 40-70 open issues scattered across the tracker. The operator has no consolidated view of "what's the cumulative debt the cleanup slices need to address?"

`/followup-rollup <plan-path>` walks open issues whose title carries the `[<plan>-<slice> followup]` prefix, groups them by severity + area, suggests which slice should consume each cluster, and emits a markdown rollup table pasteable into a planning doc.

Read-only. No state mutation. No issues mutated.

## When to invoke

- Operator says "rollup the followups", "what's the cumulative debt", "what should the D-slices clean up", "consolidate the open followups", "show me the open followups for this plan".
- Mid-grind on a long-running multi-slice plan when the follow-up backlog has grown past ~10 issues.
- Before planning a cleanup phase — the rollup tells you what the cleanup slices need to consume.
- Pairs with `/anvil-status` (B1): `/anvil-status` says how many follow-ups are open; this skill says *which* + groups them.

## When NOT to use

- For a single-PR review's findings — use `/findings-rollup` (which files a P2/P3 rollup issue + dispatches a P0/P1 fix-up agent).
- For per-slice event-log details — use `bash skills/grind/scripts/state.sh trace <slice-id>` directly.
- When you want to MUTATE follow-up state (close, retitle) — this skill is read-only.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to plan markdown (flat) OR plan folder (must contain `tasks.md`). The plan's slug (folder name or filename stem) becomes the `<plan>` portion of the title prefix searched for. |
| `--fixture <path>` | no | Use a local JSON file of issues instead of `gh issue list`. The file must match `gh issue list --json title,number,labels,body,state,url` shape. Used by smoke tests + offline runs. |
| `--repo <owner/name>` | no | Override the gh repo (default: auto-derive from `git remote get-url origin`). |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `GH_OFFLINE` | `0` | When set to `1`, skip `gh` invocation entirely. The skill emits a friendly "no issues fetched (offline mode)" rollup with zero entries. Use when `gh` is missing, unauthenticated, or rate-limited. |

## Title prefix contract

The skill searches for open issues whose title starts with `[<plan>-<slice> followup]` — for example, on plan slug `positioning-and-state-product`, slice `B1`:

```
[positioning-and-state-product-B1 followup] anvil-status: missing test for blocked-node detection
```

This prefix is **not currently enforced** by `/findings-rollup` or `/grind` (audited 2026-05-11 — both currently use a different title format). The skill fails gracefully when zero matching issues are found: emits a friendly "no follow-ups" rollup AND prints a one-liner explaining the gap, so the operator knows whether to (a) accept that there are genuinely no follow-ups, or (b) retrofit the prefix into the upstream filing path.

When the gap is closed (a future slice teaches `/findings-rollup` to use the `[<plan>-<slice> followup]` title prefix), this skill picks up automatically.

## Severity grouping

The skill derives severity from (in priority order):

1. **GitHub label** — `p0`, `p1`, `p2`, `p3` (case-insensitive).
2. **Title token** — `[P0]`, `[P1]`, `[P2]`, `[P3]` anywhere in the title.
3. **Body marker** — first `**Severity:** Pn` line in the issue body.
4. **Fallback** — `P3` (defensive default; an unlabeled follow-up is treated as cleanup-class).

## Area grouping

The skill derives area from (in priority order):

1. **GitHub label** — `test-coverage`, `correctness`, `architecture`, `operability`.
2. **Title keyword heuristic** — case-insensitive substrings:
   - `test`, `coverage`, `flaky`, `fixture`, `smoke` → `test-coverage`
   - `bug`, `incorrect`, `wrong`, `broken`, `regression`, `race` → `correctness`
   - `refactor`, `extract`, `interface`, `layer`, `coupling`, `boundary` → `architecture`
   - `log`, `metric`, `observability`, `runbook`, `alert`, `dashboard` → `operability`
3. **Fallback** — `correctness` (defensive default; an undeclared area is treated as "something's wrong somewhere").

The four buckets are exhaustive — every follow-up lands in exactly one. The bucket-priority order for the suggested consuming slice is `correctness > operability > test-coverage > architecture`.

## Output shape

```markdown
# Follow-up rollup — <plan-slug>

**Open follow-ups:** N issues across S slices.
**Source:** `gh issue list` against <repo> (or fixture path).

## Severity summary

| Severity | Count | Suggested consuming slice |
|---|---|---|
| P0 | 1 | next merge gate |
| P1 | 4 | next cleanup phase |
| P2 | 12 | cleanup phase |
| P3 | 3 | nice-to-have / backlog |

## Area breakdown

### correctness (5)
- #N1 — [plan-B1 followup] — title  (P1, slice B1)
- ...

### test-coverage (3)
- ...

### architecture (4)
- ...

### operability (8)
- ...

## Per-slice tally

| Slice | P0 | P1 | P2 | P3 | Total |
|---|---|---|---|---|---|
| B1 | 0 | 1 | 3 | 0 | 4 |
| B2 | 0 | 0 | 2 | 1 | 3 |
| ...

## Consumer suggestions

- **Drop into the next cleanup slice (P0 + P1):**
  - #N1 ...
- **Bundle into a P2 rollup issue:**
  - #N5 ...
- **Backlog / nice-to-have (P3):**
  - #N9 ...
```

When zero matching issues are found, the skill prints a friendly placeholder + the prefix-enforcement gap note:

```markdown
# Follow-up rollup — <plan-slug>

**Open follow-ups:** 0 — no issues match the `[<plan-slug>-<slice> followup]` title prefix.

> Note: the title-prefix contract is not currently enforced by `/findings-rollup`
> or `/grind`. If you expected follow-ups here, either (a) there are genuinely
> none, or (b) the upstream filing path uses a different title format. To
> close the gap, retrofit the prefix into the issue-filing call in
> `skills/grind/templates/grind-loop.md` + `skills/findings-rollup/SKILL.md`.
```

## Procedure

### Step 1: Resolve plan slug + repo

```bash
bash skills/followup-rollup/scripts/build-rollup.sh <plan-path>
```

The script:

1. Validates `<plan-path>` resolves to a flat file or folder layout with `tasks.md`.
2. Derives the plan slug — folder name (folder layout) or filename stem (flat layout). Example: `docs/plans/2026-05-11-positioning-and-state-product/` → `2026-05-11-positioning-and-state-product`.
3. Derives the gh repo from `git remote get-url origin` unless `--repo <owner/name>` is given.

### Step 2: Fetch open issues

If `--fixture <path>` is set, load the JSON from there.
Else if `GH_OFFLINE=1` is set, emit the empty-fixture friendly placeholder + exit 0.
Else: `gh issue list --repo <owner/name> --state open --limit 200 --search '<plan-slug> in:title' --json title,number,labels,body,url`.

The `--limit 200` ceiling is intentional — a plan with >200 open follow-ups has a larger problem than a missing rollup.

### Step 3: Filter to matching titles

For each issue, test the title against the regex `^\[<plan-slug>-[A-Za-z0-9]+ followup\]`. Drop non-matches.

If zero remain after filtering: emit the friendly placeholder + the prefix-enforcement gap note + exit 0.

### Step 4: Group + classify

For each surviving issue:
- Extract `<slice-id>` from the title prefix capture group.
- Derive severity per the priority order above.
- Derive area per the priority order above.

### Step 5: Emit the rollup

Render the markdown sections in the order documented in "Output shape" above. Stdout only — no file writes.

## Smoke tests

`tests/smoke/followup-rollup.bats` covers (≥5 cases):

1. **Zero matching issues** — outputs the friendly "no follow-ups" placeholder + the prefix-enforcement gap note.
2. **One follow-up per slice** — 3 slices, 3 issues → output groups them under per-slice tally + by severity.
3. **Issues without the prefix excluded** — issues whose title doesn't match `[<plan>-<slice> followup]` are filtered out (do not appear in any section).
4. **Severity grouping correctness** — fixtures with labels `p0`/`p1`/`p2`/`p3` (lowercase) + title-token `[P0]` variants → all bucket correctly.
5. **Area grouping correctness** — fixtures using labels (`test-coverage`/`correctness`/`architecture`/`operability`) AND fixtures using title-keyword heuristics → both routes resolve.

Run via `make smoke` (full suite) or `make smoke FILE=followup-rollup.bats`.

## Composition

- Pairs with `/anvil-status` — that skill says HOW MANY are open; this skill says WHICH + groups them.
- Pairs with `/findings-rollup` — that skill files NEW P2/P3 followups + dispatches a P0/P1 fix-up agent; this skill consolidates the followups that have piled up.
- Pairs with `/grind` — `/grind` files followups during a slice cycle; the operator runs this skill to plan the cleanup phase.

## Configuration

No per-project config file. The skill's behaviour is fully derivable from the plan path + open issues.

To override the gh repo or feed a fixture, use `--repo` or `--fixture` at the call site.
