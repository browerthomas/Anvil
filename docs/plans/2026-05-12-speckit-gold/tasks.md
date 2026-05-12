# speckit-gold — tasks

> Five slices. S2 → S3 → S4 serialised on `skills/spec/SKILL.md` to avoid rebase churn. S1 and S5 parallelisable against everything.

---

## Slice manifest

```yaml
slices:
  - id: S2
    name: Template override hierarchy
    depends-on: []
    files:
      - shared/lib.sh
      - skills/spec/SKILL.md
      - docs/template-overrides.md
      - tests/template-overrides.bats
    parallelizable: true
    scope: |
      Add `av_resolve_template <name>` to `shared/lib.sh` implementing a 3-layer
      resolver: `${PWD}/.anvil/templates/overrides/<name>` → `${HOME}/.anvil/presets/templates/<name>`
      → `${ANVIL_HOME}/templates/<name>`. `ANVIL_HOME` defaults to anvil's install
      root (derive from the location of `shared/lib.sh`). First hit wins. Update
      `skills/spec/SKILL.md` so its template-load step uses the resolver instead
      of a hard-coded path. Document the hierarchy in `docs/template-overrides.md`.
      Add a bats smoke test that drops a stub template into a temp project's
      `.anvil/templates/overrides/` and asserts it wins over the core default.
    constraints:
      - "Bash-only; no Node helper."
      - "Resolver returns the resolved path; caller `cat`s it."
      - "Empty preset layer (no `~/.anvil/presets/`) must not error."
      - "Test under tests/ + entry in tests/run.sh."
    acceptance:
      - "Test: `av_resolve_template plan-template.md` returns project override when present."
      - "Test: returns core default when no override exists."
      - "Test: returns preset path when only preset layer exists."
      - "Doc: docs/template-overrides.md explains the precedence order."
      - "No regression in tests/run.sh."
    checklist:
      - kind: grep
        pattern: "av_resolve_template"
        in: "shared/lib.sh"
        expect: present
      - kind: grep
        pattern: "av_resolve_template"
        in: "skills/spec/SKILL.md"
        expect: present
      - kind: shell
        run: "bash tests/run.sh"
        expect: pass
    specs:
      - "../specs/s2-template-overrides.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S1
    name: Constitution artifact pinned into dispatch brief
    depends-on: []
    files:
      - templates/constitution-template.md
      - shared/lib.sh
      - skills/dispatch-slice/SKILL.md
      - skills/config-bootstrap/SKILL.md
      - bin/init-anvil-config.sh
      - tests/constitution.bats
    parallelizable: true
    scope: |
      Add `.anvil/constitution.md` as a new project-local artifact. Ship a canonical
      `templates/constitution-template.md` that explains the slot (project ethos / north
      star / inviolable principles — strategic, not mechanical). Add `av_load_constitution`
      to `shared/lib.sh` that reads `.anvil/constitution.md` if present (returns its
      contents; empty string if absent). Update `skills/dispatch-slice/SKILL.md`'s agent
      brief construction to prepend the constitution under a `## Project constitution`
      header when non-empty. Update `skills/config-bootstrap/SKILL.md` to generate
      `.anvil/constitution.md` alongside the existing three config files, synthesised
      from the same source docs (CLAUDE.md / AGENTS.md / README) but flagged with a
      "review me — these are operator-stated ethos" header. Update `bin/init-anvil-config.sh`
      to scaffold the constitution.md from the template on first init.
    constraints:
      - "Backward-compatible: existing `.anvil/` files keep their shape."
      - "Empty/missing constitution.md = no-op (no brief change)."
      - "Constitution prepend ≤ 2KB recommended; dispatch-slice prints a warning if larger."
      - "Public-facing OSS: no project-private refs in template or examples."
      - "Test under tests/ + entry in tests/run.sh."
    acceptance:
      - "Test: dispatch-slice brief contains constitution content when .anvil/constitution.md exists."
      - "Test: brief is unchanged when the file is absent."
      - "Test: size-warning fires when constitution > 2KB."
      - "Doc: CHANGELOG entry under next minor version."
    checklist:
      - kind: grep
        pattern: "av_load_constitution"
        in: "shared/lib.sh"
        expect: present
      - kind: grep
        pattern: "constitution"
        in: "skills/dispatch-slice/SKILL.md"
        expect: present
      - kind: shell
        run: "test -f templates/constitution-template.md"
        expect: pass
      - kind: shell
        run: "bash tests/run.sh"
        expect: pass
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
      - tests/per-slice-checklist.bats
    parallelizable: false
    scope: |
      Extend the slice-manifest YAML schema with a `checklist:` field — a list of items
      where each item is `{kind: shell, run: "<cmd>", expect: pass}` OR
      `{kind: grep, pattern: "<regex>", in: "<glob>", expect: absent|present, count?: N}`.
      Update `templates/plan-template.md` and `templates/plan-folder-template/tasks.md`
      to show the field in the example slice. Update `skills/spec/SKILL.md` to prompt
      the operator for checklist items per slice (1-3 items recommended). Update
      `skills/pre-merge-gate/SKILL.md` to (a) locate the slice by branch name OR
      `--slice <id>` arg OR `--plan <path>` arg, (b) parse the checklist via a new
      `av_parse_slice_checklist` helper in `shared/lib.sh`, (c) run each item, (d)
      report pass/fail per item, (e) block merge on any fail. Smoke test: a plan with
      a `grep` checklist item against a pattern present in source must fail when
      `expect: absent`, pass when `expect: present`.
    constraints:
      - "Two kinds only (`shell` + `grep`); reject unknown kinds with a clear error."
      - "Checklist field is OPTIONAL — slices without it behave exactly as today."
      - "When `--slice` not given, pre-merge-gate matches branch name to slice id."
      - "Public-facing OSS."
      - "Test under tests/ + entry in tests/run.sh."
    acceptance:
      - "Test: failing `grep` checklist item blocks merge."
      - "Test: passing `shell` checklist item unblocks."
      - "Test: missing checklist field = legacy behaviour, no regression."
      - "Doc: CHANGELOG entry."
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
        pattern: "checklist"
        in: "skills/pre-merge-gate/SKILL.md"
        expect: present
      - kind: shell
        run: "bash tests/run.sh"
        expect: pass
    specs:
      - "../specs/s3-checklists.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S4
    name: /clarify skill — interrogation separated from specification
    depends-on: [S3]
    files:
      - skills/clarify/SKILL.md
      - skills/clarify/scripts/.gitkeep
      - skills/spec/SKILL.md
      - docs/clarify-then-spec.md
      - tests/clarify.bats
    parallelizable: false
    scope: |
      Add a new skill `skills/clarify/SKILL.md` describing the `/clarify "<intent>"`
      flow: sequential `AskUserQuestion` rounds (4 max per round, 3 rounds max) covering
      goal, scope-cuts, constraints, success criteria. Writes a transcript at
      `docs/plans/.clarify/<YYYY-MM-DD>-<slug>.md` with `## Question` / `## Answer`
      pairs and a `## Derived facts` synthesis at the end. Update `skills/spec/SKILL.md`
      with a new `--clarify-file <path>` arg that pre-populates the spec draft from
      the transcript's Derived facts and skips re-asking covered questions. Document
      the flow in `docs/clarify-then-spec.md`. Smoke test: writing a fixture transcript
      and confirming spec consumes it (assertion on derived-facts pre-population).
    constraints:
      - "Transcript is markdown; greppable and diffable."
      - "Skill-only addition; no shared/lib.sh changes required (spec consumes via file read)."
      - "Public-facing OSS."
      - "Test under tests/ + entry in tests/run.sh."
    acceptance:
      - "Test: /clarify produces a transcript file with the expected sections."
      - "Test: /spec --clarify-file <path> reads it without erroring."
      - "Doc: docs/clarify-then-spec.md exists with example."
      - "Doc: CHANGELOG entry."
    checklist:
      - kind: shell
        run: "test -f skills/clarify/SKILL.md"
        expect: pass
      - kind: grep
        pattern: "clarify-file"
        in: "skills/spec/SKILL.md"
        expect: present
      - kind: shell
        run: "test -f docs/clarify-then-spec.md"
        expect: pass
      - kind: shell
        run: "bash tests/run.sh"
        expect: pass
    specs:
      - "../specs/s4-clarify.md"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: S5
    name: /analyze-plan skill — lock-time claim consistency gate
    depends-on: []
    files:
      - skills/analyze-plan/SKILL.md
      - skills/analyze-plan/scripts/extract-claims.sh
      - skills/grind/SKILL.md
      - docs/analyze-plan.md
      - tests/analyze-plan.bats
    parallelizable: true
    scope: |
      Add a new skill `skills/analyze-plan/SKILL.md` describing `/analyze-plan <plan-path>`.
      Implement claim extraction in `skills/analyze-plan/scripts/extract-claims.sh`:
      regex-find file paths (containing `/` and a recognised extension), backticked
      identifiers (function/file names), and numeric facts ("N lines", "M slices",
      "K tests"). For each claim, verify: file paths via `test -e`; identifiers via
      `grep -r`; numeric facts via the corresponding command (`wc -l`, slice count from
      tasks.md, test count from `tests/run.sh --count` or stub if not yet defined).
      Report per-claim verdict: verified / contradicted / unverifiable. Update
      `skills/grind/SKILL.md` to run `/analyze-plan` as a pre-execution gate (step 0.5),
      with `--skip-analyze` override flag. Document in `docs/analyze-plan.md`. Smoke
      test: a plan citing a non-existent file must report `contradicted`; a plan citing
      an existing file path must report `verified`.
    constraints:
      - "Conservative regex — false-positive 'unverifiable' beats false-positive 'contradicted'."
      - "Skill must work without network (no gh/no remote calls)."
      - "Grind invocation is OPT-OUT (default on); --skip-analyze must work."
      - "Public-facing OSS."
      - "Test under tests/ + entry in tests/run.sh."
    acceptance:
      - "Test: stale file-path claim → 'contradicted' verdict."
      - "Test: correct file-path claim → 'verified' verdict."
      - "Test: prose claim with no fact-like tokens → 'unverifiable' (or skipped)."
      - "Test: grind --skip-analyze bypasses the gate."
      - "Doc: CHANGELOG entry."
    checklist:
      - kind: shell
        run: "test -f skills/analyze-plan/SKILL.md"
        expect: pass
      - kind: shell
        run: "test -x skills/analyze-plan/scripts/extract-claims.sh"
        expect: pass
      - kind: grep
        pattern: "analyze-plan"
        in: "skills/grind/SKILL.md"
        expect: present
      - kind: shell
        run: "bash tests/run.sh"
        expect: pass
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

- [x] `proposal.md` has Goal + Success criteria
- [x] `design.md` has 5 architecture decisions
- [x] Hard constraints non-empty
- [x] Every slice has acceptance criteria
- [x] Slice graph has no cycles (S2 → S3 → S4 chain; S1 + S5 parallel)
- [x] Every dependency edge resolves (S3 depends-on S2 ✓; S4 depends-on S3 ✓)
- [x] No operator-decision points in this plan (all locked — operator already approved scope)
- [x] Parallelisable slices touch non-overlapping files (S1 vs S5 share zero files; S1 vs S2 share `shared/lib.sh` only — serialise via `parallelizable: true` but coordinate at rebase time)
- [x] Out-of-scope items justified
- [x] Spec scenario file for each slice
