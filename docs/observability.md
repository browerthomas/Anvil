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
| `slice-in-flight` | agent dispatched | `{agent_id, worktree}` |
| `slice-pr-opened` | agent returned a PR | `{pr_number}` |
| `slice-reviewed` | review pass complete | `{findings_count, blocking}` |
| `slice-merged` | auto-merge succeeded | null |
| `slice-deferred` | slice paused/skipped | `{reason}` |
| `slice-skipped` | operator-paced or rejected | `{reason}` |
| `issue-filed` | follow-up issue tracked | `{number}` |
| `decision` | operator-decision invoked | `{verb, outcome, response}` |

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
- Attributes: `slice.id`, `slice.status`, `pr.number`, `verb` (for decisions)
- Duration: time between matching `slice-pending` and `slice-merged`/`slice-deferred`/`slice-skipped`

Per-slice token cost + LLM latency are NOT emitted by anvil itself — those come from the agent runtime (Claude Code's own observability, or the Anthropic API SDK's prompt-cache headers). Anvil's spans are the orchestration metadata.

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
- v0.3: per-slice token cost from Claude Code's token-counter (when the API exposes it cleanly).
- v0.3+: replay-from-checkpoint with state diff (compare slice manifests pre + post).
