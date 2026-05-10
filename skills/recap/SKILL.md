---
name: recap
description: Use after a multi-PR sprint to generate a visual session-recap HTML page — PRs shipped, issues filed/closed, test count delta, lessons learned. Drops a self-contained HTML under `~/.claude/showme/` and opens in browser. Pairs with /session-closeout (which writes the memory file). Invoke with /recap or when the operator says "recap the session", "show me what shipped", "session summary page", "post-sprint visual", or similar.
---

# /recap — visual session-recap HTML

After a multi-PR sprint, a markdown summary is fine — but a visual page is faster to scan and nicer to drop into a daily journal / Slack post / project log. This skill codifies the format.

## When to invoke

- After a multi-PR sprint (≥3 PRs merged in one session).
- Operator says "recap", "show me what shipped", "session summary", "post-sprint visual".
- Pairs with `/session-closeout` (which writes the memory file). Recap is the visual companion.

## Procedure

### Step 1: Gather the data

```bash
# PRs merged in window (default: today + yesterday; operator can override)
gh pr list --state merged --base main --limit 50 --json number,title,mergedAt,additions,deletions \
  | jq -r '.[] | select(.mergedAt > "<since>") | "\(.number)|\(.mergedAt[0:10])|\(.additions)|\(.deletions)|\(.title)"'

# Issues filed in window
gh issue list --state all --limit 50 --json number,title,createdAt,closedAt,state \
  | jq -r '.[] | select(.createdAt > "<since>") | "\(.number)|\(.state)|\(.title)"'

# Test count delta — read from session memory or run vitest summary
# git stat — net LoC, files touched
git diff --stat <baseSHA>..HEAD | tail -1
```

If the operator gives a window ("last 2 days" / "since Monday" / "this sprint"), use that. Otherwise default to "since the last memory file in `~/.claude/projects/.../memory/project_session*` was written."

### Step 2: Build the HTML

Output path:
```
~/.claude/showme/<YYYYMMDD-HHMMSS>-recap-<slug>.html
```

Slug: 2-3 words capturing the sprint theme (e.g. "platform-hardening", "p0-pushdown", "auth-cleanup", "performance-grind").

### Layout shape

The recap page should fit in one viewport at 1280×800 with no scroll for the headline metrics, then scroll for PR detail cards.

**Header strip:**
- Sprint name + date range
- Big metrics: PRs merged, tests added, LoC net, issues closed, follow-ups filed

**Metric tiles (4-up grid):**
- 🟢 PRs merged (with count)
- 🧪 Test count delta (873 → 985, +112)
- 📊 LoC delta (additions / deletions / net)
- 🎯 Issues closed (with breakdown: P0/P1/P2/P3)

**PR cards (grid, sorted by impact tier):**
- Each PR: number + title + LoC + test delta + 1-line impact statement
- Tier badge: BLOCKER (P0), FEATURE (P1), CLEANUP (P2/P3), DOCS, REFACTOR
- Color-code tiers so visual scan groups by importance

**Decisions strip (when running against a /grind output):**
- Pulled from the plan's `## Operator decision records` section
- Each entry: slice ID + verb (approve/edit/reject/respond) + one-line summary
- Skipped if no decisions were recorded

**Lessons-learned strip:**
- 3-5 bullets of "what we learned" — usually pulled from session memory file
- Mark ones that became permanent rules / fitness ratchets

**Loose ends footer:**
- In-flight PRs (CI pending, agents running)
- Issues still open from this sprint's audit
- Next-session priorities (one line each)

### Style rules

- Dark default, light via `prefers-color-scheme`.
- System fonts.
- Use color sparingly: green for shipped, amber for in-flight, red ONLY for blockers/regressions.
- Every PR card has a clickable github link.
- Print-friendly (operator may want to PDF + archive).

### Step 3: Open + summarize

```bash
open ~/.claude/showme/<filename>.html
```

Then in chat: file path + 2-sentence headline ("14 PRs merged across two sessions, v3 issue tracker emptied of code-side P0/P1/P2.")

## Cadence

Run at the end of every multi-PR sprint. Pair with `/session-closeout` — the memory file is the durable record, the HTML is the readable one.

## Style reference

If a previous recap exists at `~/.claude/showme/<YYYYMMDD-HHMMSS>-recap-<slug>.html`, reference it to keep the style consistent across runs. Otherwise, use the layout shape above as the canonical structure.
