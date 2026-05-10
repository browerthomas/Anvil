<div align="center">

# anvil

**Forge intent into merged PRs.**

Plans come in raw. PRs come out forged.
An open framework for AI-orchestrated engineering work in Claude Code.

`/spec` → `/grind` → `/recap`

[Quickstart](#quickstart) · [How it works](#how-it-works) · [Skills](#skills) · [Plan format](#plan-format) · [Contributing](CONTRIBUTING.md)

</div>

---

## What it is

A composable bundle of Claude Code skills that turns a structured plan into merged PRs with minimal operator intervention. Three phases:

| | Skill | Verb |
|---|---|---|
| **Plan** | `/spec` | Lay the blueprint |
| **Forge** | `/grind` | Run the forge |
| **Recap** | `/recap` | Stamp the work |

Each skill stands alone. Together they're a framework. Adopt incrementally — markdown files in `~/.claude/skills/`, no compilation, no platform.

## Why

Multi-PR sprints converge on the same workflow every time:

1. Lay out what you want.
2. Dispatch agents per slice in dependency order.
3. Adversarially review each.
4. Gate each merge against a project-specific battery (rebase + tsc + tests + fitness ratchets + grep-for-forbidden-patterns).
5. Squash-merge + clean up worktrees.
6. Recap what shipped + what didn't.

Anvil codifies that loop so it stops being something you re-derive every session.

## Status

**v0.3** — production-ready. All eight skills shipped, plus plan validator, multi-critic review, failure-mode triage, append-only event log, and a Claude Code plugin manifest. See [`CHANGELOG.md`](CHANGELOG.md) for what landed in each release and [`ROADMAP.md`](ROADMAP.md) for what's open.

Open follow-ups:
- v0.2.1 — Langfuse OTel adapter implementation, `@anvil/gate-mcp` npm publish.
- v0.4+ — speculative; sourced from real-world adoption signal.

## Quickstart

```bash
# 1. Clone the framework
git clone https://github.com/browerthomas/Anvil.git ~/anvil
cd ~/anvil

# 2. Heat the forge — verify your environment
bin/preflight.sh

# 3. Stoke it — install the skills (symlinks into ~/.claude/skills/)
bin/install.sh

# 4. Bootstrap a project's .anvil/ config (run from inside the target repo)
cd /path/to/your/project
~/anvil/bin/init-anvil-config.sh
```

Then in Claude Code:

```
/sweep-worktrees             # bulk-cleanup of stale worktrees + branches
/self-review                 # adversarial diff review (codex fallback)
/recap                       # visual HTML session report

/spec "what you want built"  # interactive plan capture
/grind docs/plans/<slug>.md  # end-to-end orchestrator
```

See [`docs/getting-started.md`](docs/getting-started.md) for a longer walkthrough and [`docs/architecture.md`](docs/architecture.md) for the three-layer composition model.

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

Each layer composes the layer below. Each layer is invocable standalone. Full architecture in [`docs/architecture.md`](docs/architecture.md).

## Skills

### Primitives (standalone — useful even without the rest)

| Skill | Tagline | One-liner |
|---|---|---|
| [`/sweep-worktrees`](skills/sweep-worktrees/SKILL.md) | Reset the workshop | Bulk-clean stale worktrees + branches; handles iCloud node_modules + git locks |
| [`/self-review`](skills/self-review/SKILL.md) | Test the temper | Opus-driven adversarial diff review with optional 4-critic multi-pass mode — codex fallback |
| [`/recap`](skills/recap/SKILL.md) | Stamp the work | Visual HTML session report — PRs shipped, tests added, lessons, loose ends |

### Inner-loop trio (per-PR cycle)

| Skill | Tagline | One-liner |
|---|---|---|
| [`/dispatch-slice`](skills/dispatch-slice/SKILL.md) | Strike a billet | Codifies the agent prompt template — replaces ~600-word per-agent briefs |
| [`/pre-merge-gate`](skills/pre-merge-gate/SKILL.md) | Inspect the seam | Combinator: rebase + tsc + tests + fitness + grep — one verdict |
| [`/auto-merge`](skills/auto-merge/SKILL.md) | Quench and ship | Squash-merge + branch delete + worktree wipe + main sync, in one call |

### Orchestration (end-to-end)

| Skill | Tagline | One-liner |
|---|---|---|
| [`/spec`](skills/spec/SKILL.md) | Lay the blueprint | Interactive plan capture — probes for detail, outputs structured markdown (flat or folder layout) |
| [`/grind`](skills/grind/SKILL.md) | Run the forge | End-to-end orchestrator — topo-sorts slices, dispatches agents, reviews, gates, merges, recaps |

### Compositional dependencies

Skills anvil composes with (install separately):

- [`/codex-review`](https://github.com/) — cross-model code review
- [`/codex-confer`](https://github.com/) — adversarial design opinion
- [`/codex-plan`](https://github.com/) — cross-model planning
- [`/codex-check`](https://github.com/) — binding factual yes/no
- [`/offensive-audit`](https://github.com/) — multi-lens repo audit
- [`/loop`](https://github.com/) — self-paced wakeup loop
- [`/sync-kb`](https://github.com/) — Obsidian sync

These aren't required — anvil's primitives stand alone — but `/grind` will compose with them when present.

## Plan format

Two layouts, both supported by `/spec` and `/grind`:

- **Flat:** [`templates/plan-template.md`](templates/plan-template.md) — single markdown file with the YAML manifest inline. Right for small plans (<5 slices, no architecture decisions).
- **Folder (OpenSpec-style):** [`templates/plan-folder-template/`](templates/plan-folder-template/) — `proposal.md` + `design.md` + `tasks.md` + `specs/`. Right for substantive plans with architecture decisions; the adversarial reviewer gets the `specs/` files as context.

Required sections:

- **Goal** — verifiable end-state in plain English
- **Scope** — in/out
- **Architecture decisions** — locked + rejected, with rationale
- **Hard constraints** — inviolable across all slices
- **Slice manifest** — YAML with deps + acceptance criteria + operator decision points
- **Validation checklist** — when this list is fully checked, the plan is "done"

Worked example: [`examples/example-plan.md`](examples/example-plan.md) — a logger-boundary refactor with 7 slices.

A minimal plan: [`examples/hello-world-plan.md`](examples/hello-world-plan.md) — single-slice "add a CONTRIBUTING.md" plan you can run end-to-end to verify your install.

## Installation modes

### Full install (all 8 skills)

```bash
~/Desktop/anvil/bin/install.sh           # symlink (development; edits live)
~/Desktop/anvil/bin/install.sh --copy    # copy (stable; survives folder moves)
~/Desktop/anvil/bin/uninstall.sh         # remove all anvil skills (leaves others)
```

### Group install (a subset)

Anvil ships as three composable plugin groups. Install only what you need:

```bash
~/Desktop/anvil/bin/install.sh --group core           # 3 skills: sweep + self-review + recap
~/Desktop/anvil/bin/install.sh --group pr             # 3 skills: dispatch + gate + auto-merge
~/Desktop/anvil/bin/install.sh --group orchestrator   # 2 skills: spec + grind
```

| Group | Skills | When to install |
|---|---|---|
| `anvil-core` | `/sweep-worktrees` `/self-review` `/recap` | Everyday helpers — useful even without the rest |
| `anvil-pr` | `/dispatch-slice` `/pre-merge-gate` `/auto-merge` | Per-PR cycle — recommended with `anvil-core` |
| `anvil-orchestrator` | `/spec` `/grind` | End-to-end plan-to-merged-PR drive — composes `anvil-pr` |

Higher groups recommend lower groups but don't require them. See [`groups/README.md`](groups/README.md) for the layered model.

Anvil installs each skill at `~/.claude/skills/<name>/` so Claude Code discovers them via the standard skills directory.

## Configuration (per-repo)

Skills look for project-specific config in your repo:

| Path | Used by | Shape |
|---|---|---|
| `.anvil/forbidden-patterns.txt` | `/pre-merge-gate` | grep patterns + path globs that block merge |
| `.anvil/pre-merge-gate.config.json` | `/pre-merge-gate` | rebase target, test baselines, knowable flakes |
| `.anvil/grind-state.json` | `/grind` | per-plan execution state (auto-managed) |
| `docs/plans/*.md` | `/spec`, `/grind` | plan files |
| `~/.claude/showme/*.html` | `/recap`, `/showme` | visual artifacts |

See `skills/pre-merge-gate/templates/` for starter configs.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). TL;DR:

1. Each skill is a `SKILL.md` with YAML frontmatter — edit and re-install.
2. Open a PR with a clear title and a fully-filled template.
3. New skills: add to `.claude-plugin/plugin.json`, add a brief test plan in the PR.
4. Major changes: capture them as an anvil plan first (use anvil to ship anvil).

## Hosting the landing page

`docs/index.html` is the project's landing page. To serve it:

1. Push the repo to GitHub.
2. **Settings → Pages → Source: Deploy from a branch → main → /docs**.
3. The page goes live at `https://browerthomas.github.io/Anvil/` within a minute.

GitHub Pages also renders `docs/architecture.md` and `docs/getting-started.md` as web pages at the same root — you get free `/architecture.html` and `/getting-started.html` routes.

For a custom domain, add a `CNAME` file under `docs/` containing your domain (e.g. `anvil.tools`) and configure DNS per [GitHub's docs](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site).

## License

[MIT](LICENSE) — your plan, your hammer, your ship.
