# Changelog

All notable changes to anvil are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

(Nothing yet. v0.3 priorities in [ROADMAP.md](ROADMAP.md): multi-critic review, failure triage, plan validator.)

## [0.2.0] — 2026-05-10

All five v0.2 roadmap items from competitive landscape research.

### Added — composability
- **Composable plugin groups** — anvil ships as three groups (`anvil-core`, `anvil-pr`, `anvil-orchestrator`) with per-group plugin manifests under `groups/`.
- `install.sh --group <name>` installs just one group.
- The top-level manifest stays as the meta-bundle that installs all 8 skills.
- `groups/README.md` documents the three-layer composition model.

### Added — observability
- **Append-only event log** at `.anvil/grind-events.jsonl` (one JSON event per line) replaces snapshot-mutation. All state derives by folding events.
- New `state.sh trace [slice-id]`, `state.sh snapshot`, `state.sh replay <slice-id>` subcommands.
- `docs/observability.md` documents the event shape + Langfuse adapter spec (implementation v0.2.1).
- Existing `state.sh` subcommands (init/next/ready/mark/set-pr/add-issue/status) preserve the operator-facing API.

### Added — operator decisions
- **Structured ASK verbs** (LangGraph HITL pattern) for `operator-decision` blocks: `approve | edit | reject | respond`.
- Plan template's `operator-decision` now takes `verbs:`, `default:`, `timeout-hours:`.
- Decisions appended as structured records to the plan's `## Operator decision records` section.
- `/recap` surfaces decisions inline in the visual report.
- `/spec` probe-questions.md updated to elicit verbs explicitly during plan capture.

### Added — plan layouts
- **OpenSpec-style folder layout** for plans: `docs/plans/<slug>/{proposal.md, design.md, tasks.md, specs/<scenario>.md}`.
- `templates/plan-folder-template/` scaffolds the four-file shape.
- `state.sh init` detects file vs folder transparently; existing flat plans keep working.
- The adversarial reviewer gets `specs/` files as additional context — execution compared against explicit scenarios.

### Added — MCP distribution
- **`@anvil/gate-mcp`** Node MCP server wrapping `/pre-merge-gate`. Exposes `verify_pr()` to any MCP host (Cursor, Windsurf, ChatGPT desktop, custom agents).
- `mcp-servers/anvil-gate-mcp/` — stdio MCP server, shells out to `scripts/verify.sh`, returns structured verdict.
- `mcp-servers/README.md` — server roadmap (gate now; dispatch/recap/grind later).

### Notes
- Anvil's moat sharpened: only OSS plan→PR framework that's MIT, fully local, rides the open Anthropic skills spec, AND ships MCP-portable artifacts. Distinct from Devin/Cursor BG agents (cloud), Spec-Kit (single-agent), BMAD (persona-pipeline), Symphony (disclaimed by OpenAI).
- Repo at https://github.com/browerthomas/Anvil. Public, MIT.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.2.0

## [0.1.0] — 2026-05-10

Initial Phase 0 release. Inner-loop helpers + visual reporting + cleanup, manually composed.

### Added

- **Skills (live):**
  - `/sweep-worktrees` — bulk-cleanup of stale worktrees + branches; iCloud-friendly via `find -delete`; clears stale git locks.
  - `/self-review` — adversarial diff review using an Opus sub-agent. Codex-fallback for rate-limited or offline scenarios.
  - `/recap` — visual HTML session report drop into `~/.claude/showme/`.

- **Skills (specified, ready for Phase 1+ implementation):**
  - `/dispatch-slice` — codifies the agent prompt template (templates/agent-prompt.md).
  - `/pre-merge-gate` — verification combinator (rebase + tsc + tests + fitness + grep-forbidden).
  - `/auto-merge` — squash-merge + cleanup + sync, in one call.
  - `/spec` — interactive plan capture (templates/probe-questions.md).
  - `/grind` — end-to-end orchestrator (templates/grind-loop.md).

- **Plan format:**
  - `templates/plan-template.md` — canonical plan shape with required sections.
  - `examples/example-plan.md` — worked example (logger-boundary refactor, 7 slices).
  - `examples/hello-world-plan.md` — minimal single-slice plan for verifying install.

- **Tooling:**
  - `bin/preflight.sh` — environment checker (gh auth, git, node, jq, find -delete, codex CLI).
  - `bin/install.sh` — symlink-mode (default) and copy-mode (`--copy`).
  - `bin/uninstall.sh` — removes anvil-installed skills.
  - `shared/lib.sh` — common bash helpers used across skills.

- **Documentation:**
  - `README.md` — overview, quickstart, skill matrix.
  - `docs/architecture.md` — three-layer composition model.
  - `docs/getting-started.md` — longer walkthrough.
  - `CONTRIBUTING.md` — how to extend or add skills.

- **Plugin manifest:** `.claude-plugin/plugin.json` for future marketplace publishing.

### Notes

- Phase 0 is intentionally manual-composition. Phase 1's `/dispatch-slice` + `/pre-merge-gate` + `/auto-merge` will reduce per-PR operator overhead from ~12 manual operations to 3 invocations.
- Real-world test: a 28-PR sprint executed via manual composition produced the implementation patterns these skills codify.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.1.0
