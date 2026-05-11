# Graphite evaluation for anvil — what's in those hills

**Date:** 2026-05-11
**Question:** does anvil need to integrate Graphite (`gt` CLI) to solve the stacked-PR rebase friction called out in `gstack-comparison-2026-05-11.md`?
**Short answer:** **No — adopt `git-spice` instead.** Graphite the *product* is now a proprietary SaaS code-review platform with the open-source CLI archived in 2023. The OSS fork (`charcoal`) is barely maintained. `git-spice` (Go, GPL-3.0, very active) gives anvil every primitive it needs, runs purely offline against vanilla GitHub, and ships with a clean agent-skill model already.

---

## Bottom line

The stacked-PR rebase friction anvil currently lives by hand (`git rebase origin/main && git push --force-with-lease` for every descendant after each parent merge) is **a real problem** and **a solved problem outside anvil**. The gold the gstack research pointed at is real, but the *tool to steal it with* is no longer Graphite — it's `git-spice`.

The recommended shape:

- **Add one anvil skill, `/stack-sync`,** that wraps `gs repo sync && gs stack restack && gs stack submit` (or equivalent). Triggered automatically by `/auto-merge` and `/post-merge-debrief` when the merged PR had children waiting.
- **Add a second skill, `/stack-create`,** that replaces the `git checkout -b feat/X main && git push -u && gh pr create` boilerplate in `/dispatch-slice` with `gs branch create feat/X --message=...` followed by `gs branch submit`. The parent-child relationship gets registered automatically; `gs repo sync` then knows the dep graph.
- **Don't bind anvil to a particular stacking tool.** Treat `git-spice` as a backend selected via `.anvil/config.yaml` (`stacking_backend: git-spice | graphite | none`). Default `none` (preserves today's behaviour). Operator opts in by setting the backend and installing the CLI.
- **Skip Graphite-the-SaaS entirely.** Their CLI is closed and their pricing model (free 30-day trial → paid Team plan) is a non-starter for an OSS framework. The OSS startup/maintainer program covers the SaaS but the CLI bit is gated to the SaaS account.

---

## What Graphite actually is in 2026

Graphite is now a **proprietary SaaS code-review platform** at graphite.com (graphite.dev → 301 redirect). The CLI (`gt`) is one component of a larger product that also includes AI code review, a merge queue, PR inbox, Slack integration, VS Code extension, and developer-metrics dashboards. The CLI **was** open-source until 2023-07-14, when the `withgraphite/graphite-cli` repo was archived and development moved to a private monorepo. Free users got rate-limited to 10 open stacks per org starting 2023-08-07.

