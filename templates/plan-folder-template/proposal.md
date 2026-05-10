# <PLAN NAME> — proposal

> The "why." One operator, two minutes, full context. Replace placeholders. Remove sections that don't apply, but justify the deletion in the validation checklist.

**Status:** draft <!-- draft | locked | executing | complete -->
**Author:** <name>
**Date:** YYYY-MM-DD
**Plan ID:** <slug-for-this-plan>
**Layout:** folder <!-- vs flat single-file -->

---

## Goal

One paragraph. What does success look like? End-state in plain English.

---

## Why now

What changed that makes this work worth doing now? Could be:
- Audit finding (link)
- Customer pain (link to issue)
- Strategic dependency (blocks a downstream cutover, unblocks a feature, etc)
- Tech debt forcing function (dependency EOL, deprecated API, etc)

---

## Scope

### In scope
- Bullet list. Be specific.

### Out of scope
- Bullet list. The point of this section is to prevent scope creep mid-grind.

---

## Stakeholders

Who needs to be looped in (operator-decision-points only — agents don't loop in stakeholders, they execute):
- <name/role>: <when they need to be asked>

If only the operator: say so explicitly.

---

## Success criteria

How does the operator confirm success after `/grind` finishes? Checkable:
- [ ] <criterion>
- [ ] <criterion>

This is what `/spec --validate` checks at lock-time. Each item should be observable (test passes, deploy works, metric drops, etc).
