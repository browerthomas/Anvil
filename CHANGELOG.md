# Changelog

All notable changes to anvil are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — v0.2 work in progress

### Added
- **Composable plugin groups** — anvil now ships as three groups (`anvil-core`, `anvil-pr`, `anvil-orchestrator`) with per-group plugin manifests under `groups/`. `install.sh --group <name>` installs just one. The top-level manifest stays as the meta-bundle that installs all 8 skills.
- `groups/README.md` documenting the three-layer composition model.

### v0.2 roadmap
- Append-only event log for `.anvil/grind-state.json` + optional Langfuse adapter.
- Structured ASK verbs (LangGraph HITL pattern) for operator decision points.
- OpenSpec change-folder plan layout (`<slug>/{proposal.md, specs/, design.md, tasks.md}`).
- MCP-ize `/pre-merge-gate` so Cursor + Windsurf + ChatGPT desktop can call the same gate.

See [ROADMAP.md](ROADMAP.md) for full v0.2+ priorities.

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
