---
name: pre-merge-gate
description: Use to verify a PR is merge-ready before invoking /auto-merge. Combinator runs rebase + tsc + vitest + fitness ratchets + grep for forbidden patterns, returns ready/not-ready with the specific failure. Invoke with /pre-merge-gate <pr-number-or-branch> or when the operator says "is this ready to merge", "verify before merge", "pre-merge check".
---

# /pre-merge-gate — verification combinator before merge

Many things can block a clean merge: stale rebase, type errors, test failures, fitness regressions, latent forbidden patterns (<deprecated-data-shape>

## When to invoke

- Operator says "is this ready", "verify merge", "pre-merge check", "gate this PR".
- `/grind` invokes internally before `/auto-merge`.
- Manually before flipping the merge button on any PR you didn't write yourself.

## Args

| Arg | Required | Description |
|---|---|---|
| `<pr-or-branch>` | yes | PR number (`1077`) or branch name (`fix-1064-cache-deps`) |
| `--worktree <path>` | no | Worktree path; auto-derives if branch matches existing worktree |
| `--base <branch>` | no | Base branch (defaults to `origin/main`) |
| `--skip-rebase` | no | Don't rebase; just run gates against current HEAD (use when rebase already done) |
| `--strict` | no | Treat warnings as failures (e.g. lint warnings, test retry) |

## Procedure

### Step 1: Resolve the worktree

If `--worktree` not given, find the worktree for the branch:

```bash
git worktree list | awk -v b="$BRANCH" '$3 == "[" b "]" {print $1}'
```

If no worktree exists, `git fetch` + checkout the branch to a fresh worktree:

```bash
git fetch origin "$BRANCH"
git worktree add /tmp/anvil-merge-gate-$$ "origin/$BRANCH"
WORKTREE_PATH=/tmp/anvil-merge-gate-$$
```

(Cleanup the tmp worktree at end of skill.)

### Step 2: Rebase against base (unless --skip-rebase)

```bash
cd "$WORKTREE_PATH"
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If rebase has conflicts: ABORT, report conflict file list + 5-line snippet of each conflict region. Don't try to resolve — bubble up to operator.

### Step 3: Type check

```bash
# Find all package.json with a tsconfig.json sibling
for pkg in $(find "$WORKTREE_PATH" -name "tsconfig.json" -not -path "*/node_modules/*"); do
  (cd "$(dirname "$pkg")" && npx tsc --noEmit) || FAILED=1
done
```

### Step 4: Test suite

```bash
# v3-style: per-package vitest run
for pkg in $(find "$WORKTREE_PATH" -name "vitest.config.*" -not -path "*/node_modules/*"); do
  (cd "$(dirname "$pkg")" && npx vitest run) || FAILED=1
done
```

Capture pass/fail counts. Compare against baseline (operator-supplied or auto-detected from prior commit).

### Step 5: Architecture fitness

```bash
# v3 has its own fitness ratchet suite — find + run
find "$WORKTREE_PATH" -path "*test/architecture/fitness.test.*" -not -path "*/node_modules/*" \
  | xargs -I {} npx vitest run {}
```

### Step 6: Grep for forbidden patterns

Read from `<repo>/.anvil/forbidden-patterns.txt`. See `templates/forbidden-patterns.example.txt` for the format + a starter list.

Each line:

```
# Pattern : path-glob : exclusion-glob (optional) : comment
<deprecated-mutator>\\b :: src/** :: : <deprecated-mutator> calls (use the typed command instead)
process\\.env\\. :: src/** :: src/config/** : direct env reads outside config module
BEGIN IMMEDIATE.{0,200}await :: src/** :: : await between BEGIN and COMMIT silently drops the tx lock
```

Run each as a `grep -E` over the path-glob; fail if any match.

### Step 7: Verify CI on the PR

```bash
gh pr checks <pr-number> --json name,bucket | \
  jq -r '.[] | select(.bucket == "fail" or .bucket == "pending") | "\(.bucket): \(.name)"'
```

If any "fail": report. If "pending": warn (operator can decide to wait or short-circuit).

### Step 8: Verdict

Print one of:

- **✅ Merge-ready** — all gates pass. Caller can proceed to `/auto-merge`.
- **🟡 Yellow flags** — non-blocking warnings (lint warnings, test retries). Caller can proceed but should review the flags.
- **🔴 Blocked** — list of failed gates with specifics. Caller must fix before `/auto-merge`.

### Step 9: Auto-emit a learning when a known flake retry-passes

If the test suite (Step 4) failed on the first run and passed on retry, AND the failure pattern matched a line in `.anvil/known-flakes.txt`, append a `flake` learning to `.anvil/learnings.jsonl` via `/learn add`. This way the next operator who hits the same symptom gets a hit in `/learn search`.

```bash
# Only fires when retry-passing matched a known-flakes pattern.
flake_signature="<test-name-or-regex-that-matched>"
flake_key="flake-retry-passed-$(echo "$flake_signature" | tr -c '[:alnum:]' '-' | tr -s '-' | sed 's/^-\|-$//g')"

bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
  "$flake_key" "flake" \
  "Known flake \"$flake_signature\" retry-passed on PR #$PR_NUMBER. See .anvil/known-flakes.txt." \
  --confidence medium \
  --source /pre-merge-gate \
  --file .anvil/known-flakes.txt \
  --tag retry-passed \
  2>/dev/null || true
```

The call uses the **soft-fail default** — if `/learn add` errors (disk full, JSONL corrupt), pre-merge-gate doesn't abort.

If a flake does NOT retry-pass — i.e. fails twice — that's a real test failure, not a flake. Don't emit a learning; emit the verdict as Blocked.

## Output format

```
=== /pre-merge-gate verdict ===
PR: #<n> — <title>
Branch: <branch>
Worktree: <path>

Rebase:        ✅ clean against origin/main
Type check:    ✅ tsc --noEmit clean
Tests:         ✅ 906/906 passing (v3 suite)
Fitness:       ✅ 27/27 passing
Forbidden:     ✅ no matches
CI:            ✅ all checks green

Verdict: 🟢 MERGE-READY
```

Or:

```
Verdict: 🔴 BLOCKED
- ❌ Type check: 2 errors in src/<your-module>/<your-file>.ts:NNN
- ❌ Forbidden: 1 match for <deprecated-mutator>
- ⚠️ CI: 1 check still pending (test)

Fix the errors above, re-run /pre-merge-gate, then /auto-merge when green.
```

## When this saves time

A multi-PR sprint runs ~6 manual checks per PR (rebase, tsc, tests, fitness, forbidden-pattern grep, CI verify). Twelve PRs = 72 manual operations. With this skill: 12 invocations.

## Configuration

Per-project tuning lives in `<repo>/.anvil/pre-merge-gate.config.json`. See `templates/pre-merge-gate.config.example.json` for a starter file. Shape:

```json
{
  "tests": {
    "baseline": "auto",
    "target": "$baseline+",
    "allowFlakeRetries": 1
  },
  "forbiddenPatterns": ".anvil/forbidden-patterns.txt",
  "fitnessTestPath": "test/architecture/fitness.test.ts",
  "rebaseAgainst": "origin/main"
}
```

If absent: skill uses sensible auto-detected defaults.
