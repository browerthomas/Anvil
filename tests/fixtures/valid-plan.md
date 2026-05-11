# Sample valid plan

**Status:** locked
**Author:** test
**Date:** 2026-05-11
**Plan ID:** smoke-test-fixture

---

## Goal

A minimal plan that passes `spec/scripts/validate.sh` without errors. Used by
the smoke test for the spec skill.

---

## Scope

### In scope
- Demonstrates two slices with a dependency edge.
- Includes an operator-decision shape on one slice.

### Out of scope
- Anything else.

---

## Architecture decisions

### Decision: keep it small
- **What:** two slices, one dependency.
- **Why:** smoke-test fixture must not have semantic complexity.
- **Rejected alternatives:** larger plan (would be redundant).

---

## Hard constraints

- All slices must have acceptance criteria.
- No cyclic dependencies.

---

## Slice manifest

```yaml
slices:
  - id: A1
    name: first slice
    depends-on: []
    files: []
    scope: |
      Initial slice with no dependencies.
    constraints:
      - "no new env vars"
    acceptance:
      - "Test: A1 ships a hello world"
    operator-decision:
      ask: null
      verbs: []
      default: null
      timeout-hours: null
    operator-paced: false

  - id: A2
    name: second slice
    depends-on:
      - A1
    files: []
    scope: |
      Depends on A1 — proves the dependency graph parses.
    constraints:
      - "depends on A1"
    acceptance:
      - "Test: A2 ships after A1"
    operator-decision:
      ask: "Should A2 ship now?"
      verbs:
        - approve
        - reject
      default: skip-with-warning
      timeout-hours: 24
    operator-paced: false
```
