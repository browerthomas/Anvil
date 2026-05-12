# S5 — /analyze-plan claim consistency gate at lock time

**Slice:** S5
**Status:** locked

---

## Background

Anvil's `/issue-to-spec` greps factual claims in a GitHub issue body against current code to catch the "issue body is wrong" class of plan bug. Once locked plans exist, the same drift can happen: a plan written Monday cites file paths that the Tuesday refactor renamed. `/analyze-plan` generalises `/issue-to-spec` to whole plans, run as a pre-execution gate inside `/grind`.

Claim extraction is regex-based — fast, deterministic, explainable. Anything ambiguous gets verdict `unverifiable` rather than `contradicted`; false-positive `unverifiable` is fine, false-positive `contradicted` would cause the operator to ignore the gate.

---

## Scenario — stale file path is contradicted

**WHEN** a plan's `tasks.md` references `src/foo/bar.ts` in a slice's `files:` list
**AND** `src/foo/bar.ts` does not exist in the current working tree
**AND** the operator invokes `/analyze-plan docs/plans/<slug>/`

**THEN** the report includes a line: `CONTRADICTED  src/foo/bar.ts  (file does not exist; cited in tasks.md:NN)`
**AND** the skill exits non-zero (would block `/grind` execution unless `--skip-analyze`)

## Scenario — current file path is verified

**WHEN** a plan's tasks.md references `shared/lib.sh` in a slice's `files:` list
**AND** `shared/lib.sh` exists in the current working tree
**AND** the operator invokes `/analyze-plan <plan-path>`

**THEN** the report includes: `VERIFIED  shared/lib.sh  (exists; cited in tasks.md:NN)`

## Scenario — backticked identifier is verified

**WHEN** a plan's `design.md` contains the claim "the resolver helper is `av_resolve_template`"
**AND** `grep -r 'av_resolve_template' .` returns at least one hit in source (excluding plan files themselves)
**AND** the operator invokes `/analyze-plan`

**THEN** the report includes: `VERIFIED  av_resolve_template  (N occurrences in source)`

## Scenario — backticked identifier is contradicted

**WHEN** a plan's design.md cites a function name that has zero hits in source

**THEN** the report includes: `CONTRADICTED  <name>  (zero occurrences; claim is stale or premature)`
**AND** the skill exits non-zero

## Scenario — prose without fact tokens is unverifiable

**WHEN** a plan's proposal.md contains a sentence like "this approach is faster" (no file path, no backticked identifier, no numeric fact)

**THEN** the report includes: `UNVERIFIABLE  '<excerpt>'  (no fact-like tokens to verify)`
**AND** the verdict does NOT cause the skill to exit non-zero (unverifiable is not a failure)

## Scenario — grind pre-execution gate

**WHEN** the operator invokes `/grind docs/plans/<slug>/`
**AND** the plan has at least one CONTRADICTED claim

**THEN** `/grind` halts at step 0.5 (pre-execution analyze gate)
**AND** prints the analyze-plan report
**AND** prompts the operator to either `/refine-plan` first or re-run with `/grind --skip-analyze`
**AND** does NOT dispatch any slices

## Scenario — grind --skip-analyze bypasses the gate

**WHEN** the operator invokes `/grind <plan-path> --skip-analyze`

**THEN** the analyze gate is not run
**AND** `/grind` proceeds directly to slice dispatch

---

## Negative case (refusal contract)

**WHEN** the operator invokes `/analyze-plan` on a path that does not exist or is not a plan folder/file

**THEN** the skill exits non-zero
**AND** prints: `/analyze-plan: <path> is not a plan (expected a tasks.md or a folder containing one)`

**WHEN** the plan files contain only prose (no fact-like tokens)

**THEN** the skill emits a warning: `warning: extracted 0 verifiable claims — analyze-plan provides no signal for this plan`
**AND** exits 0 (not a failure — just a no-op)
(Empty signal is not a fail; it means the plan is too high-level for grep-based verification.)
