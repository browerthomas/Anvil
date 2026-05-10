# Hello-world plan — verify your anvil install

> A minimal single-slice plan you can run end-to-end to verify your anvil install works against your repo. Designed to fit in 30 minutes wall-clock.

**Status:** locked
**Author:** anvil
**Date:** YYYY-MM-DD
**Plan ID:** hello-world

---

## Goal

Add a `CONTRIBUTING.md` to your repo if one doesn't exist. Single slice, single PR, verifiable in one `/grind` invocation. Confirms that `/spec` produced this plan, `/dispatch-slice` can dispatch an agent, `/pre-merge-gate` can check the PR, and `/auto-merge` can land it.

---

## Scope

### In scope
- A `CONTRIBUTING.md` at the repo root that explains how a new contributor would clone, install deps, run tests, and open a PR.

### Out of scope
- Any code changes. Documentation only.
- Updating existing CONTRIBUTING.md if one already exists (skill should detect + skip).

---

## Architecture decisions

### Decision: docs-only PR
- **What:** This plan ships a markdown file. No code touched.
- **Why:** Trivial scope to verify the orchestration plumbing without any risk of breaking the project.
- **Rejected alternatives:** Adding a small code change (e.g. a fitness ratchet) — too much surface area for a sanity check.

---

## Hard constraints

- DO NOT touch any file other than `CONTRIBUTING.md`.
- DO NOT run any test suite — there's nothing to test in a docs-only change.
- The CONTRIBUTING.md must be at least 50 lines and cover: clone, install, test, lint, PR.
- Commit message format: `docs: add CONTRIBUTING.md`.

---

## Slice manifest

```yaml
slices:
  - id: H1
    name: Add CONTRIBUTING.md
    depends-on: []
    files:
      - CONTRIBUTING.md
    scope: |
      If CONTRIBUTING.md does not exist at repo root, add one with the
      following sections:
        1. Welcome / overview
        2. Quickstart (clone, install, test)
        3. PR conventions (commit format, branch naming)
        4. Code of conduct (1 paragraph)

      Tone: friendly, terse, factual. Match the project's existing
      docs voice (read README.md to calibrate).

      If CONTRIBUTING.md already exists, EXIT EARLY without changes
      and report "already exists, no-op" in the agent return.
    constraints:
      - "Only touch CONTRIBUTING.md"
      - "Don't run any code-execution commands"
      - "Match existing docs voice (read README.md first)"
    acceptance:
      - "File CONTRIBUTING.md exists at repo root"
      - "File is ≥ 50 lines"
      - "Sections present: clone/install/test/PR/conduct"
      - "Commit message: docs: add CONTRIBUTING.md"
    operator-decision:
      ask: null
      default: null
    operator-paced: false
```

---

## Validation checklist

- [x] Goal is verifiable (CONTRIBUTING.md exists)
- [x] Scope is one slice
- [x] Hard constraints prevent scope creep
- [x] Acceptance criteria are concrete + checkable
- [x] No operator decision points (autonomous run)

When `/grind` finishes:
- A PR titled `docs: add CONTRIBUTING.md` should exist.
- It should pass `/pre-merge-gate` (no tests touched, no fitness ratchets affected).
- `/auto-merge` should land it on green CI.
- `/recap` should show one PR shipped, zero tests added, zero issues filed.

If all four happen, your anvil install is working end-to-end.

---

## Operator notes

This plan is intentionally trivial. Use it as a smoke test after install, or after upgrading anvil, or when teaching a teammate the framework. Real plans should be more substantive.

---

## Followups

(Nothing expected. If `/grind` files a follow-up issue here, that's a signal something went wrong — file a bug report against anvil.)
