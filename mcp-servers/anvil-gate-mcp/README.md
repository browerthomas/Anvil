# @anvil/gate-mcp

MCP server wrapping anvil's pre-merge gate. Exposes `verify_pr()` to any [Model Context Protocol](https://modelcontextprotocol.io/) host — Claude Code, Cursor, Windsurf, ChatGPT desktop, anything that speaks MCP.

## Why

Anvil's pre-merge gate (`scripts/verify.sh`) is the most reusable artifact in the framework: rebase + type-check + tests + architecture fitness ratchets + grep-for-forbidden-patterns + CI verification, with one structured verdict. Wrapping it as an MCP server makes that gate callable from any agent host without bundling anvil itself.

## Install

```bash
npm install -g @anvil/gate-mcp
```

You also need anvil checked out somewhere (this server shells out to anvil's `verify.sh`). Either:

- Default: `~/Desktop/anvil/` (the convention in anvil's docs).
- Override: set `ANVIL_REPO_ROOT=/path/to/anvil` env var.

## Configure your MCP host

### Claude Code

Add to your project's MCP config (or global `~/.cursor/mcp.json` / `~/.claude/mcp.json` depending on host):

```json
{
  "mcpServers": {
    "anvil-gate": {
      "command": "anvil-gate-mcp",
      "env": {
        "ANVIL_REPO_ROOT": "/Users/<you>/Desktop/anvil"
      }
    }
  }
}
```

### Cursor

Same shape under `.cursor/mcp.json`.

### Windsurf

Same shape under Windsurf's MCP config.

### Custom hosts

The server uses stdio transport. Spawn `anvil-gate-mcp` with stdin/stdout connected to the host's MCP transport.

## Usage

Once configured, the host's agents can call:

```
verify_pr(pr_number=1234)
verify_pr(pr_number=1234, strict=true)
verify_pr(pr_number=1234, base="develop", skip_rebase=true)
verify_pr(pr_number=1234, cwd="/path/to/target/repo")
```

Returns a structured verdict:

- **`MERGE-READY`** — all gates pass; safe to merge.
- **`YELLOW-FLAGS`** — non-blocking warnings (lint warnings, retried flakes); operator should review before merge.
- **`BLOCKED`** — at least one gate failed; specific reason in stdout.

## What it checks

| Gate | What |
|---|---|
| Rebase | Clean against the base branch |
| Type check | `tsc --noEmit` clean for every package with a `tsconfig.json` |
| Tests | `vitest run` passes for every package with a `vitest.config.*` |
| Fitness ratchets | Architectural fitness tests stay green |
| Forbidden patterns | grep for project-specific patterns from `.anvil/forbidden-patterns.txt` |
| CI | All GitHub PR checks are pass or skipping |

Configuration per repo:
- `.anvil/forbidden-patterns.txt` — pattern + path-glob list (see anvil's `pre-merge-gate/templates/forbidden-patterns.example.txt`).
- `.anvil/pre-merge-gate.config.json` — rebase target, test baselines, known flakes (see template).

## Develop

```bash
git clone https://github.com/browerthomas/Anvil.git
cd Anvil/mcp-servers/anvil-gate-mcp
npm install
npm run build
npm run start    # production
npm run dev      # tsx watch mode
```

## Why MCP, not just a Claude Code skill?

The skill (in `~/Desktop/anvil/skills/pre-merge-gate/`) is the canonical implementation. The MCP server makes the same logic callable from non-Claude-Code hosts. Two distribution rails for one gate.

## Status

v0.1.0 — initial release. Works against anvil v0.2+ skill structure. Future:
- v0.2: streaming progress (don't wait for the whole gate to finish before yielding partial output)
- v0.3: bundle a minimal anvil checkout so users don't need a separate clone
- v0.3+: MCP-ize the rest of anvil (`/dispatch-slice`, `/auto-merge`, `/recap`)

## License

MIT — see anvil's [LICENSE](https://github.com/browerthomas/Anvil/blob/main/LICENSE).
