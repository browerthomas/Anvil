# gstack vs anvil — what's gold in those hills

**Date:** 2026-05-11
**Repo studied:** gstack (MIT, ~1419 PRs deep, very active)
**Purpose of this doc:** decide what to steal for anvil.

---

## Bottom line

**The name is misleading.** "gstack" is not a stacked-PR tool. It's a **role-stack orchestrator** — 23 opinionated Claude Code skills that play CEO / designer / eng-manager / release-engineer / QA-lead / security-officer for a single developer. It is the closest published peer to anvil's own design space, but with a different center of gravity: anvil is **plan→PR mechanics for multi-slice work**; gstack is **review-rich quality gating for single features**.

That said, several patterns are directly stealable. The three biggest:

1. **Adversarial dual-voice review** (Claude subagent + Codex run in parallel, voices stay separate until synthesis) — anvil currently does Claude-only `/self-review` and Codex-only `/codex-review` as parallel options. Merging them into one `/dual-review` that runs both and produces a side-by-side findings table would close the most obvious quality gap.
2. **Append-only `learnings.jsonl` per project** — anvil has `.anvil/grind-events.jsonl` but it's an *event log*, not a *learnings log*. A second JSONL keyed by `(insight_key, timestamp)` with confidence scores would let anvil surface "we've seen this flake before, here's the fix" without the operator's MEMORY.md being the only path.
3. **The "User Challenge" gate at plan-approval time** — `/autoplan` separates auto-decidable choices from "both models think your stated direction is wrong; explicit override required." Anvil's `/spec` currently treats all probes as conversational; encoding "user challenge" as a distinct gate type would catch operator scope-creep at lock-time, not mid-grind.

**On the original premise — does gstack solve stacked-PR rebase friction?** No. Its `/ship` skill uses a *merge-base sync* strategy (not rebase), creates one PR at a time, and has no dependency-graph or stacked-PR primitives. Worktrees are mentioned only as a side-effect of Conductor (an unrelated Anthropic tool for parallel sessions) and `lib/worktree.ts` is a file-locking helper, not a stacked-PR coordinator. **The gold is in the review and learning patterns, not the PR mechanics.**

---

## Per-feature comparison

| Pattern | anvil has it | gstack has it | Notes |
|---|---|---|---|
| Multi-slice plan with dependency graph | YES (`/spec` + plan YAML with `depends-on`) | NO — single-feature focus | anvil is ahead here. Don't regress. |
| Slice dispatch in fresh worktrees | YES (`/dispatch-slice`) | NO — single session, no worktree dispatch | anvil is ahead. |
| Multi-critic review per PR | YES (`/codex-review` OR `/self-review`) | YES (`/review` + `/codex` run together by default in `/autoplan`) | gstack runs both as default and synthesizes; anvil treats them as alternatives. **Steal the synthesis pattern.** |
| Append-only learning log per project | NO (we have `MEMORY.md` per project; not structured) | YES (`learnings.jsonl` with confidence scores, search, prune) | **Steal this.** |
| Plan-approval gate with "user challenge" distinct from "taste decision" | NO (everything is conversational in `/spec`) | YES (auto-decide vs taste vs user-challenge are three explicit categories) | **Steal this.** |
| Pre-merge gate (CI + ratchets + forbidden patterns) | YES (`/pre-merge-gate`) | Partial (`/ship` runs tests + audit but no fitness-ratchet concept) | anvil is ahead. The fitness-ratchet idea is anvil-native; gstack has no equivalent. |
| Squash-merge + worktree cleanup combinator | YES (`/auto-merge` + `/post-merge-debrief`) | NO — `/ship` ends at "PR opened" | anvil is ahead. |
| Stacked-PR semantics, force-push hygiene, sync-on-parent-merge | NO (we live the manual dance) | NO (uses merge-base sync, not rebase; no stacked-PR concept) | **Neither has it.** Need to look elsewhere (Graphite CLI `gt`, sapling, or build it). |
| Adversarial persona library | Partial (10 personas in `reference_review_personas.md` — read-only memory) | YES (built into `/cso`, `/codex challenge`, `/plan-*-review` skills) | gstack has more, baked in. **Steal: turn anvil personas from memory-doc into actual invocable skills.** |
| Skill registry / router | Implicit (each skill knows its own trigger) | Explicit (`hosts/index.ts` + intent→skill table in CLAUDE.md) | gstack's table-driven router is cleaner. Minor steal. |
| GitHub layer (PR create, base detection, idempotency) | Implicit (each skill shells `gh` directly) | Explicit (Step 0 platform detection + idempotency check: "if PR exists, update body") | **Steal the idempotency check** — anvil currently re-opens duplicate PRs in edge cases. |
| Token-budget guardrail on prompts | NO | YES (160KB / ~40K token warn threshold on SKILL.md generation) | Possibly worth stealing for our larger skills like `/grind`. |
| Continuous-checkpoint mode (auto-commit WIP, squash before push) | NO | YES (opt-in `WIP:` prefix, squashed by `/ship`) | Probably **don't steal** — anvil's grind discipline (commit only when slice is green) is intentional. |
| Conductor / parallel sessions | Anvil dispatches subagents in one session | gstack defers to Anthropic's Conductor (external tool) | Not really comparable. |

