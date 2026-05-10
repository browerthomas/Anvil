---
name: grind
description: Use to execute a plan end-to-end. Reads slice manifest, dispatches agents in dependency order, runs review + pre-merge gate + auto-merge per slice, files follow-ups, recaps at end. The orchestrator wrapper. Invoke with /grind <plan-path> or when the operator says "execute the plan", "run the lift", "grind through it", "drive this to completion".
---

# /grind — orchestrate a plan to merged PRs

The end-to-end orchestrator. Reads a plan in anvil format (see `templates/plan-template.md`), drives each slice from agent dispatch to merged PR, recaps at the end. Operator only intervenes at explicit decision points.

## When to invoke

- Operator says "execute the plan", "grind", "drive the lift", "run /spec output", "ship the plan".
- After `/spec` produces a plan and operator approves it.
- For pre-existing plan docs (e.g. tonight's `<your-plan>.md`).

## When NOT to use

- The plan is rough or unvalidated — run `/spec --refine` first.
- The work is single-slice — just `/dispatch-slice`.
- The operator wants tight per-slice review — they should drive manually.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to plan markdown (e.g. `docs/plans/2026-05-12-anvil-phase2.md`) |
| `--from <slice-id>` | no | Resume from a specific slice (skip earlier ones; assumes they're already merged) |
| `--max-parallel <n>` | no | Max simultaneous agent dispatches (default 3) |
| `--no-codex` | no | Skip codex review (use `/self-review` only) — for codex outage windows |
| `--dry-run` | no | Print what would happen, don't dispatch |

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

## Resilience

- **Codex outage:** detect rate-limit error from `/codex-review`; fall back to `/self-review` automatically. Don't block.
- **Test flakes:** if `vitest` fails on a known-flaky test (pattern match against `.anvil/known-flakes.txt`), retry once before declaring failure.
- **Rebase conflicts:** if a slice's PR conflicts after sibling merges, attempt auto-rebase. If conflict requires real reasoning: defer slice + file an issue + continue with non-conflicting siblings.
- **Operator unreachable:** at decision points, fire the `default` action; never block indefinitely.

## What this skill DOES NOT do

- It does not write code itself. Agents do.
- It does not validate plan content quality (that's `/spec` + `/codex-confer`).
- It does not bypass operator decision points. The point of those is to keep humans in the loop.
- It does not handle non-PR work (e.g. operator-paced infra). Slices marked `operator-paced: true` in the manifest are skipped with a note.

## Real-world test

Tonight's session was effectively a manual `/grind` against `docs/v3/<your-plan>.md` + the codex-retro follow-ups + the audit P2/P3 rollups. 28 PRs merged across two sessions. Codifying this loop is the entire framework's purpose.

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
