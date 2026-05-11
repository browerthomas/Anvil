# Design — positioning + state-as-product

> Architecture decisions, hard constraints, risks. The adversarial reviewer compares each slice's implementation against this file.

---

## Architecture decisions

### Decision: State infrastructure is the product, not the commands

- **What:** every user-facing surface — hero, README, skill descriptions — leads with anvil's role as state infrastructure. Commands are the access path; the durable repo-native state (plan files + grind-events.jsonl + worktrees) is what's being sold.
- **Why:** critic-read concluded the moat is the state model, not the prompts. Prompts can be copied in a weekend; durable resumable workflow state is the hard problem. The current positioning sells "yet another agent-skills suite," which is a crowded category.
- **Rejected alternatives:**
  - Positioning around "the Claude Code orchestrator" — generic; doesn't differentiate.
  - Positioning around "AI coding assistant" — wrong category entirely; we'd lose to bigger players.

### Decision: Hard rename `/persona` → `/lens`

- **What:** `skills/persona/` directory + `SKILL.md` frontmatter + all references rename to `lens`. Maintainer rebuilds their local install (`bin/install.sh`) post-merge.
- **Why:** "review lens" reads as professional. "Persona" reads as cosplay. The renamed skill is otherwise unchanged (still wraps `/self-review` with a hard-coded prefix; still has 17 sub-files under `lenses/saas/`, `lenses/systems/`, `lenses/generic/`). Slow drift via aliasing wastes the rename moment.
- **Rejected alternatives:**
  - Alias only (`/lens` → `/persona`): two names for one thing, drift accumulates.
  - Soft deprecation over multiple releases: anvil is pre-v1.0; rename now is cheap.

### Decision: New skills surface existing state — `/decide` is `/learn` with decision-type ergonomics

- **What:** the 4 new state-introspection touches (`/anvil-status`, `/grind --resume`, `/decide`, recap engine v2) all operate on the EXISTING state model. `/anvil-status` reads grind-events.jsonl + plan files + gh PR state. `/grind --resume` reads grind-events.jsonl. `/decide` is implemented as a `/learn` subcommand+flag set (`/learn decisions add/search/list`) writing to the SAME `.anvil/learnings.jsonl` with `type: decision` rows — no new file, no new shape. Recap v2 reads everything; writes a recap HTML output artifact, not state.
- **Why:** the state-as-product spec is load-bearing on "no new state surfaces." Adding `.anvil/decisions.jsonl` as a separate file violates the spec on its face — the decision shape is structurally identical to `/learn`'s gotcha/invariant/migration-shape shape. Extending `/learn` with a decision sub-vocabulary + a `--affected <slice-id>` flag costs ~50 LoC and zero new state.
- **Rejected alternatives:**
  - Separate `.anvil/decisions.jsonl` file: dilutes the moat (architecture critic P0-2). Both files would have identical shape; the split is taxonomic, not functional.
  - Add a SQLite-backed state store: introduces a binary state format that breaks the "repo-native" promise.
  - Re-architect `/grind` to use a graph DB: massive scope, no proven need.

### Decision: B2 reshape — `/grind --resume` is a rename of the existing `--from` flag

- **What:** B2 ships as a thin reshape of the existing `/grind --from <slice-id>` flag → `/grind --resume <plan-path>`. The current `--from` already skips merged slices (via state.sh fold). B2 adds: (a) the `--resume` flag accepts a plan path (not just a slice id) and auto-derives the resume point from the event log's last `slice-merged`, (b) a `resume` event is appended for audit, (c) `--from` becomes a deprecated alias (warns + still works), (d) one smoke test covering the auto-derive path. Net: ~80 LoC, not a feature build from scratch.
- **Why:** the architecture critic (P0-1) caught that `/grind`'s topo-sort already resumes from event-log state on re-invocation. Building a 600-LoC resume system would duplicate state.sh's fold + the topo-sort. The actual gap is operator-discoverability: `--from` is hidden in `/grind`'s SKILL.md and operators have to know it exists.
- **Rejected alternatives:**
  - Net-new `/resume` skill: more skill-surface for the same outcome; doesn't compose with `/grind`.
  - Drop B2 entirely: loses the operator-discoverability win.

### Decision: Pre-merge leak grep is a CI gate with per-project config + PR-body override

