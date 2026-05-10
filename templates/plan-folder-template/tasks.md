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
