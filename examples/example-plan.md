# Example plan — extract logging into a typed boundary

> A representative anvil plan. The work shape is real (every team eventually does this refactor); the project context is hypothetical so it's transferable to your repo.

**Status:** locked
**Author:** example
**Date:** YYYY-MM-DD
**Plan ID:** logger-boundary
**Related plans:** none

---

## Goal

Replace 80+ direct `console.log` / `console.error` callsites across `src/` with a typed `Logger` boundary. Every call routes through one of four levels (`debug`, `info`, `warn`, `error`); production wires a structured pino-backed logger; tests inject a `recordingLogger` for assertions. Net effect: every production failure log carries the same structured fields, and tests can assert on what would have been logged.

---

## Scope

### In scope
- New `src/logging/logger.ts` exporting a `Logger` interface + `noopLogger()` + `createLogger(config)` factory.
- New `test/helpers/recordingLogger.ts` for test assertions.
- Replace direct console calls in `src/` (NOT `scripts/`, NOT `test/`).
- Add `LOG_LEVEL` env var (parsed in `src/config/index.ts`).
- Architecture-fitness ratchet that fails CI if a new direct `console.log` lands in `src/`.

### Out of scope
- Logging in `scripts/` (one-shot tooling; console is fine).
- Logging in `test/` (test assertions print directly).
- Replacing the existing pino transport — wire to it, don't replace it.
- Migrating logs to a vendor (Datadog / Logtail / etc) — that's a separate plan.

---

## Architecture decisions

### Decision: typed Logger interface
- **What:** a narrow `Logger` interface with `debug | info | warn | error` methods. Each takes `(fields: Record<string, unknown>, message: string)` — pino-style structured logging.
- **Why:** uniform shape across all callsites enables operator-grep on field names. Tests can assert on field presence without depending on pino internals.
- **Rejected alternatives:** raw pino import everywhere (couples test code to pino API); Winston (older API, weaker TypeScript types); homegrown tagged-template (cute, hostile to grep).

### Decision: `noopLogger` as default in test
- **What:** `createLogger(config)` returns a noopLogger when `config.nodeEnv === 'test'` unless the test explicitly injects a `recordingLogger`.
- **Why:** test runs shouldn't dump structured logs to the test console; failures should be assertion-driven, not log-spam-driven.
- **Rejected alternatives:** silent global pino transport (still has log overhead); per-test mute (boilerplate at every callsite).

---

## Hard constraints

- DO NOT remove pino as a dependency — wire to it, don't replace it.
- DO NOT introduce a vendor SDK (Datadog, Sentry, etc) in this plan; out of scope.
- All test counts must increase (no test deletion to lower baseline).
- Architecture fitness ratchets stay green.
- Every replaced console call must preserve its message text + add structured fields explicitly.
- Commit messages follow conventional commits.

---

## Slice manifest

```yaml
slices:
  - id: L1
    name: Logger interface + factory
    depends-on: []
    files:
      - src/logging/logger.ts
      - src/logging/index.ts
      - test/integration/logging/logger.test.ts
    scope: |
      Define the Logger interface, createLogger factory, noopLogger default.
      Wire to pino under the hood. Add config.logLevel parsing.
    constraints:
      - "No vendor SDK imports"
      - "Production logs must include nodeEnv + processRole tags"
    acceptance:
      - "Test: createLogger returns a logger that writes structured pino output"
      - "Test: noopLogger calls are no-ops (no stdout)"
      - "Test: invalid LOG_LEVEL fails boot"
      - "Test count: project baseline + 8"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L2
    name: recordingLogger test helper
    depends-on: [L1]
    files:
      - test/helpers/recordingLogger.ts
      - test/integration/logging/recording-logger.test.ts
    scope: |
      Test seam that captures every log call into an array. Tests assert
      shape: `expect(log.entries).toContainEqual({ level: 'warn', fields: { reason: 'X' } })`.
    constraints:
      - "Pure in-memory; no I/O"
    acceptance:
      - "Test: captures debug/info/warn/error in order"
      - "Test: child logger inherits parent fields"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L3a
    name: replace console in src/auth/
    depends-on: [L1, L2]
    files:
      - src/auth/**
      - test/integration/auth/**
    scope: |
      Replace ~12 console calls in src/auth/ with logger.* calls.
      Tests: assert structured fields on each.
    constraints:
      - "Preserve message text verbatim"
      - "Each replaced call must add at least one structured field"
    acceptance:
      - "Test: every existing auth test still passes"
      - "Test: 12+ new tests asserting structured log shape"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L3b
    name: replace console in src/api/
    depends-on: [L1, L2]
    files:
      - src/api/**
      - test/integration/api/**
    scope: |
      Replace ~30 console calls in src/api/. Same shape as L3a.
    constraints: []
    acceptance:
      - "Test: every existing api test still passes"
      - "Test: ≥20 new tests asserting structured log shape"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L3c
    name: replace console in src/jobs/
    depends-on: [L1, L2]
    files:
      - src/jobs/**
      - test/integration/jobs/**
    scope: |
      Replace ~25 console calls in src/jobs/. Same shape as L3a.
    constraints: []
    acceptance:
      - "Test: every existing jobs test still passes"
      - "Test: ≥15 new tests asserting structured log shape"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L4
    name: fitness ratchet
    depends-on: [L3a, L3b, L3c]
    files:
      - test/architecture/fitness.test.ts
    scope: |
      Architecture-fitness test that scans src/ for direct `console.log`,
      `console.error`, etc. Fails CI if any are present (with allowlist
      via `// fitness-ratchet-allow: console <reason>` comment).
    constraints:
      - "Allowlist must require human-written reason"
    acceptance:
      - "Test: ratchet fails when a deliberate violation is added"
      - "Test: ratchet passes on the post-L3 tree"
    operator-decision: { ask: null, default: null }
    operator-paced: false

  - id: L5
    name: docs + .env.example
    depends-on: [L1, L4]
    files:
      - docs/logging.md
      - .env.example
    scope: |
      Operator-facing docs: how to read structured logs, how to add a
      callsite, how to fly the allowlist for justified violations.
    constraints: []
    acceptance:
      - "Doc covers: levels, fields, filtering, allowlist, vendor-future"
    operator-decision:
      ask: "Should the docs include a vendor-migration section (Datadog/Logtail) to make future migration easier?"
      verbs: [approve, reject, respond]
      default: skip-with-warning
      timeout-hours: 24
    operator-paced: false
```

---

## Validation checklist

- [x] Goal section describes a verifiable end-state (typed Logger boundary in production, ratchet enforced in CI)
- [x] In-scope and Out-of-scope lists both populated
- [x] Architecture decisions documented (2)
- [x] Hard constraints non-empty
- [x] Every slice has acceptance criteria
- [x] Slice graph has no cycles (L1 → L2 → L3a/b/c → L4 → L5)
- [x] L3a/b/c are parallel-safe (independent file paths)
- [x] Operator-decision points: 1 (L5 vendor-migration section)
- [x] Out-of-scope items have implicit follow-ups (vendor migration is its own future plan)

---

## Operator notes

This is a real-world refactor pattern. The shape recurs across many projects — replace ad-hoc logging with a typed boundary so production observability is consistent. Use this plan as a starting template and adapt the file paths + slice counts to your repo.

---

## Followups

(Appended by `/grind` at runtime as issues are filed.)
