# anvil architecture

> How the skills compose. Read this if you want to extend anvil or understand its design.

## The three-layer model

anvil sits on top of Claude Code's skill system and composes existing pieces into three layers:

```
┌──────────────────────────────────────────────────┐
│  /spec       /grind       /recap                 │  ← orchestration layer
│   plan        execute      report                │
├──────────────────────────────────────────────────┤
│  /dispatch-slice  /pre-merge-gate  /auto-merge   │  ← inner-loop layer
│   per-PR cycle                                   │
├──────────────────────────────────────────────────┤
│  /codex-review   /self-review   /sweep-worktrees │  ← primitives
│  /codex-confer   /codex-plan    /codex-check     │
│  /sync-kb        /offensive-audit                │
└──────────────────────────────────────────────────┘
```

Each layer composes the layer below. Each layer is invocable standalone.

## Layer 1: primitives

These are the leaf skills. Each does one thing well. anvil's design rule: never reinvent a primitive that already exists.

| Primitive | What it does | When |
|---|---|---|
| `/codex-review` | cross-model diff review | preferred review path |
| `/self-review` | Opus-driven adversarial review | codex-fallback |
| `/codex-confer` | adversarial design opinion | pre-implementation pushback |
| `/codex-plan` | cross-model planning | sanity-check a plan |
| `/codex-check` | binding factual yes/no | "does X actually exist in code?" |
| `/sweep-worktrees` | bulk cleanup | after multi-PR sprints |
| `/sync-kb` | KB Obsidian sync | session boundaries |
| `/offensive-audit` | multi-lens repo audit | quarterly / pre-launch |

## Layer 2: inner loop

These compose primitives into per-PR cycles. They're the "do the same thing 12 times per session" automations.

### `/dispatch-slice`
Codifies the agent prompt template. Inputs: slice id + scope + constraints. Output: agent dispatched in worktree with full briefing. Replaces the ~600-word per-agent prompt I rewrote 15 times in the OPERABILITY sprint.

Composes: Agent tool, git worktree, npm install, Bash for prompt assembly.

### `/pre-merge-gate`
Verification combinator. Rebase + tsc + vitest + fitness ratchets + grep-for-forbidden-patterns + CI verify. Returns merge-ready / blocked / yellow-flags. Replaces 6 manual checks per PR.

Composes: git rebase, npx tsc, npx vitest, gh pr checks.

### `/auto-merge`
Squash-merge + branch delete + worktree wipe + git admin clear + main sync. Handles iCloud-evicted node_modules + stale lock files + "branch used by worktree" errors. Replaces 5 manual commands per PR.

Composes: gh pr merge, find -delete, git worktree prune, git pull.

## Layer 3: orchestration

These wrap the inner loop into end-to-end workflows.

### `/spec`
Interactive plan capture. Probes for detail using `templates/plan-template.md` until ambiguity is gone. Optionally fires `/codex-confer` for adversarial validation. Outputs structured markdown to `docs/plans/`.

Composes: AskUserQuestion (probes), `/codex-confer` (challenge), `/codex-plan` (cross-model planning), file write.

### `/grind`
End-to-end orchestrator. Reads a plan, topo-sorts slices, dispatches in dependency order, runs `/codex-review` (or `/self-review` fallback), runs `/pre-merge-gate`, runs `/auto-merge`, files follow-ups, recaps at end.

Composes: All layer-1 + layer-2 skills.

### `/recap`
Visual session report. PRs shipped, tests added, lessons, loose ends. HTML output for fast scanning + archival.

Composes: gh pr list, git log, file write to `~/.claude/showme/`, `open` for browser.

## Composition rules

1. **No circular dependencies.** Layer 3 calls layer 2 and 1; layer 2 calls layer 1; layer 1 stands alone.
2. **Standalone-first.** Every skill works without the layers above it. You can use `/sweep-worktrees` without ever installing `/grind`.
3. **Operator decision points are explicit.** `/grind` only pauses at `operator-decision.ask` markers in the plan. Implicit pauses are forbidden.
4. **Failures cascade gracefully.** Codex outage → fall back to `/self-review`. `/pre-merge-gate` blocked → file an issue + skip slice + continue with siblings. Plan slice can't be auto-resolved → mark deferred + continue.
5. **No silent state.** Every skill prints its verdict + cites file paths + leaves a trace under `~/.claude/showme/` or `.codex-log/` or commit message.

## Plan format

A anvil plan is markdown with a parseable YAML slice manifest. See `templates/plan-template.md` for the canonical shape and `examples/operability-plan-example.md` for a real plan that ran successfully.

Required sections:
- Goal
- Scope (in / out)
- Architecture decisions
- Hard constraints
- Slice manifest (YAML)
- Validation checklist

Optional:
- Operator notes
- Followups (orchestrator appends here at runtime)

## Failure modes (and how anvil handles them)

| Failure | anvil's response |
|---|---|
| Codex rate-limited | `/self-review` fallback, no operator action |
| CI flake on known-flaky test | retry once before declaring fail |
| Sibling PR merge causes rebase conflict | auto-rebase if trivial; defer slice + continue siblings if reasoning needed |
| Operator decision point reached | pause + AskUserQuestion; apply `default` after timeout |
| Operator unreachable for >N hours | apply slice's `default` (skip-with-warning) |
| Worktree wipe hangs (iCloud quirk) | `find -delete` parallel, fall back to skip with operator notification |
| Stale `.git/*.lock` | clear automatically, retry once |

## Extension points

- **Custom forbidden patterns**: drop a `.anvil/forbidden-patterns.txt` in your repo. `/pre-merge-gate` reads it.
- **Custom plan templates**: copy `templates/plan-template.md`, modify, point `/spec` at your version.
- **Custom recap layouts**: copy `templates/recap-template.html`, modify, point `/recap` at your version. Coming in Phase 1.
- **Multi-repo plans**: a plan can reference slices in multiple repos via `repo:` field on each slice. Coming in Phase 2.

## What anvil does NOT do

- It does not write code itself. Agents do.
- It does not validate code quality (that's review).
- It does not skip operator decision points.
- It does not handle non-PR work (operator-paced infra is out of scope; mark slices as `operator-paced: true` to skip).
- It does not auto-commit to main without going through a PR.
