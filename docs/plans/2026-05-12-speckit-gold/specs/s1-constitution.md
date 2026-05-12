# S1 — Constitution prepended into dispatch brief + prompt-to-disk

**Slice:** S1
**Status:** locked

---

## Background

Anvil's `dispatch-slice` skill composes the agent brief from per-slice scope + per-plan hard constraints + dispatch-defaults boilerplate. Adopting projects use `.anvil/forbidden-patterns.txt`, `dispatch-defaults.txt`, and `known-flakes.txt` for mechanical config, but there is no slot for project-wide *ethos* — the strategic principles a smart engineer would internalise before touching anything. Result: dispatched agents periodically rediscover or violate principles the project considers obvious.

This slice adds `.anvil/constitution.md` as that slot. Crucially, the slice also adds a small but load-bearing mechanical change: the assembled agent prompt is written to `.anvil/dispatched-prompts/<slice-id>.prompt.md` BEFORE the Agent tool is invoked. Without this, the constitution-prepend behaviour is not testable from bats (the prompt string is otherwise an in-memory argument to `Agent()`).

---

## Scenario — constitution present, written to dispatched-prompts

**WHEN** `.anvil/constitution.md` exists in the dispatching repo and contains the marker line `TEST_MARKER_CONSTITUTION`
**AND** the operator invokes `/dispatch-slice S-test --scope "smoke"` (directly or via `/grind`)

**THEN** the file `.anvil/dispatched-prompts/S-test.prompt.md` is created BEFORE the Agent tool is invoked
**AND** the file contains the substring `## Project constitution`
**AND** the file contains the substring `TEST_MARKER_CONSTITUTION`
**AND** the rest of the prompt composition is unchanged (existing hard-constraints, scope, return-shape sections all still present in the on-disk file)

## Scenario — constitution absent

**WHEN** `.anvil/constitution.md` does not exist OR contains only whitespace
**AND** the operator invokes `/dispatch-slice S-test --scope "smoke"`

**THEN** the file `.anvil/dispatched-prompts/S-test.prompt.md` is created BEFORE the Agent tool is invoked
**AND** the file does NOT contain the substring `## Project constitution`
**AND** the prompt body is byte-identical to the prompt that would have been composed without S1's changes (no spurious empty section header, no extra whitespace)

## Scenario — constitution oversize warning (recommended threshold)

**WHEN** `.anvil/constitution.md` exists and exceeds 2048 bytes but is under 8192 bytes
**AND** the operator invokes `/dispatch-slice S-test --scope "smoke"`

**THEN** the file `.anvil/dispatched-prompts/S-test.prompt.md` contains the full constitution (no truncation)
**AND** a warning is printed to stderr matching the pattern `warning: \.anvil/constitution\.md is \d+ bytes \(recommended ≤ 2048\)`
**AND** the dispatch proceeds (warning is non-blocking)

## Scenario — constitution oversize warning (second tier)

**WHEN** `.anvil/constitution.md` exists and exceeds 8192 bytes

**THEN** a stronger warning is printed: `warning: \.anvil/constitution\.md is \d+ bytes — this will bloat every dispatched-agent prompt`
**AND** the dispatch still proceeds (operator's call)

## Scenario — non-UTF-8 constitution is skipped gracefully

**WHEN** `.anvil/constitution.md` exists but contains non-UTF-8 bytes

**THEN** `dispatch-slice` skips the prepend
**AND** prints to stderr: `warning: \.anvil/constitution\.md is not valid UTF-8; skipping prepend`
**AND** the dispatch continues with the legacy brief shape (graceful degradation, not a hard fail)
**AND** `.anvil/dispatched-prompts/<slice-id>.prompt.md` does NOT contain the `## Project constitution` section

## Scenario — init scaffolds the template

**WHEN** the operator runs `bin/init-anvil-config.sh` on a project that does NOT yet have `.anvil/constitution.md`

**THEN** `.anvil/constitution.md` is created from `templates/constitution-template.md` (via `av_resolve_template`)
**AND** the file includes placeholder sections (`## North star`, `## Inviolable principles`, `## Out of scope for every slice`) the operator is meant to fill in
**AND** the file is NOT auto-populated with synthesised content from CLAUDE.md / AGENTS.md / README (this was rejected in adversarial review)

## Scenario — config-bootstrap does NOT touch constitution

**WHEN** the operator invokes `/config-bootstrap` on a project that has CLAUDE.md / AGENTS.md / README

**THEN** `.anvil/forbidden-patterns.txt`, `dispatch-defaults.txt`, and `known-flakes.txt` are generated as today
**AND** `.anvil/constitution.md` is NOT created or modified by `/config-bootstrap`
(Rejected alternative in design.md decision 1.)

---

## Negative case (refusal contract)

**WHEN** the directory `.anvil/dispatched-prompts/` cannot be created (permission denied, disk full)

**THEN** `dispatch-slice` exits non-zero before invoking Agent
**AND** prints: `error: cannot write to .anvil/dispatched-prompts/: <reason>`
(Hard fail — without the on-disk prompt, the constitution feature has no testable footprint.)
