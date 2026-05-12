# S3 — Per-slice checklists threaded through pre-merge-gate

**Slice:** S3
**Status:** locked

---

## Background

Anvil's `/pre-merge-gate` runs a fixed set of gates (rebase, tsc, vitest, fitness ratchet, forbidden-pattern grep). These are global. Today, when a specific slice needs a bespoke gate (e.g. "this slice must not introduce a new `console.log`" or "this slice must register its handler in the dispatch table"), the operator either bolts it into the global ratchet (wrong scope) or remembers to check manually (forgotten).

Per-slice checklists let the plan itself carry slice-specific acceptance gates that `pre-merge-gate` enforces at merge time. Two `kind:` values cover the realistic surface: `shell` (run a command, expect exit 0) and `grep` (assert a pattern is/isn't present).

**Slice lookup uses `.anvil/dispatched-agents.json` exact match** (slice id → branch), NOT branch-name prefix matching. Adversarial review (P0-3) enumerated four collision modes in prefix matching (substring match, rebase splits, re-dispatch on new branch, branch rename). The dispatched-agents.json approach uses the existing source of truth populated by `/dispatch-slice` (per `skills/dispatch-slice/SKILL.md:177`).

---

## Scenario — failing grep blocks merge

**WHEN** a plan's slice S-test has `checklist: [{kind: grep, pattern: "TODO\\(s-test\\)", in: "src/**", expect: absent}]`
**AND** `.anvil/dispatched-agents.json` maps `S-test` to branch `fix-S-test-foo`
**AND** the operator is on branch `fix-S-test-foo`
**AND** the branch contains a file `src/foo.ts` with the line `// TODO(s-test): wire this up`
**AND** the operator invokes `/pre-merge-gate`

**THEN** the gate looks up the slice via dispatched-agents.json
**AND** runs the S-test checklist
**AND** reports: `S-test checklist FAIL: grep pattern 'TODO\(s-test\)' present in src/foo.ts (expected absent)`
**AND** the gate exits non-zero
**AND** `/auto-merge` would refuse if called next

## Scenario — passing shell unblocks (with default timeout)

**WHEN** a slice has `checklist: [{kind: shell, run: "make -C tests smoke", expect: pass}]`
**AND** the branch's `make -C tests smoke` exits 0 within 300 seconds (default timeout)
**AND** the operator invokes `/pre-merge-gate`

**THEN** the gate reports: `S-test checklist PASS: shell 'make -C tests smoke' exit 0`
**AND** the gate continues to the existing global gates (rebase, tsc, fitness, etc.)

## Scenario — per-item timeout override

**WHEN** a slice has `checklist: [{kind: shell, run: "<long-running-cmd>", expect: pass, timeout: 600}]`
**AND** the command takes 400 seconds

**THEN** the gate does NOT time out (per-item timeout is 600s)

## Scenario — count assertion in grep

**WHEN** a slice has `checklist: [{kind: grep, pattern: "av_resolve_template", in: "shared/lib.sh", expect: present, count: 1}]`
**AND** the file `shared/lib.sh` contains exactly one match

**THEN** the gate reports pass

**WHEN** the file contains 0 matches OR 2+ matches

**THEN** the gate reports: `S-test checklist FAIL: grep pattern 'av_resolve_template' found N matches in shared/lib.sh (expected exactly 1)`

## Scenario — missing checklist field = legacy behaviour

**WHEN** a slice's manifest has no `checklist:` key
**AND** the operator invokes `/pre-merge-gate`

**THEN** the gate runs the existing global gates only
**AND** does NOT emit any "no checklist" warning (silent absence)
**AND** behaviour is byte-identical to anvil pre-S3

## Scenario — slice located via dispatched-agents.json exact match

**WHEN** `.anvil/dispatched-agents.json` contains `{"S-test": {"branch": "fix-S-test-foo", ...}}`
**AND** the operator is on branch `fix-S-test-foo`
**AND** the operator invokes `/pre-merge-gate` (no `--slice` arg)

**THEN** the gate matches branch `fix-S-test-foo` to slice id `S-test` via exact match
**AND** runs the S-test checklist

## Scenario — explicit --slice arg overrides json lookup

**WHEN** the operator invokes `/pre-merge-gate --slice S-other`
**AND** `.anvil/dispatched-agents.json` maps the current branch to slice `S-test`

**THEN** the gate runs the S-other checklist (--slice wins)

## Scenario — no slice context found

**WHEN** the operator invokes `/pre-merge-gate` on a branch not present in `dispatched-agents.json`
**AND** no `--slice` arg is given

**THEN** the gate prints: `error: no slice context found; pass --slice <id> or run inside /grind`
**AND** exits non-zero before running ANY gate (including global ones)
(Hard fail — without slice context, the per-slice checklist can't run; better to fail loudly than silently skip.)

---

## Negative case (refusal contract)

**WHEN** a checklist item has `kind:` other than `shell` or `grep`

**THEN** the gate exits non-zero
**AND** prints: `S-test checklist ERROR: unknown kind '<kind>' (expected: shell | grep)`

**WHEN** a `grep` item has `expect:` other than `present` or `absent`

**THEN** the gate exits non-zero with `S-test checklist ERROR: invalid expect '<value>' for grep (expected: present | absent)`

**WHEN** a `shell` item's `run:` command exceeds its `timeout:` (default 300s)

**THEN** the gate kills the command and reports `S-test checklist FAIL: shell '<cmd>' timed out after Ns`
