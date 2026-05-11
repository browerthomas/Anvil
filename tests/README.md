# anvil tests

Smoke-test suite for anvil's own skills. Catches the obvious-regression class
of bugs that would otherwise surface at dogfood time — a script blows up on
its argument parser, a SKILL.md drops its frontmatter, a markdown bash block
has unbalanced quotes, a persona file leaks project-private references.

These are **smoke tests, not comprehensive tests.** They confirm scripts run
and outputs are shape-correct. They don't validate semantic correctness of
the prompts/templates a skill emits.

## Run

```bash
# from repo root
make -C tests smoke

# or
cd tests && make smoke

# a single file
make -C tests smoke FILE=learn.bats
```

Requires:
- `bats-core` (`brew install bats-core` on macOS, `apt install bats` on Debian/Ubuntu)
- `jq`
- `git`, `bash` 4+

## Layout

```
tests/
├── README.md            — this file
├── Makefile             — `make smoke` target
├── test_helper.bash     — shared setup/teardown helpers
├── fixtures/            — sample plans, reviews, context docs
└── smoke/               — one bats file per skill, plus install/preflight/structure
```

## What's covered

| File | Covers | Test count |
|---|---|---|
| `learn.bats` | `/learn` (add/search/summary/prune/export) — 5 scripts | 14 |
| `dispatch-slice.bats` | `build-prompt.sh` happy path + arg validation | 6 |
| `config-bootstrap.bats` | `derive-rules.sh` against fixture context doc | 5 |
| `findings-rollup.bats` | `parse-review.sh` + `dispatch-fixup.sh` arg shape | 6 |
| `spec.bats` | `validate.sh` against valid/invalid/folder plans | 6 |
| `grind.bats` | `state.sh` (init/next/ready/mark/status/trace) | 9 |
| `dual-review.bats` | `capture-diff.sh` against an in-flight worktree | 4 |
| `auto-merge.bats` | `merge.sh` arg validation + syntax | 3 |
| `pre-merge-gate.bats` | `verify.sh` arg validation + syntax | 3 |
| `issue-to-spec.bats` | `verify-issue.sh` arg validation | 3 |
| `codex-review.bats` | `/codex-review` SKILL.md presence + syntax | 2 (skip if absent) |
| `codex-confer.bats` | `/codex-confer` SKILL.md presence + syntax | 2 (skip if absent) |
| `personas.bats` | every persona file: shape, placeholder, no leaks | 6 |
| `markdown-syntax.bats` | every SKILL.md's bash blocks parse | 16 |
| `skill-structure.bats` | frontmatter, name match, no project-private refs | 10 |
| `install.bats` | `bin/install.sh` against a throwaway HOME | 6 |
| `preflight.bats` | `bin/preflight.sh` runs + emits summary | 3 |

Total: ~100 tests across 17 bats files.

## How to add a new test

1. If the skill has a script:
   ```bash
   # tests/smoke/<skill-name>.bats
   #!/usr/bin/env bats
   load ../test_helper

   setup() { setup_fresh_repo; }

   @test "<skill> <happy path>" {
     run bash "$ANVIL_ROOT/skills/<skill>/scripts/<x>.sh" <args>
     [ "$status" -eq 0 ]
     # assert side-effect or output shape
   }
   ```

2. If the skill is markdown-only: the file is already covered by
   `markdown-syntax.bats` + `skill-structure.bats`. Add a dedicated
   `<skill>.bats` only if the SKILL.md describes something verifiable
   programmatically (e.g. `recap` has no script, but the file shape
   could be asserted).

3. If your test needs fixture data: add a file under `tests/fixtures/`
   and reference it via `$FIXTURES_DIR/<name>`.

## CI

The suite runs on every push to `main` and every PR via
[`.github/workflows/smoke-test.yml`](../.github/workflows/smoke-test.yml).
First failure blocks merge.

## Helper reference

The `test_helper.bash` file exposes:

- `ANVIL_ROOT` — repo root (the anvil source tree).
- `FIXTURES_DIR` — `tests/fixtures/` absolute path.
- `setup_fresh_repo` — `mkdir + git init + first commit` in `$BATS_TEST_TMPDIR/repo`. Idempotent: safe to call twice in one test.
- `setup_fresh_repo_with_seed_learnings` — same plus `.anvil/learnings.jsonl` with 3 seed entries (used by /learn search + summary tests).
- `extract_md_bash_blocks <md-file> <out-sh>` — pulls every ```bash fenced block, substitutes `<placeholder>` tokens so `bash -n` accepts them.

## When this fails

If a smoke test fails on CI after a recent SKILL.md or script edit, the
fix is usually one of:

- Syntax error in a bash block of a SKILL.md — `bash -n` will report
  the line number after the helper extracts blocks to a `.sh` file.
- A SKILL.md lost its YAML frontmatter or the `name:` field — restore
  it; the `skill-structure.bats` test names which file.
- A persona file lost the `{{project_context}}` placeholder — re-add
  it; the `personas.bats` test will name the file.
- A script's argument parser was changed and no longer accepts what
  the smoke test passes — update the smoke test if the change is
  intentional.
