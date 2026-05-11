# Changelog

All notable changes to anvil are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [v0.6.0] - 2026-05-11

**Sprint summary.** 18 slices shipped across Phases A (positioning + copy), B (state-introspection skills), C (`/persona` → `/lens` hard rename), D (quality fences + backlog rollup), and E (release wrap) — full plan at `docs/plans/2026-05-11-positioning-and-state-product/`. Anvil now leads with **state-as-product** positioning (plans, slice status, reviews, merge gates, and recaps live in the repo, not the conversation). Four new state-introspection capabilities ship: `/anvil-status` (read-only rank-ordered dashboard), `/grind --resume` (auto-derive resume point from event log; `--from` deprecated alias kept), `/decide` (as a `/learn` extension with `--decision-type` + `--affected` flags — no new state file), and `/recap v2` (TLDR + 4-section WHY engine with three-form citation resolution). Plus: `/persona` → `/lens` hard rename with one-shot operator migrator, a pre-merge / CI leak-grep gate (`bin/check-leaks.sh` + per-project `.anvil/check-leaks.patterns.txt`), `/followup-rollup`, `/plan-health`, `/learn-promote`, and the chronic `install.bats` worker flake closed at root.

### BREAKING — `/persona` → `/lens` rename

- The skill formerly named `/persona` is now `/lens`. C1 renamed `skills/persona/` → `skills/lens/`, `skills/persona/personas/` → `skills/lens/lenses/`, `resolve-persona.sh` → `resolve-lens.sh`, the SKILL.md frontmatter `name: persona` → `name: lens`, the plugin.json skills array entry, and `.anvil/persona-context.md` → `.anvil/lens-context.md`. C2 swept the remaining internal text references (README, landing, dispatch-slice / grind composition notes, test fixtures, test-file rename `tests/smoke/personas.bats` → `tests/smoke/lenses.bats`).
- "Review lens" vocabulary is consistent across all anvil-internal docs. The 17 role files under `skills/lens/lenses/{systems,saas,generic}/` are referred to as **lenses**, not personas. Bare-name lookup + the `oncall-3am` → `systems/sre-incident-responder` shim still work.
- **Operator action post-merge:**
  1. Re-run `bin/install.sh`. It auto-invokes `bin/migrate-persona-to-lens.sh`, which detects an existing `~/.claude/skills/persona/` install (symlink-mode or copy-mode) and removes it before installing the new `~/.claude/skills/lens/`. Local modifications under the old dir → migrator warns + skips by default; pass `--force` to override.
  2. Then grep operator memory for stale references and rewrite to `/lens`:
     ```bash
     grep -l '/persona' ~/.claude/projects/*/memory/MEMORY.md
     # for each match, rewrite occurrences of `/persona` → `/lens`.
     ```
- Past CHANGELOG entries (date-prefixed semver blocks below) preserve `/persona` as historical wording — that's the language used at the time they shipped.

### Added

