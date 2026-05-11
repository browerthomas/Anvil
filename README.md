<div align="center">

# anvil

**Forge ideas into shipped code.**

`/spec` → `/grind` → `/recap`

[Quickstart](#quickstart) · [Install](#install) · [Skills](#skills) · [How it works](#how-it-works) · [Contributing](CONTRIBUTING.md)

</div>

---

Anvil is a Claude Code skill suite that takes a multi-slice plan and drives it from spec → PRs → merged. Markdown skills + bash + MCP. No platform, no compilation, no lock-in.

## Who it's for

- **Solo developers who want the agent to handle the GitHub review + merge dance**, not just write the code. Adversarial review, pre-merge gate, squash + branch + worktree cleanup — all scripted.
- **Operators running multi-slice sprints** who want agent dispatch + review + merge orchestrated end-to-end across a dependency graph, pausing only at decision points they defined.

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

### Subsets

Anvil ships as three composable groups. Install only what you need:

```bash
~/anvil/bin/install.sh --group core           # /sweep-worktrees /self-review /recap
~/anvil/bin/install.sh --group pr             # /dispatch-slice /pre-merge-gate /auto-merge
~/anvil/bin/install.sh --group orchestrator   # /spec /grind
```

`--copy` instead of symlink for a stable install that survives folder moves. `bin/uninstall.sh` to remove.

## Battle-tested on real sprints

Anvil is dogfooded on its operator's main project. Recent grinds:

- **http-client-standardisation** — 4 slices, 4 PRs merged in one session (theirownstory#1080, #1082, #1084, #1086). Full orchestration via `/grind`; surfaced the v0.4 glue-layer skills (`/findings-rollup`, `/refine-plan`, `/config-bootstrap`, `/issue-to-spec`, `/post-merge-debrief`).
- **architecture-standardisation** — 15-slice plan, 5 slice PRs merged so far (theirownstory#1097, #1098, #1103, #1104, #1115) plus mid-grind plan refine (#1122) via `/refine-plan`. Live; sequential lanes still rolling.

If you adopt anvil and want to be added here, open a PR.

## Skills

Thirteen skills. You won't call all of them — `/grind` composes most. Plain-English descriptions below; skill names stay stable for backwards compatibility.

| Skill | What it does |
|---|---|
| [`/spec`](skills/spec/SKILL.md) | Capture work as a structured plan (interactive probe). Validates before `/grind` can execute. |
| [`/grind`](skills/grind/SKILL.md) | Drive a plan end-to-end. Topo-sorts slices, dispatches agents, reviews, gates, merges. Pauses only at ASK decision points. |
| [`/dispatch-slice`](skills/dispatch-slice/SKILL.md) | Fire an agent against one slice with the full prompt template (worktree, deps, constraints, PR template). Three-line invocation. |
| [`/pre-merge-gate`](skills/pre-merge-gate/SKILL.md) | Verify a PR is mergeable: rebase + tsc + tests + fitness ratchets + grep for forbidden patterns + GH check status. One verdict. |
| [`/auto-merge`](skills/auto-merge/SKILL.md) | Squash + delete branch + wipe worktree + sync main. One call. |
| [`/post-merge-debrief`](skills/post-merge-debrief/SKILL.md) | After a one-off merge outside `/grind`: cleanup + mark merged in event log + pull main + dispatch next slice. |
| [`/self-review`](skills/self-review/SKILL.md) | Adversarial diff review via an Opus sub-agent. `--multi-critic` mode runs four parallel critics + a synthesizer. Codex fallback. |
| [`/findings-rollup`](skills/findings-rollup/SKILL.md) | Translate a multi-critic review into action: file P2/P3 as a rollup issue + dispatch a fix-up agent for the P0/P1 list. |
| [`/refine-plan`](skills/refine-plan/SKILL.md) | Mid-grind plan correction. Edit plan files in-place, log a `plan-revised` event, comment on in-flight PRs whose contract moved. |
| [`/config-bootstrap`](skills/config-bootstrap/SKILL.md) | Derive `.anvil/` configs (forbidden patterns, dispatch defaults, known flakes) from your project's existing context docs (CLAUDE.md, AGENTS.md, post-mortems). |
| [`/issue-to-spec`](skills/issue-to-spec/SKILL.md) | Verify a GitHub issue body's factual claims against the codebase before locking a plan. Catches issue-body-is-wrong errors at lock-time. |
| [`/sweep-worktrees`](skills/sweep-worktrees/SKILL.md) | Bulk-clean stale worktrees + branches. Handles cloud-sync-evicted `node_modules` and stale git locks. |
| [`/recap`](skills/recap/SKILL.md) | Visual HTML session report — PRs shipped, tests added, decisions made, loose ends. Dropped into `~/.claude/showme/`. |

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
- **Folder (OpenSpec-style):** [`templates/plan-folder-template/`](templates/plan-folder-template/) — `proposal.md` + `design.md` + `tasks.md` + `specs/`. For substantive plans; the adversarial reviewer gets the `specs/` files as context.

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

## License

[MIT](LICENSE).
