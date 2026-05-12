# S2 — Template override hierarchy

**Slice:** S2
**Status:** locked

---

## Background

Anvil ships canonical templates under `templates/` (e.g. `plan-template.md`, `plan-folder-template/`). Today, skills like `/spec` reference these by hard-coded path relative to the anvil install. Adopting projects that want a customised plan shape have to fork anvil. Speckit's 4-layer template override hierarchy is the industry-standard answer; anvil adopts a 3-layer version (project / user-preset / core), enough to cover the real cases without an extension ecosystem to feed the 4th layer.

---

## Scenario — project override wins

**WHEN** a project has a file at `${PWD}/.anvil/templates/overrides/plan-template.md`
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function prints the absolute path to the project's override file
**AND** exits 0

## Scenario — preset wins over core

**WHEN** no project override exists for `plan-template.md`
**AND** a file exists at `${HOME}/.anvil/presets/templates/plan-template.md`
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function prints the path to the preset file
**AND** exits 0

## Scenario — core default fallback

**WHEN** neither project override nor preset exists for `plan-template.md`
**AND** the file exists at `${ANVIL_HOME}/templates/plan-template.md`
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function prints the path to the core file
**AND** exits 0

## Scenario — /spec uses the resolver

**WHEN** the operator invokes `/spec "<intent>"` in a project that has a project-local override of `plan-template.md`

**THEN** `/spec` loads its template from the override path (verifiable by an identifying marker in the override file appearing in the spec's output)
**AND** the spec's generated plan structurally matches the override, not the core default

## Scenario — empty preset layer is silent

**WHEN** `${HOME}/.anvil/presets/` does not exist
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function does NOT emit an error or warning about the missing preset dir
**AND** falls through cleanly to the core layer

---

## Negative case (refusal contract)

**WHEN** a caller invokes `av_resolve_template <name>` where `<name>` does not exist at any layer

**THEN** the function exits non-zero
**AND** prints to stderr: `av_resolve_template: <name> not found in any layer (project: …, preset: …, core: …)`

**WHEN** a caller invokes `av_resolve_template` with a name containing `..` or starting with `/`

**THEN** the function exits non-zero
**AND** prints: `av_resolve_template: refusing path traversal in <name>`
(Defence-in-depth — templates should be relative names, not paths.)