- **`/anvil-status <plan-path>`** (B1, closes anvil#27). New read-only skill emitting a rank-ordered text dashboard of a plan's state. First line answers "what should I think about next?" — `NEXT:` → `IN-FLIGHT:` → `BLOCKED:` → `SHIPPED:` → `DEFERRED:` — plus cumulative test delta and open follow-up count. Folds `.anvil/grind-events.jsonl` + the plan's `tasks.md` + `gh pr list`. Offline mode: `GH_OFFLINE=1` reads PR linkage from the event log only.
- **`/decide` via `/learn` extension** (B3). `/learn` gains `--decision-type <architecture|scope|trade-off|reversal|constraint>` + `--affected <slice-id>` (repeatable) flags. New subcommand `/learn decisions` lists rows where `type:decision`. Rows live in the existing `.anvil/learnings.jsonl` — no new state file. `/dispatch-slice`'s prompt template auto-injects a "Recent decisions:" section reading rows filtered by `--affected` matching the dispatching slice. Closed `type` vocabulary (already includes `decision`) preserved.
- **`/recap v2`** (B4). Extends `/recap` with structured WHY output. Reads `grind-events.jsonl` + plan files + merged-PR diff history; sub-agent produces a TLDR section (1 sentence per WHY section, 4 sentences total) plus four named sections: What shipped (factual), What assumptions changed, What architectural drift, What residual risk. **Three-form citation vocabulary pinned** across design / tasks / spec: `path/to/file.ext:N` OR `#PR_NUMBER` OR `<commit-sha>`. **Citation resolution test** (load-bearing): each citation in WHY sections must resolve — `path:N` requires file exists + `wc -l path` ≥ N; `#N` requires `gh pr view N` exits 0 (or fixture allowlist if `GH_OFFLINE=1`); `<sha>` requires `git cat-file -e <sha>` exits 0. Hallucinated `#9999` fails the test. Output is HTML report + markdown summary pasteable into operator's MEMORY.md.
- **`/followup-rollup <plan-path>`** (D4, closes anvil#28). New skill walks open issues with title prefix `[<plan>-<slice> followup]`, groups by severity (P0/P1/P2/P3) + area (test-coverage / correctness / architecture / operability), suggests which slice should consume each cluster. Severity derivation chain: label > title token > body marker > `P3` fallback. Area derivation chain: label > title-keyword heuristic > `correctness` fallback. Title-prefix-enforcement gap audited + skill fails gracefully when zero matching issues are found (the upstream `/findings-rollup` + `/grind` filing paths don't enforce the prefix yet; the skill emits a one-liner explaining the gap so the operator can decide whether to retrofit). Offline support via `--fixture <path>` + `GH_OFFLINE=1`.
- **`/plan-health <plan-path>`** (D5, closes anvil#29). Non-blocking gate that computes per-plan follow-up filing-vs-closing ratio over the most recent 3 merged slices. Flags when filing > closing × 1.5 for 3 consecutive slices. When the gate fires it appends one `plan-health-degraded` event to `.anvil/grind-events.jsonl` + posts a metric snapshot comment on the most-recent open PR — **never pauses `/grind` dispatch**. Auto-invoked by `/grind` step h.5. Insufficient-data branches (< 3 merged slices, total filed = 0, or `GH_OFFLINE=1`) don't flag.
- **`/learn-promote --since <date> [--min-confidence <conf>]`** (D5, closes anvil#30). Drafts a MEMORY.md-pasteable markdown chunk of high-confidence learnings recorded since a given date. Defaults to `--min-confidence high` (`/learn export` keeps `medium`). Decisions appear FIRST in the output (most-durable type-order); each entry emits a Pasteable bullet shaped to match operator MEMORY.md style.
- **Pre-merge leak gate** (D1). `bin/check-leaks.sh` scans tracked files for forbidden patterns from per-project `.anvil/check-leaks.patterns.txt` (gitignored or committed at the project's discretion; anvil ships `.anvil/check-leaks.patterns.example.txt` as a template). Pattern shape: `<substring-or-regex> :: <path-glob> :: <exclusion-glob>`. Hardcoded conflict-marker checks (`^<<<<<<<`, `^=======`, `^>>>>>>>`) always run. Default missing config = soft-pass with one-line warning. PR-body override: workflow grep-greps for `[leak-allow: <reason>]` in PR body; presence soft-passes with a warning comment. `.github/workflows/leak-check.yml` runs the gate on every PR + push to main; fails-closed on script crash.
- **Smoke-test extension** (D2). New bats files: `tests/smoke/anvil-status.bats`, `tests/smoke/grind-resume.bats`, `tests/smoke/learn-decisions.bats`, `tests/smoke/recap-v2.bats`. Backward-compat regression test uses `tests/fixtures/sample-events.jsonl` (pre-sprint event types only) to assert `/anvil-status` + `/grind --resume` parse it. Coverage target met: each new/extended skill has ≥5 enumerated tests.
- **Four-way skill-count consistency test** (D3, closes anvil#24). `tests/smoke/skill-structure.bats` extended with four-way consistency: count(README skill mentions) == count(landing skill mentions) == `jq '.skills | length' .claude-plugin/plugin.json`; every entry in `plugin.json.skills` resolves to an existing `skills/<name>/SKILL.md`; every `skills/*/SKILL.md` is referenced in `plugin.json` (no orphan dirs). Pinned selectors: README uses `(\d+)\s+skills\b` regex; landing uses a `data-skill-count` HTML attribute.
- **One-shot migrator** (C3). `bin/migrate-persona-to-lens.sh` detects an existing `~/.claude/skills/persona/` install (symlink-mode or copy-mode) and removes it. `bin/install.sh` invokes the migrator before installing if it detects the old name. Idempotent. Local modifications → warns + skips by default; `--force` overrides. Smoke test pins isolated `$BATS_TEST_TMPDIR/home` — never touches the operator's real `~/.claude/`.

### Changed

- **Positioning shift to state-as-product** (Phase A, 5 slices). Hero on `docs/index.html` rewrites from "Forge ideas into shipped code" to "Ship large Claude Code tasks without losing state. Anvil keeps plans, slice status, reviews, merge gates, and recaps in your repo — not buried in chat." Hammer SVG dropped. Audience grid collapsed to one primary card (solo or small-team engineers running multi-PR Claude Code work) + one inline secondary line; all 4 original audiences still mentioned somewhere on the page; the 17 review-lens callouts (`/lens systems/*`, `/lens saas/*`, `/lens generic/*`) retained in the skill section. Forge metaphor stripped from skill descriptions where decorative. Insider language swept: `OpenSpec-style` → `folder layout for non-trivial plans`; `multi-slice` only used with inline explanation on first use; `ASK verbs` → `operator decision points`; `battle-tested` header → `Where it's been used`; `lay-strike-stamp` three-phase framing dropped; `billet` / `Strike` / `Quench` as decorative verbs dropped. README restructure aligned with new positioning: state-not-chat as the elevator; "What makes this different" paragraph surfacing the durable state model + local-only stance.
- **`/grind --resume <plan-path>` flag rename** (B2). Existing `/grind --from <slice-id>` flag renamed to `/grind --resume <plan-path>` (auto-derives the resume point from the event log's last `slice-merged` event). `--from` becomes a deprecated alias (warns + still works — backward-compat preserved). Appends one `resume` event to `grind-events.jsonl` when `--resume` fires (for audit). Idempotent: running `--resume` twice in a row appends 2 resume events but doesn't re-dispatch merged slices. Concurrent invocations hold a file lock on `grind-events.jsonl`; second invocation prints a warning + exits 0 without dispatching. Reshape (not net-new build): ~80 LoC.
- **README structural refresh** (A5). Opens with the state-not-chat framing. Audience section collapsed per A3. Skills table descriptions match A4's forge-free updates. New "What makes this different" paragraph surfaces the durable state model + the local-only stance.
- **Landing pill copy locked** at `19 skills · 17 review lenses` (was `16 skills · 17 adversarial personas`). Four-way consistency test from D3 enforces the bump propagates to README + landing badge + skills disclosure summary + plugin.json.

### Fixed

- **Chronic `install.bats` worker-crash flake** root-caused + closed (was the leading source of pre-push false-fails). Smoke suite's `make smoke` exits 0 across full bats runs.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.6.0...HEAD
[v0.6.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.6.0

## [0.5.0] — 2026-05-11

Cross-model agreement signal. One new skill that wraps the two existing adversarial reviewers.

### Added — `/dual-review`
- Runs `/self-review` (Claude) and `/codex-review` (Codex) in **parallel** as background sub-agents, then synthesizes both findings lists into a single table with a `Source` column: `Both` / `Claude only` / `Codex only`.
- Cross-model agreement (`Both`) is the strongest signal in adversarial review — two different model families flagging the same line is almost certainly real. Disagreements (one-only) are blind-spot complements.
- `--multi-critic` mode escalates the Claude leg to 4 parallel critics + synthesizer (so 6 agents total: 4 Claude critics + 1 Codex review + 1 dual-review synthesizer). Use on the highest-stakes diffs.
- `--no-codex` degrades to Claude-only when the operator has reason to skip codex.
- Same arg shape as `/self-review` and `/codex-review`: PR number, branch, SHA, or no-arg (uncommitted).
- Codex fallback: if codex is rate-limited or fails mid-run, the synthesis step is dropped, the Claude leg's output stands alone, and a banner makes the degraded signal visible (`⚠ Codex unavailable; this run is Claude-only — strictly weaker signal`).
- Saves the merged transcript under `.codex-log/<timestamp>-dual-review.md` (same paper-trail directory as the underlying skills).
- Composes with `/findings-rollup` for P2/P3 + fix-up dispatch.
- `scripts/capture-diff.sh` handles diff extraction, 4000-line size cap, and codex-availability probe.
- `templates/synthesizer.md` is the canonical prompt for the synthesis sub-agent.

### Why
- Source: gstack research (`research/gstack-comparison-2026-05-11.md`). gstack's `/autoplan` runs both reviewers by default and synthesizes — anvil treated them as alternatives. `/dual-review` closes that gap without breaking the existing skills (both remain invocable standalone).
- Closes [#4](https://github.com/browerthomas/Anvil/issues/4).

### Notes
- `/self-review` and `/codex-review` are unchanged. `/dual-review` is a new top-level skill that wraps them.
- Plugin manifest bumped to 0.5.0; skills array now lists 14 skills.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.5.0

## [0.5.0] — 2026-05-11

Per-project memory. One new skill closing the "chronic flake gets rediscovered every 2-3 sprints" gap surfaced by the gstack research pass (2026-05-11).

### Added — `/learn`
- Append-only `.anvil/learnings.jsonl` per-project log. One JSON object per line: `{key, type, insight, confidence, source_skill, files, tags, slice_id, prior_count, timestamp}`.
- Subcommands: `/learn add` (append), `/learn search` (substring + filter + rank by confidence × recurrence), `/learn prune` (archive entries older than cutoff, with `--keep-confidence` to preserve high-confidence invariants), `/learn summary` (last 20 grouped by type), `/learn export` (paste-ready MEMORY.md-compatible markdown chunk).
- Closed `type` vocabulary: `flake | gotcha | invariant | decision | cost | perf | migration-shape`. Future skills filter by type.
- Dedup-by-key: re-adding the same key appends a new line with `prior_count` incremented; `/learn search` surfaces re-confirmation count. Default 60s idempotency window for auto-emit callers.
- Soft-fail by default — auto-emit hooks must not block the parent skill. Pass `--strict` to opt out (use in tests).
- Helper scripts: `scripts/learn-add.sh`, `scripts/learn-search.sh`, `scripts/learn-prune.sh`, `scripts/learn-summary.sh`, `scripts/learn-export.sh`.
- Inspired by gstack's `learnings.jsonl` pattern documented in `research/gstack-comparison-2026-05-11.md`. Closes issue #5.

### Added — auto-emit hooks in existing skills
- `/pre-merge-gate` — when a flake retry-passes a pattern in `.anvil/known-flakes.txt`, emits a `flake` learning with the test signature.
- `/findings-rollup` — when a multi-critic review consolidates ≥3 P1s, emits a `gotcha` learning capturing the cross-cutting theme.
- `/auto-merge` — when a merge involved a non-trivial rebase (>0 commits), emits a `migration-shape` learning. Confidence is `low` per occurrence; the dedup-by-key + `prior_count` mechanism converts repeated occurrences into a high-signal entry over time.
- `/dispatch-slice` — when worktree creation or deps install fails, emits a `gotcha` learning with the failure mode + slice ID so the next dispatcher sees prior history.

### Drive-by changes
- `bin/init-anvil-config.sh` now bootstraps an empty `learnings.jsonl` and adds the file (plus `grind-events.jsonl`, `grind-snapshot.json`, `learnings.archive.jsonl`) to the per-project `.gitignore`. The `.anvil/README.md` table updated to list the two new files.
- `bin/install.sh` group hint for `--group core` mentions `/learn search`.
- Plugin manifest bumped to `0.5.0`; top-level skills array now lists 14 skills. `learn` joins `anvil-core` (it's a standalone primitive). All three group manifests bumped to `0.5.0` for consistency.
- README.md status line now says "Fourteen skills"; the Primitives table gains a `/learn` row; the Configuration table lists `.anvil/learnings.jsonl` + `.anvil/grind-events.jsonl`; the layer ASCII swaps `/codex-review` (compositional dep, not anvil-shipped) for `/learn`.

### Privacy
- `.anvil/learnings.jsonl` is **default-gitignored** because it can hold project-specific gotchas, test names, and file paths. Operators who want to commit it can `git add -f .anvil/learnings.jsonl`.

[Unreleased]: https://github.com/browerthomas/Anvil/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/browerthomas/Anvil/releases/tag/v0.5.0

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
- All five skills surfaced from real friction during the first dogfood (`http-client-standardisation` plan, 2026-05-10). Each closes a manual sequence the operator was running step-by-step.
- Plugin manifest bumped to 0.4.0; skills array now lists 13 skills.

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
