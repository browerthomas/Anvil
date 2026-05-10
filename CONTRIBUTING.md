# Contributing to anvil

Thanks for forging with us. Anvil is MIT-licensed and contribution-friendly.

## Quick orientation

- Skills live at `skills/<name>/SKILL.md`. Each is a markdown file with YAML frontmatter that Claude Code reads as procedural instructions.
- Templates referenced by skills live at `skills/<name>/templates/`.
- Shared helpers live at `shared/lib.sh`.
- Plan format is at `templates/plan-template.md`.
- Worked examples are at `examples/`.

The full architecture is at [`docs/architecture.md`](docs/architecture.md). Read that before extending across layer boundaries.

## How to add a skill

1. Create `skills/<your-skill>/SKILL.md` with the YAML frontmatter:

   ```markdown
   ---
   name: your-skill
   description: When to invoke (the trigger sentence + a few synonyms). Be specific — Claude Code matches against this.
   ---

   # /your-skill — short description

   Body explains procedure step-by-step.
   ```

2. If your skill needs templates / config samples / shell helpers, add them under `skills/<your-skill>/templates/` or `skills/<your-skill>/scripts/`.

3. Register the skill:
   - Add `"skills/<your-skill>"` to `.claude-plugin/plugin.json`.
   - Add `<your-skill>` to the install loop in `bin/install.sh` (it iterates `skills/*/` so usually no edit needed).
   - Update `README.md`'s skill table.

4. Test:
   - `bin/install.sh` (symlink mode — your edits go live).
   - In Claude Code, invoke `/your-skill` with a representative input.
   - Iterate until the skill behaves as expected.

5. Ship a PR using the template at `.github/PULL_REQUEST_TEMPLATE.md`.

## Skill style guide

- **Description field**: 1-3 sentences. Lead with the trigger ("Use when..."). End with synonym phrasing ("...or when the operator says X / Y / Z, or similar.").
- **Body opens with one paragraph of context.** What problem the skill solves. Why it exists.
- **Procedure section is numbered.** Each step is concrete. Bash snippets are real, not pseudocode.
- **Hard constraints are explicit.** What the skill MUST NOT do.
- **Failure modes are tabled.** Common error + cause + fix.
- **No marketing language in skill bodies.** Skills are tools, not products.

## How to add a plan template variant

1. Copy `templates/plan-template.md` to `templates/<variant>-plan-template.md`.
2. Document the variant's intended use at the top.
3. Reference it in `docs/plan-format.md` (TBD) or `README.md`.

## How to extend `/pre-merge-gate` for your project

The skill reads project-level config. Drop these in your repo:

- `.anvil/forbidden-patterns.txt` — grep patterns + path globs that block merge. Format documented in `skills/pre-merge-gate/templates/forbidden-patterns.example.txt`.
- `.anvil/pre-merge-gate.config.json` — rebase target, test baselines, known flakes. Sample at `skills/pre-merge-gate/templates/pre-merge-gate.config.example.json`.

These are read by `/pre-merge-gate` at invocation time. No anvil-side change needed.

## PR conventions

- **Conventional commits.** `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`. Scope optional.
- **PR template** must be filled (`.github/PULL_REQUEST_TEMPLATE.md`).
- **One concern per PR.** Multiple skills in one PR is fine if they ship together; avoid bundling unrelated fixes.
- **Update docs alongside code.** If you change a skill's trigger phrase, update README + the skill's description field together.

## Major changes

For changes that span ≥3 skills or break the layer model:

1. Open an issue first describing the proposal.
2. Use anvil to ship anvil — write a `/spec`, lock the plan, run `/grind` against the anvil repo.
3. Reference the plan + recap in the PR body.

## Code of conduct

Be kind. Argue ideas, not people. Disagree publicly, then commit. No bots, no sock-puppets, no harassment. Maintainers reserve the right to remove abusive content + ban repeat offenders.

## License

By contributing, you agree your contributions are licensed under [MIT](LICENSE).
