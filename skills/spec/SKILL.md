---
name: spec
description: Use to capture work intent as a structured plan with explicit slices, dependencies, acceptance criteria, and operator decision points. Interactive — probes for detail until ambiguity is removed. Output is a markdown plan that /grind can execute. Invoke with /spec <intent> or when the operator says "plan this", "spec out X", "let's design before we build", "write the lift plan".
---

# /spec — interactive plan capture

The operator describes intent. This skill probes for the detail an orchestrator needs to act, generates a structured plan, and presents it for approval.

Two output layouts:

- **Flat** (default for plans <5 slices, no architecture decisions): a single markdown file at `docs/plans/<YYYY-MM-DD>-<slug>.md` built from `templates/plan-template.md`.
- **Folder** (OpenSpec-style, default for plans with ≥2 architecture decisions or ≥5 slices): a directory at `docs/plans/<YYYY-MM-DD>-<slug>/` with `proposal.md` + `design.md` + `tasks.md` + `specs/<scenario>.md` files, built from `templates/plan-folder-template/`.

`/grind` reads both layouts transparently — point it at a file or a directory, it figures out the rest. The folder layout is recommended when the adversarial reviewer should compare execution against explicit acceptance scenarios (the `specs/` files).

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

Resolve the plan template via the 2-layer template resolver — project overrides win, core default falls back:

```bash
# ANVIL_ROOT is exported by anvil's installer (bin/install.sh writes it
# into the per-prefix anvil-config.sh). Sourcing via $(git rev-parse
# --show-toplevel)/shared/lib.sh would resolve to the ADOPTING project's
# git root — which doesn't ship shared/lib.sh. Use ANVIL_ROOT.
source "${ANVIL_ROOT:?ANVIL_ROOT not set — run bin/install.sh first}/shared/lib.sh"
PLAN_TEMPLATE="$(av_resolve_template plan-template.md)"
# For folder-layout plans, resolve each file under the folder template:
FOLDER_PROPOSAL="$(av_resolve_template plan-folder-template/proposal.md)"
FOLDER_DESIGN="$(av_resolve_template plan-folder-template/design.md)"
FOLDER_TASKS="$(av_resolve_template plan-folder-template/tasks.md)"
```

`av_resolve_template <name>` searches `${PWD}/.anvil/templates/overrides/<name>` first, then `$(av_anvil_root)/templates/<name>`. Projects that want a customised plan shape drop their override under `.anvil/templates/overrides/` without forking anvil — see `docs/template-overrides.md`.

Prompt the operator with the resolved template. Pre-fill any sections from operator's initial message; leave others blank with placeholder probes.

### Step 2: Probe for missing detail

For each blank section, ask 1-3 specific questions via AskUserQuestion. Examples:

- **Scope** — "What's explicitly out of scope?" (force the operator to draw the line)
- **Architecture decisions** — "Are there alternatives you considered + rejected? Why?"
- **Hard constraints** — "What CAN'T this touch? (DB migrations, vendor APIs, public surface)"
- **Slices** — "How does this decompose? What's the dependency graph?"
- **Acceptance criteria** — for each slice: "What does 'done' look like? What test pins it?"
- **Per-slice checklist items** — for each slice with a non-trivial change, ask: "Are there 1-3 narrow, scriptable acceptance gates `/pre-merge-gate` should run before merge?" Two kinds are supported:
  - **`shell`** — run a command, expect exit 0 within a per-item timeout (default 300s).
    Example: `{kind: shell, run: "make -C tests smoke", expect: pass}` — re-runs the smoke suite from the worktree before approving merge.
    Example: `{kind: shell, run: "npm run lint", expect: pass, timeout: 60}` — short lint gate with override timeout.
  - **`grep`** — assert a regex is `absent` or `present` in a file-glob. Optional `count: N` requires exactly N matches.
    Example: `{kind: grep, pattern: "console\\.log", in: "src/**", expect: absent}` — block merge if a debug log leaked in.
    Example: `{kind: grep, pattern: "registerHandler", in: "src/dispatch.ts", expect: present, count: 1}` — assert the slice's new handler is wired in exactly once.

  These are written as `checklist:` under the slice in the YAML manifest (see `templates/plan-template.md` / `templates/plan-folder-template/tasks.md` for the schema). Leave the field off entirely for slices that need no bespoke gate — `/pre-merge-gate` silently skips per-slice checks when no `checklist:` is present.
- **Operator decision points** — "Where would you want to be asked before the orchestrator continues?"

### Step 3: Adversarial challenge

The plan needs a second pair of eyes BEFORE lock — under-specified slices become broken PRs. Two paths, in priority order:

**Preferred:** `/codex-confer` for cross-model pushback. Fire it with adversarial framing:

```
Argue against this plan. Find what's missing, ambiguous, or under-specified.
What would the orchestrator be unable to act on?
Read the four plan files (proposal.md, design.md, tasks.md, specs/*.md) before answering.
```

**Fallback** (codex rate-limited, network outage, or the codex-shared helper errors): run `/self-review` against the plan files instead. Read every plan file, then self-adversarially push back through the four critic lenses (correctness / security / test-coverage / architecture). Treat the plan files as a "diff" — what's the architectural-fit critic seeing? what's missing in the test-coverage critic's view? Write findings as P0/P1/P2 against the plan; iterate before locking.

**Treat exit code != 0 from `/codex-confer` as "unavailable"** and switch to the fallback automatically. Do NOT let codex unavailability silently skip the adversarial pass — an un-challenged plan is worse than a plan with no validation pass at all, because the operator assumes it was reviewed.

In either path, surface findings, iterate, and document the dismissed ones. The plan file's `## Operator decision records` (or commit message if not yet locked) should note which path was taken.

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
Plan written: docs/plans/<YYYY-MM-DD>-<slug>.md
- N slices, M acceptance criteria
- K operator decision points
- L hard constraints

Run /grind docs/plans/<YYYY-MM-DD>-<slug>.md to execute, or
/spec --refine <plan-path> "<question>" to iterate.
```

## Plan format

The canonical shape lives at `templates/plan-template.md` (core default). Resolve at runtime via `av_resolve_template plan-template.md` so a project override under `.anvil/templates/overrides/plan-template.md` wins if present. Required sections:

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
    checklist:                 # optional, enforced by /pre-merge-gate
      - kind: shell            # or `grep`
        run: <command>
        expect: pass
        timeout: 300           # optional, default 300s
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
- `example-plan.md` — multi-slice flat-layout example (logger-boundary refactor)
- `hello-world-plan.md` — single-slice plan to verify your install

## Composition

`/spec` typically composes:
- AskUserQuestion (interactive probes)
- `/codex-confer` (adversarial pushback)
- File write to `docs/plans/`
- Optional: `/showme` for visual concepts (if plan has a UI/visual component)

`/grind` is the natural next step. `/spec` does NOT auto-invoke `/grind` — operator approval is a deliberate gate.