- **What:** `bin/check-leaks.sh` reads a per-project patterns file at `.anvil/check-leaks.patterns.txt` (forbidden substrings + regex, gitignored by default — each project commits or doesn't at its discretion). Anvil's own repo ships `.anvil/check-leaks.patterns.example.txt` as a template. The script always catches stale conflict markers (`^<<<<<<<` / `^=======` / `^>>>>>>>`) without project config. PR-body override: an operator can add `[leak-allow: <reason>]` to the PR body to soft-pass with a warning posted as a PR comment. Workflow itself fails-closed if jq or grep crashes.
- **Why:** anvil is OSS — hardcoding the maintainer's project codenames in the public script is both a privacy leak (third-party reading sees the maintainer's projects) AND useless to third parties. Per-project config is the only model that works across adopters. The PR-body override unblocks legit references (e.g. discussing a project codename in a leak post-mortem).
- **Rejected alternatives:**
  - Hardcoded regex list: only works for the maintainer (architecture critic P0-3 + operator critic P0-3).
  - Pre-commit hook only: only catches the developer's local copy, doesn't catch agents.
  - Soft warning everywhere: critics said "merging fast catches issues post-merge" today; warnings get ignored.

### Decision: Recap engine v2 — structured prompt + TLDR + citation resolution

- **What:** `/recap v2` reads grind-events.jsonl + plan files + the merged-PR diff history. Output structure is fixed:
  1. **TLDR** — 1 sentence per WHY section (4 sentences total). At top of output. Operator scan-reads this.
  2. **What shipped** — concrete, factual.
  3. **What assumptions changed** — each cited with `file:line` or PR `#N` or commit `<sha>` (one canonical citation vocabulary — pin this everywhere).
  4. **What architectural drift** — same citation rule.
  5. **What residual risk** — same citation rule.

  **Citation resolution test:** the smoke test asserts every claim in sections 3-5 has a citation AND each citation RESOLVES — for `path:N`, the file exists + `wc -l path` ≥ N; for `#N`, `gh pr view N` returns 0 (or fixture allowlist if offline); for `<sha>`, `git cat-file -e <sha>` returns 0. A hallucinated `#999` fails the test.
- **Why:** unstructured "recap" prompts produce generic summaries. Structured prompting forces the WHY. TLDR layer is required because operators scan recaps; the structured WHY without a TLDR ships value nobody reads (operator critic P1-4). Citation resolution closes the hallucinated-source loophole (test-coverage critic P0-3 + correctness critic P0-4).
- **Rejected alternatives:**
  - Keep v1 (just-what-shipped HTML): doesn't address the WHY point.
  - Free-form 3-form citation (file:line OR sha OR PR#) without resolution: shape test passes hallucinated cites.
  - Multi-agent recap (separate sub-agents per section + synthesizer): 5x cost; the value isn't there for a recap.

---

## Hard constraints

- **No project-private references in any committed file.** Maintainer's main project, internal codenames, named individuals (outside maintainer's own attribution) are all forbidden. Enforced by `bin/check-leaks.sh`.
- **No stale conflict markers.** Same script catches them.
- **Repo-native forever.** No new SaaS dependency, no GitHub App, no proprietary state format. All state on local disk in repo-readable formats (markdown, jsonl, yaml, json).
- **Backward compat for `/grind` event log format.** Existing `.anvil/grind-events.jsonl` files must continue to parse after the sprint. New event types are additive.
- **No new env vars outside `core/config.js` equivalent.** Anvil doesn't have a config module per se; the env-var-discipline rule from TOS doesn't apply directly, but we should still avoid scattered `process.env` reads.
- **Smoke-test suite stays green throughout.** Every slice that adds a skill also adds its smoke test in the same PR.
- **No `--no-verify` on push.** All anvil PRs run `bash tests/install.test.sh` + `make smoke` pre-push starting this sprint.
- **No emojis in committed code.** Existing rule.
- **No comments unless WHY is non-obvious.** Existing rule.
- **Default model: Opus.** Default through 2026-06-07 per operator memory.
- **PR template fully filled** on every PR.
- **`anvil status` works without git history walking.** Read `.anvil/grind-events.jsonl` + plan files + `gh` API for PR state. No `git log --all --grep`.

