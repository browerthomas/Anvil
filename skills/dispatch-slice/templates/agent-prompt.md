# Agent prompt template — used by /dispatch-slice

Variables in `{{ ... }}` are filled in by the skill before the prompt is sent to the agent.

---

You are implementing **{{slice-id}}** — {{slice-title}}.

{{#if issue-number}}**Issue:** [#{{issue-number}}]({{issue-url}}){{/if}}
**Worktree:** `{{worktree-path}}` on branch `{{branch-name}}` based on `{{base-branch}}`. Deps installing in background — run `npm install` in any sub-package if its `node_modules` is empty.

## Scope

{{slice-scope}}

## Required tests

{{#each acceptance-criteria}}
- {{this}}
{{/each}}

Tests target: **{{test-target}}+ passing** (current baseline: {{test-baseline}}).

## Hard constraints

{{#each project-default-constraints}}
- {{this}}
{{/each}}

{{#if slice-constraints}}
### Slice-specific:
{{#each slice-constraints}}
- {{this}}
{{/each}}
{{/if}}

## Procedure

1. `npm install` if any package's `node_modules` is empty.
2. Read the relevant files:
{{#each files-to-read}}
   - `{{this}}`
{{/each}}
3. Implement the scope above.
4. Run from the worktree:
   - `npx tsc --noEmit` (must be clean)
   - `npx vitest run` (must hit {{test-target}}+)
5. Architecture fitness ratchets must stay green: `npx vitest run test/architecture/fitness.test.ts`.
6. Commit with conventional message:
   ```
   {{commit-message}}
   ```
7. Push the branch.
8. Open a PR against `main`. Use `gh pr create` and FILL the PR template fully (What/Summary/Why/Risks/Testing(Manual+Automated)/Scope/Links). Reference {{#if issue-number}}issue #{{issue-number}}{{/if}} {{#if related-plan}}+ plan `{{related-plan}}`{{/if}} in the body.

{{#unless no-codex}}
9. After implementation: a `/codex-review` will run post-merge for paper trail. If you have time during implementation, ask `/codex-confer` for adversarial feedback on tricky design choices.
{{/unless}}

## Return shape

Return ONLY:
- PR URL
- Test count (before → after)
- LoC delta (additions / deletions / files changed)
- Files changed (paths)
- Design decisions (especially: choices that diverged from the scope or surprised you)
- Pushback (anything you'd flag — empty if clean)

Do NOT validate the scope, do NOT summarise the code, do NOT recap the task. Findings + facts only.

## Framework expectations

The orchestrator that dispatched you expects:
- Self-verified `tsc` + `vitest` pass before commit
- PR opened with full template
- Pushback documented in the return summary
- LoC delta + test count delta in return summary

Default Opus reasoning. Operator on higher-tier through {{higher-tier-end-date}} — quality over token-thrift.
