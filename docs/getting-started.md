# Getting started with anvil

A 15-minute walkthrough from "never heard of anvil" to "shipped a PR through `/grind`."

## Prerequisites

You'll need:

- macOS or Linux. (Windows works in WSL2; native untested.)
- Claude Code installed + authenticated.
- `gh` CLI authenticated (`gh auth login`). Anvil leans on `gh` for PR + issue automation.
- `git` ≥ 2.40, `node` ≥ 20, `npm`, `jq`. Most of these you already have.
- A repo to point anvil at. Your own project, a fork, or a sandbox repo work fine.
- Optional but recommended: `codex` CLI (for cross-model review). Anvil has `/self-review` as a fallback.

Run the preflight check to verify:

```bash
~/Desktop/anvil/bin/preflight.sh
```

It'll tell you what's missing. Fix anything red before continuing.

## Install

```bash
~/Desktop/anvil/bin/install.sh
```

This symlinks each anvil skill from `~/Desktop/anvil/skills/<name>/` into `~/.claude/skills/<name>/`. Claude Code discovers them automatically.

To verify, open Claude Code and ask:

```
/recap
```

If anvil is installed correctly, the skill should be invocable. (It'll fail because there's no recent activity to recap, but the failure should be specific — "no commits found" — not "skill not found.")

## Phase 0 walkthrough — the live skills

These three are usable today.

### `/sweep-worktrees`

After a multi-PR sprint, run `/sweep-worktrees` to bulk-clean stale worktrees + branches. Anvil reads your `git worktree list` and `gh pr list`, classifies each, and prompts before deleting.

### `/self-review`

Before merging a PR you're unsure about, run `/self-review <pr-number>`. Anvil dispatches an Opus sub-agent to adversarially review the diff and surfaces P0/P1/P2/P3 findings.

This is the fallback for when `/codex-review` is rate-limited. If you have codex available, prefer that — cross-model review catches things same-model review can't.

### `/recap`

After a sprint, run `/recap` to generate a visual HTML session report. PRs shipped, tests added, lessons learned, loose ends. Drops in `~/.claude/showme/` and opens in your browser.

## Phase 1 walkthrough (when shipped)

The inner-loop trio reduces per-PR overhead to three invocations:

```bash
# Per slice in a plan:
/dispatch-slice <slice-id>     # spin up agent in worktree
# (agent runs, opens PR)
/pre-merge-gate <pr>           # rebase + tsc + tests + fitness + grep
/auto-merge <pr>               # squash + cleanup + sync
```

Each of these is specified in `skills/<name>/SKILL.md`; implementation lands in Phase 1.

## Phase 2 walkthrough (when shipped)

The end-to-end orchestrator:

```
claude> /spec "I want to extract direct console.log calls into a typed Logger interface"
```

`/spec` interactively probes for detail using `templates/probe-questions.md`. It writes a plan to `docs/plans/<slug>.md` and surfaces it for your approval.

```
claude> /grind docs/plans/2026-XX-XX-logger-boundary.md
```

`/grind` reads the plan, dispatches agents per slice in dependency order, runs review + pre-merge-gate + auto-merge per slice, files follow-ups for any P0/P1 findings, and recaps at the end. It pauses only at operator-decision points you defined in the plan.

## Smoke test

Once the full framework ships, smoke-test your install with the hello-world plan:

```
claude> /grind ~/Desktop/anvil/examples/hello-world-plan.md
```

It adds a `CONTRIBUTING.md` to your repo (if missing) — single slice, docs-only, low-risk. If it merges cleanly + the recap shows the expected output, your install is working.

## Per-repo setup

For `/pre-merge-gate` to police your project's specifics, drop config in your repo:

```
.anvil/
├── forbidden-patterns.txt          # grep patterns that block merge
└── pre-merge-gate.config.json      # rebase target, baselines, known flakes
```

Starter samples are in `~/Desktop/anvil/skills/pre-merge-gate/templates/`. Copy and tune.

## Common patterns

### "I want to ship a refactor across many files"

Use `/spec` to capture it as a plan. The interactive probe will push you to:
- Define out-of-scope explicitly.
- Decompose into ≤500 LoC slices.
- Identify operator-decision points (e.g. "should I bump the schema_version?").

Then `/grind` the plan.

### "Codex is rate-limited but I want review"

`/self-review <pr>` is the fallback. Same adversarial framing, same P0-P3 output. Trade-off: same-model blind spots, but better than no review.

### "I just want a recap of what shipped today"

`/recap` reads recent merged PRs (default: last 24h) + generates the HTML.

## Where to ask questions

- Bug reports: file a GitHub issue using the template at `.github/ISSUE_TEMPLATE/bug.md`.
- New skill ideas: `.github/ISSUE_TEMPLATE/skill-proposal.md`.
- Architecture questions: read `docs/architecture.md` first; if still unclear, file an issue.

## What's next

Read `docs/architecture.md` for the three-layer composition model. It explains how the skills compose and how to extend the framework cleanly.
