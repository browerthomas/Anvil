---
name: issue-to-spec
description: Use before locking a plan that derives from a GitHub issue body. Greps the codebase for each factual claim in the issue (file:line references, "X retries on N", "Y is at Z") and verifies it against current code. Outputs a corrected mini-spec marking which claims were verified, which contradicted, which couldn't be verified. Catches the "issue body wrong" class of plan bug at lock-time. Invoke with /issue-to-spec <issue-number> or when the operator says "verify the issue", "check the issue claims", "issue says X — is that true?".
---

# /issue-to-spec — verify an issue body's factual claims against the codebase

GitHub issues are written from memory. By the time someone reads the issue weeks later, the code has moved. A plan that takes the issue body as ground truth inherits whatever's wrong in it.

Real example from the http-client dogfood: issue #673 said `core/lulu.js — custom retry pattern`. Reading the actual code: there's no 5xx retry, only a 401-token-refresh dance. The plan based on the issue would have instructed the slice agent to "preserve 5xx retry verbatim" against retry behavior that doesn't exist.

This skill catches that class of bug at the moment it matters most — before `/spec` locks the plan.

## When to invoke

- Operator says "verify the issue", "check the issue claims", "is what this issue says still true?".
- `/spec` invokes internally before step 4 (validation gate) when the plan was derived from a GitHub issue.
- Before any plan that lists ≥2 file:line references quoted from an issue body.

## When NOT to use

- Issue is purely conceptual ("we should add a CONTRIBUTING.md") — no factual claims to verify.
- Issue is brand-new (≤24h old) — claims should still be accurate.
- The operator already read the source files and is writing a spec from current state.

## Args

| Arg | Required | Description |
|---|---|---|
| `<issue-number>` | yes | GitHub issue number to verify |
| `--repo <owner/repo>` | no | Defaults to current repo via `gh repo view` |
| `--paths <comma-list>` | no | Restrict greps to these path globs (default: read from `.anvil/issue-to-spec.config.json` or all of `core/ web/ src/`) |
| `--out <path>` | no | Write the corrected mini-spec to this path (default: stdout) |
| `--strict` | no | Treat any unverifiable claim as a failure (exit 1) — for CI use |

## Procedure

### Step 1: Fetch the issue

```bash
gh issue view <N> --repo <owner/repo> --json body,title --jq '.body'
```

### Step 2: Extract factual claims

Find lines in the body that name specific code locations or behaviors:

- **File:line references** — `core/lulu.js:76`, `web/auth.js#L656`, `src/asset/AssetService.ts:123`
- **Function/identifier mentions** — backtick-quoted symbols (`` `luluFetch` ``, `` `forVendor()` ``, `` `assertUnderProcessCap` ``)
- **Behavioral claims** — "X retries on Y", "Z is wrapped by W", "the current pattern does N"
- **Module references** — `core/lulu.js — custom retry pattern`

Heuristic shape: a "claim" is anything where the issue body asserts a fact about the codebase that can be falsified by reading the code.

### Step 3: Verify each claim

For each extracted claim, run the appropriate verification:

| Claim shape | Verification |
|---|---|
| `<path>:<line>` | `git ls-files \| grep <path>` exists; the line near the cited number contains code shaped like the claim. |
| `` `<symbol>` `` | `git grep -nE 'function <symbol>\|<symbol>\s*=' --include='*.js' --include='*.ts'` finds at least one definition. |
| `<file> — <behavioral-pattern>` | Read the file. Verify the pattern is present (e.g. issue says "retries on 5xx" → grep for `status >= 500` or `retry` near `status`). |
| `<feature> exists` | Grep + read for evidence. |

For each claim, classify:
- **VERIFIED** — claim matches current code.
- **CONTRADICTED** — code says something different. Quote the actual code snippet.
- **MOVED** — file/symbol exists but at a different path/line than cited.
- **UNVERIFIABLE** — couldn't determine; flag for human review.

### Step 4: Write the corrected mini-spec

Output a markdown file (or stdout) with:

```markdown
# Issue #<N> — claims verification

**Title:** <issue title>
**Verified at:** <iso timestamp>
**Repo HEAD:** <sha>

## Verified claims

- ✅ `core/foo.js:42` — `<symbol>` exists (matches issue body)

## Contradicted claims

- ❌ `core/lulu.js — "custom retry pattern"`
  Issue says: <quoted from body>
  Actual: <code snippet from `core/lulu.js:100-135`>
  Difference: the retry described in the issue is the 401-token-refresh dance only; there is no 5xx retry. Plans derived from this issue should NOT assume a 5xx retry to preserve.

## Moved claims

- ⚠️ `<old-path>` — symbol moved to `<new-path>` since the issue was opened.

## Unverifiable

- ❓ <claim that needs human eyes>
```

### Step 5: Exit code

- 0 if all claims VERIFIED or only `MOVED`/`UNVERIFIABLE` (warnings).
- 1 if any CONTRADICTED (with `--strict`, also fail on UNVERIFIABLE).

## Composition

- `/spec` invokes internally before validation gate (step 4) when `--from-issue <N>` is in args.
- Operator can run standalone before manually drafting a plan.
- Output integrates with `/refine-plan` — if a plan was already locked and `/issue-to-spec` finds contradictions, `/refine-plan` applies the corrections to the plan files.

## Configuration

Per-project tuning at `.anvil/issue-to-spec.config.json` (optional):

```json
{
  "default_paths": ["core/", "web/", "src/"],
  "skip_extensions": [".html", ".css", ".lock"],
  "max_claim_search_lines": 100,
  "strict_default": false
}
```

If absent: skill uses generic defaults.
