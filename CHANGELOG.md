# Changelog

All notable changes to anvil are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed — docs polish per #3 (Bill's feedback, 2026-05-11)

- README restructure: elevator pitch + "Who it's for" framing up top; Quickstart and Install moved to top; battle-tested dogfood section surfaced (http-client 4/4, arch-standardisation 5/15 in flight); skill glossary rebuilt as plain-English `Skill → What it does` rows (no decorative taglines, names preserved for backwards compatibility); GitHub Pages hosting moved out of README.
- `docs/index.html` polish: decorative `skill-tag-line` strings removed from the skills disclosure; new **Battle-tested** strip with theirownstory PR numbers and counts; entry-tiers section relabelled "Install + entry points" for clarity; hero subtitle tightened to the elevator pitch + Who-it's-for framing; CTA copy "Install" instead of "Pick your entry point"; "Written to the open Agent Skills spec" sub-blurb dropped from the skills section.
- `CONTRIBUTING.md`: GitHub Pages hosting workflow moved here from README.

## [0.4.0] — 2026-05-10

Glue + correction layer. Five new skills closing the manual sequences that surrounded the v0.3 core skills.

### Added — `/findings-rollup`
- After `/self-review --multi-critic` or `/codex-review` returns findings, automatically: file P2/P3 as a single rollup issue with checkboxes, dispatch a fix-up agent against the same PR/branch with the P0/P1 list as its acceptance contract, comment on the PR linking both.
- `scripts/parse-review.sh` extracts the four severity sections from a review markdown.
- `scripts/dispatch-fixup.sh` assembles the fix-up agent prompt with project's `.anvil/dispatch-defaults.txt` appended.
- `templates/rollup-issue.md` is the canonical issue body template.
- Closes the 5-step manual dance every operator runs after every multi-critic review.

### Added — `/issue-to-spec`
- Pre-lock plan validation: take a GitHub issue body, grep the codebase for each factual claim ("X retries on Y", "Z exists at file:line"), output a corrected mini-spec marking which claims were verified, contradicted, or moved.
- Catches the "issue body wrong" class of plan bug at lock-time. Real example: `core/lulu.js — custom retry pattern` in an issue body where the actual code only has 401-token-refresh, no 5xx retry.
- `scripts/verify-issue.sh` extracts factual claims from an issue body as TSV.

### Added — `/refine-plan`
- Mid-grind plan correction. Updates plan files in-place via `Edit`, writes a `plan-revised` event to `.anvil/grind-events.jsonl`, optionally comments on any in-flight PRs whose acceptance contract just moved.
- Closes the manual sequence "Edit plan files → git commit → status update".

### Added — `/config-bootstrap`
- Companion to `bin/init-anvil-config.sh`. Where init writes starter templates with placeholders, `/config-bootstrap` populates them from the project's existing context docs (CLAUDE.md, AGENTS.md, README, post-mortems, audits).
- Extracts forbidden patterns ("DO NOT" / "must not" / "never use" / "deleted in"), dispatch defaults ("always" / "every PR must" / "default to"), and known flakes ("flaky" / "retry once" / "known race").
- `scripts/derive-rules.sh` does the doc-scanning pass.
- One-time-per-project skill but high leverage when adopting anvil on a new repo.

### Added — `/post-merge-debrief`
- Single-PR cleanup + next-slice dispatch in one call: verify-merge + sweep-this-worktree + mark-merged-in-event-log + pull-main + auto-dispatch-next-slice-if-deps-met.
- For when an operator merges outside `/grind` (one-off PR, manual `gh pr merge`, GitHub-UI merge).
- Composes existing scripts; no new helpers.

### Notes
- All five skills surfaced from real friction during the first dogfood (`http-client-standardisation` plan against the TOS pilot project, 2026-05-10). Each closes a manual sequence the operator was running step-by-step.
- Plugin manifest bumped to 0.4.0; skills array now lists 13 skills.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.4.0

