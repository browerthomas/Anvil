---
name: grind
description: Use to execute a plan end-to-end. Reads slice manifest, dispatches agents in dependency order, runs review + pre-merge gate + auto-merge per slice, files follow-ups, recaps at end. The orchestrator wrapper. Invoke with /grind <plan-path> or when the operator says "execute the plan", "run the lift", "grind through it", "drive this to completion".
---

# /grind — orchestrate a plan to merged PRs

The end-to-end orchestrator. Reads a plan in anvil format (flat single-file OR folder layout — see below), drives each slice from agent dispatch to merged PR, recaps at the end. Operator only intervenes at explicit decision points.

## Plan layouts

`/grind` reads two layouts transparently:

**Flat:** `docs/plans/<slug>.md` — single file with the YAML slice manifest inline. Right for small plans (`templates/plan-template.md`).

**Folder (OpenSpec-style):** Right for substantive plans with architecture decisions.
```
docs/plans/<slug>/
├── proposal.md        # the why (goal, scope, success criteria)
├── design.md          # the how (architecture decisions, risks)
├── tasks.md           # the slice manifest (this is what /grind reads)
└── specs/
    └── <scenario>.md  # acceptance scenarios per slice (referenced from tasks.md)
```
The adversarial reviewer (`/codex-review` or `/self-review`) gets `specs/` files as additional context — execution is compared against the explicit scenarios, not vibes.

Built from `templates/plan-folder-template/`.

## When to invoke

- Operator says "execute the plan", "grind", "drive the lift", "run /spec output", "ship the plan".
- After `/spec` produces a plan and operator approves it.
- For pre-existing plan docs at `docs/plans/<your-plan>.md`.

## When NOT to use

- The plan is rough or unvalidated — run `/spec --refine` first.
- The work is single-slice — just `/dispatch-slice`.
- The operator wants tight per-slice review — they should drive manually.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to plan markdown (e.g. `docs/plans/2026-05-12-anvil-phase2.md`) |
| `--resume <plan-path>` | no | Resume an in-flight plan. Auto-derives the resume point from the event log's last `slice-merged`; failed/deferred slices are re-queued. Appends a `resume` event for audit. Replaces `--from`. |
| `--from <slice-id>` | no | **DEPRECATED** — prefer `--resume <plan-path>`. Still works (operator gets a deprecation warning); skips earlier slices and assumes they're already merged. |
| `--max-parallel <n>` | no | Max simultaneous agent dispatches (default 3) |
| `--no-codex` | no | Skip codex review (use `/self-review` only) — for codex outage windows |
| `--dry-run` | no | Print what would happen, don't dispatch |

### `--resume` semantics

Operator runs `/grind --resume <plan-path>` (no slice id needed). Under the hood `/grind` calls `state.sh resume <plan-path>`, which:

1. Validates the plan path (file or folder layout).
2. Acquires a file lock at `.anvil/grind-events.jsonl.lock` — concurrent `--resume` invocations get a warning + exit 0 (no double dispatch).
3. If the event log does not exist yet, initializes it from the plan (same shape as `state.sh init`).
4. Re-queues any `deferred` or `in-flight` slices back to `pending` so they're retried. `slice-merged` is the only terminal state that `--resume` skips.
5. Computes the next ready slice via the existing topo-sort (deps satisfied + status pending).
6. Appends one `resume` event to `grind-events.jsonl` with payload `{plan_path, resumed_from, merged_count, total_count, fresh_init}` for audit.
7. Releases the lock + dispatches the next slice.

Idempotent: running `--resume` twice in a row appends 2 `resume` events but does not re-dispatch already-merged slices.

`--from <slice-id>` is the deprecated path. It still works (the operator gets a one-line deprecation warning pointing to `--resume`) and skips slices up to but not including the named slice. Prefer `--resume <plan-path>` — it does not require remembering a slice id.

## Procedure

### Step 1: Parse plan + validate

Read the plan markdown. Extract the slice manifest YAML block. Validate:

- All required sections present (per `templates/plan-template.md`)
- Slice graph has no cycles
- Every dependency edge resolves
- Every operator-decision point has both `ask` + `default`
- Hard constraints section non-empty

If validation fails: report + abort. Direct operator to `/spec --refine`.

### Step 2: Topo-sort slices

