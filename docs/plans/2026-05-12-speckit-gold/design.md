# speckit-gold — design

> Locked architecture decisions for the five additive features. Each decision is small but load-bearing — wrong call here = churn across the slice surface.

---

## Architecture decisions

### Decision: Constitution is a NEW file alongside existing config, not a rename

- **What:** `.anvil/constitution.md` is added as a new file. Existing `forbidden-patterns.txt` + `dispatch-defaults.txt` + `known-flakes.txt` keep their current shape and semantics. The constitution carries strategic ethos ("we never break the DB without a migration", "user data > everything"); the existing files keep their mechanical roles (grep patterns / dispatch boilerplate / flake retry rules).
- **Why:** A rename would break every adopting project's `.anvil/` config silently. Additive lands clean; the constitution slot is *new*, not a re-purposing.
- **Rejected alternatives:**
  - Merge all four files into one constitution.md — too much shape collapse; pattern files want to stay greppable.
  - Constitution as a section header inside dispatch-defaults.txt — same churn cost as rename, less clarity.

### Decision: Template resolver is bash, lives in `shared/lib.sh`, three layers only

- **What:** `av_resolve_template <name>` searches in fixed order: `${PWD}/.anvil/templates/overrides/<name>` → `${HOME}/.anvil/presets/templates/<name>` → `${ANVIL_HOME}/templates/<name>`. First hit wins. `ANVIL_HOME` defaults to anvil's install root; preset layer is optional (no error if missing).
- **Why:** Three layers cover the real cases — project, user, system — without the cognitive overhead of speckit's 4-level (extensions add a fourth that anvil doesn't have an ecosystem for yet). Bash keeps zero deps. `shared/lib.sh` is already sourced by every skill.
- **Rejected alternatives:**
  - Node helper — adds dep for a 6-line function.
  - 4-layer like speckit — premature; anvil has no extension ecosystem.
  - Single-layer override — too coarse for users who want a global preset across multiple projects.

### Decision: Per-slice checklists are inline YAML in tasks.md, not a separate file

