# Tasks — positioning + state-as-product

> The slice manifest. `/grind` parses this block.
>
> **Refined 2026-05-11 post-critic-pass.** 4-critic adversarial review surfaced ~20 actionable findings. Highest-leverage refinements applied: B3 reshaped to `/learn` extension (no new state file); B2 reshaped to `--from` → `--resume` rename (not net-new); D1 uses per-project config + PR-body override; B4 enforces citation resolution + TLDR; C1 adds `.anvil/persona-context.md` rename; C3 acceptance pins isolated `$BATS_TEST_TMPDIR/home`; plugin.json-touching slices flagged `parallelizable: false`; fictional dep edges dropped; honest 2-3 week estimate documented in design.md risk register.

---

## Slice manifest

```yaml
slices:
  # ── Phase A: positioning + copy (5 slices) ─────────────
  - id: A1
    name: Hero rewrite — state-not-chat
    depends-on: []
    files:
      - docs/index.html
    parallelizable: false
    scope: |
      Rewrite the hero section of docs/index.html. Drop the "Forge ideas
      into shipped code" tagline. Lead with the actual pain + the actual
      moat: "Ship large Claude Code tasks without losing state. Anvil
      keeps plans, slice status, reviews, merge gates, and recaps in
      your repo — not buried in chat." Drop the hammer SVG illustration.
      Keep the install CTAs + the existing "Tired of Claude stopping
      mid-sprint?" hook (move it into the new hero structure).
    constraints:
      - The skill name "anvil" stays.
      - No new fonts, no new CDN dependencies.
      - Mobile breakpoints preserved.
    acceptance:
      - "H1 no longer says 'Forge ideas into shipped code'"
      - "Hammer SVG removed from hero"
      - "Hero subtitle contains both 'state' AND 'repo' (case-insensitive grep)"
      - "Mobile screenshot still renders clean"
    operator-decision:
      ask: null
      verbs: []
      default: null

  - id: A2
    name: Strip insider language across landing + README
    depends-on: [A1]
    files:
      - docs/index.html
      - README.md
    parallelizable: false
    scope: |
      Find + replace insider terms across landing + README: "OpenSpec-style"
      → "folder layout for non-trivial plans"; "multi-slice" → "multi-PR
      work" on first occurrence (or explain inline); "ASK verbs" →
      "operator decision points"; "battle-tested" header → "Where it's
      been used"; drop "lay-strike-stamp" three-phase entirely; drop
      "billet" terminology; drop "Strike"/"Quench"/"Forge as verb"/"Anvil
      as verb" decorative metaphor everywhere it surfaces. Audit every
      section + skill description.
    constraints:
      - Skill names stay (no /grind → /run-plan rename).
      - CHANGELOG entries from past releases stay as-is (historical).
    acceptance:
      - "grep -i 'OpenSpec-style\\|ASK verbs\\|lay-strike-stamp\\|billet\\|forge metaphor' on landing + README returns 0 hits"
      - "'multi-slice' only appears with inline explanation on first use"
      - "'Strike'/'Quench' as decorative verbs returns 0 hits in skill descriptions"

  - id: A3
    name: Audience wedge — single primary + 7-day rollback trigger
    depends-on: [A1]
    files:
      - docs/index.html
    parallelizable: false
    scope: |
      Collapse the 4-card audience grid into ONE primary card (solo or
      small-team engineers running multi-PR Claude Code work) + a
      one-line "also useful for" mention of systems/SaaS/OSS. Keep the
      17 review-lens callouts (`/lens systems/*`, `/lens saas/*`,
      `/lens generic/*`) inline somewhere on the page (skill section is
      fine) so the namespace surface still advertises. Add a
      conditional Phase A.5 trigger documented in proposal.md: if
      stars/clones drop >20% vs the prior 7-day baseline by
      2026-06-08, A3 reverts to a 4-audience single-column layout.
    constraints:
      - All 4 original audiences still mentioned somewhere on the page.
      - The 17 review-lens taxonomy stays visible (do not bury it).
    acceptance:
      - "Audience section is one primary card + one inline secondary line"
      - "All 4 original audiences still mentioned somewhere on the page"
      - "17 review-lens callouts retained in the skill section"
      - "Phase A.5 rollback trigger documented in proposal.md"
    operator-decision:
      ask: "Confirm the primary wedge wording + the order of the 3 secondary mentions before merging A3 (the bet without measurement)."
      verbs: [approve, edit, reject]
      default: approve
      timeout-hours: 4

  - id: A4
    name: Drop forge metaphor + decorative imagery
    depends-on: [A1, A2]
    files:
      - docs/index.html
      - skills/persona/SKILL.md
      - skills/grind/SKILL.md
      - skills/recap/SKILL.md
      - skills/learn/SKILL.md
      - skills/spec/SKILL.md
    parallelizable: false
    scope: |
      Remove the forge metaphor from skill descriptions where it's
      decorative. Drop "Three phases. Lay it. Strike it. Stamp it."
      section heading from landing. Drop the "fire" gradient in the
      hero SVG (if SVG kept at all per A1). Touch each skill's
      frontmatter description only — do NOT touch lens content under
      skills/persona/personas/ (that content stays for C1 rename).
    constraints:
      - Skill names stay.
      - "Per-skill SKILL.md frontmatter `name` field unchanged."
      - skills/persona/personas/ content not touched (handled by C1).
    acceptance:
      - "grep -iE 'Strike|Quench|Forge|Anvil-as-verb|billet' on listed skill files returns 0 hits"
      - "Landing reads as 'state infrastructure', not 'forge metaphor'"

  - id: A5
    name: README structural refresh aligned with new positioning
    depends-on: [A2, A3, A4]
    files:
      - README.md
    parallelizable: false
    scope: |
      Rewrite README "Who it's for" + "Status" + "Skills" sections to
      match the new positioning. State-not-chat as the elevator.
      Audience wedge collapsed per A3. Skills table descriptions match
      A4's forge-free updates. Add a one-paragraph "what makes this
      different" section surfacing the durable state model + the
      local-only stance.
    acceptance:
      - "README opens with the state-not-chat framing"
      - "Audience section matches A3's wedge structure"
      - "Skills table descriptions match A4's forge-free updates"
    operator-decision:
      ask: "Drop the entire 'Three phases' / 'Forge metaphor' framing from how anvil is explained, or keep an abbreviated version?"
      verbs: [approve, edit, reject]
      default: approve
      timeout-hours: 4

  # ── Phase B: state-introspection skills (4 slices) ─────
  - id: B1
    name: /anvil-status — text dashboard of plan state
    depends-on: []
    files:
      - skills/anvil-status/SKILL.md
      - skills/anvil-status/scripts/build-status.sh
      - .claude-plugin/plugin.json
    parallelizable: false  # plugin.json-touching slice
    scope: |
      New skill /anvil-status <plan-path>. Reads .anvil/grind-events.jsonl
      + the plan's tasks.md + `gh pr list` for PR state. Emits a text
      dashboard. **Rank order locked**: the first line of output answers
      "what should I think about next?" — format:
        NEXT: <slice-id> (parallel/deps-blocking, N follow-ups)
        IN-FLIGHT: <slice-id> (PR #N, codex-pending/operator-pending)
        BLOCKED: <slice-id> (deps: <list>)
        SHIPPED: <slice-ids> (N slices, +M tests, K follow-ups)
        DEFERRED: <slice-ids>
      Plus: cumulative test delta + open follow-up count. Offline mode:
      if `gh` unauthenticated/missing, GH_OFFLINE=1 fallback reads PR
      linkage from event log only (slice-merged events already record
      PR#). Closes anvil#27.
    constraints:
      - Read-only. No state mutation.
      - Works on both flat plans and folder-layout plans.
      - No new dependencies (uses bash + jq + gh).
      - Output is plain stdout, no terminal cursor control, no
        interactive input — pipeable to `cat`/`tee`.
      - GH_OFFLINE=1 path documented + smoke-tested.
    acceptance:
      - "/anvil-status against a known-good plan prints the dashboard with NEXT: line first"
      - "Smoke test landed: tests/fixtures/folder-plan/ fixture asserts output contains 'NEXT:' as the first non-blank line"
      - "Smoke test: GH_OFFLINE=1 mode parses + emits dashboard without `gh` invocation"
      - "Smoke test: pre-sprint sample-events.jsonl fixture parses + emits sensible output (backward-compat guard)"
      - "Smoke test: blocked-node detection — when a dep's status is failed, that slice appears under BLOCKED with the failing-dep cited"
      - "Smoke test: cumulative test-delta count matches sum of per-slice deltas in event log"
      - "Closes anvil#27"

  - id: B2
    name: /grind --resume — flag rename + auto-resume documentation
    depends-on: [B1]
    files:
      - skills/grind/SKILL.md
      - skills/grind/scripts/state.sh
    parallelizable: false
    scope: |
      **Reshape** (not net-new build): rename existing `/grind --from
      <slice-id>` flag to `/grind --resume <plan-path>` (which
      auto-derives the resume point from the event log's last
      slice-merged event). Existing `--from` becomes deprecated alias
      (warns + still works). Append one `resume` event to
      grind-events.jsonl when --resume fires (for audit).

      Why thin: /grind's state.sh fold + topo-sort already skips
      merged slices on re-invocation. The gap is operator
      discoverability + the auto-derive of plan path. ~80 LoC.
    constraints:
      - "Backward compat — existing `--from <slice-id>` keeps working."
      - resume event is additive to the event log (does not modify
        existing events).
      - "Idempotent — running --resume twice in a row appends 2 resume events but doesn't re-dispatch already-merged slices."
    acceptance:
      - "/grind --resume <plan-path> against a 3-slice plan where slice 1 is merged skips slice 1 + dispatches slice 2"
      - "/grind --from <slice-id> still works (deprecation warning printed; behavior unchanged)"
      - "/grind --resume twice appends 2 resume events but doesn't re-dispatch merged slices"
      - "Smoke test rejects --resume against a plan path that doesn't exist"
      - "Smoke test: concurrent --resume (file lock on grind-events.jsonl) — second invocation prints a warning + exits 0 without dispatching"
      - "Smoke test: plan with one slice marked failed → --resume retries it (failed != merged)"

  - id: B3
    name: /decide — /learn extension with decision-type ergonomics
    depends-on: []
    files:
      - skills/learn/SKILL.md
      - skills/learn/scripts/learn-add.sh
      - skills/learn/scripts/learn-search.sh
    parallelizable: false  # SKILL.md + scripts touched (no plugin.json change — uses existing /learn skill)
    scope: |
      **Reshape** (no new state file): extend /learn with decision
      ergonomics. New flags: `--decision-type <architecture|scope|
      trade-off|reversal|constraint>` + `--affected <slice-id>` (repeatable).
      New subcommand: `/learn decisions` lists rows where `type:decision`
      (a thin filter on existing learn-search.sh). Rows written to
      EXISTING `.anvil/learnings.jsonl` with `type:decision` (already in
      the closed vocabulary). /dispatch-slice's prompt template
      auto-injects "Recent decisions:" section reading rows with
      `type:decision` filtered by `--affected` matching the dispatching
      slice. No new file. No new shape.
    constraints:
      - Same .anvil/learnings.jsonl (per state-as-product spec: no new state).
      - All existing /learn behaviour preserved.
      - --affected accepts comma-separated slice ids OR repeatable flag.
    acceptance:
      - "/learn add --decision-type architecture --affected B1 chose-redis-over-postgres-listen 'retry semantics under worker restart' writes a learnings.jsonl row with type:decision"
      - "/learn decisions lists only type:decision rows"
      - "/learn search redis (without --decision-type) returns the decision (single store; no segregation)"
      - "/dispatch-slice prompt template includes 'Recent decisions:' when /learn decisions returns rows affecting the dispatched slice"
      - "Smoke test: write 3 rows (decision + flake + gotcha); /learn decisions returns 1; /learn search returns all 3"
      - "Smoke test: /dispatch-slice template renders 'Recent decisions:' section when relevant rows exist"

  - id: B4
    name: /recap v2 — structured WHY engine + TLDR + citation resolution
    depends-on: []
    files:
      - skills/recap/SKILL.md
      - skills/recap/scripts/build-recap.sh
      - skills/recap/templates/why-recap.md
    parallelizable: false
    scope: |
      Extend /recap with structured v2 output. Reads grind-events.jsonl
      + plan files + merged-PR diff history. Sub-agent prompt produces:
        1. TLDR (top-of-output, 1 sentence per WHY section — 4 sentences)
        2. What shipped (factual)
        3. What assumptions changed (each cited)
        4. What architectural drift (each cited)
        5. What residual risk (each cited)
      **Pin citation vocabulary**: `path/to/file.ext:N` OR `#PR_NUMBER`
      OR `<commit-sha>` — three forms, used consistently across design,
      tasks, and spec. **Citation resolution test** (load-bearing):
      smoke test asserts each citation in sections 3-5 RESOLVES — for
      `path:N`, file exists + `wc -l path` ≥ N; for `#N`, `gh pr view N`
      exits 0 (or fixture allowlist if offline); for `<sha>`,
      `git cat-file -e <sha>` exits 0. Hallucinated #999 fails the test.
      Output is HTML report + markdown summary pasteable into operator's
      MEMORY.md.
    constraints:
      - Three-form citation vocabulary pinned across design/tasks/spec.
      - HTML output self-contained (no external CDN deps).
      - Citation resolution path supports offline mode (fixture allowlist).
      - TLDR is the first content in the markdown output (operator scans).
    acceptance:
      - "Recap against a 3-slice fixture plan emits TLDR section first + 4 named sections after"
      - "TLDR has exactly 4 sentences (one per WHY section)"
      - "Every line under 'What assumptions changed' / 'What architectural drift' / 'What residual risk' contains a citation matching one of three forms"
      - "Smoke test: hallucinated citation `#9999` against a 5-PR fixture fails the test"
      - "Smoke test: file:line citation against an existing file with too-high line number fails the test"
      - "Smoke test: GH_OFFLINE=1 mode passes citation resolution against a fixture allowlist"
    operator-decision:
      ask: "Recap v2 — confirm 3-form citation vocabulary (file:line, #PR, commit-sha) + TLDR-at-top structure, OR request a strict/permissive toggle."
      verbs: [approve, edit]
      default: approve
      timeout-hours: 4

  # ── Phase C: /persona → /lens hard rename (3 slices) ───
  - id: C1
    name: Rename skills/persona/ → skills/lens/ + .anvil/persona-context.md → .anvil/lens-context.md
    depends-on: [A4]  # A4 frontmatter rewrite must merge BEFORE C1 renames the dir
    files:
      - skills/lens/SKILL.md
      - skills/lens/lenses/
      - skills/lens/scripts/resolve-lens.sh
      - .anvil/lens-context.md  # renamed from .anvil/persona-context.md
      - .claude-plugin/plugin.json
    parallelizable: false  # plugin.json + directory rename
    scope: |
      Hard rename. `git mv skills/persona/ skills/lens/`. Rename
      sub-directory `personas/` to `lenses/`. Rename resolver script
      `resolve-persona.sh` to `resolve-lens.sh`. SKILL.md frontmatter
      `name: persona` → `name: lens`. Update description to use 'review
      lens' vocabulary. Update plugin.json skills array. **Also rename
      .anvil/persona-context.md → .anvil/lens-context.md** (the
      project-context injection file — without this, resolver script
      looks for lens-context but finds nothing). Verify by greping
      anvil's own .anvil/ dir + the operator's repo .anvil/ dir.
    constraints:
      - The {{project_context}} placeholder stays.
      - The 17 lens content files' content unchanged.
      - resolver script API unchanged (resolves bare-name + category/name).
      - .anvil/persona-context.md content preserved in .anvil/lens-context.md.
    acceptance:
      - "skills/persona/ no longer exists"
      - "skills/lens/SKILL.md frontmatter says name: lens"
      - "plugin.json skills array has skills/lens not skills/persona"
      - ".anvil/lens-context.md exists with the prior content of .anvil/persona-context.md (if the source existed)"
      - "bash skills/lens/scripts/resolve-lens.sh systems/sre-incident-responder works"

  - id: C2
    name: Update all internal references — /persona → /lens
    depends-on: [C1]
    files:
      - README.md
      - docs/index.html
      - CHANGELOG.md
      - skills/dispatch-slice/SKILL.md
      - skills/grind/SKILL.md
      - tests/smoke/lenses.bats  # renamed from personas.bats
      - tests/smoke/*.bats
    parallelizable: false
    scope: |
      Find + replace `/persona` → `/lens` across all anvil-internal
      docs + tests. Skill names + description fields say 'review lens'
      consistently. Test file rename: tests/smoke/personas.bats becomes
      tests/smoke/lenses.bats. Update internal test-fixture paths if
      any reference personas/ dir. Update PR body template + operator
      MEMORY-update note: add to PR body a callout
      "Operator action post-merge: re-run bin/install.sh; then
      `grep -l '/persona' ~/.claude/projects/*/memory/MEMORY.md` and
      update references."
    constraints:
      - "CHANGELOG entries from past releases stay as-is (historical)."
      - "CHANGELOG [Unreleased] entry describes the rename."
      - "Battle-tested pill copy locked — 16 skills + 17 review lenses (no stale 17 personas badge)."
    acceptance:
      - "grep -rln '/persona' --include='*.md' --include='*.html' --include='*.bats' OUTSIDE past CHANGELOG entries returns 0 hits"
      - "grep -rln '/lens' shows updated references"
      - "Landing pill copy: '16 skills · 17 review lenses' (not '17 personas')"
      - "PR body includes operator MEMORY.md migration note"

  - id: C3
    name: One-shot migrator for operator's local install
    depends-on: [C2]
    files:
      - bin/migrate-persona-to-lens.sh
      - bin/install.sh
    parallelizable: false
    scope: |
      Ship `bin/migrate-persona-to-lens.sh` that detects an existing
      `~/.claude/skills/persona/` install + removes it. bin/install.sh
      invokes the migrator before installing if it detects the old
      name. **Smoke test pins isolated HOME** — uses
      $BATS_TEST_TMPDIR/home (or equivalent) — MUST NOT touch operator's
      real $HOME/.claude/. Migrator idempotent. Detects symlink-mode +
      copy-mode installs. Local modifications → warns + skips by
      default; --force overrides.
    constraints:
      - "Migrator is idempotent (running twice is a no-op)."
      - "Migrator detects symlink-mode + copy-mode installs."
      - "Local modifications to old /persona dir → warns + skips by default."
      - "Smoke test runs against isolated HOME (BATS_TEST_TMPDIR or equivalent). MUST NOT mutate the operator's real ~/.claude/ during testing."
    acceptance:
      - "Migrator detects + removes ~/.claude/skills/persona/ (isolated test)"
      - "bin/install.sh post-migrate puts skills/lens/ in place"
      - "Smoke test under $BATS_TEST_TMPDIR/home: pre-seed isolated_home/.claude/skills/persona/, run HOME=isolated_home bin/install.sh, assert persona/ gone + lens/ exists"
      - "Smoke test does NOT touch $HOME/.claude/ (assert by checking real $HOME/.claude before + after — must be byte-identical)"
    operator-decision:
      ask: "Confirm: hard rename is destructive to operator's local install. Run bin/install.sh after this PR merges to migrate."
      verbs: [approve]
      default: approve
      timeout-hours: 24

  # ── Phase D: quality fences + backlog rollup (5 slices) ─
  - id: D1
    name: Pre-merge leak-grep — per-project config + CI hook + override
    depends-on: []
    files:
      - bin/check-leaks.sh
      - .anvil/check-leaks.patterns.example.txt
      - .github/workflows/leak-check.yml
    parallelizable: false
    scope: |
      bin/check-leaks.sh reads patterns from `.anvil/check-leaks.patterns.txt`
      (per-project, gitignored by default — each project commits or
      doesn't at its discretion). Anvil's own repo ships
      `.anvil/check-leaks.patterns.example.txt` as the template.
      Hardcoded patterns (always checked, no config needed): stale
      conflict markers `^<<<<<<<`, `^=======`, `^>>>>>>>`. Per-project
      patterns: substring + filepath-pattern shape, one per line, e.g.
      `theirownstory :: **/*` or `\\bTOS\\b :: **/*.md :: !skills/lens/lenses/systems/vendor-tos-auditor.md`.
      PR-body override: workflow grep-greps for `[leak-allow: <reason>]`
      in PR body; presence soft-passes with a warning posted as a PR
      comment. Workflow fails-closed if jq or grep crashes.
    constraints:
      - "Default missing config = soft-pass with one-line warning (don't block fresh installs)."
      - "Allowlist shape — `<substring-or-regex> :: <path-glob> :: <exclusion-glob>`."
      - "Past CHANGELOG entries (date-prefixed) auto-excluded."
      - "Workflow fail-closed on script crash."
    acceptance:
      - "bash bin/check-leaks.sh on current main exits 0 (with example patterns file present)"
      - "Adding 'theirownstory' to a tracked file fails the check (with anvil's own patterns)"
      - "Missing .anvil/check-leaks.patterns.txt = soft-pass with warning"
      - "PR-body `[leak-allow: legit reference to project X]` soft-passes with a PR comment"
      - "Workflow crash (e.g., jq missing) = fail-closed (PR blocked, operator gets a clear error message)"
      - "CI workflow added; runs on every PR + push to main"

  - id: D2
    name: Smoke-test extension to new/extended skills (B1-B4)
    depends-on: [B1, B2, B3, B4]
    files:
      - tests/smoke/anvil-status.bats
      - tests/smoke/grind-resume.bats
      - tests/smoke/learn-decisions.bats
      - tests/smoke/recap-v2.bats
      - tests/fixtures/folder-plan/
      - tests/fixtures/sample-events.jsonl
    parallelizable: false
    scope: |
      For each new or extended skill (B1 + B2 + B3 + B4), add a bats
      file. Each B-slice ships its OWN smoke test in the same PR — D2
      is the aggregation + backward-compat regression slice. D2 adds:
        - Backward-compat regression test using
          tests/fixtures/sample-events.jsonl (pre-sprint event types
          only) — assert /anvil-status + /grind --resume parse it.
        - Cross-skill: assert /learn decisions + /recap v2 together
          produce the dispatch-slice prompt scaffold.
      Coverage target: each skill has ≥5 enumerated tests (specific
      cases listed in each B-slice's acceptance bullets, not deferred).
    acceptance:
      - "tests/smoke/ has 4 new files matching the 4 new/extended skills"
      - "make smoke includes the new files + passes"
      - "Backward-compat regression: sample-events.jsonl fixture parses + both skills emit expected output"

  - id: D3
    name: Close anvil#24 — four-way skill-count consistency
    depends-on: [D1]
    files:
      - tests/smoke/skill-structure.bats
    parallelizable: false
    scope: |
      Extend tests/smoke/skill-structure.bats with four-way consistency:
        1. count(README skill mentions) == count(landing skill mentions)
        2. count(both) == `jq '.skills | length' .claude-plugin/plugin.json`
        3. Every entry in plugin.json.skills resolves to existing skills/<name>/SKILL.md
        4. Every `skills/*/SKILL.md` is referenced in plugin.json (no orphan dirs)
      Pin selectors: README uses `(\\d+)\\s+skills\\b` regex; landing
      uses a data-skill-count HTML attribute (or equivalent stable hook
      added in this slice). Catches the drift class shipped today.
    acceptance:
      - "Test asserts all 4 consistency rules"
      - "Pinned selector: data-skill-count attribute on landing OR documented regex anchor"
      - "Closes anvil#24"

  - id: D4
    name: Close anvil#28 — /followup-rollup
    depends-on: [D1]
    files:
      - skills/followup-rollup/SKILL.md
      - skills/followup-rollup/scripts/build-rollup.sh
      - .claude-plugin/plugin.json
    parallelizable: false  # plugin.json-touching
    scope: |
      /followup-rollup <plan-path> walks open issues with title prefix
      `[<plan>-<slice> followup]`, groups by severity (P0/P1/P2/P3) +
      area (test-coverage / correctness / architecture / operability),
      suggests which slice should consume each. Output: markdown rollup.
    constraints:
      - "Title prefix `[<plan>-<slice> followup]` must be enforced by /findings-rollup (audit if not — if missing, this slice fails gracefully + the operator gets a one-liner explaining the gap)."
    acceptance:
      - "Skill exists + is invocable"
      - "Smoke test enumerates: (a) zero issues, (b) one per slice, (c) issues without prefix excluded, (d) severity grouping, (e) area grouping"
      - "Closes anvil#28"

  - id: D5
    name: Close anvil#29 + #30 — plan-health gate (non-blocking) + /learn-promote
    depends-on: [B1]
    files:
      - skills/plan-health/SKILL.md
      - skills/plan-health/scripts/check-health.sh
      - skills/learn/scripts/learn-promote.sh
      - skills/grind/SKILL.md  # add step h.5 hook
      - .claude-plugin/plugin.json
    parallelizable: false  # plugin.json-touching
    scope: |
      Two skills.

      /plan-health <plan-path>: computes a per-slice metric
      (open-follow-ups-filed-this-slice / follow-ups-closed-this-slice).
      Flags if filing > closing × 1.5 for 3 consecutive slices. Auto-
      invoked from /grind step h.5. **Non-blocking** — appends a
      `plan-health-degraded` event to grind-events.jsonl + comments
      on the most-recent open PR with the metric snapshot. Never pauses
      /grind dispatch. Closes anvil#29.

      /learn-promote --since <date>: drafts a markdown chunk of
      high-confidence /learn entries pasteable into the operator's
      MEMORY.md. Closes anvil#30.
    constraints:
      - /plan-health is non-blocking. No operator override needed
        because it never blocks.
      - "The metric is per-plan, sliding-3-slice window. Filed-this-slice = issues opened between this slice's slice-dispatched + slice-merged events. Closed-this-slice = issues closed in the same window."
    acceptance:
      - "Both skills exist + invocable"
      - "/grind step h.5 auto-invokes /plan-health post-merge (smoke-test confirms event appended + PR comment posted; /grind dispatch not paused)"
      - "Smoke test: 3-slice fixture where filing > closing × 1.5 → flag fires (PR comment posted); 3-slice fixture where ratio is in band → no flag"
      - "/learn-promote --since 2026-05-01 emits markdown for paste"
      - "Closes anvil#29 + anvil#30"

  # ── Phase E: release wrap (1 slice) ────────────────────
  - id: E1
    name: Version bump to v0.6.0 + breaking-change-led CHANGELOG
    depends-on: [A5, B4, C3, D1, D2, D3, D4, D5]
    files:
      - .claude-plugin/plugin.json
      - groups/*/plugin.json
      - CHANGELOG.md
      - README.md
    parallelizable: false
    scope: |
      Bump version to 0.6.0 across plugin.json + group manifests.
      Consolidate CHANGELOG [Unreleased] entries into a v0.6.0 release
      block. **CHANGELOG entry leads with a `### BREAKING — /persona → /lens`
      section** explaining the rename + bin/install.sh migration step
      + the operator MEMORY.md grep to run. Release notes summarise
      the sprint.
    constraints:
      - Past CHANGELOG entries untouched.
      - Version bump matches semver (additive features for B/D, single
        breaking change for C — /persona → /lens rename — flagged
        explicitly at top of release block).
      - First section under [v0.6.0] is the BREAKING callout.
    acceptance:
      - "plugin.json version = 0.6.0"
      - "CHANGELOG has a v0.6.0 release block with BREAKING section first"
      - "BREAKING section explains: re-run bin/install.sh; grep ~/.claude/projects/*/memory/MEMORY.md for /persona; update to /lens"
      - "README status line matches 0.6.0"
      - "Full smoke suite passes (`make smoke` exits 0)"
    operator-decision:
      ask: "Version: bump to v0.6.0 (current trajectory) OR re-tag as v1.0.0-rc1 to signal confidence + cut perceived churn ahead of GitHub-discoverability push?"
      verbs: [approve, edit]
      default: approve
      timeout-hours: 4
