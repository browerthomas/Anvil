---
name: refine-plan
description: Use mid-grind when new code-reading or new findings contradict the locked plan. Updates the plan files (proposal/design/tasks/specs) in-place, writes a `plan-revised` event to `.anvil/grind-events.jsonl`, and optionally comments on any in-flight PRs whose acceptance contract just moved. Closes the manual sequence "Edit plan files → git commit → status update". Invoke with /refine-plan <plan-path> "<correction>" or when the operator says "the plan is wrong about X", "fix the spec", "revise mid-grind".
---

# /refine-plan — mid-grind plan correction

Plans get written in advance. Code is the contract. When mid-grind reading reveals the plan asserts something the code disagrees with (or the plan's slice scope was wrong about a vendor's actual behavior, or the file count was estimated and grep found a different number), the plan needs to update — not the code, not the slice agent's instructions.

This skill applies a correction to the plan files atomically: one Edit pass, one commit, one event-log entry, one PR comment per in-flight slice that the correction affects.

Real example from the http-client dogfood: post-S1 reading revealed `core/email.js`'s "bare-fetch" reference at line 898 was inside a comment, not real code. S4's "Resend migration" was therefore not a thing — the plan needed to update before S4 dispatched.

## When to invoke

- Operator says "the plan is wrong about X", "fix the spec", "revise mid-grind", "the spec contradicts the code", "callsite count is off."
- After `/issue-to-spec` finds a CONTRADICTED claim that needs to propagate to a locked plan.
- Mid-`/grind` when reading the actual code reveals the slice scope is off.

## When NOT to use

- Plan hasn't been locked yet — just edit the draft directly via /spec.
- The "correction" is actually scope creep — operator should reject the slice or open a new plan instead of stretching this one.
- The correction would invalidate already-merged slices — that's a follow-up plan, not a refinement.

## Args

| Arg | Required | Description |
|---|---|---|
| `<plan-path>` | yes | Path to the plan folder (or flat file) |
| `<correction>` | yes | One-paragraph description of what's wrong + what the corrected version should say |
| `--slice <id>` | no | If the correction affects one slice specifically, name it (so the event log + PR comment scope to that slice) |
| `--file <plan-file>` | no | Restrict the correction to one file (e.g. `tasks.md`, `specs/<name>.md`); default: AI orchestrator picks |
| `--no-pr-comment` | no | Skip commenting on in-flight PRs (use when the correction is editorial / not contract-affecting) |

## Procedure

### Step 1: Read the current plan

Load all plan files. Identify which file(s) the correction touches.

### Step 2: Apply the correction

Use the `Edit` tool to update the relevant file(s). Use exact-string-replace; don't paraphrase. Include enough surrounding context so the Edit is unambiguous.

If the correction creates new specs (e.g. a new file:line that wasn't covered before), add a new spec file under `specs/<scenario>.md` rather than bloating an existing one.

### Step 3: Update the plan's `Status:` if needed

If the plan was `Status: locked` and the correction is substantive (not just typo fix), keep it locked but add a note in `proposal.md`'s `## Operator decision records` section describing the revision:

```
### Decision: <date> — plan-revised — <slice-id>
- **What:** <one-line>
- **Why:** <one-paragraph — what new info forced the revision>
- **Affected:** <which files updated>
```

### Step 4: Commit

```bash
git add docs/plans/<slug>/
git commit -m "docs(plan): refine <slug> — <correction-summary>"
```

If `--slice` was given, prefix the message: `docs(plan): refine <slug> S<N> — <correction-summary>`.

### Step 5: Write event log entry

Append to `.anvil/grind-events.jsonl`:

```json
{"t": "<iso>", "ev": "plan-revised", "slice": "<slice-id-or-null>", "data": {"plan_path": "...", "files_changed": [...], "correction_summary": "..."}}
```

### Step 6: Comment on in-flight PRs (if applicable + not --no-pr-comment)

For each slice currently `in-flight` per the event log, if its branch has an open PR, post a comment:

```
The plan was refined while this PR was in-flight: <link to commit>.

If the change affects this slice's contract, please incorporate; otherwise no action needed.

Refinement summary: <one-line>
```

Skip if `--slice` is set and the in-flight slice doesn't match.

### Step 7: Push

`git push origin main` (the plan files live on main). If the operator has a "no direct push to main" policy, the skill should detect that via repo settings and instead open a tiny PR with the refinement.

## Output

```
=== /refine-plan ===
Plan: docs/plans/2026-05-10-http-client-standardisation/
Correction: Resend already wraps via sendWithRetry; S4 scope reduces to health.js probe only

Files changed:
- specs/sweep-completeness.md (Resend "NOT in scope" note added)
- tasks.md (S4 scope paragraph rewritten)

Event logged. Commit: <sha>.
PR comments posted: #1080 (S4 not yet dispatched — no comment).
```

## Composition

- `/spec` produces the original plan; `/refine-plan` corrects it.
- `/issue-to-spec` can feed `/refine-plan` automatically when a CONTRADICTED claim is found.
- `/grind` watches for `plan-revised` events; if the affected slice is in-flight, alerts the operator before merging.