- **What:** Each slice in the YAML manifest gets a new `checklist:` field — a list of items where each item is either `{kind: shell, run: "<cmd>", expect: pass}` or `{kind: grep, pattern: "<regex>", in: "<glob>", expect: absent|present, count?: N}`. `/pre-merge-gate` reads the plan, finds the slice by branch name (or `--slice <id>` arg), and runs each item.
- **Why:** Inline keeps the plan self-contained — operator reviewing the plan sees the gates without dereferencing. The two `kind:` values cover ~95% of real checks (run a script; assert a pattern is/isn't there). Anything more elaborate stays in the global fitness ratchet.
- **Rejected alternatives:**
  - Free-form shell strings — no structure for grep/shell distinction, harder to fail with a useful message.
  - Separate `.checklist.yml` file per slice — adds a second file to keep in sync.
  - YAML-only declarative DSL — fancy but premature.

### Decision: `/clarify` writes a markdown transcript, `/spec` reads it optionally

- **What:** `/clarify "<intent>"` runs sequential `AskUserQuestion` rounds, writes a markdown file at `docs/plans/.clarify/<YYYY-MM-DD>-<slug>.md` containing `## Question` / `## Answer` pairs plus a `## Derived facts` synthesis. `/spec --clarify-file <path>` pre-populates its draft from the transcript and skips re-asking covered questions.
- **Why:** Markdown is grep-friendly + diffs cleanly + can be committed with the plan. Optional consumption keeps `/spec` backward-compatible.
- **Rejected alternatives:**
  - JSON transcript — harder to read, no benefit since `/spec` is the only consumer.
  - Inline into `/spec` (no separate skill) — defeats the whole point of separating interrogation from specification.
  - Database-backed Q&A log — gross over-engineering for a markdown-first tool.

### Decision: `/analyze-plan` greps factual claims; doesn't try semantic understanding

- **What:** `/analyze-plan <plan-path>` extracts every claim that looks like a fact (regex-matched file paths, function names, "N lines", "M slices", quoted identifiers) and verifies each against current code (file exists, grep finds, count matches). Reports verified / contradicted / unverifiable per claim. Does NOT try to understand prose intent.
- **Why:** Grepping is fast, deterministic, and explainable. Semantic claim verification is research-grade and would 10× the skill complexity. Anvil already has `/issue-to-spec` doing essentially this for issue bodies — `/analyze-plan` is the generalisation.
- **Rejected alternatives:**
  - LLM-based claim verification — slow, expensive, non-deterministic.
  - Test-execution gate — already covered by `/pre-merge-gate`.
  - Skip entirely (rely on adversarial review in `/spec`) — adversarial review catches scoping mistakes, not factual drift over time.

---

## Hard constraints

The orchestrator passes these to every agent dispatched for this plan:

- **Public-facing OSS:** anvil is a public repo. No project-private refs (theirownstory, BookGen, agoku64, customer codenames). Brief every dispatched agent that this is a public-facing repo.
- **Backward-compatible:** every change is additive. No existing `.anvil/` file is renamed or repurposed. Existing skills keep working with their existing file paths.
- **No new runtime deps:** bash + the existing helpers in `shared/lib.sh` only. No Node modules, no Python venvs.
- **Smoke-tested:** every new surface (constitution prepend, template resolver, checklist runner, clarify transcript, analyze-plan grep) needs at least one test under `tests/` that exercises it end-to-end with a fixture.
- **CHANGELOG + ROADMAP:** every shipped slice updates `CHANGELOG.md` under the next minor version; the final slice ticks `ROADMAP.md`.
- **Test target:** existing tests stay green; `bash tests/run.sh` is the smoke entrypoint.
- **No skill renames:** all five new surfaces are additive skill files. Don't refactor existing skill names or descriptions.

---

## Cross-slice coordination

- **Shared file:** `shared/lib.sh` is touched by S1 (constitution loader) and S2 (template resolver). S2 lands first; S1 rebases against S2 to avoid lib.sh conflict.
- **Shared file:** `skills/spec/SKILL.md` is touched by S2 (use resolver), S3 (prompt for checklist), and S4 (consume clarify file). Serialise S2 → S3 → S4 to avoid rebase churn.
- **Shared file:** `templates/plan-folder-template/tasks.md` is touched by S3 only.
- **Shared file:** `skills/pre-merge-gate/SKILL.md` is touched by S3 only.
- **Shared file:** `skills/grind/SKILL.md` is touched by S5 only.
- **Shared file:** `skills/config-bootstrap/SKILL.md` is touched by S1 only.
- **Shared file:** `skills/dispatch-slice/SKILL.md` is touched by S1 only.
- **Constitution-template path:** S1 owns `templates/constitution-template.md`; S2's resolver discovers it under `${ANVIL_HOME}/templates/`. S1 must place the template at that exact path so S2's resolver test passes.

---

## Dependencies on external surfaces

- **GitHub CLI (`gh`):** existing dep. Used by `pre-merge-gate` already; this plan doesn't add a new use.
- **`bats` test framework:** existing dep. New smoke tests use the existing `tests/run.sh` shape.
- **No vendor APIs touched.**

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Three slices touch `skills/spec/SKILL.md` → rebase churn | high | low | Serialise S2 → S3 → S4 in the dependency graph; each rebases against the prior. |
| Constitution prepend bloats every dispatched-agent prompt → cost regression | low | med | Cap constitution.md at a documented size (~2KB recommended); `dispatch-slice` warns if larger. |
| `/analyze-plan` regex flags too many false positives → operator ignores it | med | med | Conservative regex set (file paths with `/`, identifiers in backticks, numbers with units); explicit "unverifiable" verdict over a false-positive "contradicted". |
| Per-slice checklist YAML structure invites bikeshedding | low | low | Lock to two `kind:` values (`shell`, `grep`) in S3; resist new kinds without an open issue first. |
| Clarify transcript drifts from final plan if operator edits plan but not transcript | med | low | `/spec --clarify-file` records transcript path in plan's `proposal.md` for traceability; operator owns the drift. |
