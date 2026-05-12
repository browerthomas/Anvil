# speckit-gold — tasks

> Four slices. S2 lands first (shared `shared/lib.sh` + `skills/spec/SKILL.md`). S1 and S3 depend on S2. S5 parallel against everything.

---

## Slice manifest

```yaml
slices:
  - id: S2
    name: Template override hierarchy (2-layer, reusing av_anvil_root)
    depends-on: []
    files:
      - shared/lib.sh
      - skills/spec/SKILL.md
      - docs/template-overrides.md
      - tests/smoke/template-overrides.bats
    parallelizable: true
    scope: |
      Add `av_resolve_template <name>` to `shared/lib.sh` implementing a 2-layer
      resolver: `${PWD}/.anvil/templates/overrides/<name>` → `$(av_anvil_root)/templates/<name>`.
      Reuse the existing `av_anvil_root()` function at `shared/lib.sh:144` for the
      core layer — do NOT introduce a new `ANVIL_HOME` env var; the canonical
      install-root variable is `ANVIL_ROOT` and the existing helper already handles
      plugin / manual-clone / symlinked install. First hit wins. Refuse path
      traversal in the name (no `..`, no leading `/`).

      Update `skills/spec/SKILL.md` so its template-load step uses the resolver
      instead of a hard-coded path. Document the hierarchy in `docs/template-overrides.md`
      (cover: project layer location, when to use it, that the preset layer is
      deferred until a real preset use-case appears).

      Add a bats smoke test at `tests/smoke/template-overrides.bats` that drops a
      stub `plan-template.md` into a temp project's `.anvil/templates/overrides/`
      and asserts it wins over the core default; also asserts core-default fallback
      when no override exists; also asserts path-traversal refusal.
    constraints:
      - "Bash-only; no Node helper."
      - "Use `av_anvil_root()` and `ANVIL_ROOT`; do NOT introduce `ANVIL_HOME`."
      - "Resolver returns the resolved absolute path on stdout; caller `cat`s it."
      - "Path traversal refused with non-zero exit + clear stderr message."
      - "Test under `tests/smoke/*.bats`, runnable via `make -C tests smoke`."
    acceptance:
      - "Test: project override at `.anvil/templates/overrides/plan-template.md` wins."
      - "Test: core default returned when no override exists."
      - "Test: `av_resolve_template ../foo` exits non-zero with stderr 'refusing path traversal'."
      - "Doc: docs/template-overrides.md exists and explains precedence."
      - "No regression: existing `make -C tests smoke` stays green."
      - "CHANGELOG entry under next minor."
    checklist:
      - kind: grep
        pattern: "av_resolve_template"
        in: "shared/lib.sh"
        expect: present
      - kind: grep
        pattern: "av_resolve_template"
        in: "skills/spec/SKILL.md"
        expect: present
      - kind: grep
        pattern: "ANVIL_HOME"
        in: "shared/lib.sh"
        expect: absent
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300
    specs:
      - "../specs/s2-template-overrides.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S1
    name: Constitution artifact pinned into dispatch brief + prompt-to-disk
    depends-on: [S2]
    files:
      - templates/constitution-template.md
      - shared/lib.sh
      - skills/dispatch-slice/SKILL.md
      - skills/dispatch-slice/scripts/build-prompt.sh
      - bin/init-anvil-config.sh
      - tests/smoke/constitution.bats
    parallelizable: false
    scope: |
      Add `.anvil/constitution.md` as a new project-local artifact. Ship a canonical
      `templates/constitution-template.md` (operator scaffolds via `bin/init-anvil-config.sh`
      or copies manually — config-bootstrap does NOT auto-synthesise content into it).
      The template explains the slot: project ethos, north star, inviolable principles
      — strategic, not mechanical.

      Add `av_load_constitution` to `shared/lib.sh` that reads `.anvil/constitution.md`
      if present (returns its contents; empty string if absent or empty). Reject
      non-UTF-8 bytes with a warning + empty-return (graceful degradation).

      Update `skills/dispatch-slice/SKILL.md` (and `scripts/build-prompt.sh`) so that
      the assembled agent prompt: (a) includes a `## Project constitution` section near
      the top when constitution content is non-empty; (b) writes the full assembled
      prompt to `.anvil/dispatched-prompts/<slice-id>.prompt.md` BEFORE invoking the
      Agent tool. The on-disk emission is load-bearing for grep-testability.

      Update `bin/init-anvil-config.sh` to scaffold `.anvil/constitution.md` from the
      template on first init if the file does not exist. Do NOT touch `config-bootstrap`
      — auto-synthesis was rejected in adversarial review.
    constraints:
      - "Backward-compatible: existing `.anvil/` files keep their shape."
      - "Empty/missing constitution.md = no-op (no brief change, no `## Project constitution` section)."
      - "Constitution prepend ≤ 2KB recommended; warn to stderr if larger; ≥ 8KB second-tier warning."
      - "Non-UTF-8 bytes → warning + skip prepend (no hard fail)."
      - "Assembled prompt MUST be written to `.anvil/dispatched-prompts/<slice-id>.prompt.md` before Agent invocation."
      - "Do NOT modify `skills/config-bootstrap/SKILL.md`."
      - "Public-facing OSS: no project-private refs in template or examples."
      - "Use `av_anvil_root()` for any path resolution; reuse `av_resolve_template` (from S2) for the template file."
      - "Test under `tests/smoke/*.bats`."
    acceptance:
      - "Test: when `.anvil/constitution.md` exists with content 'TEST_MARKER', the file `.anvil/dispatched-prompts/<id>.prompt.md` contains 'TEST_MARKER' and a `## Project constitution` header."
      - "Test: when `.anvil/constitution.md` is absent, the file `.anvil/dispatched-prompts/<id>.prompt.md` is byte-identical (minus the section) to the pre-S1 prompt shape."
      - "Test: 3KB constitution emits a stderr warning matching 'recommended ≤ 2048'."
      - "Test: `bin/init-anvil-config.sh` creates `.anvil/constitution.md` from template on a fresh project."
      - "CHANGELOG entry."
    checklist:
      - kind: grep
        pattern: "av_load_constitution"
        in: "shared/lib.sh"
        expect: present
      - kind: grep
        pattern: "dispatched-prompts"
        in: "skills/dispatch-slice/SKILL.md"
        expect: present
      - kind: shell
        run: "test -f templates/constitution-template.md"
        expect: pass
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300
    specs:
      - "../specs/s1-constitution.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S3
    name: Per-slice checklists threaded through pre-merge-gate
    depends-on: [S2]
    files:
      - templates/plan-template.md
      - templates/plan-folder-template/tasks.md
      - skills/spec/SKILL.md
      - skills/pre-merge-gate/SKILL.md
      - shared/lib.sh
      - tests/smoke/per-slice-checklist.bats
    parallelizable: false
    scope: |
      Extend the slice-manifest YAML schema with a `checklist:` field — a list of items
      where each item is `{kind: shell, run: "<cmd>", expect: pass, timeout?: <seconds>}` OR
      `{kind: grep, pattern: "<regex>", in: "<glob>", expect: absent|present, count?: N}`.
      Default `timeout` is 300 seconds; per-item override allowed.

      Update `templates/plan-template.md` and `templates/plan-folder-template/tasks.md`
      to show the field in the example slice. Update `skills/spec/SKILL.md` to prompt
      the operator for checklist items per slice during Step 2 of /spec (1-3 items
      recommended).

      Update `skills/pre-merge-gate/SKILL.md` to:
      (a) Locate the slice in this order:
          1. `--slice <id>` arg if provided;
          2. `.anvil/dispatched-agents.json` exact match (slice id whose `branch` field == current branch name);
          3. error: 'no slice context found; pass --slice <id> or run inside /grind'.
      (b) Parse the checklist via a new `av_parse_slice_checklist` helper in `shared/lib.sh`.
      (c) Run each item; kill on per-item timeout; report pass/fail per item.
      (d) Block merge on any fail; pass through to existing global gates on success.

      Reject `kind:` other than `shell|grep` and `expect:` other than `absent|present` (for grep) with a clear error.

      Smoke test at `tests/smoke/per-slice-checklist.bats`: a plan with a `grep` item
      that should be `absent` but is `present` blocks; the same plan with `expect: present`
      passes. Test the dispatched-agents.json lookup path with a stub json file. Test
      the error path when no slice context is found.
    constraints:
      - "Two kinds only (`shell` + `grep`); reject unknown kinds with clear stderr."
      - "Checklist field is OPTIONAL — slices without it behave exactly as today (silent absence)."
      - "Slice lookup: --slice arg > dispatched-agents.json exact match > error. Do NOT use branch-name prefix matching."
      - "Per-item timeout default 300s; override via `timeout:` field."
      - "Use `av_anvil_root()` if any path resolution needed."
      - "Public-facing OSS."
      - "Test under `tests/smoke/*.bats`."
    acceptance:
      - "Test: failing `grep` checklist item blocks merge."
      - "Test: passing `shell` checklist item unblocks (global gates still run)."
      - "Test: missing checklist field = legacy behaviour, no regression."
      - "Test: slice located via dispatched-agents.json exact match."
      - "Test: --slice arg overrides json lookup."
      - "Test: invalid `kind:` fails loudly."
      - "CHANGELOG entry."
    checklist:
      - kind: grep
        pattern: "checklist:"
        in: "templates/plan-folder-template/tasks.md"
        expect: present
      - kind: grep
        pattern: "av_parse_slice_checklist"
        in: "shared/lib.sh"
        expect: present
      - kind: grep
        pattern: "dispatched-agents.json"
        in: "skills/pre-merge-gate/SKILL.md"
        expect: present
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300
    specs:
      - "../specs/s3-checklists.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S5
    name: /analyze-plan v1 — file-path existence gate
    depends-on: []
    files:
      - skills/analyze-plan/SKILL.md
      - skills/analyze-plan/scripts/extract-paths.sh
      - skills/grind/SKILL.md
      - docs/analyze-plan.md
      - tests/smoke/analyze-plan.bats
    parallelizable: true
    scope: |
      Add a new skill `skills/analyze-plan/SKILL.md` describing `/analyze-plan <plan-path>`.
      v1 scope: file-path verification ONLY. Identifier and numeric-fact verification
      are deferred to a v2 follow-up issue.

      Implement claim extraction in `skills/analyze-plan/scripts/extract-paths.sh`:
      regex-find file paths in the plan text. Conservative regex requirements:
      - Path must contain at least one `/`.
      - Path must end in a recognised extension (`.ts|.js|.sh|.md|.json|.yml|.yaml|.bash|.py|.txt|.bats`).
      - Path must NOT contain placeholder tokens: angle brackets `<...>`, date patterns `\d{4}-\d{2}-\d{2}`, `{...}`.
      - Strip leading `./` and surrounding backticks/quotes.

      For each extracted path, verify: file/dir exists via `test -e`. Emit verdict:
      - `verified` — path exists.
      - `expected-by-slice` — path does NOT exist BUT appears in some slice's `files:` list in the plan's tasks.md (forward-looking).
      - `contradicted` — path does not exist AND not in any slice's `files:` list.
      - `unverifiable` — path matched too loosely (e.g. inside a code fence) — no fact to check.

      Emit a summary report to stdout. Exit non-zero if any `contradicted` verdict found.

      Update `skills/grind/SKILL.md` to run `/analyze-plan` as a pre-execution gate
      (step 0.5), with `--skip-analyze` override flag. On `contradicted` verdict, halt and
      print: "stale claims; either run /refine-plan or /grind --skip-analyze".

      Document in `docs/analyze-plan.md` (v1 scope, what's deferred, FP/FN tradeoff).
    constraints:
      - "v1: file-path verification ONLY. Do NOT extract backticked identifiers or numeric facts."
      - "Conservative regex (extension required, no placeholders, slash required) — false-positive 'unverifiable' beats false-positive 'contradicted'."
      - "Excludes paths cited in plan's slice `files:` lists from `contradicted` (uses `expected-by-slice` instead) to avoid blocking the speckit-gold plan's own grind."
      - "Skill must work without network."
      - "Grind invocation is OPT-OUT (default on); --skip-analyze must work."
      - "Public-facing OSS."
      - "Test under `tests/smoke/*.bats`."
    acceptance:
      - "Test: stale file-path claim (no slice files match) → 'contradicted' verdict + non-zero exit."
      - "Test: existing file-path claim → 'verified' verdict."
      - "Test: path in slice `files:` list but not on disk → 'expected-by-slice' verdict + zero exit."
      - "Test: angle-bracket path (e.g. `<plan>/foo.md`) → not extracted (no verdict)."
      - "Test: `make -C tests smoke` via /grind --skip-analyze bypasses the gate."
      - "Doc: docs/analyze-plan.md exists and explains v1 scope + v2 deferred."
      - "CHANGELOG entry."
    checklist:
      - kind: shell
        run: "test -f skills/analyze-plan/SKILL.md"
        expect: pass
      - kind: shell
        run: "test -x skills/analyze-plan/scripts/extract-paths.sh"
        expect: pass
      - kind: grep
        pattern: "analyze-plan"
        in: "skills/grind/SKILL.md"
        expect: present
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300
    specs:
      - "../specs/s5-analyze-plan.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false
```

---

## Validation checklist

Before locking this plan + running `/grind`:

- [x] `proposal.md` has Goal + Success criteria
- [x] `design.md` has 4 architecture decisions
- [x] Hard constraints non-empty
- [x] Every slice has acceptance criteria
- [x] Slice graph has no cycles (S2 first; S1 + S3 depend on S2; S5 parallel)
- [x] Every dependency edge resolves (S1 depends-on S2 ✓; S3 depends-on S2 ✓)
- [x] No operator-decision points (all locked)
- [x] Parallelisable slices touch non-overlapping files (S5 has zero overlap with S1/S2/S3)
- [x] Out-of-scope items justified
- [x] Spec scenario file for each slice
- [x] Adversarial review pass complete (self-review Opus + hermes-ask cross-family, 2026-05-12). All P0 findings addressed; P1 mitigations documented in design.md.
