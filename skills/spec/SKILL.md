---
name: spec
description: Use to capture work intent as a structured plan with explicit slices, dependencies, acceptance criteria, and operator decision points. Interactive — probes for detail until ambiguity is removed. Output is a markdown plan that /grind can execute. Invoke with /spec <intent> or when the operator says "plan this", "spec out X", "let's design before we build", "write the lift plan".
---

# /spec — interactive plan capture

The operator describes intent. This skill probes for the detail an orchestrator needs to act, generates a structured plan markdown file, and presents it for approval.

## When to invoke

- Operator says "plan this", "spec out", "design before we build", "write the lift plan".
- Before any non-trivial multi-PR work (≥3 slices).
- When operator's intent is rough and would benefit from being rigorously elaborated before agents touch code.

## When NOT to use

- Single-PR fixes (just `/dispatch-slice` with the issue).
- Operator gives a fully-formed plan already (just `/grind` it).
- Throwaway exploration ("try this and see what breaks") — `/spec` is for committed work.

## Procedure

### Step 1: Capture intent

Prompt the operator with the project's plan template (from `templates/plan-template.md`). Pre-fill any sections from operator's initial message; leave others blank with placeholder probes.

### Step 2: Probe for missing detail

For each blank section, ask 1-3 specific questions via AskUserQuestion. Examples:

- **Scope** — "What's explicitly out of scope?" (force the operator to draw the line)
- **Architecture decisions** — "Are there alternatives you considered + rejected? Why?"
- **Hard constraints** — "What CAN'T this touch? (DB migrations, vendor APIs, public surface)"
- **Slices** — "How does this decompose? What's the dependency graph?"
- **Acceptance criteria** — for each slice: "What does 'done' look like? What test pins it?"
- **Operator decision points** — "Where would you want to be asked before the orchestrator continues?"

### Step 3: Cross-model challenge (optional)

If `/codex-confer` is available, fire it on the assembled plan with adversarial framing:

```
Argue against this plan. Find what's missing, ambiguous, or under-specified.
What would the orchestrator be unable to act on?
```

Surface the findings; let operator address or dismiss.

### Step 4: Validation gate

Before declaring the plan ready, run a structural lint:

- ✅ Every slice has acceptance criteria
- ✅ Every dependency edge resolves (no orphan refs)
- ✅ No cycles in slice graph
- ✅ Every "ASK" point names what's being asked + provides a default fallback
- ✅ Hard constraints section non-empty
- ✅ Validation checklist itself non-empty (the plan declares its own done-ness criteria)

If any fail: list them, prompt operator to fill them in, loop.

### Step 5: Write the plan file

```
docs/plans/<YYYY-MM-DD>-<slug>.md
```

Slug: 2-3 words capturing the work theme.

### Step 6: Operator approval

Print the path + a summary (slice count, total acceptance criteria, ASK points).

```
Plan written: docs/plans/2026-05-12-anvil-phase2.md
- 7 slices, 23 acceptance criteria
- 2 operator decision points (deploy gate, schema migration)
- 4 hard constraints

Run /grind docs/plans/2026-05-12-anvil-phase2.md to execute, or
/spec --refine <plan-path> "<question>" to iterate.
```

## Plan format

See `templates/plan-template.md` for the canonical shape. Required sections:

```markdown
# <Plan name>

**Status:** draft | locked | executing | complete
**Author:** <name>
**Date:** YYYY-MM-DD
**Worked example:** <link to docs/case-studies/X if any>

## Goal

One paragraph. What does success look like?

## Scope

### In
- Bullet list

### Out
- Bullet list

## Architecture decisions

### Locked
- **Decision:** <name>
  - **What:** <one line>
  - **Why:** <one paragraph>
  - **Rejected alternatives:** <list>

## Hard constraints

- Bullet list. These are inviolable across all slices.

## Slice manifest

For each slice:

```yaml
slices:
  - id: A1
    name: <name>
    depends-on: []
    files: [list of paths]
    scope: |
      <one-paragraph description>
    constraints:
      - bullet list
    acceptance:
      - test: <description>
      - assertion: <description>
    operator-decision:
      ask: <question if pause-needed; null otherwise>
      default: <fallback if operator doesn't respond in N hours>
```

## Validation checklist

- [ ] <criterion>
- [ ] <criterion>

When all checked: plan is "locked" and `/grind` can execute.
```

## Example plans

See `examples/`:
- `operability-plan-example.md` — 11-slice operability lift, real-world test
- `frontend-extraction-plan-example.md` — slow-burn refactor across many sessions

## Composition

`/spec` typically composes:
- AskUserQuestion (interactive probes)
- `/codex-confer` (adversarial pushback)
- File write to `docs/plans/`
- Optional: `/showme` for visual concepts (if plan has a UI/visual component)

`/grind` is the natural next step. `/spec` does NOT auto-invoke `/grind` — operator approval is a deliberate gate.
