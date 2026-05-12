# <PLAN NAME> — tasks

> The "what." Slice manifest in machine-readable YAML. The orchestrator parses this block.

---

## Slice manifest

```yaml
slices:
  - id: <unique-id>             # e.g. A1, slice-3, fix-csrf
    name: <human readable>      # short title
    depends-on: []              # list of slice ids that must complete first; [] for none
    files: []                   # list of file paths the slice will touch (informational)
    parallelizable: true        # can run in parallel with siblings whose deps are also met
    scope: |
      One paragraph describing what the agent should do in this slice.
      The orchestrator passes this verbatim into the agent prompt.
    constraints:
      - "Per-slice constraint 1"
      - "Per-slice constraint 2"
    acceptance:
      - "Test: integration test asserts X"
      - "Assertion: behaviour Y is preserved"
      - "Test count: N+ passing"
    checklist:                   # optional per-slice acceptance gates enforced by /pre-merge-gate
      # Two kinds:
      #   - `shell` runs a command + expects exit 0 within the per-item
      #     timeout (default 300s; override with `timeout:`).
      #   - `grep` asserts a regex is `present` | `absent` in `in:`.
      #     Optional `count: N` requires exactly N matches (only valid under
      #     `expect: present`).
      # NOTE: `in:` is a directory path, a file path, or a `dir/**` suffix
      # (only the trailing `**` is wildcard-expanded — it is NOT a full glob).
      # Slices without a `checklist:` block behave exactly as today (no
      # warning, no extra processing). Use 1-3 narrow items per slice.
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300              # optional, seconds, default 300
      - kind: grep
        pattern: "TODO\\(slice-id\\)"
        in: "src/**"
        expect: absent            # absent: pattern must NOT match anywhere in `in`
        # `count:` is NOT valid under `expect: absent` — omit it.
      - kind: grep
        pattern: "export const FOO ="
        in: "src/foo.ts"
        expect: present
        count: 1                  # optional, exact match count (only valid under `expect: present`)
    specs:                       # references to scenario files in ../specs/
      - "../specs/<scenario>.md"
    operator-decision:
      ask: null
      verbs: []                  # subset of [approve, edit, reject, respond]
      default: null              # skip-with-warning | retry | abort
      timeout-hours: null
    operator-paced: false        # if true: skip dispatch, mark as needing-human

  - id: <next>
    # ...
```

---

## Validation checklist

Before locking this plan + running `/grind`:

- [ ] `proposal.md` has a verifiable Goal + at least one Success criterion
- [ ] `design.md` has at least one Architecture decision (or this plan is mechanical-only)
- [ ] `design.md` Hard constraints non-empty
- [ ] Every slice has acceptance criteria (≥1 testable item)
- [ ] Slice graph has no cycles
- [ ] Every dependency edge resolves to an existing slice id
- [ ] Every operator-decision point has `ask`, `verbs` (≥1), AND `default`
- [ ] `parallelizable: true` slices touch non-overlapping files (per `files:` list)
- [ ] Out-of-scope items in `proposal.md` have a follow-up plan or "won't do" justification
- [ ] At least one `specs/<scenario>.md` exists for each non-trivial slice (recommended; not required for hello-world plans)

When all are checked: change `proposal.md` Status to `locked` and run `/grind <this-folder>`.
