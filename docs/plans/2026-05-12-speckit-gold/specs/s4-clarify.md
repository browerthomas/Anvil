# S4 — /clarify separates interrogation from specification

**Slice:** S4
**Status:** locked

---

## Background

Anvil's `/spec` is interactive — it probes for missing detail through AskUserQuestion rounds, then writes the plan in one pass. This conflates two activities: interrogation (extracting what the operator wants) and specification (writing it down in plan format). They have different cadences: interrogation is iterative + Q&A-shaped; specification is structural + template-driven. When interleaved, edits to one bleed into the other (the operator clarifies a detail, the spec is rewritten, and the original question/answer pair is lost).

`/clarify` extracts the interrogation step into its own skill that emits a markdown transcript. `/spec` then optionally consumes the transcript to pre-populate its draft, skipping covered ground. The transcript is committed alongside the plan, so the provenance of every spec line is recoverable.

---

## Scenario — /clarify writes a transcript

**WHEN** the operator invokes `/clarify "ship an admin dashboard for order state"`

**THEN** the skill runs up to 3 rounds of `AskUserQuestion`, each round asking 1-4 specific questions
**AND** the questions cover: Goal (what success looks like), Scope-cuts (what's explicitly out), Constraints (what can't be touched), Success criteria (how to verify done)
**AND** at the end, a file is written at `docs/plans/.clarify/<YYYY-MM-DD>-<slug>.md`
**AND** the file contains a `## Question` / `## Answer` block for each round
**AND** the file ends with a `## Derived facts` synthesis section (5-10 bullets)

## Scenario — /spec consumes the transcript

**WHEN** a transcript exists at `docs/plans/.clarify/2026-05-12-admin-dashboard.md`
**AND** the operator invokes `/spec --clarify-file docs/plans/.clarify/2026-05-12-admin-dashboard.md`

**THEN** `/spec` reads the transcript before any AskUserQuestion call
**AND** the Goal / Scope / Constraints / Success-criteria sections in `proposal.md` are pre-populated from the Derived facts
**AND** `/spec` does NOT re-ask questions already answered in the transcript
**AND** the generated `proposal.md` includes a footer: `Clarify transcript: docs/plans/.clarify/2026-05-12-admin-dashboard.md`

## Scenario — /spec without transcript still works

**WHEN** the operator invokes `/spec "<intent>"` without the `--clarify-file` arg

**THEN** `/spec` behaves exactly as it does today (full interactive probe)
**AND** no transcript file is consulted

## Scenario — transcript references stale state

**WHEN** the operator invokes `/spec --clarify-file <path>`
**AND** the transcript's Derived facts contain a claim that contradicts current code (e.g. references a deleted file)

**THEN** `/spec` includes the claim in the draft
**AND** flags it with `<!-- clarify drift: this claim may be stale; verify before locking -->`
(Operator-resolved at lock time; `/spec` does not auto-correct.)

---

## Negative case (refusal contract)

**WHEN** the operator invokes `/spec --clarify-file <path>` and the file does not exist

**THEN** `/spec` exits non-zero
**AND** prints: `clarify file not found: <path>`

**WHEN** the transcript file exists but does NOT contain a `## Derived facts` section

**THEN** `/spec` prints a warning: `warning: <path> has no ## Derived facts section; falling back to full interactive probe`
**AND** proceeds with the full interactive flow
(Graceful degradation — malformed transcript is treated as no transcript.)