```

---

## Validation checklist

- [x] proposal.md has goal + 15 success criteria
- [x] design.md has 5 architecture decisions
- [x] design.md hard constraints non-empty (11 constraints)
- [x] Every slice has acceptance criteria
- [x] Slice graph has no cycles (A1→A2→A4→C1; A1→A3; A1→A4; A2→A4; A2+A3+A4→A5; B1→B2; B1→D5; D1→D3+D4; A5+B4+C3+D1+D2+D3+D4+D5→E1)
- [x] Every dependency edge resolves (B4→B1 fictional edge dropped; D5→B1 kept for plan-health UX; A4→C1 added)
- [x] Every operator-decision point has ask + default
- [x] All plugin.json-touching slices flagged `parallelizable: false`
- [x] B4 citation vocabulary pinned to one form (file:line OR #PR OR sha)
- [x] B4 citation resolution test enforced (not just shape)
- [x] C3 acceptance pins isolated $BATS_TEST_TMPDIR/home (not just spec)
- [x] D1 uses per-project `.anvil/check-leaks.patterns.txt` config + PR-body override
- [x] B3 reshape: /learn extension, no new state file
- [x] B2 reshape: --from rename, ~80 LoC not 600+
- [x] C1 includes `.anvil/persona-context.md` → `.anvil/lens-context.md` rename
- [x] D5 plan-health explicit non-blocking spec
- [x] E1 depends-on includes D1+D3+D4 (was missing)
- [x] Per-skill test cases enumerated in acceptance bullets (not deferred)
- [x] Out-of-scope items explained in proposal.md
- [x] At least one spec scenario for the highest-risk slices (under specs/)

When all checked: change proposal.md Status to `locked` and run `/grind <this-folder>`.
