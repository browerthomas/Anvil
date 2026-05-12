# Observability

How anvil tracks per-plan execution state + how to plug in hosted observability without lock-in.

## Append-only event log

`.anvil/grind-events.jsonl` is anvil's source of truth for what happened during a `/grind` run. One JSON event per line. Append-only — never mutated.

### Event shape

```json
{"t": "2026-05-10T12:34:56Z", "ev": "<event-type>", "slice": "<slice-id>", "data": {...}}
```

### Event types

| Type | When | Data |
|---|---|---|
| `plan-init` | plan loaded | `{plan_path, slices: {...}}` |
| `slice-pending` | slice queued (initial) | null |
| `slice-in-flight` | agent dispatched | `{agent_id, worktree, tokens_in?, tokens_out?, cost_usd?}` |
| `slice-pr-opened` | agent returned a PR | `{pr_number, tokens_in?, tokens_out?, cost_usd?}` |
| `slice-reviewed` | review pass complete | `{findings_count, blocking}` |
| `slice-merged` | auto-merge succeeded | `{pr_number?, tests_delta?, tokens_in?, tokens_out?, cost_usd?}` |
| `slice-deferred` | slice paused/skipped | `{reason}` |
| `slice-skipped` | operator-paced or rejected | `{reason}` |
| `issue-filed` | follow-up issue tracked | `{number}` |
| `decision` | operator-decision invoked | `{verb, outcome, response}` |

### Token / cost fields (optional, nullable)

| Field | Type | Source | Notes |
|---|---|---|---|
| `tokens_in` | integer | agent runtime | Input/prompt tokens consumed. |
| `tokens_out` | integer | agent runtime | Output/completion tokens. |
| `cost_usd` | number | agent runtime | Dollar cost as a JSON number (e.g. `0.0123`). |

All three are **optional** on `slice-in-flight`, `slice-pr-opened`, and
`slice-merged`. The fold accumulates them additively across all three events
so a re-dispatched slice carries the sum of its dispatches. When the runtime
cannot report them (e.g. codex CLI review, manual edits, hermes-routed
agents) the writer simply omits the keys; the folded snapshot then carries
nulls and `/anvil-status` + `/recap v2` suppress the cost footer / TLDR cost
claim for that plan.

Writers populate them via the same `state.sh` API:

```bash
bash skills/grind/scripts/state.sh mark <slice> in-flight \
  --tokens-in 1234 --tokens-out 567 --cost-usd 0.0123

bash skills/grind/scripts/state.sh set-pr <slice> 42 \
  --tokens-in 200 --cost-usd 0.005

bash skills/grind/scripts/state.sh mark <slice> merged \
  --tests-delta 8 --pr 42 --tokens-out 100 --cost-usd 0.003
```

The flags are accepted on `mark` (any status) and `set-pr`; unknown flags
fail-loud so a typo can't silently lose cost data.

### Snapshot rollups

The folded snapshot at `.anvil/grind-snapshot.json` carries three top-level
rollups derived from the per-slice token/cost fields:

| Key | Type | Meaning |
|---|---|---|
| `cost_total_usd` | number | Sum of `slices[*].cost_usd` (0 when none reported). |
| `tokens_in_total` | integer | Sum of `slices[*].tokens_in`. |
| `tokens_out_total` | integer | Sum of `slices[*].tokens_out`. |

`/anvil-status` reads these to emit the `Cost:` footer; `/recap v2`'s prompt
template embeds the per-slice rollup so the model can include a cost line in
its TLDR (when the runtime actually reported the fields).

### Snapshot view

`.anvil/grind-snapshot.json` is auto-derived from the event log by folding all events. Never edit by hand. `state.sh status` rebuilds it on every call. The event log is the durable record.

### Replay + trace

```bash
# Print full event log (or filter to one slice)
state.sh trace
state.sh trace A1

# Rebuild snapshot from the log + print
state.sh snapshot

# Rewind a slice back to "pending" (writes a new slice-pending event;
# subsequent events overlay)
state.sh replay A1
```

The append-only shape means you can:
- See exactly what happened, when, in what order
- Resume a halted run (`/grind --resume <slice-id>` reads from the last frame)
- Diff state across two runs (the events are the diff)
- Time-travel debug (replay events up to point-in-time, examine snapshot)

## Hosted observability adapter (Langfuse)

The event log is local-first by default. For teams that want hosted traces, anvil emits OTel-compatible spans to [Langfuse](https://langfuse.com) (MIT, OSS, self-hostable) when configured.

### Configure

Drop `.anvil/observability.config.json`:

```json
{
  "enabled": true,
  "provider": "langfuse",
  "endpoint": "https://cloud.langfuse.com",
  "public_key_env": "LANGFUSE_PUBLIC_KEY",
  "secret_key_env": "LANGFUSE_SECRET_KEY",
  "tags": ["anvil", "<your-project-name>"]
}
```

Set the env vars (`LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY`) in your shell or via direnv.

### What's emitted

Each `slice-*` event becomes an OTel span:
- Span name: `anvil.<event-type>`
- Attributes: `slice.id`, `slice.status`, `pr.number`, `verb` (for decisions),
  `slice.tokens_in`, `slice.tokens_out`, `slice.cost_usd` (when reported)
- Duration: time between matching `slice-pending` and `slice-merged`/`slice-deferred`/`slice-skipped`

Anvil now propagates the optional `tokens_in` / `tokens_out` / `cost_usd`
fields when the writer attached them to the event. Where the runtime cannot
report them (codex CLI review, manual marks) the OTel span omits the
attribute — Langfuse's UI will show the column as null for that span. Anvil's
spans remain orchestration metadata; raw LLM call traces still come from the
agent runtime itself (Claude Code's own observability, Anthropic SDK
prompt-cache headers).

### Self-host

Langfuse runs as Docker / docker-compose. See [langfuse.com/self-hosting](https://langfuse.com/self-hosting). Point `endpoint` at your instance. Same OTel emission, no SaaS bill.

### Disable

Either delete `.anvil/observability.config.json` or set `"enabled": false`. Anvil reverts to event-log-only.

## What this gives you vs LangGraph + LangSmith

LangGraph's checkpointer is the gold standard for agent-orchestration observability — replay-from-any-checkpoint, time-travel, per-node token + latency, hierarchical traces.

Anvil's event log + Langfuse adapter targets the same shape with a different cost profile:
- **Anvil:** local-first, OSS, optional hosted backend, MIT.
- **LangGraph + LangSmith:** hosted-first (LangSmith is closed-source SaaS), Python-only, more powerful but proprietary observability.

For OSS + multi-language (Claude Code skills are bash + markdown) anvil's shape is the right fit. If you outgrow it, the event log is portable — you can ETL it into any tracing backend.

## Roadmap

- v0.2: append-only event log + snapshot fold (shipped).
- v0.2.1: Langfuse adapter implementation (currently spec'd; emit OTel spans for each event).
- v0.3: per-slice token cost wired through the event log (shipped — see `slice-in-flight` / `slice-pr-opened` / `slice-merged` token/cost fields above). Writers populate them when the agent runtime exposes the counters; readers (`/anvil-status`, `/recap v2`) surface totals only when present.
- v0.3+: replay-from-checkpoint with state diff (compare slice manifests pre + post).
