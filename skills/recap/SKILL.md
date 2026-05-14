---
name: recap
description: Use after a multi-PR sprint to generate a session-recap. Two modes — v1 (visual HTML page in ~/.claude/showme/) and v2 (structured TLDR + WHY markdown with citation resolution). Pairs with /session-closeout. Invoke with /recap, /recap --v2, or when the operator says "recap the session", "show me what shipped", "session summary page", "post-sprint visual", "what assumptions changed", "what's the residual risk".
---

# /recap — session recap (v1 visual + v2 structured WHY)

After a multi-PR sprint, a markdown summary is fine — but a visual page is faster
to scan, and an operator who wants to know "why did we end up here?" needs the
structured WHY engine. This skill ships both.

- **v1 mode** — visual HTML page under `~/.claude/showme/`. Layout-heavy, scan-
  friendly, pasteable into a project log or Slack post. **Default mode.**
- **v2 mode** — structured markdown. TLDR (4 sentences, one per WHY section) +
  four named WHY sections (What shipped / What assumptions changed / What
  architectural drift / What residual risk). Sections 3-5 require **citation**
  using a three-form vocabulary; the script runs **citation resolution** on the
  output and fails the build if any citation can't be resolved.

## When to invoke

- After a multi-PR sprint (≥3 PRs merged in one session).
- Operator says "recap", "show me what shipped", "session summary", "post-
  sprint visual" → **v1**.
- Operator says "what assumptions changed", "what's the residual risk",
  "structured recap", "WHY recap" → **v2**.
- Pairs with `/session-closeout` (which writes the memory file). The recap is
  the readable companion; the memory file is the durable record.

## v1 Procedure (visual HTML)

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

If the operator gives a window ("last 2 days" / "since Monday" / "this sprint"), use that. Otherwise default to "since the last commit on the previous business day" — or whatever the host's session-memory mechanism provides if one is wired up.

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

Then in chat: file path + 2-sentence headline ("14 PRs merged across two sessions, v3 issue tracker emptied of code-side P0/P1/P2.").

## v2 Procedure (structured WHY + citation resolution)

### Step 1: Render the prompt

```bash
bash skills/recap/scripts/build-recap.sh --v2 --plan docs/plans/<slug>/
```

Without `--model-cmd` set, this emits the structured prompt to stdout. The
prompt embeds the event log excerpt, PR list in window, plan tasks.md, the
decisions log (`.anvil/learnings.jsonl` rows with `type:decision`), and the
slice-merged diff stats.

### Step 2: Hand the prompt to a model

```bash
bash skills/recap/scripts/build-recap.sh --v2 \
  --plan docs/plans/<slug>/ \
  --output /tmp/recap-v2.md \
  --model-cmd 'claude --print --model opus'
```

The `--model-cmd` shell command receives the prompt on stdin and is expected to
emit the markdown recap on stdout. Any command works:
- `claude --print --model opus` (Opus via Claude CLI)
- `codex chat --no-banner` (Codex CLI)
- `cat > /tmp/in.md; nano /tmp/out.md; cat /tmp/out.md` (manual fill-in)

### Step 3: Citation resolution runs automatically

The script validates two things on the model output:

1. **Structure.** Required sections in order: `## TLDR`, `## What shipped`,
   `## What assumptions changed`, `## What architectural drift`, `## What
   residual risk`. TLDR must be exactly 4 sentences.

