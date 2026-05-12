---
name: analyze-plan
description: Use as a pre-execution gate before `/grind` dispatches a locked plan, or standalone when an operator suspects plan drift. Greps the plan's prose for cited file paths and verifies each one against the current working tree, flagging stale citations as CONTRADICTED so they can be refined before dispatch. v1 file-path verification only; identifier + numeric-fact verification deferred to v2. Auto-invoked by `/grind` step 0.5 (opt-out via `--skip-analyze`). Invoke with /analyze-plan <plan-path> or when the operator says "verify the plan", "check the plan claims", "is the plan stale", "are the paths still valid".
---

# /analyze-plan — verify a locked plan's file-path claims against the working tree

Plans drift between writing and execution. A plan written Monday cites `src/foo/bar.ts`; Tuesday's refactor renames it to `src/foo/baz.ts`; Wednesday's `/grind` dispatches an agent that re-reads "preserve the retry pattern at `src/foo/bar.ts`" against a path that no longer exists. The result is wasted slice time and a confused agent.

`/analyze-plan` catches that cheapest class of drift before `/grind` ships an agent. It's the same idea as `/issue-to-spec` for GitHub issue bodies — but applied to a whole plan (proposal.md + design.md + tasks.md + specs/*) and run as a pre-execution gate.

**v1 scope: file-path verification ONLY.** Identifier extraction and numeric-fact verification are deferred to v2 once the v1 false-positive rate has been measured on real plans. Adversarial review surfaced that bare-symbol regex extraction projected >30% FP rate on common English words (`done`, `pass`, `present`) — v1 keeps the bar high by extracting only paths that look like paths (slash + recognised extension + no placeholder tokens).

## When to invoke

- Operator says "verify the plan", "check the plan claims", "is the plan stale", "are the paths still valid".
- Auto-invoked by `/grind` step 0.5 (pre-execution gate) — see "Grind integration" below.
- Standalone, before locking a plan that was drafted over multiple sessions.
- Mid-grind, manually, when an operator suspects a recent refactor invalidated paths in the remaining slices.

## When NOT to use

- The plan is a fresh draft (≤24h since write) — claims should still be accurate.
- The plan is purely conceptual (no factual paths to verify). The skill exits 0 with a "warning: extracted 0 verifiable claims" note in that case.
- You want symbol-level verification — that's deferred to v2 (track via the v2 follow-up issue).

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to a `tasks.md` file, a flat single-file plan, or a plan folder containing `tasks.md` |

The skill has no flags in v1. The `--skip-analyze` opt-out lives on `/grind` itself (the consumer), not on `/analyze-plan` (the producer).

## Procedure

### Step 1: Resolve the plan layout

Accept either:
- A flat plan markdown file (`docs/plans/<slug>.md`).
- A folder containing `tasks.md` (+ optionally `proposal.md`, `design.md`, `specs/*.md`). Standard anvil folder layout.

If neither resolves, the skill exits 2 with `/analyze-plan: <path> is not a plan (expected a tasks.md or a folder containing one)`.

### Step 2: Build the `FORWARD_PATHS` set

Parse the YAML slice manifest in `tasks.md`. Union every entry across every slice's `files:` list. These are paths the plan promises to create or touch — they're "forward-looking" and must NOT be treated as drift when absent from disk.

Without this set, running `/analyze-plan` on a plan that hasn't started executing would flag every slice's planned-output file as CONTRADICTED — including the speckit-gold plan flagging `templates/constitution-template.md` and `skills/analyze-plan/SKILL.md` as drift on its own first execution.

### Step 3: Extract file-path claims

Walk every plan markdown file. For each line:

1. Toggle fenced-code-block state on any ` ``` ` line.
2. Apply the path regex: at least one `/`, ends in `.ts .js .sh .md .json .yml .yaml .bash .py .txt .bats`.
3. Reject candidates containing `<…>`, `{…}`, or `\d{4}-\d{2}-\d{2}` (date pattern).
4. Strip leading `./` and surrounding backticks/quotes.
5. Record `(plan_file, line, in_fence, path)`.

URL-form occurrences (`http(s)://…`) are stripped before matching to avoid false positives on linked docs.

### Step 4: Emit verdicts

For each extracted claim:

| Verdict | When | Effect on exit |
|---|---|---|
| `VERIFIED` | path exists in the working tree (or as an absolute path) | exit 0 |
| `EXPECTED-BY-SLICE` | path is absent BUT appears in some slice's `files:` list (forward-looking) | exit 0 |
| `UNVERIFIABLE` | path matched inside a fenced code block (illustrative) | exit 0 |
| `CONTRADICTED` | path is absent AND not in any slice's `files:` list | exit 1 |

### Step 5: Report

Print a per-verdict listing followed by a summary line:

```
summary: VERIFIED=N  EXPECTED-BY-SLICE=N  UNVERIFIABLE=N  CONTRADICTED=N
```

If any CONTRADICTED claims exist, a follow-up section lists them with file:line citations and the skill exits 1.

If zero claims were extracted, the skill emits `warning: extracted 0 verifiable claims — analyze-plan provides no signal for this plan` and exits 0 (not a failure — the plan is too high-level for grep-based verification).

## Grind integration

`/grind` invokes the script at step 0.5 (between plan validation and topo-sort):

```bash
bash skills/analyze-plan/scripts/extract-paths.sh "<plan-path>"
```

On CONTRADICTED verdict (script exits 1), `/grind` halts and prints:

```
stale claims found; either run /refine-plan or re-run /grind with --skip-analyze
```

The operator decides whether to refine the plan (preferred) or override with `--skip-analyze` (e.g. when the CONTRADICTED claims are spec-scenario illustrations, not real drift — the speckit-gold-on-itself case).

`--skip-analyze` is OPT-OUT — the gate is on by default for every `/grind` invocation. Add `--skip-analyze` to the `/grind` invocation to bypass.

## What this skill DOES NOT do (v1)

- **No identifier verification.** Extracting backticked symbols (`` `runFullGeneration` ``, `` `assertUnderProcessCap` ``) projected >30% false-positive rate against English words during adversarial review. Deferred to v2 with a stricter regex (snake_case ≥6 chars OR CamelCase ≥6 chars).
- **No numeric-fact verification.** "21 lines", "12 retries", "Phase 5 has 7 slices" — these can drift just as easily as paths, but the regex is harder to pin without flagging benign numbers. Deferred to v2.
- **No cross-artifact consistency.** This skill checks claims-vs-code, not proposal-vs-tasks or design-vs-specs. That's a different category of bug — out of scope.
- **No network calls.** No `gh`, no `curl`. The script is offline-safe so `/grind --resume` works on a flight.

## Composition

- `/grind` invokes at step 0.5 (pre-execution gate). Halts on CONTRADICTED unless `--skip-analyze`.
- `/refine-plan` is the recommended follow-up when CONTRADICTED is real drift — refines plan files in-place, then operator re-runs `/grind`.
- Standalone: operator runs before locking a plan to catch the cheapest class of drift before any agent dispatches.

## Configuration

No per-project config in v1. v2 may add `.anvil/analyze-plan.config.json` for symbol-regex tuning + skip-extension lists; defer until v1 FP rate is measured.