---

## Cross-slice coordination

- **Shared file: `.anvil/grind-events.jsonl`.** B1 (`/anvil-status`) reads it. B2 (`/grind --resume`) reads it + appends one `resume` event for audit. Existing writers (`/grind` proper) stay unchanged.
- **Shared file: `.anvil/learnings.jsonl`.** B3 (`/decide` as `/learn` decision-extension) writes `type: decision` rows here — same file, same shape. Other skills read it (specifically `/dispatch-slice` injects rows with `type: decision` into slice agent prompts when relevant slice-affected match).
- **Plugin manifest: `.claude-plugin/plugin.json`.** C1 + B1 + B3 + D4 + D5 all add entries to the skills array. **All plugin.json-touching slices are flagged `parallelizable: false`** to enforce sequential merge. Order: B1 → B3 → C1 → D4 → D5 (alphabetical by slice id within shared-file conflict group).
- **README + landing.** A1-A5 all touch both. Sequential within Phase A. **A4 frontmatter rewrite must merge BEFORE C1 directory rename** (added depends-on edge); otherwise A4's glob picks up the renamed `skills/lens/SKILL.md` mid-edit.
- **`bin/check-leaks.sh`.** D1 ships it WITH `.anvil/check-leaks.patterns.txt` config (per-project, not hardcoded — see decision above); A1-A5 + B1-B4 + C1-C3 are the FIRST PRs gated by it. Each must pass it pre-merge. PR-body override `[leak-allow: <reason>]` supported for legit references.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `/persona` → `/lens` rename breaks operator's local install before they re-run `bin/install.sh` | high | medium | C3 ships a one-shot migrator that the operator runs locally; maintainer acknowledges break-during-cutover. |
| Recap engine v2 produces hallucinated WHY claims (model invents architectural drift that didn't happen) | medium | high | Structured prompt requires every WHY claim to cite a file:line or commit SHA from the diff history. Tests pin the citation requirement. |
| `/grind --resume` corrupts grind-events.jsonl when replaying mid-event | low | high | Replay is read-only on the existing file; emits a new resume-event marking the resume boundary. Idempotency tests cover replay correctness. |
| Pre-merge leak grep produces false positives (legit references to "tos" inside vendor-tos-auditor lens name) | medium | low | Allowlist file `bin/check-leaks.allowlist.txt` for known-safe substrings (e.g. `vendor-tos-auditor`). |
| Stripping forge metaphor breaks brand recognition / user familiarity | low | low | "anvil" name stays. Only decorative imagery + "forge"/"billet"/"strike" verbs go. The framework still feels like itself. |
| New skill cluster (B1-B4) lands without smoke-test coverage, regresses silently later | high | medium | Hard constraint: every B-slice ships its smoke test in the same PR. D2's expansion + the existing `make smoke` CI gate enforce. Per-skill test cases are enumerated in tasks.md acceptance bullets (not deferred to slice-agent judgment). |
| The sprint takes 2x estimate + delays TOS arch-standardisation resumption | high | high | **Honest estimate: 12-16 calendar-days (~2-3 weeks)**, not the original "1 week." Per-phase: Phase A 1.5-2d (5 sequential slices on shared landing.html); Phase B 3-5d (B2/B3 reshape to smaller scope, but B1+B4 still substantial); Phase C 1.5-2d; Phase D 3-4d; Phase E ~1d; plus 2-3d slack for codex retros + ASKs. Operator decision: pause TOS at 9/16 for ~2-3 weeks vs ship anvil-quality work that compounds across remaining TOS slices + every future grind. |
| Phase A positioning bet (A3 wedge collapse) lands wrong + adoption funnel drops | medium | high | A3 acceptance adds a 7-day post-merge rollback trigger: if stars/clones drop >20% vs prior 7-day baseline by 2026-06-08, A3 reverts to a 4-audience single-column layout (no metaphor return, just structural). Phase A.5 follow-up slice scheduled as conditional. |
| `/plan-health` gate (D5) behaviour ambiguous — blocks vs warns | medium | low | D5 spec pins: **non-blocking** — appends event to grind-events.jsonl + comments on most-recent open PR with the metric snapshot + does not pause /grind dispatch. Operator override is not needed because the gate never blocks. |
