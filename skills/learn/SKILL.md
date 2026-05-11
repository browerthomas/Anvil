---
name: learn
description: Use to record + recall per-project learnings as an append-only JSONL log at .anvil/learnings.jsonl. Skills auto-append on discovery ("chronic flake X bit again, retry once"); operators search before re-rediscovering. Subcommands add, search, prune, summary, export. Invoke with /learn add <key> <type> "<insight>", /learn search <query>, /learn summary, /learn prune --before <date>, /learn export, or when the operator says "log this lesson", "have we seen this flake before", "what did we learn last sprint".
---

# /learn — append-only per-project learnings log

A chronic flake gets rediscovered every 2-3 sprints because there's no structured per-project memory between conversations. MEMORY.md is human-curated and lives in `~/.claude/` (per-conversation, not per-project). `.anvil/grind-events.jsonl` is the *event* log — slice transitions, not insights.

`.anvil/learnings.jsonl` is the **per-project, append-only learnings log**. Skills auto-append when they discover something worth remembering. Operators (or other skills) search before treating a new symptom as new. The operator's MEMORY.md becomes a *human-curated layer on top*, not the only layer.

Inspired by gstack's `learnings.jsonl` pattern (`research/gstack-comparison-2026-05-11.md`).

## When to invoke

- Operator says "log this", "log a lesson", "remember this for next time", "have we seen this before", "what did we learn last sprint".
- Skills auto-invoke when they detect a re-occurring pattern (see [Integration points](#integration-points) below).
- Before locking a `/spec` plan or starting a `/grind`: `/learn search <topic>` to surface relevant prior gotchas.

## When NOT to use

- One-off observations that aren't worth re-surfacing — don't pollute the log with single-use detail.
- Things that belong in commit messages, PR bodies, or CHANGELOG — those have their own surfaces.
- Cross-project insights — those belong in the operator's `~/.claude/.../MEMORY.md`. The JSONL is **per-project**.

## Storage shape

`.anvil/learnings.jsonl` — one JSON object per line. Append-only.

Each line:

```json
{
  "key":          "chronic-vitest-flake",
  "type":         "flake",
  "insight":      "vitest worker crash on macOS 25.3 under CPU contention; retry once before treating as slice-fail",
  "confidence":   "high",
  "source_skill": "/pre-merge-gate",
  "files":        [".anvil/known-flakes.txt"],
  "tags":         ["retry-once"],
  "slice_id":     null,
  "prior_count":  0,
  "timestamp":    "2026-05-11T00:14:32Z"
}
```

**Fields:**

| Field | Description |
|---|---|
| `key` | Short slug, unique per insight. Used for dedup + recurrence counting. Lowercase, `[a-z0-9._-]`. |
| `type` | Closed vocabulary: `flake \| gotcha \| invariant \| decision \| cost \| perf \| migration-shape`. Future skills filter by type. |
| `insight` | One-paragraph human-readable summary. |
| `confidence` | `low \| medium \| high`. Updates as the insight is re-confirmed. |
| `source_skill` | Which skill emitted it (`/grind`, `/pre-merge-gate`, `/dispatch-slice`, etc) — or `manual` if added by hand. |
| `files` | Array of relevant file paths. May be empty. |
| `tags` | Optional ad-hoc strings for free-text search. |
| `slice_id` | Optional reference to a plan slice (e.g. `"B1"`). |
| `prior_count` | Auto-managed: count of prior entries with this `key`. Re-confirmations rank higher in search. |
| `timestamp` | ISO 8601 UTC. |

**Dedup semantics:** The JSONL is append-only. Re-adding the same `key` does NOT overwrite — it appends a new line with `prior_count` incremented. `/learn search` dedup-by-key by default (keep the most-confident, most-recent), surfaces re-confirmation count next to the key.

**Idempotency window:** If the same `(key, source_skill)` pair is added within 60s, the second call is a no-op (default — auto-emit hooks call `learn add` whenever they see the pattern; we don't want N entries per second). Override with `--idempotency-window <seconds>` (0 = disabled).

## Subcommands

### `/learn add <key> <type> "<insight>"`

Append a new entry.

```bash
/learn add chronic-vitest-flake flake "vitest worker crash on macOS 25.3 under CPU contention; retry once before treating as slice-fail" \
  --confidence high \
  --source /pre-merge-gate \
  --file .anvil/known-flakes.txt \
  --tag retry-once
```

| Flag | Default | Description |
|---|---|---|
| `--confidence <c>` | `medium` | One of `low`, `medium`, `high` |
| `--source <s>` | `manual` | Emitting skill (`/grind`, `/pre-merge-gate`, etc) |
| `--file <p>` | — | Repeatable; relevant file path |
| `--tag <t>` | — | Repeatable; free-text tag |
| `--slice <id>` | — | Plan slice reference (e.g. `S3`, `B1`) |
| `--idempotency-window <s>` | `60` | Skip if same (key,source) added within window. `0` = disabled. |
| `--strict` | off | Exit non-zero on validation failure (use in tests). Default: soft-fail (exit 0, warn to stderr) so auto-emit can't block the parent skill. |

### `/learn search <query>`

Substring search with ranking. Default top 10.

```bash
/learn search flake                          # query
/learn search "" --type flake                # filter only
/learn search vitest --type flake --limit 5
/learn search worker --json                  # raw JSON
/learn search chronic --all                  # don't dedup by key
```

**Ranking:** `confidence_weight * 10 + min(prior_count, 5)`, tie-broken by recency. Re-confirmed high-confidence learnings always float to the top.

**Default dedup:** one row per `key` (the highest-scoring). Pass `--all` to see every line.

### `/learn prune --before <YYYY-MM-DD>`

Drop entries older than the cutoff. Default: prompts for confirmation, archives dropped lines to `.anvil/learnings.archive.jsonl` (never deletes).

```bash
/learn prune --before 2026-04-01 --dry-run             # preview
/learn prune --before 2026-04-01                       # interactive
/learn prune --before 2026-04-01 --yes                 # no prompt
/learn prune --before 2026-04-01 --keep-confidence high # never drop high-confidence
```

`--keep-confidence` preserves entries at that confidence level or above regardless of age — high-confidence invariants don't decay.

### `/learn summary`

Last 20 entries grouped by type.

```bash
/learn summary
/learn summary --limit 50 --since 2026-05-01
```

### `/learn export`

Emit a MEMORY.md-compatible markdown chunk on stdout. The operator can paste it into their durable per-conversation memory if they want to promote some learnings.

```bash
/learn export                                 # all high+medium confidence
/learn export --since 2026-05-01 --min-confidence high
```

## Procedure (when invoked)

### `/learn add`

1. Validate args: `key` is a slug; `type` is in the closed vocabulary; `confidence` is `low|medium|high`.
2. Resolve `.anvil/learnings.jsonl` (auto-create if missing).
3. Check idempotency window: if same `(key, source_skill)` within 60s, no-op.
4. Count prior entries with this `key` → `prior_count`.
5. Build the JSON line + append.
6. Print confirmation (or "re-confirmed Nx" if `prior_count > 0`).

### `/learn search`

1. Resolve `.anvil/learnings.jsonl`. If absent: "no learnings yet" + exit 0.
2. Filter: `--type`, `--source`, `--key`, substring match on `insight + key + tags`.
3. Score each: confidence weight × 10 + min(prior_count, 5).
4. Sort by score desc, recency desc.
5. Default-dedup by `key` (keep highest-scored). `--all` to skip dedup.
6. Take top `--limit` (default 10).
7. Print human table, or `--json` for raw matches.

### `/learn prune`

1. Validate `--before` is `YYYY-MM-DD`.
2. Compute keep + drop counts via jq.
3. Print plan; if `--dry-run`: exit.
4. Prompt for confirm (skip with `--yes`).
5. Split: keep → atomic write to `.anvil/learnings.jsonl` (via `.tmp` + `mv`), drop → append to `.anvil/learnings.archive.jsonl`.

### `/learn summary`

1. Read `.anvil/learnings.jsonl`.
2. Filter by `--since` if set.
3. Sort by recency desc, take `--limit`, group by `type`.
4. Print each group as a section.

### `/learn export`

1. Read `.anvil/learnings.jsonl`.
2. Filter by `--since` and `--min-confidence` if set.
3. Sort by type, then recency desc.
4. Emit a markdown chunk grouped by type with paste-ready formatting.

## Integration points (auto-emit hooks)

These existing skills auto-call `/learn add` at the right moments. Auto-emit calls use the soft-fail default — if the JSONL is corrupted, full disk, etc., the parent skill keeps going (the `/learn add` script exits 0 with a warning to stderr).

| Skill | When | Type | Example `key` |
|---|---|---|---|
| `/pre-merge-gate` | Detects a flake retry-passing per `.anvil/known-flakes.txt` | `flake` | `vitest-worker-crash-retry-passed` |
| `/findings-rollup` | Consolidates a multi-critic review with ≥3 P1s | `gotcha` | `multi-critic-pattern-<plan-slug>` |
| `/auto-merge` | Successful merge after a non-trivial rebase (rebase commits > 0) | `migration-shape` | `rebase-shape-<plan-slug>-S<N>` |
| `/dispatch-slice` | Dispatch attempt fails (worktree busy, deps install fail) | `gotcha` | `dispatch-fail-<reason>` |

Each integration point invokes the script via a short helper at the end of its procedure:

```bash
# Soft, non-blocking — auto-emit hooks must never abort the parent skill.
bash "$ANVIL_ROOT/skills/learn/scripts/learn-add.sh" \
  "<key>" "<type>" "<insight>" \
  --confidence medium --source "<skill-name>" \
  2>/dev/null || true
```

`/grind` does not directly auto-emit — it composes the four skills above, which each emit on their own.

## Privacy

`.anvil/learnings.jsonl` may contain project-specific gotchas (test names, file paths, internal terminology). It is **default-gitignored** so cloned repos start clean. If the operator wants to share the learnings as part of the repo, they can:

```bash
git add -f .anvil/learnings.jsonl
git commit -m "chore(anvil): seed learnings log"
```

The archive file (`.anvil/learnings.archive.jsonl`) is gitignored under the same rule.

## Composition with other anvil skills

- After `/codex-review` or `/self-review --multi-critic` lands findings → consider `/learn add` for the cross-cutting pattern (or let `/findings-rollup` auto-emit one).
- Before `/spec`-ing a new plan in a familiar problem area → `/learn search <topic>` first.
- After `/grind` reports a slice deferral → `/learn add <slice-id> gotcha "..."` so the next plan touching the same area gets a heads-up.
- `/recap` could pull last-N entries by type — left as a follow-up.

## Configuration

Per-project tuning lives in `.anvil/learn.config.json` (optional). Shape:

```json
{
  "default_idempotency_window_seconds": 60,
  "search_default_limit": 10,
  "summary_default_limit": 20,
  "export_min_confidence": "medium"
}
```

If absent: skill uses the defaults above. The file is read but not parsed by the current scripts — it's a hook for future extension; the scripts honor the same defaults shipped here.

## Output examples

```
$ /learn add chronic-vitest-flake flake "vitest worker crash on macOS 25.3 under CPU contention; retry once" --confidence high --source /pre-merge-gate
✓ learning recorded: chronic-vitest-flake [flake/high]

$ /learn add chronic-vitest-flake flake "third confirmation" --source /grind
✓ learning re-confirmed: chronic-vitest-flake (now seen 3x)

$ /learn search vitest
[anvil] Top 1 learnings:

  [FLAKE/high] chronic-vitest-flake  (seen 3x)
    vitest worker crash on macOS 25.3 under CPU contention; retry once
    source: /grind · ts: 2026-05-11T00:14:35Z
```
