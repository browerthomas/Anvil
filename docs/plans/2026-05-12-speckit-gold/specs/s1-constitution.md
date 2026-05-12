# S1 — Constitution prepended into every dispatch brief

**Slice:** S1
**Status:** locked

---

## Background

Anvil's `dispatch-slice` skill currently composes the agent brief from per-slice scope + per-plan hard constraints + a small amount of dispatch-defaults boilerplate. Adopting projects use `.anvil/forbidden-patterns.txt`, `dispatch-defaults.txt`, and `known-flakes.txt` for mechanical config, but there is no slot for project-wide *ethos* — the strategic principles a smart engineer would internalise before touching anything. Result: dispatched agents periodically rediscover or violate principles the project considers obvious.

---

## Scenario — constitution present

**WHEN** `.anvil/constitution.md` exists in the dispatching repo and contains non-empty content
**AND** the operator invokes `/dispatch-slice <id>` (directly or via `/grind`)

**THEN** the composed agent brief contains a `## Project constitution` section near the top (before per-slice scope)
**AND** the section body equals the contents of `.anvil/constitution.md` verbatim
**AND** the rest of the brief composition is unchanged (existing hard-constraints, scope, return-shape sections all still present)

## Scenario — constitution absent

**WHEN** `.anvil/constitution.md` does not exist OR is empty
**AND** the operator invokes `/dispatch-slice <id>`

**THEN** the composed agent brief does NOT contain a `## Project constitution` section
**AND** the brief is byte-identical to the brief that would have been composed without S1's changes (no spurious whitespace, no empty section header)

## Scenario — constitution oversize warning

**WHEN** `.anvil/constitution.md` exists and exceeds 2KB
**AND** the operator invokes `/dispatch-slice <id>`

**THEN** the brief still contains the full constitution prepended (no truncation)
**AND** a warning is printed to stderr: `warning: .anvil/constitution.md is N bytes (recommended ≤ 2048)`
**AND** the dispatch proceeds (warning is non-blocking)

## Scenario — config-bootstrap generates the file

**WHEN** the operator invokes `/config-bootstrap` on a project that has `CLAUDE.md` or `AGENTS.md` or `README.md` but no `.anvil/constitution.md`

**THEN** `.anvil/constitution.md` is created
**AND** its first line is `<!-- review me — this is operator-stated ethos, synthesised from project docs -->`
**AND** its body is a synthesis (5-15 lines) of the project's strategic principles drawn from the source docs

## Scenario — init scaffolds the template

**WHEN** the operator runs `bin/init-anvil-config.sh` on a project that does NOT yet have `.anvil/constitution.md`

**THEN** `.anvil/constitution.md` is created with the content of `templates/constitution-template.md`
**AND** the template includes placeholder sections (`## North star`, `## Inviolable principles`, `## Out of scope for every slice`) the operator is meant to fill in

---

## Negative case (refusal contract)

**WHEN** `.anvil/constitution.md` exceeds 8KB

**THEN** `dispatch-slice` still proceeds (no hard block — operator's call)
**AND** a stronger warning is printed: `warning: .anvil/constitution.md is N bytes — this will bloat every dispatched-agent prompt`

**WHEN** `.anvil/constitution.md` contains non-UTF-8 bytes

**THEN** `dispatch-slice` skips the prepend with a warning: `warning: .anvil/constitution.md is not valid UTF-8; skipping prepend`
**AND** the dispatch continues with the legacy brief shape (graceful degradation, not a hard fail)
