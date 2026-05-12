# Anvil vocabulary

> One-page glossary of the terms anvil uses. Dispatched agents should read this before working on a slice so the vocabulary in plan files, skill briefs, and review feedback lines up.

Terms in alphabetical order. Each entry cites the canonical implementation file or skill.

---

## checklist

A per-slice block of acceptance gates inside the slice manifest, enforced by `/pre-merge-gate` after the global gates and before CI verification. Two kinds: `shell` (run a command, expect exit 0) and `grep` (assert a regex is present or absent in a path glob). Missing `checklist:` field is a silent absence — legacy slices behave exactly as before. See `templates/plan-template.md` and `skills/pre-merge-gate/SKILL.md`.

## constitution

A short, durable statement of the project's ethos — north star, inviolable principles, things explicitly out of scope. Lives at `.anvil/constitution.md` and is auto-prepended to every dispatched-agent prompt. Strategic frame, not mechanical config. Soft warning at 2KB, stronger warning at 8KB. See `templates/constitution-template.md` and `skills/dispatch-slice/SKILL.md`.

## dispatch

The act of spinning up a fresh Claude Code agent for a single slice in its own worktree with a full briefing — worktree path, deps reminder, hard constraints, return shape. Codified in `/dispatch-slice` so the ~600-word per-agent prompt is consistent across a multi-slice sprint. See `skills/dispatch-slice/SKILL.md`.

## event log

The append-only JSONL file at `.anvil/grind-events.jsonl` that records every state transition during a `/grind` run — slice dispatched, PR opened, review complete, slice merged, decision made. Source of truth for resume + replay + trace; the snapshot view is derived. See `docs/observability.md`.

## fitness ratchet

A test (typically under `test/architecture/`) that pins a structural invariant — forbidden imports, layer-crossing rules, count of legacy callsites that should not grow. The ratchet fails the build if the invariant regresses. `/pre-merge-gate` runs the fitness suite as a hard gate. The term is borrowed from evolutionary-architecture practice; the invariants are project-defined.

## follow-up

An issue filed during a `/grind` run for work that surfaced but didn't fit the current slice's scope. Tagged `[<plan>-<slice> followup]` so `/followup-rollup` can consolidate them by severity (P0/P1/P2/P3) and suggested consuming slice. See `skills/findings-rollup/SKILL.md` and `skills/followup-rollup/SKILL.md`.

## gate

A pass/fail check that blocks a merge or a dispatch step. `/pre-merge-gate` is the canonical example — a verification combinator of rebase + tsc + vitest + fitness ratchets + forbidden-pattern grep + per-slice checklist. Gates return ready/not-ready with the specific failure cited; they never silently degrade. See `skills/pre-merge-gate/SKILL.md`.

## grind

End-to-end orchestration of a plan. `/grind` reads the slice manifest, topo-sorts the dependency graph, dispatches agents in order, runs review + pre-merge gate + auto-merge per slice, files follow-ups, and recaps at the end. Pauses only at explicit operator-decision points. See `skills/grind/SKILL.md`.

## known flake

A test or check that fails intermittently for a documented reason, listed in `.anvil/known-flakes.txt`. `/grind` retries known flakes once before treating them as slice-fails. Use sparingly — chronic flakes are a P0 to fix, not background. See `skills/grind/SKILL.md`.

## learning

A per-project, append-only insight recorded at `.anvil/learnings.jsonl` via `/learn add`. Types include `gotcha`, `flake`, and `decision`. Skills auto-append when they discover something worth remembering; operators and other skills search before treating a new symptom as new. See `skills/learn/SKILL.md`.

## lens

A named adversarial review perspective — kernel developer, SRE, distributed-systems engineer, privacy lawyer, security researcher, etc. Lenses are namespaced into `systems/`, `saas/`, and `generic/`. Each lens is a hard-coded role prefix that wraps `/self-review` or `/codex-review` to focus the model's attention on one stance. See `skills/lens/SKILL.md`.

## operator-decision point

An explicit pause inside a slice manifest where `/grind` stops, asks the operator a question, and waits for an answer (with `verbs` defining the valid responses and `default` defining the fallback after `timeout-hours`). The only kind of pause `/grind` makes — implicit pauses are forbidden. See `templates/plan-template.md`.

## operator-paced

A slice flag (`operator-paced: true`) marking work that requires human hands — deployments, DNS edits, billing approval, physical hardware. `/grind` skips the dispatch step for these slices and surfaces them as needing-human in the status dashboard. See `templates/plan-template.md`.

## plan

A markdown file (flat layout) or directory (folder layout) that captures work intent as goal + scope + architecture decisions + hard constraints + slice manifest + validation checklist. Produced by `/spec`, consumed by `/grind`. See `templates/plan-template.md` and `templates/plan-folder-template/`.

## plan health

A non-blocking signal — flagged when follow-up issues are filed faster than they are closed across three slices in a row (1.5x filing-to-closing ratio). Auto-invoked by `/grind` post-merge; comments on the most-recent open PR and writes a `plan-health-degraded` event, never pauses dispatch. See `skills/plan-health/SKILL.md`.

## primitive

A leaf skill that does one thing well and stands alone — `/codex-review`, `/self-review`, `/sweep-worktrees`, `/codex-confer`, etc. Layer 1 of anvil's three-layer model. The design rule is: never reinvent a primitive that already exists. See `docs/architecture.md`.

## recap

The visual or structured session report produced by `/recap` after a multi-PR sprint. Two modes — `v1` writes a self-contained HTML page to `~/.claude/showme/`, `v2` writes a markdown TLDR + WHY with citation resolution. See `skills/recap/SKILL.md`.

## slice

A single dependency-ordered unit of work inside a plan — typically <=500 LoC, single PR, one acceptance contract. Each slice carries an `id`, `scope`, `depends-on`, `acceptance`, optional `checklist`, and optional `operator-decision` block. `/grind` dispatches one agent per slice. See `templates/plan-template.md` and `skills/dispatch-slice/SKILL.md`.

## slice manifest

The YAML block inside `plan.md` or `tasks.md` that machine-readably defines every slice — id, deps, scope, constraints, acceptance, checklist, operator-decision. The orchestrator parses this; humans read it too. See `templates/plan-template.md`.

## spec

The interactive plan-capture skill. Probes the operator's intent until ambiguity is removed, then writes a plan that `/grind` can execute. Two output layouts (flat / folder) chosen by slice count and decision count. See `skills/spec/SKILL.md`.

## verb

The set of valid answers an operator can give at an operator-decision point — subset of `[approve, edit, reject, respond]`, defined per decision in the slice manifest. The orchestrator records the chosen verb in the operator decision records section of the plan. See `templates/plan-template.md`.

## worktree

A separate working tree on disk (created via `git worktree add`) where a single dispatched agent does its work, isolated from the operator's main checkout. One worktree per slice; `/sweep-worktrees` bulk-cleans them after a sprint. See `skills/dispatch-slice/SKILL.md` and `skills/sweep-worktrees/SKILL.md`.