---

## 3-5 concrete adoption ideas for anvil

1. **`/dual-review` combinator skill.** Run `/self-review` (Claude) and `/codex-review` (Codex) in parallel, then emit a single findings table: agreement / Claude-only / Codex-only / disagreement. File as anvil issue. One-paragraph rationale: today an operator picks one or the other; both is the strictly better signal when the slice touches money/auth/storage. Rough budget: ~1 evening to write the skill, ~one PR.

2. **`.anvil/learnings.jsonl` per-project log.** Append-only JSON lines with `{key, type, insight, confidence, source_skill, files, timestamp}`. Add `/learn add`, `/learn search`, `/learn prune`. Skills like `/dispatch-slice` and `/pre-merge-gate` write into it automatically on each invocation. Operator's MEMORY.md becomes a *human-curated* layer on top, not the only layer. Rationale: chronic flakes get re-discovered every 2-3 sprints today because there's no structured machine-readable history.

3. **`/spec` "user-challenge" gate.** During plan capture, when the operator's stated direction conflicts with both Claude's and the codex-confer signal, flag it as a `user_challenge` requiring explicit override instead of silent accept. Rationale: anvil's `/spec` currently bias-confirms operator scope; this is the single biggest unforced error in the v3 lift was twice during operability planning.

4. **`/dispatch-slice` PR-exists idempotency.** Before opening a PR, check `gh pr list --head <branch>`; if one exists, update its body via `gh pr edit` instead of erroring or creating a duplicate. Rationale: small, an annoying class of "branch existed from a previous failed dispatch" bug. ~30 lines in the dispatch-slice skill.

5. **Adversarial personas become invocable skills, not memory docs.** Turn the 10 personas in `reference_review_personas.md` into `/persona-privacy-lawyer`, `/persona-stripe-risk`, `/persona-3am-oncall`, etc. — each one a thin skill that wraps `/self-review` with a hard-coded prompt prefix. Rationale: today the operator has to remember to invoke them by name; making them top-level discoverable makes them get used.

---

## Anti-patterns / don't-steal

- **Sequential `/autoplan` enforcement** ("phases MUST execute in strict order, NEVER in parallel"). Gstack enforces CEO → design → eng sequentially because *each phase reads the prior*. Anvil's slices are explicitly parallelizable when `depends-on` is empty. Don't regress to gstack's serial model.
- **Sprint-shaped vocabulary** ("sprint", "release engineer", "CEO interrogation"). Cute, but anvil's slice/grind/ratchet vocabulary is sharper. Don't dilute.
- **Continuous-checkpoint WIP commits.** Gstack auto-commits with `WIP:` and squashes at `/ship` time. Anvil's discipline (commit only when slice is green, one commit per atomic change) keeps `git bisect` honest. Don't trade that away.
- **23-skill explosion before we need it.** Gstack has 23 + 8 power tools. Anvil has ~16. Each new skill is a thing the operator has to remember exists. Stay disciplined; add only when an existing skill is too generic.
- **Daemon model for persistent state.** Gstack runs a long-lived browser daemon (`.gstack/browse.json` with PID + port). For anvil's plan-PR mechanics there's no equivalent need; stateless skills + JSONL logs is cheaper and crashes more gracefully.
- **Hosts/model overlays config layer.** Gstack has `hosts/index.ts` typing every host with model + tier + cost budget. Overkill for anvil's current scale where the operator's "default to Opus until 2026-06-07" memory rule does the job.

---

## Side note on the actual "stacked-PR" question

Anvil's original pain — *five slices share `fitness.test.js`, each merge force-rebases the next four* — is unsolved by gstack. The honest answer is **anvil should look at Graphite's `gt` CLI** (or sapling, or `git-spice`) for that specific problem. Those tools encode parent-child PR relationships at the GitHub layer, auto-rebase children when a parent merges, and handle the force-push-with-lease dance with explicit primitives. Roughly:

- `gt create` — branch off the current stack tip, register parent
- `gt sync` — pull main, restack all descendants
- `gt submit` — push every branch in the stack, open/update PRs, link them

That's the gold for the stacked-PR question. Filing a separate issue for "evaluate `gt` integration with anvil" is the cleaner path than trying to graft stacked-PR mechanics onto gstack (gstack itself doesn't have them).

---

## Closing note

gstack is well-built, very active (PRs every 2-3 days), and represents probably the most mature published "Claude Code skill stack" in the public eye right now. It's reassuring that anvil's design intuitions overlap heavily (skills + commit-after-each-slice + cross-model review). The deltas above are real but small — most are afternoon-sized adoptions, not architectural shifts. The biggest meta-lesson: **gstack puts review quality first; anvil puts PR mechanics first. Both are valid axes; we can pick up gstack's quality patterns without giving up anvil's mechanics.**
