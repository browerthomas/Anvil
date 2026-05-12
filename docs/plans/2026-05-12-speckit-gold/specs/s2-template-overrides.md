# S2 — Template override hierarchy (2-layer)

**Slice:** S2
**Status:** locked

---

## Background

Anvil ships canonical templates under `templates/` (e.g. `plan-template.md`, `plan-folder-template/`). Today, skills like `/spec` reference these by hard-coded path relative to the anvil install. Adopting projects that want a customised plan shape have to fork anvil. A 2-layer resolver (project override → core default) covers every real use today; the preset layer in spec-kit assumes an extension ecosystem anvil doesn't have, and adding it preemptively would create dead documentation and an unexercised codepath.

The resolver reuses anvil's existing `av_anvil_root()` (at `shared/lib.sh:144`) and the canonical `ANVIL_ROOT` env var. Do NOT introduce a new `ANVIL_HOME` variable — `ANVIL_HOME` is already used in 15+ files with a different meaning (Claude install dir fallback in the bin/ scripts).

---

## Scenario — project override wins

**WHEN** a project has a file at `${PWD}/.anvil/templates/overrides/plan-template.md` containing the marker `OVERRIDE_MARKER`
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function prints the absolute path to the project's override file on stdout
**AND** exits 0
**AND** `cat $(av_resolve_template plan-template.md)` contains `OVERRIDE_MARKER`

## Scenario — core default fallback

**WHEN** no project override exists for `plan-template.md`
**AND** the file exists at `$(av_anvil_root)/templates/plan-template.md`
**AND** a caller invokes `av_resolve_template plan-template.md`

**THEN** the function prints the path to the core file on stdout
**AND** exits 0

## Scenario — /spec uses the resolver

**WHEN** the operator invokes `/spec "<intent>"` in a project that has a project-local override of `plan-template.md` containing the marker `SPEC_TEST_MARKER`

**THEN** `/spec` loads its template via `av_resolve_template plan-template.md`
**AND** the generated plan structurally reflects the override (verifiable by `SPEC_TEST_MARKER` appearing in the spec's output)

## Scenario — preset layer deferred (negative case for premature feature)

**WHEN** `${HOME}/.anvil/presets/templates/plan-template.md` exists but no project override exists

**THEN** the function falls through to the core default (preset layer is NOT searched in v1)
**AND** prints the core path
**AND** exits 0
(Preset layer adoption deferred to a follow-up issue, per design.md decision 2.)

---

## Negative case (refusal contract)

**WHEN** a caller invokes `av_resolve_template <name>` where `<name>` does not exist at any layer

**THEN** the function exits non-zero
**AND** prints to stderr: `av_resolve_template: <name> not found (project: <path>, core: <path>)`

**WHEN** a caller invokes `av_resolve_template ../foo` or `av_resolve_template /etc/passwd`

**THEN** the function exits non-zero before any filesystem access
**AND** prints: `av_resolve_template: refusing path traversal in <name>`

**WHEN** a caller invokes `av_resolve_template` with no argument

**THEN** the function exits non-zero
**AND** prints: `av_resolve_template: missing template name argument`

**WHEN** the test suite greps the codebase for `ANVIL_HOME`

**THEN** the new code in `shared/lib.sh` MUST NOT introduce any reference to `ANVIL_HOME`
(Use `ANVIL_ROOT` / `av_anvil_root()` exclusively. Verified via the slice checklist: `grep "ANVIL_HOME" shared/lib.sh expect: absent`.)
