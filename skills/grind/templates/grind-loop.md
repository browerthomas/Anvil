# /grind execution loop — pseudocode

Concrete shape of the orchestrator loop. /grind's SKILL.md describes the API; this is the runtime shape.

## Entry point

```
/grind <plan-path> [--from <slice-id>] [--max-parallel <n>] [--no-codex] [--dry-run]
```

## Step 0: Preconditions

```
plan = parse_plan(plan_path)
if plan.status != "locked":
  abort("plan must be locked before /grind; run /spec --refine first")

validation = validate_plan(plan)
if validation.failures:
  abort("plan invalid: " + validation.failures)

slices = topo_sort(plan.slices)  # respecting depends-on edges
if --from <slice-id>:
  slices = slices.skip_until(slice_id)
```

## Step 1: Per-slice loop

```
for slice in slices:
  if slice.operator-paced:
    log("⏭ skipping operator-paced slice: " + slice.id)
    continue

  if slice.depends-on still has unmerged ones:
    if any-unmerged-is-deferred:
      defer(slice, "blocked by deferred dep")
      continue
    wait_for_deps()

  # === Operator decision point (LangGraph HITL pattern) ===
  if slice.operator-decision.ask:
    verbs = slice.operator-decision.verbs or [approve, edit, reject]
    options = build_ask_options(verbs)  # AskUserQuestion options + optional free-text
    timeout_hours = slice.operator-decision.timeout-hours or 4

    answer, verb, free_text = ask_user_with_timeout(
      slice.operator-decision.ask,
      options,
      timeout_hours
    )

    # Append structured decision record to the plan markdown's
    # ## Operator decision records section
    append_decision_record(plan_path, slice.id, ask, verb, free_text, outcome="pending")

    if answer == "TIMEOUT":
      apply_default(slice.operator-decision.default)
      record.verb = "(default applied)"
      record.outcome = default_to_outcome(default)
      if default == "skip-with-warning":
        defer(slice, "operator timeout — default applied")
        continue
      if default == "abort":
        halt_orchestration("operator aborted at " + slice.id)
        return

    # Normal verb-driven flow:
    case verb:
      "approve" → continue with original scope
      "edit"    → slice.scope = original_scope + "\n\nOperator edit:\n" + free_text
      "reject"  → defer(slice, "operator rejected: " + free_text); continue
      "respond" → log free_text; continue with original scope
    record.outcome = "slice continued" if verb in [approve, edit, respond] else "slice deferred"

  # === Dispatch ===
  worktree = ensure_worktree(slice.id)
  install_deps_background(worktree)
  agent_id = dispatch_slice(slice, worktree)
  log("→ dispatched " + slice.id + " (agent " + agent_id + ")")

  # === Wait for agent ===
  result = await_agent(agent_id)
  if result.status == "failed":
    file_followup(slice.id, result.error)
    defer(slice, "agent failed: " + result.error)
    continue

  pr_number = parse_pr_number(result.summary)

  # === Review ===
  if codex_available() and not --no-codex:
    review = run("/codex-review", pr_number)
  else:
    review = run("/self-review", pr_number)

  for finding in review.findings.filter(p in [P0, P1]):
    issue_url = file_followup(finding)
    log("  filed follow-up: " + issue_url)

  if review.findings.has_blocking():
    # Don't merge. Wait for fix in a follow-up cycle.
    defer(slice, "review found blocking findings; see PR #" + pr_number)
    continue

  # === CI ===
  arm_ci_monitor(pr_number)
  ci_result = await_ci(pr_number)
  if ci_result == "failed":
    if is_known_flake(ci_result.failed_test):
      retry_ci(pr_number)
      ci_result = await_ci(pr_number)
    if ci_result == "failed":
      defer(slice, "CI failed: " + ci_result.failed_test)
      continue

  # === Pre-merge gate ===
  gate = run("/pre-merge-gate", pr_number)
  if gate.verdict == "blocked":
    file_followup(slice.id, "pre-merge gate blocked: " + gate.reason)
    defer(slice, "pre-merge gate blocked")
    continue

  if gate.verdict == "yellow-flags":
    if --strict:
      defer(slice, "yellow flags in strict mode")
      continue

  # === Merge ===
  merge_result = run("/auto-merge", pr_number)
  if merge_result.status != "ok":
    defer(slice, "auto-merge failed: " + merge_result.error)
    continue

  log("✓ merged slice " + slice.id + " — PR #" + pr_number)

  # === Sync ===
  pull_main_locally()

  # === Periodic checkpoints ===
  if slices_completed_count % 5 == 0:
    log_progress_summary()

# === End of loop ===
```

## Step 2: Closeout

```
log_final_summary(slices_merged, slices_deferred, issues_filed)

run("/recap", since=plan.start_timestamp)
run("/sweep-worktrees")
run("/sync-kb")  # if configured
write_session_memory_file()
```

## Failure-mode tree

```
                     ┌─ codex rate-limited
       /codex-review─┤  └─ fall back to /self-review
                     └─ codex outage
                        └─ fall back to /self-review

                 ┌─ rebase conflict → auto-rebase if trivial → defer if not
/pre-merge-gate ─┼─ tsc fail → defer + file issue
                 ├─ vitest fail (known flake) → retry once
                 ├─ vitest fail (real) → defer + file issue
                 ├─ fitness fail → defer + file issue
                 └─ forbidden pattern → defer + file issue

             ┌─ "branch used by worktree" → re-run cleanup, retry
/auto-merge ─┼─ stale lock files → clear + retry
             ├─ iCloud node_modules hang → find -delete fallback
             └─ CI not green → wait + re-arm (don't merge)

operator-decision.ask reached:
  ├─ operator answers within timeout → continue
  ├─ operator unreachable + default=skip-with-warning → mark deferred, continue
  ├─ operator unreachable + default=retry → re-ask in N minutes
  └─ operator unreachable + default=abort → halt orchestration
```

## State tracking

/grind maintains state in `.anvil/grind-state.json`:

```json
{
  "plan_path": "docs/plans/2026-05-12-anvil-phase2.md",
  "started_at": "2026-05-10T10:00:00Z",
  "slices": {
    "A1": {"status": "merged", "pr": 1049, "merged_at": "2026-05-08T04:22:12Z"},
    "A2": {"status": "merged", "pr": 1052, "merged_at": "2026-05-08T05:23:53Z"},
    "A3": {"status": "in-flight", "pr": 1051, "agent": "a944e74e..."},
    "A4": {"status": "deferred", "reason": "agent failed", "issue": 1080},
    "A5": {"status": "blocked-by-dep", "depends-on": ["A2"]},
    "A6": {"status": "pending"}
  },
  "issues_filed": [1080, 1081, 1082],
  "last_recap": "~/.claude/showme/20260510-recap-anvil-phase2.html"
}
```

State allows `--from <slice-id>` resumption + survives session restarts.

## What /grind outputs

Throughout execution: terse one-line status per major event.

At end: a structured summary (PRs merged, deferred, issues filed) AND fires /recap automatically for the visual report.

## When /grind stops without completing

- Operator-decision aborted
- Critical failure (DB corruption, gh auth lost, etc) — halt + alert
- Manual interrupt (Ctrl-C) — save state + exit cleanly
- Plan validation re-fails after a refine — abort

In all cases: prints state file path so operator can resume with `/grind --from <next-slice>`.
