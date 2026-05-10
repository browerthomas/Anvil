# anvil roadmap

> Distilled from a landscape research pass on agentic dev workflow tooling (drydock.build, shipyard.build, Devin, Cursor BG agents, Cline, Aider, Spec-Kit, OpenSpec, BMAD, Symphony, LangGraph, CrewAI, OpenHands, CodeRabbit, Greptile, PR-Agent, Backlog.md, ccswarm, Claude Flow, Langfuse). Date: 2026-05-10.

## v0.1 — shipped

Phase 0 skills (live):
- `/sweep-worktrees`
- `/self-review`
- `/recap`

Phase 1 skills (spec'd + helper scripts in place; SKILL.md procedures complete):
- `/dispatch-slice` + `scripts/build-prompt.sh`
- `/pre-merge-gate` + `scripts/verify.sh`
- `/auto-merge` + `scripts/merge.sh`

Phase 2 skills (spec'd):
- `/spec` + `templates/probe-questions.md`
- `/grind` + `scripts/state.sh` + `templates/grind-loop.md`

Plus: plan template, 2 worked example plans, plugin manifest, MIT license, CHANGELOG, CONTRIBUTING, .github/ templates, GH Pages-ready landing at `docs/index.html`, `bin/init-anvil-config.sh` for per-repo bootstrapping.

## v0.2 — composability + observability — SHIPPED 2026-05-10

All five highest-leverage moves from competitive research landed:

### 1. Composable skill distribution ✅

Today anvil is monolithic — `bin/install.sh` puts all 8 skills in `~/.claude/skills/`. With 4,200+ skills in the Claude Code marketplace by May 2026, monolithic installs are harder to discover than focused single-purpose ones.

**Plan:**
- Split anvil into installable groups: `anvil-core` (sweep + self-review + recap), `anvil-pr` (dispatch-slice + pre-merge-gate + auto-merge), `anvil-orchestrator` (spec + grind).
- Each group is a separate `.claude-plugin/plugin.json` and ships independently to the marketplace.
- A meta-package `anvil` installs all three.
- Users who want only the gate can `/plugin install anvil-pr`.

**Why now:** distribution lever in a crowded marketplace. The narrative shifts from "install our framework" to "compose what you need."

### 2. Append-only event log + observability adapter ✅

`.anvil/grind-state.json` is a flat snapshot today. LangGraph's checkpointer writes a per-node event frame; that gives you replay-from-checkpoint, time-travel debugging, and per-slice token cost / latency / prompt traces (via Langfuse).

**Plan:**
- Convert `grind-state.json` from snapshot to append-only event log: each slice transition (`pending → in-flight → review → merge`) writes a frame.
- New `state.sh replay <slice-id>` and `state.sh trace` subcommands.
- Optional adapter: if Langfuse public key is set in `.anvil/observability.config.json`, anvil emits OTel spans to Langfuse. Self-host or use Langfuse Cloud — both work, both MIT.
- `/grind --resume <slice-id>` replays from the last frame.

**Why now:** closes the largest gap vs LangGraph + LangSmith. Operators get post-mortem traces for free. Zero lock-in (Langfuse is OSS).

### 3. Structured ASK verbs (LangGraph HITL pattern) ✅

Anvil's `operator-decision.ask` is freeform today — operator can answer anything, recap can't structure it. LangGraph's `interrupt()` + `Command(resume=...)` defines four verbs: `approve`, `edit`, `reject`, `respond`.

**Plan:**
- Plan template's `operator-decision` block gets a `verbs:` list — subset of `[approve, edit, reject, respond]`.
- `/grind` presents the ASK as an AskUserQuestion with those verbs as options.
- Operator's response + verb choice + free-text annotation become a structured "decision record" appended to the plan's `## Followups` section.
- `/recap` includes a "Decisions" subsection listing the records.

**Why now:** turns operator-in-the-loop from chat into a reproducible artifact. Recap quality jumps from "what shipped" to "what shipped + why operator approved/edited."

### 4. OpenSpec change-folder plan layout ✅

Today an anvil plan is one markdown file (`docs/plans/<slug>.md`). OpenSpec puts each change in a folder: `proposal.md` (the why) + `specs/` (acceptance scenarios) + `design.md` (the how) + `tasks.md` (the slice list).

**Plan:**
- New plan layout: `docs/plans/<slug>/proposal.md`, `<slug>/specs/<scenario>.md`, `<slug>/design.md`, `<slug>/tasks.md`.
- `/spec` produces this folder structure.
- `/grind` reads `tasks.md` for the manifest (same YAML shape as today).
- `/codex-review` and `/self-review` get the relevant `specs/` files as additional context — adversarial review compares execution against the explicit acceptance scenarios.
- Backwards-compat: single-file plans still work (`tasks.md` becomes the inline slice manifest).

**Why now:** sharpens adversarial review from "vibes vs diff" to "specs vs diff." Drive-by readers grok proposal-vs-design-vs-tasks separation faster than wall-of-markdown.

### 5. MCP-ize `/pre-merge-gate` ✅

Today the gate is a Claude Code skill. The 5,000+ MCP server ecosystem (March 2026) is portable across Cursor, Windsurf, Claude Code, ChatGPT desktop, and more.

**Plan:**
- Wrap `scripts/verify.sh` in a small MCP server (`anvil-gate-mcp`) that exposes one tool: `verify_pr(pr_number, options)`.
- Publish as a separate npm package + register on the MCP marketplace.
- The skill remains for Claude Code; the MCP server lets every agent host call the same gate.

**Why now:** anvil's gate becomes the reference "lint+test+ratchet+forbidden-pattern" implementation for the whole agent lane, not a Claude-Code-only artifact. Brand surface widens; anvil becomes infrastructure for everyone, not just our users.

## v0.3 — adversarial review + failure resilience — SHIPPED 2026-05-10

All three v0.3 items landed:

### 6. Multi-agent parallel critics ✅

Today `/codex-review` and `/self-review` are single-reviewer. Qodo Merge runs separate critics for security, bug, quality, tests in parallel. Greptile reports 82% bug catch with full-codebase indexing vs CodeRabbit's 44% with diff-only.

**Plan:**
- Split review into 3-4 specialized prompts (correctness, security, test-coverage, architectural-fit).
- Run them in parallel (background agents).
- Synthesize findings into one structured P0/P1/P2/P3 report.
- Optional: feed the reviewer the call-graph downstream of the diff (not just the diff text) — Greptile's catch-rate gap is mostly context.

### 7. Failure-mode triage (Symphony pattern) ✅

Today anvil halts on any agent failure. Distinguish:
- **Slice-fail** → defer that slice, continue dep-independent siblings, file an issue.
- **Plan-fail** → halt, write a structured incident report.
- **Infra-fail** (gh down, codex limit, network) → skip-and-retry with backoff.

Plus: circuit-breaker fallback chain. Opus rate-limited? Try Sonnet with tighter constraints. Both rate-limited? File the slice as a follow-up issue + continue.

### 8. Plan validation pass ✅

Add `/spec --validate <plan-path>` that runs:
- Schema check on slice manifest (every slice has acceptance, deps resolve, no cycles).
- Ambiguity check (every slice scope is ≥1 paragraph + ≥3 acceptance criteria).
- Cross-slice file-overlap check (warn when two parallel-marked slices touch the same file paths).
- Dry-run dispatch (assemble the agent prompt for each slice and verify it's well-formed).

Spec-Kit's `/speckit.analyze` is the model.

## v0.4 — glue + correction layer — SHIPPED 2026-05-10

Five new skills closing the manual sequences that surrounded the v0.3 core skills. All five surfaced from the first dogfood (`http-client-standardisation` plan). 13 skills total now.

### 9. /findings-rollup ✅
After `/self-review --multi-critic` or `/codex-review` returns findings, automatically: file P2/P3 as a single rollup issue with checkboxes, dispatch a fix-up agent against the same PR/branch with the P0/P1 list as its acceptance contract, comment on the PR linking both. Closes the 5-step manual dance every operator runs after every multi-critic review.

### 10. /issue-to-spec ✅
Pre-lock plan validation. Takes a GitHub issue body, greps the codebase for each factual claim, outputs a corrected mini-spec marking claims as verified / contradicted / moved / unverifiable. Catches the "issue body wrong" class of plan bug (the `core/lulu.js — custom retry pattern` class).

### 11. /refine-plan ✅
Mid-grind plan correction. Updates plan files in-place via Edit, writes a `plan-revised` event to `.anvil/grind-events.jsonl`, optionally comments on in-flight PRs whose contract moved.

### 12. /config-bootstrap ✅
Companion to `bin/init-anvil-config.sh`. Populates the `.anvil/` starter templates from the project's existing context docs (CLAUDE.md, AGENTS.md, post-mortems, audits) by extracting "DO NOT" / "always" / "flaky" patterns.

### 13. /post-merge-debrief ✅
Single-PR cleanup + next-slice dispatch in one call. For when an operator merges outside `/grind`. Composes existing scripts.

## v0.5+ — speculative

- **Cross-slice file-conflict detection** (Augment Code's Coordinator + Verifier pattern).
- **Persona-driven multi-role pipeline** (BMAD pattern: Analyst → PM → Architect → Dev → QA personas, each a separate agent role).
- **Production signal integration in `/recap`**: post-merge Sentry / production logs / `gh pr checks` results surfaced inline (Replit Agent 3 pattern).
- **Plan-driven monorepo support**: a single plan that touches multiple repos, each slice can specify which repo it targets.
- **Skill marketplace**: a small directory of community-built anvil skills extending the framework.

## Design principles (non-negotiable)

- **MIT, no SaaS, no vendor lock-in.** Skills are markdown. Repos are git. State is JSON. Adapters (Langfuse, MCP) are optional.
- **Composable, not monolithic.** Every skill stands alone.
- **Operator-in-the-loop is structured, not chat.** ASK markers + decision records.
- **Plans are auditable artifacts.** Markdown + YAML, lives in the repo, diff-friendly.
- **Failure handling: defer, don't halt** unless plan integrity is at risk.
- **No mystery boxes.** Every skill prints its verdict + cites file paths + leaves a trace.

## Cadence

- v0.1 — shipped 2026-05-10 (initial scaffold + 8 skills + plugin manifest + landing page).
- v0.2 — shipped 2026-05-10 (composability + event log + ASK verbs + folder plans + MCP gate).
- v0.3 — shipped 2026-05-10 (multi-critic review + failure triage + plan validator).
- v0.2.1 — open: Langfuse adapter implementation, `@anvil/gate-mcp` publish to npm.
- v0.4+ (open-ended): speculative items above, prioritized by real-world adoption signal.

## Anvil is production-ready

After v0.3, the framework is complete enough to drive real multi-PR work end-to-end. The next priorities are sourced from real-world friction, not speculation. Drive a real plan, see what hurts, fix that.

## Sources

The research that drove this roadmap surveyed 30+ tools across hosted spec-to-product platforms, OSS agent frameworks, plan-driven engineering automation, GitHub-native PR review tools, and skill/extension ecosystems. The key references are linked inline above; the full source list is in the research transcript at `~/.claude/projects/.../tasks/<id>.output` (operator-local artifact, not committed).
