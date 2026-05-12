# <PLAN NAME>

> Replace placeholders. Delete sections that don't apply, but justify the deletion in the validation checklist.

**Status:** draft <!-- draft | locked | executing | complete -->
**Author:** <name>
**Date:** YYYY-MM-DD
**Plan ID:** <slug-for-this-plan>
**Related plans:** <list any predecessor or sibling plans, or `none`>

---

## Goal

One paragraph. What does success look like? End-state in plain English. The orchestrator's "did we succeed?" question gets answered against this paragraph.

---

## Scope

### In scope
- Bullet list. Be specific.
- Files / surfaces / behaviour changes that this plan WILL touch.

### Out of scope
- Bullet list. Be more specific.
- The point of this section is to prevent scope-creep mid-grind.

---

## Architecture decisions

For each non-trivial decision, name it + lock it + explain alternatives rejected.

### Decision: <short name>
- **What:** one-line summary
- **Why:** one paragraph
- **Rejected alternatives:** bullet list with one line each on why each was passed

(Repeat for each decision. If only one decision, that's fine.)

---

## Hard constraints

Inviolable rules across all slices in this plan. The orchestrator passes these to every agent dispatch.

- Bullet list.
- Use the project's fitness ratchets as a starting point (no <deprecated-data-shape>
- Add per-plan constraints (e.g. "this slice cannot touch the schema_version", "no new env vars", "test target = N+ passing").

---

## Slice manifest

Machine-readable. The orchestrator parses this YAML block.

```yaml
slices:
  - id: <unique-id>             # e.g. A1, slice-3, fix-csrf
    name: <human readable>      # short title
    depends-on: []              # list of slice ids that must complete first; [] for none
    files: []                   # list of file paths the slice will touch (informational, not enforced)
    scope: |
      One paragraph describing what the agent should do in this slice.
      The orchestrator passes this verbatim into the agent prompt.
    constraints:
      - "Per-slice constraint 1"
      - "Per-slice constraint 2"
    acceptance:
      - "Test: integration test asserts X"
      - "Assertion: behaviour Y is preserved"
      - "Test count: 906+ passing"
    checklist:                    # optional per-slice acceptance gates enforced by /pre-merge-gate
      # Two kinds: `shell` (run a command, expect exit 0) and `grep`
      # (assert a regex is present | absent in a path glob). Slices without
      # a `checklist:` block behave exactly as today — silent absence.
      - kind: shell
        run: "make -C tests smoke"
        expect: pass
        timeout: 300              # optional, seconds, default 300
      - kind: grep
        pattern: "TODO\\(slice-id\\)"
        in: "src/**"
        expect: absent            # absent | present
        count: 1                  # optional, exact match count when expect: present
    operator-decision:
      ask: null              # if non-null: orchestrator pauses + asks operator before this slice
      verbs: []              # subset of [approve, edit, reject, respond] — operator's valid answers
      default: null          # fallback if operator unreachable (skip-with-warning | retry | abort)
      timeout-hours: null    # if set: apply default after N hours of no operator response
    operator-paced: false    # if true: orchestrator skips dispatch, marks slice as needing-human

  - id: <next>
    # ...
```

---

## Validation checklist

The plan is "locked" when all of these are true:

- [ ] Goal section describes a verifiable end-state
- [ ] In-scope and Out-of-scope lists are both populated
- [ ] At least one architecture decision is documented
- [ ] Hard constraints section is non-empty
- [ ] Every slice has acceptance criteria (≥1 testable item)
- [ ] Slice graph has no cycles
- [ ] Every dependency edge resolves to an existing slice id
- [ ] Every operator-decision point has `ask`, `verbs` (≥1), AND `default`
- [ ] Out-of-scope items have a follow-up plan or "won't do" justification

When all are checked: change Status to `locked` and run `/grind <this-plan>.md`.

---

## Operator notes

Free-form. Anything the operator wants to remember about why this plan exists, who asked for it, what came before, what comes after.

---

## Operator decision records

Structured artifacts from `operator-decision.ask` invocations during execution. The orchestrator appends one entry per decision point reached. Shape:

```
### <slice-id> — <ask question> @ <iso-timestamp>
- Verb: approve | edit | reject | respond
- Response: <operator's free-text answer, or "(default applied)" if timeout fired>
- Outcome: slice continued | slice deferred | plan halted
```

`/recap` surfaces this list as a "Decisions" section in the visual report.

- (none yet)

## Followups

Issues filed during execution that didn't fit in scope. Link as they're created. The orchestrator appends here automatically.

- (none yet)