Compute execution order respecting `depends-on` edges. Identify parallelizable batches (slices whose deps are all merged can run simultaneously up to `--max-parallel`).

### Step 3: Per-slice loop

For each slice (in topo-sorted order, batched by parallel-safety):

#### a. Pre-flight

- If slice has `operator-decision.ask`: pause + AskUserQuestion. Wait for answer (or apply `default` after timeout if configured).
- Verify worktree path is free; clean up if stale.

#### b. Dispatch

```
/dispatch-slice <slice.id> --scope "<slice.scope>" --tests "<acceptance.target>" --constraints "<slice.constraints>"
```

Returns: agent ID + worktree path. Note for tracking.

#### c. Wait for agent return

Background agent fires task-notification when complete. Don't poll — wait for the notification.

#### d. Review

If codex available + not `--no-codex`: `/codex-review <pr-number>`.
Else: `/self-review <pr-number>`.

For each P0/P1 finding: file an issue + amend the PR with the fix (dispatch a fix agent OR operator-side amend if trivial).

#### e. Wait for CI

Monitor PR checks. Don't poll; arm a Monitor on `gh pr checks`.

#### f. Pre-merge gate

`/pre-merge-gate <pr-number>` — must return MERGE-READY.

If BLOCKED: log the failure, don't merge, file an issue with the specific failure, continue to next slice (the human can come back to this one).

#### g. Auto-merge

`/auto-merge <pr-number>` — squash + cleanup.

#### h. Sync + log

Pull main locally. Update orchestration state (which slices merged, which deferred, which open).

#### h.5. Non-blocking plan-health gate

Auto-invoke `/plan-health <plan-path>` after each `slice-merged` event has been appended. The gate computes a per-plan follow-up filing-vs-closing ratio over the most recent 3 slices and flags drift when filing > closing × 1.5 for 3 consecutive slices.

**Non-blocking by contract.** When the gate fires it:

- Appends one `plan-health-degraded` event to `.anvil/grind-events.jsonl` (audit trail).
- Posts a metric snapshot comment on the most-recent open PR.

It NEVER pauses `/grind` dispatch. The loop continues to the next slice regardless of gate outcome. Failure modes (gh rate-limited, no PR derivable, plan-health crash) are caught + logged; `/grind` continues unaffected.

Wired to:

```
bash skills/plan-health/scripts/check-health.sh <plan-path>
```

The hook fails-safe: if `gh` is rate-limited or unreachable, plan-health crashes silently + `/grind` continues unaffected. No opt-out needed — the gate is non-blocking by design.

### Step 4: Periodic check-in

Every N slices (operator-configurable; default 5): print a one-line status:

```
[grind] 5/11 slices merged, 0 deferred. v3 tests 873 → 916. ETA ~2h.
```

### Step 5: Plan completion

When all slices have either merged OR been deferred (with reason):

- Run `/recap` for the visual session report.
- Run `/sync-kb` if KB integration is configured.
- Print final summary:
  - Slices merged
  - Slices deferred (with reasons)
  - Issues filed
  - Tests added
  - Final test count

## Operator decision point markup (LangGraph HITL pattern)

In the plan YAML:

```yaml
slices:
  - id: A2
    operator-decision:
      ask: "Is the Sentry DSN configured in the deploy secret store yet?"
      verbs: [approve, edit, reject]
      default: skip-with-warning
      timeout-hours: 4
```

The four verbs:

| Verb | Meaning | Outcome |
|---|---|---|
| `approve` | Yes, proceed as planned | Slice continues with current scope |
| `edit` | Adjust the slice scope before proceeding | Operator's edit appended to slice scope; slice continues |
| `reject` | Don't run this slice | Slice marked deferred; orchestrator continues with siblings |
| `respond` | Free-text answer (no scope change implied) | Slice continues; response logged in decision record |

When `/grind` reaches A2, it presents an `AskUserQuestion` with the listed verbs as options. Operator picks one + optionally adds free-text annotation.

If operator unreachable for `timeout-hours` (default 4): apply the `default`:
- `skip-with-warning` → mark deferred, continue siblings
- `retry` → re-ask in N more hours
- `abort` → halt orchestration

Every decision is appended to the plan's `## Operator decision records` section as a structured record. `/recap` surfaces these inline in its visual report.

