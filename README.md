<div align="center">

# anvil

**Ship large Claude Code tasks without losing state.**

`/spec` → `/grind` → `/recap`

[Quickstart](#quickstart) · [Install](#install) · [Skills](#skills) · [How it works](#how-it-works) · [Contributing](CONTRIBUTING.md)

</div>

---

## Status

**v0.6.0** — 19 skills · 17 review lenses · MIT, public, fully local.

Anvil keeps plans, slice status, reviews, merge gates, and recaps **in your repo — not buried in chat**. It's a Claude Code skill suite that takes a multi-PR plan (multiple stacked or independent PRs that ship one logical change) and drives it from spec → PRs → merged. Markdown skills + bash + MCP. No platform, no compilation, no lock-in.

**Tired of Claude stopping mid-sprint?** State lives in plan files, an append-only event log, and worktrees on disk — not the conversation. Stop and resume anywhere. The next slice fires in a fresh agent with full context.

## Who it's for

**Solo or small-team engineers running multi-PR Claude Code work** — you want the agent to handle the GitHub review + merge dance across a sprint, not just write the code. `/grind` dispatches each slice, `/pre-merge-gate` + `/auto-merge` close the loop, `/recap` writes it up.

Also useful for systems engineers, software engineers shipping refactors and migrations, SaaS operators, and OSS maintainers — the 17 review lenses below cover those surfaces.

## What makes this different

Anvil treats plan state as a **product of the repo**, not a side effect of a conversation. Plan files, slice status, the append-only event log (`.anvil/grind-events.jsonl`), recorded decisions (`.anvil/learnings.jsonl`), and worktree layout all live on disk and version with your code. A fresh agent in a new session reads the same state your last agent wrote — no chat scrollback to rehydrate, no SaaS dashboard to log into. Everything runs **locally** against your existing `git` + `gh` + Claude Code install: no platform account, no hosted control plane, no telemetry leaving your machine. Anvil composes with what you already have rather than replacing it.

## Quickstart

```bash
# In Claude Code, after install:
/sweep-worktrees             # bulk-cleanup of stale worktrees + branches
/self-review                 # adversarial diff review (codex fallback)
/recap                       # visual HTML session report

/spec "what you want built"  # interactive plan capture
/grind docs/plans/<slug>.md  # end-to-end orchestrator
```

Longer walkthrough: [`docs/getting-started.md`](docs/getting-started.md).

## Install

```bash
# 1. Clone
git clone https://github.com/browerthomas/Anvil.git ~/anvil

# 2. Verify environment (gh + git + node + jq)
~/anvil/bin/preflight.sh

# 3. Install the skills (symlinks into ~/.claude/skills/)
~/anvil/bin/install.sh

# 4. Bootstrap per-repo config inside your target project
cd /path/to/your/project
~/anvil/bin/init-anvil-config.sh
```

`bin/install.sh` writes `~/.claude/anvil-config.sh` exporting `ANVIL_ROOT` so skill scripts can locate `shared/lib.sh` regardless of where the checkout lives. Override with `ANVIL_ROOT=/elsewhere/anvil <command>` at runtime. `--prefix <dir>` (or `ANVIL_HOME` / `CLAUDE_HOME`) installs to a non-default location — used by `tests/install.test.sh`.

`bin/install.sh` invokes `bin/preflight.sh` automatically at the end. Preflight now verifies installed skills work post-install (syntax-check + `shared/lib.sh` resolution smoke) — failures abort the install with the specific failure printed. Pass `--no-preflight` to skip.

### Subsets

Anvil ships as three composable groups. Install only what you need:

```bash
~/anvil/bin/install.sh --group core           # /sweep-worktrees /self-review /recap
~/anvil/bin/install.sh --group pr             # /dispatch-slice /pre-merge-gate /auto-merge
~/anvil/bin/install.sh --group orchestrator   # /spec /grind
```

`--copy` instead of symlink for a stable install that survives folder moves. `bin/uninstall.sh` to remove (also drops `anvil-config.sh`).

### Tests

Before submitting changes:

```bash
bash tests/install.test.sh
```

End-to-end test of install + preflight + uninstall against a temp HOME. Asserts `anvil-config.sh` is created with the right `ANVIL_ROOT`, every skill script syntax-checks, the `shared/lib.sh` resolution works in both copy and symlink modes, and uninstall cleans up.

## Where it's been used

Anvil is dogfooded on its maintainer's main project. Recent grinds:

- **HTTP-client standardisation** — 4-slice sprint, every slice landed in one session via `/grind`. Surfaced the v0.4 glue-layer skills (`/findings-rollup`, `/refine-plan`, `/config-bootstrap`, `/issue-to-spec`, `/post-merge-debrief`).
- **Architecture standardisation** — multi-week 15-slice plan, mid-flight. Mid-grind plan correction via `/refine-plan` after the first slice surfaced an incorrect path assumption in the spec. Sequential lanes still rolling.

If you adopt anvil and want to be added here, open a PR.

## Skills

19 skills. You won't call all of them — `/grind` composes most. Plain-English descriptions below; skill names stay stable for backwards compatibility.

| Skill | What it does |
|---|---|
| [`/spec`](skills/spec/SKILL.md) | Capture work intent as a structured plan with explicit slices, dependencies, acceptance criteria, and operator decision points. Interactive — probes for detail until ambiguity is removed. Output is a markdown plan that `/grind` can execute. |
| [`/grind`](skills/grind/SKILL.md) | Execute a plan end-to-end. Reads the slice manifest, dispatches agents in dependency order, runs review + pre-merge gate + auto-merge per slice, files follow-ups, recaps at end. The orchestrator wrapper. |
| [`/dispatch-slice`](skills/dispatch-slice/SKILL.md) | Dispatch a single agent for a single plan slice with consistent briefing. Codifies the agent prompt template (worktree path, deps install reminder, commit format, PR template requirement, default-Opus posture, return shape). |
| [`/pre-merge-gate`](skills/pre-merge-gate/SKILL.md) | Verify a PR is merge-ready before invoking `/auto-merge`. Combinator runs rebase + tsc + vitest + fitness ratchets + grep for forbidden patterns, returns ready/not-ready with the specific failure. |
| [`/auto-merge`](skills/auto-merge/SKILL.md) | Squash-merge a PR + delete branch + wipe worktree + sync main, in one shot. Assumes `/pre-merge-gate` has already greenlit the PR. |
| [`/post-merge-debrief`](skills/post-merge-debrief/SKILL.md) | After a single PR squash-merges outside `/grind`: bundle verify-merge + sweep-this-worktree + mark-merged-in-event-log + pull-main + auto-dispatch-next-slice-if-deps-met. Compresses 5 manual steps into one call. |
| [`/self-review`](skills/self-review/SKILL.md) | Adversarial diff review via an Opus sub-agent when `/codex-review` is unavailable. Returns structured findings (P0/P1/P2/P3). Codex-fallback. `--multi-critic` mode runs four parallel critics + a synthesizer. |
| [`/dual-review`](skills/dual-review/SKILL.md) | Run `/self-review` (Claude) and `/codex-review` (Codex) concurrently on a high-stakes diff, then emit a single agreement table — `Both` / `Claude only` / `Codex only` — so cross-model agreement signal is visible. |
| [`/lens`](skills/lens/SKILL.md) | Adversarial review through a named review lens — kernel developer, SRE, distributed-systems engineer, privacy lawyer, security researcher, etc. Lenses are namespaced into `systems/` / `saas/` / `generic/`. Each lens wraps `/self-review` or `/codex-review` to focus the model's attention on one perspective. |
| [`/learn`](skills/learn/SKILL.md) | Record + recall per-project learnings + decisions as an append-only JSONL log at `.anvil/learnings.jsonl`. Skills auto-append on discovery ("chronic flake X bit again, retry once"); operators search before re-rediscovering. Subcommands: add, search, decisions, prune, summary, export. |
| [`/findings-rollup`](skills/findings-rollup/SKILL.md) | After `/self-review` or `/codex-review` produces a multi-finding report: file P2/P3 findings as a single rollup issue with checkboxes, and dispatch a fix-up agent against the same PR/branch with the P0/P1 list as its acceptance contract. |
| [`/refine-plan`](skills/refine-plan/SKILL.md) | Mid-grind plan correction. Updates the plan files (proposal/design/tasks/specs) in-place, writes a `plan-revised` event to `.anvil/grind-events.jsonl`, and optionally comments on any in-flight PRs whose acceptance contract just moved. |
| [`/config-bootstrap`](skills/config-bootstrap/SKILL.md) | Once per project that adopts anvil, populate `.anvil/forbidden-patterns.txt` + `.anvil/dispatch-defaults.txt` + `.anvil/known-flakes.txt` from the project's existing context docs (CLAUDE.md / AGENTS.md / README / post-mortems). |
| [`/issue-to-spec`](skills/issue-to-spec/SKILL.md) | Before locking a plan that derives from a GitHub issue body, verify the issue's factual claims (file:line references, "X retries on N", "Y is at Z") against current code. Outputs a corrected mini-spec marking which claims were verified, which contradicted, which couldn't be verified. |
| [`/sweep-worktrees`](skills/sweep-worktrees/SKILL.md) | Bulk-clean stale worktrees + branches after a multi-PR sprint. Handles iCloud-evicted `node_modules`, stale `.git/*.lock` files, `.git/worktrees/*` admin dirs, and force-deletes branches whose PRs are MERGED or CLOSED. |
| [`/recap`](skills/recap/SKILL.md) | After a multi-PR sprint, generate a session recap. Two modes — v1 (visual HTML page in `~/.claude/showme/`) and v2 (structured TLDR + WHY markdown with citation resolution). |
| [`/anvil-status`](skills/anvil-status/SKILL.md) | Read-only rank-ordered text dashboard of a plan's state — what to think about next, what's in-flight, what's blocked, what's shipped, what's deferred — plus cumulative test delta + open follow-up count. Folds `.anvil/grind-events.jsonl` + tasks.md + `gh pr list` (or `GH_OFFLINE=1` fallback). |
| [`/followup-rollup`](skills/followup-rollup/SKILL.md) | Consolidate open follow-up issues for a multi-slice plan. Walks issues whose title carries the `[<plan>-<slice> followup]` prefix, groups by severity (P0/P1/P2/P3) + area (test-coverage / correctness / architecture / operability), suggests which slice should consume each cluster. Output: markdown pasteable into a planning doc. |
| [`/plan-health`](skills/plan-health/SKILL.md) | Non-blocking gate that flags when follow-up filing outpaces closing by 1.5× for three slices in a row. Auto-invoked by `/grind` step h.5 post-merge. Appends a `plan-health-degraded` event + comments on the most-recent open PR; never pauses dispatch. |

### Optional companions

Anvil composes with these when present; they install separately:

`/codex-review` cross-model code review · `/codex-confer` adversarial design opinion · `/codex-plan` cross-model planning · `/codex-check` binding factual yes/no · `/offensive-audit` multi-lens repo audit · `/loop` self-paced wakeup · `/sync-kb` Obsidian sync.

## How it works

Three layers compose:

```
┌──────────────────────────────────────────────────┐
│  /spec       /grind       /recap                 │  ← orchestration
├──────────────────────────────────────────────────┤
│  /dispatch-slice  /pre-merge-gate  /auto-merge   │  ← inner loop (per PR)
├──────────────────────────────────────────────────┤
│  /codex-review  /self-review  /sweep-worktrees   │  ← primitives
└──────────────────────────────────────────────────┘
```

Each layer composes the layer below; each is invocable standalone. Full architecture: [`docs/architecture.md`](docs/architecture.md).

## Plan format

Two layouts, both supported by `/spec` and `/grind`:

- **Flat:** [`templates/plan-template.md`](templates/plan-template.md) — single markdown file with the YAML manifest inline. For <5 slices, no architecture decisions.
- **Folder layout for non-trivial plans:** [`templates/plan-folder-template/`](templates/plan-folder-template/) — `proposal.md` + `design.md` + `tasks.md` + `specs/`. For substantive plans; the adversarial reviewer gets the `specs/` files as context.

Required sections: Goal, Scope, Architecture decisions, Hard constraints, Slice manifest (YAML with deps + acceptance + operator decision points), Validation checklist.

Worked example: [`examples/example-plan.md`](examples/example-plan.md) (logger-boundary refactor, 7 slices). Minimal: [`examples/hello-world-plan.md`](examples/hello-world-plan.md).

## Per-repo configuration

`/pre-merge-gate` and `/grind` read project-specific config from your repo:

| Path | Used by | Shape |
|---|---|---|
| `.anvil/forbidden-patterns.txt` | `/pre-merge-gate` | grep patterns + path globs that block merge |
| `.anvil/pre-merge-gate.config.json` | `/pre-merge-gate` | rebase target, test baselines, known flakes |
| `.anvil/known-flakes.txt` | `/grind` | retry-once patterns |
| `.anvil/grind-events.jsonl` | `/grind` | append-only event log (auto-managed) |

Starter templates in `skills/pre-merge-gate/templates/`. Use `/config-bootstrap` to fill them from your project's docs.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for skill style, PR conventions, and the major-changes workflow (anvil ships anvil — use `/spec` + `/grind` for big changes).

Anvil has its own smoke-test suite. Run `make -C tests smoke` before submitting a PR. Requires `bats-core` (`brew install bats-core` / `apt install bats`) and `jq`. See [`tests/README.md`](tests/README.md) for layout and how to add a new test.

## License

[MIT](LICENSE).
