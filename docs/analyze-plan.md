# /analyze-plan — design notes

`/analyze-plan` is a pre-execution gate that verifies a locked plan's cited file paths against the working tree before `/grind` dispatches the first slice. Catches the cheapest class of plan drift: paths cited in `proposal.md` / `design.md` / `tasks.md` / `specs/*` that a subsequent refactor renamed or removed.

This document covers v1 scope, v2 deferrals, and the verdict design — read it before extending the extractor or removing constraints.

---

## v1 scope — file paths only

The extractor regex matches:

- At least one `/` (a single token without a slash is not a path).
- Ends in one of: `.ts`, `.js`, `.sh`, `.md`, `.json`, `.yml`, `.yaml`, `.bash`, `.py`, `.txt`, `.bats`.
- Does NOT contain `<…>`, `{…}`, or a `\d{4}-\d{2}-\d{2}` date pattern (these are placeholders the operator wrote intentionally — not facts to verify).

Leading `./` is stripped; surrounding `` ` ``, `"`, `'` are stripped. `http(s)://…` URL prefixes are scrubbed before matching so linked docs do not produce false positives.

---

## What's deferred to v2

Two verification surfaces were proposed during plan design and explicitly cut from v1:

### Backticked identifiers

Lines like `` the `runFullGeneration` orchestrator wraps `assertUnderProcessCap` `` carry verifiable claims. The v0 sketch grepped `` ` `` -delimited tokens against `git grep` results.

**Why deferred:** adversarial review (hermes-ask P1-5, 2026-05-12) projected a >30% false-positive rate against common English words backticked for emphasis — `done`, `pass`, `present`, `match`, `verified`. v1 would have surfaced more noise than signal.

**v2 plan:** stricter regex — snake_case ≥6 chars OR CamelCase ≥6 chars. Filed as a separate follow-up issue, gated on measured v1 FP rate across ≥3 real plans.

### Numeric facts

Lines like `the queue handles 17 concurrent slices`, `12 retries on the 401 branch`, `Phase 5 has 7 slices`. Numbers drift just like paths.

**Why deferred:** regex without context flags many benign numbers (`Step 4`, `v0.6.0`, `Phase 5`). v2 needs a heuristic — claim phrasing like "N <unit-noun>" — that's not yet validated.

---

## The verdict set

Four verdicts. Three exit 0; one exits 1.

| Verdict | Meaning | Exit |
|---|---|---|
| `VERIFIED` | Path exists in the working tree. | 0 |
| `EXPECTED-BY-SLICE` | Path is absent on disk BUT in some slice's `files:` list — forward-looking, the plan promises to create it. | 0 |
| `UNVERIFIABLE` | Path matched inside a fenced code block (illustrative, e.g. `path/to/example.ts` in a how-to-use example). | 0 |
| `CONTRADICTED` | Path is absent AND not in any slice's `files:` list — real drift. | 1 |

### Why `EXPECTED-BY-SLICE` is load-bearing

Without this verdict, `/analyze-plan` on a plan whose first grind hasn't started would flag every planned-output file as CONTRADICTED. The canonical example is the speckit-gold plan that introduces `/analyze-plan` itself: at lock-time, `templates/constitution-template.md` (S1's output) and `skills/analyze-plan/SKILL.md` (S5's output) do not exist on disk yet — but they ARE listed in `tasks.md` as slice `files:` entries.

The `FORWARD_PATHS` set (the union of every slice's `files:` list, parsed from the YAML manifest) is the difference between a plan analyzing-itself and being refusable on its own first execution.

### Why `UNVERIFIABLE` is load-bearing

Plans embed many illustrative paths inside fenced code blocks — bash snippets, example YAML, sample directory trees. These are not factual claims about extant code. Flagging them as CONTRADICTED would spam the report. `UNVERIFIABLE` records that the extractor saw the path but cannot meaningfully check it.

`tasks.md`'s slice-manifest YAML block is itself a fenced code block, so every path inside the manifest is `UNVERIFIABLE` (correct — the manifest is canonical, not a separate claim).

---

## Grind integration

`/grind` runs `/analyze-plan` as step 0.5 — between Step 1 (parse + validate the plan) and Step 2 (topo-sort slices). The gate is opt-out via `--skip-analyze`. On any CONTRADICTED verdict the script exits 1; `/grind` halts and prints:

```
stale claims found; either run /refine-plan or re-run /grind with --skip-analyze
```

Operator decision tree:

- The CONTRADICTED claims represent real drift (a rename was missed) → run `/refine-plan` to update the plan files, then re-run `/grind` (the gate should now pass).
- The CONTRADICTED claims are spec-scenario illustrations (paths chosen specifically because they don't exist — e.g. `src/foo/bar.ts` in an `/analyze-plan` self-test) → re-run `/grind --skip-analyze`.

`--skip-analyze` is intentionally documented as an escape hatch, not a default. The point of the gate is to make the operator pause and choose; bypassing should be deliberate.

---

## False-positive vs false-negative tradeoff

The regex is conservative by design: better to leave a real drift uncaught (false negative) than to flag a benign mention as drift (false positive). Operators tune out gates that flag noise; a gate that misses 1 in 10 real drifts but never lies is more useful than a gate that catches everything and cries wolf 30% of the time.

If v1 turns out to be too quiet on real plans, v2 widens the regex. If v1 is too loud, the extension list narrows. Measure first — at least 3 real plans through the gate — before tuning.

---

## Why no network

The script makes no `gh` / `curl` / `git fetch` calls. Reasons:

1. `/grind --resume` should work on a flight.
2. The gate runs on every grind invocation. Network calls would amortise badly.
3. The only state we need is the working tree + the plan files — both local.

If v2 adds external-fact verification (e.g. "issue #1064 is open" from `gh issue view`), it ships as an optional `--with-network` flag, not the default.
