# Sample invalid plan

This plan is intentionally broken: missing Goal, missing Hard constraints,
unresolved dependency. Used by the smoke test to confirm validate.sh
returns non-zero on bad plans.

## Scope

### In scope
- Nothing.

### Out of scope
- Everything.

## Slice manifest

```yaml
slices:
  - id: B1
    name: broken slice
    depends-on:
      - DOES-NOT-EXIST
    acceptance: []
    operator-decision:
      ask: "Sure?"
      verbs: []
      default: null
```
