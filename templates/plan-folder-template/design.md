# <PLAN NAME> — design

> The "how." Architecture decisions, locked + rejected with rationale. This is what the adversarial reviewer checks the implementation against.

---

## Architecture decisions

For each non-trivial design choice:

### Decision: <short name>
- **What:** one-line summary
- **Why:** one paragraph
- **Rejected alternatives:** bullet list with one line each on why each was passed

(Repeat for each decision. If only one decision, that's fine. If zero — push back: this should be `tasks.md` only, no `design.md` needed.)

---

## Hard constraints

Inviolable rules across all slices in this plan. The orchestrator passes these to every agent dispatch via `dispatch-defaults.txt` augmented with these.

- Bullet list.
- Use the project's fitness ratchets as a starting point.
- Add per-plan constraints (e.g. "this slice cannot touch the schema_version", "no new env vars", "test target = N+ passing").

---

## Cross-slice coordination

If slices need shared assumptions, document them here. Example:

- **Shared interface:** all generation handlers must implement `process(input: Input): Output` — slice 3 introduces; slices 4+ depend on the shape.
- **Shared types:** `OrderState` enum extended in slice 1; subsequent slices import.
- **Shared test utilities:** `test/helpers/recordingLogger.ts` added in slice 2; reused by slices 3-7.

---

## Dependencies on external surfaces

What does this plan assume about systems anvil doesn't control?

- **Vendor APIs:** which versions, which features, what happens if the vendor changes shape mid-plan.
- **Data:** what schema is assumed, what migration is needed.
- **Infrastructure:** is the staging env required, is a deploy gate involved.

---

## Risks

What could go wrong + how the plan mitigates each:

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| <risk> | low/med/high | low/med/high | <mitigation, or "accepted"> |