2. **Citation resolution.** Every bullet in sections 3-5 ("What assumptions
   changed" / "What architectural drift" / "What residual risk") must contain
   at least one citation matching one of three forms — and each citation MUST
   resolve.

### Citation vocabulary

Three forms. Pinned across design, tasks, specs. No new forms.

| Form | Example | Resolution check |
|------|---------|------------------|
| `path/to/file.ext:N` | `web/server.js:142` | File must exist + `wc -l` >= N. |
| `#PR_NUMBER` | `#1010` | `gh pr view N` exits 0 (offline: fixture allowlist). |
| `<commit-sha>` | `<a1b2c3d>` or `<a1b2c3def4567...>` | `git cat-file -e <sha>` exits 0. |

A bullet may contain multiple citations. As long as at least one resolves, the
bullet passes. **A hallucinated `#9999` fails the build** — operators have
caught models inventing plausible-looking PR numbers; the citation-resolution
pass closes that loop.

### Offline mode

Set `GH_OFFLINE=1` to skip `gh pr view` calls. The script falls back to a
fixture allowlist at `.anvil/recap-pr-allowlist.txt` (one PR number per line)
or whatever `--pr-allowlist <path>` points at. SHA + file:line citations still
resolve locally.

### Output

If `--output <path>` is supplied, the v2 markdown lands there. Otherwise it
prints to stdout. The first content in the output is `## TLDR` — operators
scan-read the TLDR; the WHY sections live below.

## Grind summary (agent token / tool / wall-time rollup)

Both v1 and v2 recaps emit a per-slice rollup of agent token spend + tool
use + wall time, folded from the `agent-completed` events that
`/dispatch-slice` appends to `.anvil/grind-events.jsonl`. The rollup also
ships as a standalone sub-command — `/grind-summary` — for operators who
just want the table without the full visual / WHY-structured recap.

### Output

```
=== Grind summary: <plan-path> ===

Slice  PR      Tokens     Tool uses  Wall time
B0     #949    150,200    88         12m 14s
B2     #952    202,018    140        17m 36s
...
────────────────────────────────────────────────
Total          1,847,221  1,002      4h 12m  (n=11 agents)
+ orchestrator: run `/cost` in Claude Code for parent-side tokens
```

- Multiple agents per slice (review fix-ups, dispatched fixers) sum into
  one row. The trailing `n=N agents` count covers every agent contribution.
- The `PR` column is filled from a sibling `slice-pr-opened` event when one
  exists for the same slice; left blank otherwise.
- The orchestrator footer is explicit and always printed. The runtime
  tracks parent-side tokens but doesn't expose them as a callable tool, so
  operators have to run `/cost` in Claude Code itself to see them. This is
  the framework's permanent gap and the line names it.
- Codex / Hermes CLI calls are NOT counted — they're separate
  subscriptions, not Claude tokens.

### Standalone invocation

```bash
# Default — read .anvil/grind-events.jsonl from the current repo:
bash skills/recap/scripts/grind-summary.sh

# Label the section with a plan path:
bash skills/recap/scripts/grind-summary.sh --plan docs/plans/<slug>/

# Point at a specific event log (tests, archived plans):
bash skills/recap/scripts/grind-summary.sh \
  --events /path/to/grind-events.jsonl \
  --plan docs/plans/<slug>/
```

When no `agent-completed` events exist (older runtimes, no /grind drove the
sprint), the rollup prints a one-line "(no agent-completed events recorded)"
notice and the orchestrator footer — never an error.

### Out of scope

- **Dollar conversion.** Token counts only. Cloud-model prices move too
  fast and anvil would be wrong by month two; the event log carries token
  counts (and an optional, separately-reported `cost_usd` field — see
  `docs/observability.md`) but the recap rollup intentionally does not
  multiply tokens by a rate table.
- **Orchestrator-side tokens.** Listed above; the `/cost` footer names the
  gap.

## Cadence

- v1 — run at the end of every multi-PR sprint.
- v2 — run at the end of plan-driven sprints where WHY matters (operator
  briefing future-self, decision-records audit, retrospective).
- `/grind-summary` — any time during or after a sprint, to see the
  per-slice cost-of-agent-work breakdown without the full recap.
- Pair both with `/session-closeout`.

## Style reference

If a previous v1 recap exists at `~/.claude/showme/<YYYYMMDD-HHMMSS>-recap-<slug>.html`, reference it to keep the style consistent across runs. Otherwise, use the layout shape above as the canonical structure.

## Files

- `scripts/build-recap.sh` — entry point. `--v2` enables structured mode;
  `--resolve <file>` re-runs validation + citation resolution against an
  already-generated markdown file (used for tests).
- `scripts/grind-summary.sh` — standalone per-slice rollup of agent token
  spend + tool use + wall time. Backs `/grind-summary` and is invoked
  internally by both recap modes when the operator wants the table inline.
- `templates/why-recap.md` — the structured prompt template for v2.