## [0.3.0] — 2026-05-10

Resilience + review-quality + plan validation. All three v0.3 roadmap items.

### Added — multi-critic adversarial review
- `/self-review --multi-critic` spawns 4 parallel Opus sub-agents, one per lens:
  - `correctness` (logic bugs, race conditions, edge cases)
  - `security` (auth/authz, injection, CSRF, secrets, sanitization)
  - `test-coverage` (negative cases, weak assertions, bypassed contracts)
  - `architecture` (layer boundaries, vendor SDK boundaries, fitness rules)
- Plus a 5th synthesizer agent that deduplicates findings, re-ranks by severity, identifies cross-critic risk areas, and returns a verdict (`BLOCK | PROCEED-WITH-CAUTION | CLEAN`).
- Per-critic prompts live in `skills/self-review/templates/critics/`; synthesizer prompt at `skills/self-review/templates/synthesizer.md`.
- Each critic stays in its lane (skip findings outside its lens) — prevents redundant double-up coverage.
- Trade-off: 5x agent cost, ~2x catch rate. Recommended for high-stakes diffs (auth, payments, state machines, schema migrations, >500 LoC).

### Added — failure-mode triage (Symphony pattern)
- `/grind` now distinguishes three failure classes:
  - **Slice-fail** → defer this slice + file issue, continue siblings.
  - **Plan-fail** → halt with structured incident report; drain in-flight.
  - **Infra-fail** → skip-this-tick, circuit-breaker backoff (30s → 1m → 5m → 15m), model fallback chain (Opus → Sonnet → file issue).
- Default posture: **defer and continue.** Never halt the whole orchestration when a single slice trips.
- `.anvil/known-flakes.txt` config for retry-once on flake patterns.
- `.github/ISSUE_TEMPLATE/grind-deferral.md` auto-filed when /grind defers a slice; gives operator one-click triage.
- Resilience matrix in `skills/grind/SKILL.md` documents handler per failure type.
- `bin/init-anvil-config.sh` now bootstraps `.anvil/known-flakes.txt` alongside the other config files.

### Added — plan validator
- `skills/spec/scripts/validate.sh` — Spec-Kit `/speckit.analyze` analog. Lints flat or folder plans for completeness + structural integrity:
  1. Goal section present + non-empty
  2. In-scope and Out-of-scope lists populated
  3. Hard constraints non-empty
  4. Slice manifest YAML parses
  5. Slice graph dependency edges resolve (also catches cycles)
  6. Every slice has acceptance criteria
  7. Every operator-decision has `ask` + `verbs` + `default`
- Returns: 0 valid, 1 errors, 2 warnings only. `--strict` treats warnings as errors.
- Operators can add to CI: `validate.sh docs/plans/<plan> --strict || exit 1`.

### Drive-by fixes
- `shared/lib.sh` color prefix had stale `SY_` refs in three skill scripts (verify.sh, merge.sh, new validate.sh). Globbed-replaced to `AV_`.
- awk YAML extraction was leaking the closing ``` fence into the parsed payload. Fixed in all skill scripts.
- `examples/example-plan.md` L5 operator-decision was missing verbs (predates v0.2 ASK-verb landing); validator caught it; updated to current shape.

### Notes
- Anvil is now production-ready for driving real multi-PR work. The combination of plan validator + multi-critic review + failure-mode triage closes the gap to LangGraph + LangSmith for orchestration quality, while staying MIT, fully local, and composable.
- Repo: https://github.com/browerthomas/Anvil. Public, MIT.
- Next: drive a real plan end-to-end. v0.4 priorities sourced from real-world friction.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.3.0

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
  - `/sweep-worktrees` — bulk-cleanup of stale worktrees + branches; cloud-sync-friendly via `find -delete` (handles iCloud / Dropbox / OneDrive / Google Drive evicted files); clears stale git locks.
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
- Real-world test: a multi-PR sprint executed via manual composition produced the implementation patterns these skills codify.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.1.0