Legacy operator behavior (verbs unset / freeform answer):
- Answer the ask → continues
- Say "skip" → marks slice deferred, continues
- Say "stop" → halts orchestration, leaves merged slices in main

The `default` fires if operator is unreachable for >N hours (configurable via `--ask-timeout`).

## Failure-mode triage (Symphony pattern)

`/grind` distinguishes three classes of failure and handles each differently. The default posture is **"defer and continue"** — never halt the whole orchestration when a single slice trips.

### 1. Slice-fail — defer this slice, keep the rest going

Symptoms: agent returns an error, CI fails (real test failure), pre-merge-gate blocks, review surfaces a P0/P1 finding.

Handler:
- Mark slice as `deferred` in the event log with the reason.
- File a follow-up issue using `.github/ISSUE_TEMPLATE/grind-deferral.md`.
- Continue with sibling slices that don't depend on this one. A sibling with `depends-on: [<this-slice>]` cascades to deferred; siblings with no dep stay in flight.

### 2. Plan-fail — halt with structured incident

Symptoms: plan validation fails mid-run; state file corrupted; ≥3 slices fail in a row (suggests systemic issue); critical operator-decision aborted.

Handler:
- Write `.anvil/incidents/<timestamp>-<reason>.md` with last successful slice + failed slice + raw error + event-log tail (last 50 events) + operator action required.
- Stop dispatching new agents; let in-flight agents finish (drain).
- Emit final state-event so `/grind --resume` can see the halt point.

### 3. Infra-fail — skip-this-tick, keep reconciliation alive

Symptoms: `gh` API rate-limited, codex subscription rate-limited, network hiccup, GitHub Pages 503, Sentry endpoint timeout.

Handler:
- Don't mark the slice as failed.
- Circuit-breaker backoff: 30s → 1m → 5m → 15m on consecutive failures.
- Try the next slice in parallel (an unrelated slice may not hit the same rate limit).
- Model fallback chain on agent dispatch:
  - **Opus rate-limited** → retry with Sonnet (tighter constraints + agent told it's the fallback).
  - **Sonnet rate-limited** → file an issue with the slice spec, defer slice.
  - **Both rate-limited for >1h** → escalate to plan-fail.

### Known flakes

Per-project flake list at `.anvil/known-flakes.txt` (see `skills/pre-merge-gate/templates/known-flakes.example.txt` for shape). One regex per line; matches against test names + file paths. `/grind` retries matching failures once before treating as slice-fail.

### Resilience matrix

| Failure | Class | Handler |
|---|---|---|
| Agent dispatch fails (worktree busy, deps install) | infra-fail | retry once after 30s; persists → defer |
| CI fails on known flake | infra-fail | retry once; persists → slice-fail |
| CI fails on real test | slice-fail | defer + file issue |
| pre-merge-gate blocks | slice-fail | defer + file issue with gate's specific failure |
| Review finds P0/P1 | slice-fail | defer + file follow-up issue with finding |
| Trivial sibling rebase conflict | (auto-rebase) | rebase + retry |
| Non-trivial rebase conflict | slice-fail | defer + file issue + continue siblings |
| codex-review rate-limited | infra-fail | fall back to /self-review automatically |
| Operator unreachable at decision point | (operator-paced) | apply `default`; never block indefinitely |
| 3 slices fail in a row | plan-fail | halt; write incident; require operator restart |

## What this skill DOES NOT do

- It does not write code itself. Agents do.
- It does not validate plan content quality (that's `/spec` + `/codex-confer`).
- It does not bypass operator decision points. The point of those is to keep humans in the loop.
- It does not handle non-PR work (e.g. operator-paced infra). Slices marked `operator-paced: true` in the manifest are skipped with a note.

## Real-world test

The patterns this skill codifies came from a multi-PR sprint that was driven manually — slice-by-slice dispatch, codex review per PR, pre-merge gate, auto-merge, follow-up issue filing, recap. Codifying that loop is the entire framework's purpose: you should never re-derive it by hand again.

## Composition

Internally calls:
- `/dispatch-slice` (per slice)
- `/codex-review` or `/self-review` (post-agent)
- `/pre-merge-gate` (pre-merge)
- `/auto-merge` (on green)
- `/sweep-worktrees` (periodic cleanup)
- `/recap` (at end)
- `/sync-kb` (at end, if configured)

Each of these works standalone. `/grind` is the conductor, not the orchestra.