Public artefacts as of 2026-05-11:
- `withgraphite/graphite-cli` — archived 2023, useless as a base.
- `withgraphite/agent-skills` — single SKILL.md targeting Claude Code (read it; it's a 345-line "how to use `gt`" prompt with worktree handling, branch-naming convention, troubleshooting table, and surgical-rebasing escape hatch). Useful as a *prompt model* even if we don't ship `gt`.
- `withgraphite/homebrew-tap` — install path (binary download from their CDN).
- `withgraphite/gitoxide` — Rust git library; tangentially useful.
- Pricing: 30-day trial → Standard plan (paid, exact tier not listed publicly), free Standard for startups ≤ 10 GH members or OSS projects (you apply).
- GitHub App: required for the SaaS features; the CLI on its own can talk to vanilla GitHub via `gh`, but install requires their auth token.

**Bottom line on Graphite:** the surface anvil would actually use (branch-create with parent registration, stack-submit, stack-restack-on-merge) is technically available via the closed-source CLI binary, but you can't read the source, contribute upstream, or guarantee it stays free. **Not a fit for an OSS framework.**

---

## The actual recommendation: `git-spice`

`git-spice` (`gs`) is what `gt` was before it went private:

| Property | Verdict |
|---|---|
| License | GPL-3.0 |
| Language | Go (single static binary; `brew install git-spice` or `go install`) |
| Active | Very — v0.27.x in 2026, regular changelog entries, healthy issue tracker |
| Server-side state | **None.** All state stored locally in the Git repo. |
| Forge support | GitHub, GitLab, Bitbucket |
| Offline | Yes — "Most branch stacking operations are local and do not require a network connection" |
| GitHub App | **Not required.** Uses a personal access token via `gs auth login` or shells out to `gh`. |
| Auto-restack on parent merge | Yes — `gs repo sync` deletes merged branches AND restacks descendants onto their new bases automatically. |
| Force-push hygiene | Refuses by default if the push would lose data; `--force` overrides; force-push-with-lease semantics implicit. |
| Agent-friendliness | `AGENTS.md` in repo root with full TDD workflow; the design tells agents how to use it. |
| Conflict UX | When `gs stack restack` hits a conflict, it pauses; operator/agent resolves + `git rebase --continue`. Same as anvil's current dance, but scoped to the specific stack instead of full repo. |
| Visualisation | `gs log` shows the stack tree. |
| Per-branch metadata | Each tracked branch knows its parent; deps are real, not implicit. |

The full primitive set anvil cares about:

| Anvil need | git-spice primitive |
|---|---|
| Create slice branch with parent recorded | `gs branch create <name>` (or `gs bc`) |
| Submit stack as PRs | `gs stack submit` (or `gs ss`) |
| Sync after main update / parent merge | `gs repo sync` |
| Restack children after merge | `gs stack restack` (or `gs sr`) — chains automatically from sync via `--restack` |
| Inspect stack | `gs log` |
| Move branch onto different parent | `gs branch onto` |
| Fold a tiny slice into its parent | `gs branch fold` |
| Reorder slices | `gs upstack onto` / `gs branch onto` |

`gs repo sync` is the killer. After `/auto-merge` of slice N, calling `gs repo sync && gs stack restack && gs stack submit` from each child worktree replaces the entire manual `rebase --onto + force-push-with-lease` dance.

---

## Concrete adoption ideas for anvil (3-5, with effort)

1. **`/stack-create` skill — replace `/dispatch-slice`'s branch+PR boilerplate (effort: 1 evening, 1 PR).** Today `/dispatch-slice` shells `git checkout -b feat/X main && git push -u && gh pr create`. Wrap that in a thin skill that detects `.anvil/config.yaml`'s `stacking_backend` and routes to `gs branch create <name> --message=...` + `gs branch submit` when it's `git-spice`, falling back to the current `git/gh` flow when it's `none`. Slice's PR knows its parent; `gs repo sync` post-merge will restack siblings automatically.

2. **`/stack-sync` skill — post-merge restack-and-push (effort: 1 evening, 1 PR).** Called from `/auto-merge` and `/post-merge-debrief` when the merged PR has children. Logic: `gs repo sync` (pulls main, deletes merged refs) → if any descendants still active, `gs stack restack` → push with `gs stack submit`. Conflicts: pause, surface to operator with file list, exit non-zero. This eliminates the four-step manual dance the operator currently runs per merge in the v3 stack.

3. **`.anvil/config.yaml` `stacking_backend` field (effort: 30 min, 1 PR).** Single new config key, three legal values (`none`, `git-spice`, `graphite`). Default `none`. `/stack-create` and `/stack-sync` check it; everything else stays backend-agnostic. Keeps anvil tool-agnostic and lets later operators pick `graphite` if they happen to be paying for the SaaS.

4. **Steal the Graphite SKILL.md prompt patterns, not the tool (effort: 2-3 hours, 1 PR).** Their 345-line skill encodes useful agent-targeted patterns: "never use Bash heredocs for PR descriptions; use `Write` tool + `gh pr edit --body-file`", explicit "untracked branch in worktree" workaround, surgical-rebase escape hatch for when `gt restack` hits unrelated conflicts. Port those into anvil's existing `/dispatch-slice` and `/auto-merge` skills regardless of whether we adopt `git-spice` itself.

5. **PR-body idempotency in `/stack-create` (effort: 30 lines, folded into #1).** Before opening a PR, check `gh pr list --head <branch>`; if one exists, update body via `gh pr edit --body-file` instead of erroring. Same gold-nugget the gstack research flagged as adoption idea #4. Bundle it with `/stack-create` since both ideas touch the same code path.

Total: ~1.5 days of focused work, 3-4 PRs.

---

## Risk callouts — what to NOT couple to

- **Don't make `git-spice` (or any stacking tool) a hard dependency.** The `stacking_backend: none` default keeps anvil usable for ops who don't want to install Go binaries on their dev machine, and keeps anvil's existing dogfood loop working with no behavioural change.
- **Don't ship a Graphite (`gt`) backend before validating their licensing.** The CLI binary is technically still installable via their tap, but the EULA covers it as part of their SaaS product. Filing a "graphite backend" issue and parking it until someone actually asks is fine.
- **Don't adopt their branch-naming convention as anvil-default.** The Graphite SKILL.md pushes `stack-name/terse-description` (e.g. `auth-bugfix/handle-401`). Anvil's existing convention (`feat/<scope>-<description>` per issue) is fine; making it backend-configurable is overkill.
- **Don't assume `gs repo sync` is atomic.** If it crashes mid-restack (network blip, conflict, signal), anvil's `/stack-sync` skill needs to surface a clear "interrupted; here's where you are; here's how to recover" message rather than silently leave the operator in a half-restacked state. The gstack-research recovery-from-interrupted-rebase block is the right model.
- **Don't shell out blindly.** `gs` exits non-zero with structured messages — anvil's skill should parse them rather than just dumping stdout to the operator. Treat it as a backend API, not a console.

---

## Alternatives — one paragraph each

- **Sapling (`sl`).** Meta's Mercurial-derived CLI with native stacked-diff support, GPL-2.0, very polished. Killer feature: it operates on a parallel client-side history model that makes restacking trivial. Killer downside for anvil: it replaces the entire `git` workflow rather than augmenting it; existing skills that shell `git` and `gh` would need parallel implementations. Operator's mental model would have to switch. **Verdict: too disruptive for a backend-pluggable framework.**

- **`charcoal`.** Open-source fork of pre-2023 Graphite CLI, AGPL-3.0, ~1.4k commits, last release March 2025. Works against vanilla GitHub. Caveats: AGPL-3.0 is more restrictive than GPL-3.0 (network-use copyleft); maintenance is one-person and slower than git-spice; the codebase is the older TypeScript Graphite CLI rather than a clean greenfield. **Verdict: viable fallback if `git-spice` ever stalls, but `git-spice` is a better default in 2026.**

- **`git rebase --onto` discipline (no tool).** What anvil does today. Honest assessment: it works, but it's tedious and the operator has to track child-branch lists by hand. For 2-3 slice stacks it's fine. For the 5-slice v3 fitness-test cluster, it bit twice. **Verdict: stop relying on it as the only model; add `/stack-sync` for the >3-slice cases.**

- **`gh-stack` (GitHub's official).** A `gh` extension; does much less than `gt`/`gs` — basically renders the dep graph as a comment in each PR but doesn't do auto-restack. **Verdict: not enough for anvil's needs.**

- **`spr`, `git-branchless`, `ghstack`.** The git-spice author specifically built `gs` after evaluating these and finding gaps. Each has a niche, but none have the offline-first + GitHub-vanilla + agent-friendly trio that `gs` does. **Verdict: skip.**

---

## Recommendation

**Anvil should integrate `git-spice` as an opt-in `stacking_backend` via two new skills (`/stack-create`, `/stack-sync`), with a config-keyed default of `none` to preserve today's behaviour.** File three issues:

1. `[stacking] Add stacking_backend config key + /stack-create + /stack-sync skills (git-spice integration)` — depends on operator installing `gs` locally; ~1.5 days work.
2. `[stacking] Port useful patterns from Graphite SKILL.md` — backend-agnostic prompt-hygiene improvements; ~2-3 hours.
3. `[stacking] /stack-sync auto-trigger from /auto-merge when PR has children` — wiring, ~1 hour after #1 lands.

The original framing — "anvil should integrate Graphite via `/stack-create` + `/stack-sync` skills" — is right in shape but wrong in tool. Graphite-the-product is no longer the right partner for an OSS framework; `git-spice` is.
