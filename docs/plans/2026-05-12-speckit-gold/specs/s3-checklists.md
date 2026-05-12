# S3 — Per-slice checklists threaded through pre-merge-gate

**Slice:** S3
**Status:** locked

---

## Background

Anvil's `/pre-merge-gate` runs a fixed set of gates (rebase, tsc, vitest, fitness ratchet, forbidden-pattern grep). These are global. Today, when a specific slice needs a bespoke gate (e.g. "this slice must not introduce a new `console.log`" or "this slice must register its handler in the dispatch table"), the operator either bolts it into the global ratchet (wrong scope) or remembers to check manually (forgotten).

Per-slice checklists let the plan itself carry slice-specific acceptance gates that `pre-merge-gate` enforces at merge time. Two `kind:` values cover the realistic surface: `shell` (run a command, expect exit 0) and `grep` (assert a pattern is/isn't present).

---

## Scenario — failing grep blocks merge

**WHEN** a plan's slice has `checklist: [{kind: grep, pattern: "TODO\\(s3\\)", in: "src/**", expect: absent}]`
**AND** the branch implementing the slice contains a file `src/foo.ts` with the line `// TODO(s3): wire this up`
**AND** the operator invokes `/pre-merge-gate <branch>`

**THEN** the gate reports the checklist item failed: `S3 checklist FAIL: grep pattern 'TODO\(s3\)' present in src/foo.ts (expected absent)`
**AND** the gate exits non-zero
**AND** `/auto-merge` would refuse if called next (gate did not greenlight)

## Scenario — passing shell unblocks

**WHEN** a slice has `checklist: [{kind: shell, run: "bash tests/run.sh", expect: pass}]`
**AND** the branch's `tests/run.sh` exits 0
**AND** the operator invokes `/pre-merge-gate <branch>`

**THEN** the gate reports the checklist item passed: `S3 checklist PASS: shell 'bash tests/run.sh' exit 0`
**AND** the gate continues to the other global gates (tsc, fitness, etc.)

## Scenario — count assertion in grep

**WHEN** a slice has `checklist: [{kind: grep, pattern: "av_resolve_template", in: "shared/lib.sh", expect: present, count: 1}]`
**AND** the file `shared/lib.sh` contains exactly one match
**AND** the operator invokes `/pre-merge-gate`

**THEN** the gate reports pass

**WHEN** the file contains 0 matches OR 2+ matches

**THEN** the gate reports `S3 checklist FAIL: grep pattern 'av_resolve_template' found N matches in shared/lib.sh (expected exactly 1)`

## Scenario — missing checklist field = legacy behaviour

**WHEN** a slice's manifest has no `checklist:` key
**AND** the operator invokes `/pre-merge-gate`

**THEN** the gate runs the existing global gates only
**AND** does NOT emit any "no checklist" warning (silent absence)
**AND** behaviour is byte-identical to anvil pre-S3

## Scenario — slice located by branch name

**WHEN** the operator invokes `/pre-merge-gate fix-S3-foo` (no `--slice` arg)
**AND** the plan's tasks.md has a slice with `id: S3`

**THEN** the gate locates the S3 slice by matching the branch prefix to the slice id
**AND** runs the S3 checklist

## Scenario — slice located by explicit --slice arg

**WHEN** the operator invokes `/pre-merge-gate fix-something-else --plan docs/plans/<slug>/tasks.md --slice S3`

**THEN** the gate runs the S3 checklist regardless of branch name

---

## Negative case (refusal contract)

**WHEN** a checklist item has `kind:` other than `shell` or `grep`

**THEN** the gate exits non-zero
**AND** prints: `S3 checklist ERROR: unknown kind '<kind>' (expected: shell | grep)`
(No silent skip — invalid config must fail loudly.)

**WHEN** a `grep` item has `expect:` other than `present` or `absent`

**THEN** the gate exits non-zero with `S3 checklist ERROR: invalid expect '<value>' for grep (expected: present | absent)`

**WHEN** a `shell` item's `run:` command times out (>60s)

**THEN** the gate kills the command and reports `S3 checklist FAIL: shell '<cmd>' timed out after 60s`
(Cap the cost of a runaway check.)
