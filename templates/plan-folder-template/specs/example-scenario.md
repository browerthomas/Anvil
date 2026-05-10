# <Scenario name>

> One scenario file per non-trivial behaviour change. The adversarial reviewer compares the slice's implementation against these — execution must satisfy every WHEN/THEN below.

**Slice:** <slice-id>
**Status:** locked

---

## Background

What state must hold before this scenario applies. One paragraph.

---

## Scenario

**WHEN** <preconditions / trigger>
**AND** <additional preconditions>

**THEN** <observable outcome>
**AND** <additional outcome>

---

## Negative case (refusal contract)

**WHEN** <invalid input or precondition violation>

**THEN** <specific error / rejection>
**AND** <state remains unchanged>

---

## Edge cases

For each surprising-but-real case:

### Edge: <one-line description>
**WHEN** <edge condition>
**THEN** <expected handling>
