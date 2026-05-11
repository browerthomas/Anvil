# Changelog

All notable changes to anvil are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed — `/persona` → `/lens` hard rename (2026-05-11)

- The skill formerly known as `/persona` is now `/lens`. C1 (PR #44) renamed `skills/persona/` → `skills/lens/` and `.anvil/persona-context.md` → `.anvil/lens-context.md`. C2 (PR #46) sweeps the remaining internal text references — README + landing + this CHANGELOG's [Unreleased] block + dispatch-slice / grind composition notes + test fixtures.
- "Review lens" vocabulary is consistent across all anvil-internal docs. The 17 role files under `skills/lens/lenses/{systems,saas,generic}/` are referred to as **lenses**, not personas. Bare-name lookup + the `oncall-3am` → `systems/sre-incident-responder` shim still work.
- Landing-page badge copy: `19 skills · 17 review lenses` (was `16 skills · 17 adversarial personas`). Skill count is the real current value (19, post-D5).
- **Operator action post-merge:** re-run `bin/install.sh` (auto-invokes the migrator that removes any stale `~/.claude/skills/persona/` install). Then `grep -l '/persona' ~/.claude/projects/*/memory/MEMORY.md` and rewrite operator memory references to `/lens`.
- Past CHANGELOG entries (date-prefixed semver blocks below) preserve `/persona` as historical wording — that's the language used at the time they shipped. The [Unreleased] block is updated to current `/lens` terminology because it describes the next-release surface area.

### Added — `/plan-health` + `/learn-promote` close the cleanup-debt observability gap (D5, anvil#29 + anvil#30)

- Two skills shipped together. Both operate against existing `.anvil/grind-events.jsonl` + `.anvil/learnings.jsonl` state — no new state surfaces.
- **`/plan-health <plan-path>`** computes a per-plan follow-up filing-vs-closing ratio over the most recent 3 merged slices. Flags when filing > closing × 1.5 for 3 consecutive slices. **Non-blocking by contract** — when the gate fires it appends one `plan-health-degraded` event to `.anvil/grind-events.jsonl` + posts a metric snapshot comment on the most-recent open PR. Never pauses `/grind` dispatch. Operator override is not needed because the gate never blocks.
- The metric is per-plan, sliding-3-slice window. Filed-this-slice = issues whose `issue-filed` event sits between this slice's `slice-in-flight` and `slice-merged` timestamps. Closed-this-slice = the subset of those issues whose `gh` close timestamp falls before this slice's `slice-merged` event.
- Insufficient-data branches don't flag: fewer than 3 merged slices, total filed across the window is zero, or `GH_OFFLINE=1` (close ratios unknowable).
- Auto-invoked by `/grind` step h.5 (the half-step between h "sync + log" and step 4 "periodic check-in"). Wired in `skills/grind/SKILL.md` procedure section. Failure modes (gh rate-limited, no PR derivable, plan-health crash) caught + logged; `/grind` continues unaffected.
- **`/learn-promote --since <date> [--min-confidence <conf>]`** drafts a MEMORY.md-pasteable markdown chunk of high-confidence learnings recorded since a given date. Defaults to `--min-confidence high` (sister `/learn export` defaults to medium); decisions appear FIRST in the output (most-durable type-order); each entry emits a Pasteable bullet line shaped to match operator MEMORY.md style.
- Smoke tests in `tests/smoke/plan-health.bats` (14 cases) + `tests/smoke/learn-promote.bats` (16 cases). Cover: gate fires on 3 degraded slices, gate does NOT fire when one slice is healthy, < 3 merged slices = insufficient, vacuous (zero filed) = no flag, `--dry-run` snapshot path, GH_OFFLINE skip, /grind step h.5 documentation pin, decisions-first ordering, --min-confidence widening, --type filter, affected-slice surfaced for decisions.
- Skill count bumps 18 → 19. Four-way consistency test from D3 enforces the bump propagates to README + landing badge + skills disclosure summary + plugin.json.
- Closes anvil#29 + anvil#30. Slice D5 of `docs/plans/2026-05-11-positioning-and-state-product/`.

### Added — `/followup-rollup` consolidates open follow-up issues for a plan (D4, anvil#28)

- New skill `/followup-rollup <plan-path>` walks open issues whose title carries the `[<plan>-<slice> followup]` prefix, groups by severity (P0/P1/P2/P3) + area (test-coverage / correctness / architecture / operability), suggests which slice should consume each cluster. Output: markdown rollup pasteable into a planning doc. Read-only — no state mutation, no issues touched.
- **Severity derivation**: label (`p0`/`p1`/`p2`/`p3`, case-insensitive) > title token (`[P0]`/`[P1]`/`[P2]`/`[P3]`) > body marker (`**Severity:** Pn`) > `P3` fallback.
- **Area derivation**: label (`test-coverage`/`correctness`/`architecture`/`operability`) > title-keyword heuristic (e.g. `test|coverage|flaky` → test-coverage; `bug|broken|race` → correctness; `refactor|coupling|layer` → architecture; `log|metric|observability` → operability) > `correctness` fallback.
- **Title-prefix-enforcement gap audit**: as of 2026-05-11, the `[<plan>-<slice> followup]` title prefix is NOT enforced by `/findings-rollup` (which uses `[<severity>/<category-rollup>] <slug> review followups (#<pr>)` format) or `/grind` (template only — `file_followup()` is pseudocode). The skill **fails gracefully** when zero matching issues are found: emits a friendly "no follow-ups" placeholder + a one-liner explaining the gap so the operator can decide whether to retrofit the prefix into the upstream filing path.
- **Offline support**: `--fixture <path>` flag accepts a local JSON file (matching `gh issue list --json title,number,labels,body` shape) for testing + air-gapped runs; `GH_OFFLINE=1` short-circuits to the empty placeholder without invoking `gh`.
- Composes with `/anvil-status` (which says how many follow-ups are open) — this skill says which + groups them.
- Smoke tests in `tests/smoke/followup-rollup.bats` cover (a) zero matching issues + gap note, (b) one-per-slice grouping, (c) prefix-less issues excluded, (d) severity grouping across all four derivation routes, (e) area grouping across label + heuristic routes, plus flat-plan + `GH_OFFLINE=1` edge cases.
- Closes anvil#28. Slice D4 of `docs/plans/2026-05-11-positioning-and-state-product/`.

### Changed — `docs/index.html` maturation pass (2026-05-11)

- Critic-read feedback from the maintainer's 2026-05-11 dogfood pass surfaced seven landing-page gaps. Single PR covers all seven.
- **One-liner install** above the existing 3-tier quickstart tabs — single `git clone … && install.sh` row labelled "Just run this" for visitors who want one paste-and-go command. The 3-tier panel (single skill / inner loop / full orchestration) is preserved below for operators who want the explicit version.
- **Copy buttons on all four terminal blocks** (one-liner + tier 1 / 2 / 3). ~15 lines of vanilla JS; click pulls `.cmd` text content out of the target terminal, joins with newlines, copies via `navigator.clipboard.writeText()`, flashes "Copied!" for 1.5s.
- **Hero copy tightened** — merged the two stacked `.hero-sub` paragraphs into one crisp elevator + one italic differentiator line. Dropped the "Built for solo developers" sentence (that framing moves into the new "Who it's for" callout).
- **Smoke-test + CI credibility badges** under the hero CTAs: `100+ tests · CI on every push` (links to `.github/workflows/smoke-test.yml`), `17 skills · 17 review lenses`, `Vanilla GitHub · no SaaS, no GitHub App`.
- **New "Who it's for" section** between hero and entry-tiers, audience grid of four cards — systems engineers, software engineers, SaaS operators, OSS maintainers. Expands the framing past the original solo-developer-SaaS-shaped audience to reflect anvil#20's lens namespacing.
- **Lens namespacing surfaced** as a callout block inside the skills section: 17 lenses across `systems/` (8) / `saas/` (6) / `generic/` (3) listed explicitly. Closes the gap where the landing claimed 17 lenses in a badge but never showed the namespace structure.
- **Lens examples balanced** — `/lens systems/*`, `/lens saas/*`, `/lens systems/open-source-maintainer` lead with systems-coded callouts so the SaaS bias from earlier copy is visibly broken.
- Mobile breakpoints extended for the new sections (audience grid collapses to 1col, copy button compresses, oneliner padding tightens).
- No new fonts, no new CDN dependencies, no analytics/tracking, no project-private references.

### Changed — `/lens` namespaced into `saas/` / `systems/` / `generic/`; 7 new systems lenses added

- Anvil's real audience is systems + software engineers, not just SaaS operators. The original 10 lenses leaned SaaS-coded (Stripe references, customer-support framing, AI-product exposé framing). The skill now namespaces lenses into three categories so systems-engineering work has first-class lenses too.
- **`systems/`** — eight lenses covering kernel development (memory safety, locking, ABI), SRE incident response (renamed from `oncall-3am`), embedded engineering (WCET, ISR safety), distributed systems (consensus, idempotency, retries), performance engineering (hot paths, allocation, syscall overhead), compiler/build engineering (hermeticity, reproducibility), OSS maintainership (PR triage, ABI stability), and architecture review (boundaries, coupling, dependency direction).
- **`saas/`** — six existing lenses moved unchanged: `privacy-lawyer`, `payment-risk`, `angry-customer`, `competitor-recon`, `end-user`, `journalist`.
- **`generic/`** — three lenses genericized to drop SaaS-coded language so they work across both categories: `security-researcher` (broadened beyond web-stack vulnerabilities), `new-engineer` (already generic), `vendor-tos-auditor` (broadened from LLM/API focus to cover any external dependency: libraries, compilers, runtimes, cloud, package licenses + AUPs).
- **New helper:** `skills/lens/scripts/resolve-lens.sh` resolves a lens name (bare or `category/<name>`) to its prompt body. Handles bare-name cross-category lookup, ambiguity errors, and the `oncall-3am` → `systems/sre-incident-responder` backward-compat shim.
- **Backward compat:** existing `/lens privacy-lawyer "..."` invocations from operator memory still work — the resolver looks across categories when given a bare name. The legacy `oncall-3am` name resolves to `systems/sre-incident-responder` and prints a one-line deprecation notice; the rename will be enforced in a future release.
- Lens count: 10 → 17 (7 net-new in `systems/`; the eighth systems lens is the `oncall-3am` rename).
- Motivation: dogfood feedback during the 2026-05-11 self-critique pass flagged the SaaS lean as a barrier to adoption among systems engineers. Namespacing was the minimum-change fix that preserves the existing prompts while opening room for systems-coded lenses.

### Fixed — install reliability (#19, 2026-05-11)

- **`bin/install.sh` now writes `~/.claude/anvil-config.sh`** exporting `ANVIL_ROOT` so skill scripts can locate `shared/lib.sh` post-install. Previously, scripts in `~/.claude/skills/<name>/scripts/` resolved `ANVIL_ROOT` to `~/.claude` (three levels up from the script location) — but `shared/lib.sh` only exists in the anvil checkout, so every script broke at runtime with `shared/lib.sh: No such file or directory`. Surfaced at dogfood time.
- **All 14 scripts that source `shared/lib.sh`** (13 in `skills/*/scripts/`, 1 in `bin/init-anvil-config.sh`) now resolve `ANVIL_ROOT` via a four-tier chain: (1) existing env var, (2) `<install-root>/anvil-config.sh` resolved relative to the script (works post-install regardless of `--prefix`), (3) `$ANVIL_HOME` / `$CLAUDE_HOME` / `$HOME/.claude` honoured `anvil-config.sh`, (4) relative-path fallback for in-checkout dev mode. Backward-compatible: scripts still work when invoked from the anvil checkout without any install step.
- **`bin/preflight.sh` extended** with a post-install verification section. After install, preflight syntax-checks every installed skill script (`bash -n`) and smoke-tests `shared/lib.sh` resolution by invoking each script with no args and inspecting stderr for the resolution-failure signature. New summary header: `Skills installed: N` + `Skill scripts: M of N passed`. New flags: `--prefix <dir>`, `--skills-only`, `--no-skills`. Backwards-compatible — `preflight.sh` alone still runs the original tool/version/auth checks.
- **`bin/install.sh` auto-invokes `bin/preflight.sh`** at the end of a successful install. Operators find skill breakage now, not at first `/grind`. Pass `--no-preflight` to skip (used by `tests/install.test.sh`).
- **`bin/uninstall.sh` removes `~/.claude/anvil-config.sh`** in addition to skill symlinks/copies. Also gains `--prefix <dir>` for symmetry.
- **`tests/install.test.sh`** added — first end-to-end test in the framework. Installs into a temp HOME via `--prefix`, verifies `anvil-config.sh` lands with the right `ANVIL_ROOT`, every skill script syntax-checks, three representative scripts resolve `shared/lib.sh` cleanly in both copy and symlink modes, preflight exits 0, and uninstall removes the config. `bash tests/install.test.sh` is now the recommended pre-PR check (added to README).

### Added — bats smoke-test suite for all 16 skills (2026-05-11)

- `tests/smoke/` — bats-based smoke-test suite covering all 16 skills + the install / preflight scripts. ~100 tests across 17 files. Catches the obvious-regression class (script blows up on argument parser, SKILL.md drops its frontmatter, lens file leaks a project-private reference, markdown bash block has unbalanced quotes).
- Per-skill coverage: `/learn` (14 tests across 5 scripts), `/dispatch-slice`, `/config-bootstrap`, `/findings-rollup`, `/spec`, `/grind` (9 tests across state-machine subcommands), `/dual-review`, `/auto-merge`, `/pre-merge-gate`, `/issue-to-spec`. Markdown-only skills (`/recap`, `/refine-plan`, `/self-review`, `/post-merge-debrief`, `/sweep-worktrees`) covered by `markdown-syntax.bats` — every fenced bash block must `bash -n` after placeholder substitution.
- Cross-cutting tests: every lens file has the `{{project_context}}` placeholder + no project-private leaks; every SKILL.md has YAML frontmatter with a `name:` matching its directory; every script under `skills/*/scripts/` and `bin/` passes `bash -n`.
- `tests/test_helper.bash` — shared `setup_fresh_repo` + `setup_fresh_repo_with_seed_learnings` + `extract_md_bash_blocks` helpers. Idempotent setup so a test can call its own re-setup mid-flight without `git init` collisions.
- `tests/Makefile` — `make smoke` target. Single-file mode via `make smoke FILE=learn.bats`.
- `.github/workflows/smoke-test.yml` — CI runs the suite on every push to `main` and every PR. Ubuntu, `apt install bats jq`, `make -C tests smoke`.
- `tests/README.md` — covers run instructions, the helper API, how to add a new test, common failure modes.

### Changed — docs polish per #3 (2026-05-11)

- README restructure: elevator pitch + "Who it's for" framing up top; Quickstart and Install moved to top; battle-tested dogfood section surfaced (described abstractly); skill glossary rebuilt as plain-English `Skill → What it does` rows (no decorative taglines, names preserved for backwards compatibility); GitHub Pages hosting moved out of README.
- `docs/index.html` polish: decorative `skill-tag-line` strings removed from the skills disclosure; new **Battle-tested** strip describing recent dogfood grinds; entry-tiers section relabelled "Install + entry points" for clarity; hero subtitle tightened to the elevator pitch + Who-it's-for framing; CTA copy "Install" instead of "Pick your entry point"; "Written to the open Agent Skills spec" sub-blurb dropped from the skills section.
- `CONTRIBUTING.md`: GitHub Pages hosting workflow moved here from README.

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
