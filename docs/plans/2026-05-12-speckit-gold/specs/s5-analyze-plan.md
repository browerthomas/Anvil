# S5 — /analyze-plan v1, file-path existence gate

**Slice:** S5
**Status:** locked

---

## Background

Anvil's `/issue-to-spec` greps factual claims in a GitHub issue body against current code to catch the "issue body is wrong" class of plan bug. Once locked plans exist, the same drift can happen: a plan written Monday cites file paths that the Tuesday refactor renamed. `/analyze-plan` generalises `/issue-to-spec` to whole plans, run as a pre-execution gate inside `/grind`.

**v1 scope: file-path verification ONLY.** Adversarial review (hermes-ask P1-5) walked through realistic plan prose and projected >30% false-positive rates on backticked-identifier extraction (matches on common English words like `done`, `pass`, `present`). Identifier and numeric-fact verification are deferred to a v2 follow-up scoped as "add identifier verification with stricter regex (snake_case ≥6 chars OR CamelCase ≥6 chars) once the v1 FP rate is measured on 3+ real plans."

Claim extraction is regex-based — fast, deterministic, explainable. The verdict set is:
- `verified` — path exists.
- `expected-by-slice` — path does NOT exist BUT appears in some slice's `files:` list in the plan's tasks.md (forward-looking; not a failure).
- `contradicted` — path does not exist AND not in any slice's `files:` list.
- `unverifiable` — path matched too loosely (e.g. inside a code fence, contains placeholder tokens) — no fact to check.

The `expected-by-slice` verdict is load-bearing: without it, `/analyze-plan` running on the speckit-gold plan itself during its own grind would flag `templates/constitution-template.md` (created by S1) and `skills/analyze-plan/SKILL.md` (created by S5) as CONTRADICTED.

---

## Scenario — stale file path is contradicted

**WHEN** a plan's `tasks.md` references `src/foo/bar.ts` outside any slice's `files:` list
**AND** `src/foo/bar.ts` does not exist in the current working tree
**AND** the operator invokes `/analyze-plan docs/plans/<slug>/`

**THEN** the report includes a line: `CONTRADICTED  src/foo/bar.ts  (file does not exist; cited at <plan-file>:<line>)`
**AND** the skill exits non-zero (would block `/grind` execution unless `--skip-analyze`)

## Scenario — current file path is verified

**WHEN** a plan's tasks.md references `shared/lib.sh` and `shared/lib.sh` exists
**AND** the operator invokes `/analyze-plan <plan-path>`

**THEN** the report includes: `VERIFIED  shared/lib.sh  (exists; cited at <plan-file>:<line>)`

## Scenario — forward-looking path in slice files list

**WHEN** a plan's `tasks.md` references `templates/constitution-template.md` AND lists it in some slice's `files:` list
**AND** the file does not exist on disk yet
**AND** the operator invokes `/analyze-plan <plan-path>`

**THEN** the report includes: `EXPECTED-BY-SLICE  templates/constitution-template.md  (forward-looking; in slice S1 files: list)`
**AND** this verdict does NOT cause non-zero exit
(This is the speckit-gold-on-itself case — without this verdict, /grind would refuse to start its own first execution.)

## Scenario — placeholder path is not extracted

**WHEN** a plan contains the string `docs/plans/.transcripts/<YYYY-MM-DD>-<slug>.md`

**THEN** the extractor does NOT emit a claim for it (placeholder tokens `<...>` make it unverifiable at extraction time)
**AND** the path does NOT appear in the report (silent skip — not even `UNVERIFIABLE`)

## Scenario — code-fenced path is unverifiable

**WHEN** a plan contains a fenced code block with a path like `path/to/example.ts` used illustratively

**THEN** the extractor flags it as `UNVERIFIABLE  path/to/example.ts  (inside code fence; illustrative)`
**AND** this verdict does NOT cause non-zero exit

## Scenario — grind pre-execution gate halts on contradiction

**WHEN** the operator invokes `/grind docs/plans/<slug>/`
**AND** the plan has at least one CONTRADICTED claim

**THEN** `/grind` halts at step 0.5 (pre-execution analyze gate)
**AND** prints the analyze-plan report
**AND** prompts: "stale claims found; either run /refine-plan or re-run /grind with --skip-analyze"
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

**WHEN** the plan files contain only prose (no fact-like file paths)

**THEN** the skill emits a warning: `warning: extracted 0 verifiable claims — analyze-plan provides no signal for this plan`
**AND** exits 0 (not a failure — just a no-op)
(Empty signal is not a fail; means the plan is too high-level for grep-based verification. v2 with identifier extraction may catch more.)

**WHEN** any plan file is unreadable (permissions, encoding)

**THEN** the skill exits non-zero
**AND** prints: `/analyze-plan: cannot read <path>: <reason>`
