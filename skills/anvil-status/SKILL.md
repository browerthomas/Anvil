---
name: anvil-status
description: Use to print a rank-ordered text dashboard of a plan's current state — what to think about next, what's in-flight, what's blocked, what's shipped, what's deferred — plus cumulative test delta + open follow-up count. Reads `.anvil/grind-events.jsonl` + the plan's tasks.md + `gh pr list` for PR state (or GH_OFFLINE=1 fallback). Read-only. Invoke with /anvil-status <plan-path> or when the operator says "what's the plan state", "where are we on the lift", "what should I think about next", "status of the grind".
---

# /anvil-status — text dashboard of plan state

Mid-grind on a multi-slice plan, the operator has no consolidated view of: which slices merged, which are in-flight, which are blocked, which are deferred, what's next, cumulative test count delta, open follow-up issues. They have to reconstruct it by reading `.anvil/grind-events.jsonl` + GitHub + plan files by hand.

`/anvil-status <plan-path>` is the read-only inverse of `/grind`. It folds the same state — event log, plan manifest, gh PR state — and emits a text dashboard whose **first line answers "what should I think about next?"**

The skill is intentionally read-only — no state mutation. Use `/grind --resume` to act on the state; this skill just renders it.

## When to invoke

- Operator says "where are we", "what's next", "status", "what should I think about now", "is the lift stuck", "anvil status".
- Mid-grind on a long-running plan when the orchestrator hasn't printed a status line recently.
- After a stop-and-resume to reorient — pairs with `/grind --resume` (B2).
- Before opening a follow-up issue, to confirm the slice in question is in the expected state.

## When NOT to use

- For a per-session WHAT-shipped summary — use `/recap` (B4 for the v2 structured version).
- For per-slice event-log details — use `bash skills/grind/scripts/state.sh trace <slice-id>` directly.
- When you want to MUTATE state (resume, defer, replay) — this skill is read-only.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to plan markdown (flat) OR plan folder (OpenSpec-style — must contain `tasks.md`). |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `GH_OFFLINE` | `0` | When set to `1`, skip `gh` invocation entirely. PR linkage is read from `slice-pr-opened` + `slice-merged` events in the event log (`/grind` records PR# at those moments). Use when `gh` is missing, unauthenticated, or rate-limited. |

## Output shape (rank-locked)

```
NEXT: <slice-id> (parallel/deps-blocking, N follow-ups)
IN-FLIGHT: <slice-id> (PR #N, codex-pending/operator-pending)
BLOCKED: <slice-id> (deps: <list>)
SHIPPED: <slice-ids> (N slices, +M tests, K follow-ups)
DEFERRED: <slice-ids>

Tests: <total> cumulative (Δ across N slices)
Follow-ups: <open> open / <closed> closed
```

Rank order is locked. The first non-blank line of output is always `NEXT:` — the operator scans top-down.

Sections are omitted when empty (a plan with nothing in-flight skips the `IN-FLIGHT:` line). The summary footer (Tests / Follow-ups) is always present.

## Procedure

### Step 1: Resolve plan + event log

```bash
bash skills/anvil-status/scripts/build-status.sh <plan-path>
```

The script:

1. Locates the plan's `tasks.md` (flat or folder layout).
2. Reads `.anvil/grind-events.jsonl` to fold slice statuses + follow-up counts + per-slice test-deltas.
3. If `GH_OFFLINE=1` is unset AND `gh` is on PATH AND authenticated: queries `gh pr list` for the current PR state of in-flight slices. Otherwise: reads PR# from `slice-pr-opened` events in the log.
4. Computes the dashboard sections + rank order.
5. Emits plain stdout — no ANSI cursor control, no interactive prompts. Pipeable to `cat` / `tee` / a file.

### Step 2: Read the dashboard

The first line tells you what to act on. Read down — each section is a different state-class:

- **NEXT** — the topo-sorted earliest pending slice whose deps are all merged. If multiple are ready, the alphabetically-first id wins (deterministic ordering). The annotation `(parallel/deps-blocking, N follow-ups)` indicates whether other slices can run in parallel + how many follow-ups are already open against this slice.
- **IN-FLIGHT** — slices currently dispatched (event log has `slice-in-flight` but no `slice-merged` or `slice-deferred`). The annotation includes the PR# + review status (codex-pending / operator-pending / merge-ready).
- **BLOCKED** — slices whose dependencies are NOT all merged. The annotation lists which deps are still pending/in-flight/deferred/failed. A slice whose dep has a `failed` status (event log has a `slice-deferred` for that dep) appears here with the failing dep cited.
- **SHIPPED** — merged slices (event log has `slice-merged`). Summary count + cumulative test delta from `slice-merged.data.tests_delta` if present.
- **DEFERRED** — slices with `slice-deferred` (no subsequent `slice-merged`).

The footer summarises totals.

## Offline mode

`GH_OFFLINE=1` short-circuits the gh invocation. PR linkage is read from the event log only — `slice-pr-opened` events record `pr_number` at dispatch time, and `slice-merged` records the final PR#. This mode is the default fallback when `gh` is missing or unauthenticated; the script auto-detects and switches silently. Setting `GH_OFFLINE=1` explicitly forces the fallback even when `gh` is available (useful for tests + CI without GitHub credentials).

## Smoke tests

`tests/smoke/anvil-status.bats` covers:

1. Dashboard prints `NEXT:` as the first non-blank line against the folder-plan fixture.
2. `GH_OFFLINE=1` emits the dashboard without invoking `gh`.
3. Pre-sprint `sample-events.jsonl` fixture parses + emits sensible output (backward-compat guard).
4. Blocked-node detection — when a dep has `slice-deferred` status, the dependent slice appears under `BLOCKED:` with the failing dep cited.
5. Cumulative test-delta in the footer equals the sum of `slice-merged.data.tests_delta` rows in the event log.

## What this skill DOES NOT do

- It does not mutate state. No event-log writes. Use `/grind --resume` to act.
- It does not run codex review or any vendor calls. Pure local read.
- It does not validate plan content quality — `/spec` + `/codex-confer` do that.
- It does not block on rate limits — degrades to offline mode automatically.

## Composition

Read by:

- `/grind` step h.5 (per-slice post-merge status line; future hookup in D5).
- `/recap v2` (sources state for the WHAT-shipped section; B4).

Reads:

- `.anvil/grind-events.jsonl` — primary state source.
- `<plan>/tasks.md` or `<plan>.md` — slice manifest.
- `gh pr list` (optional, when online) — current PR state of in-flight slices.
