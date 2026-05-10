# anvil MCP servers

Model Context Protocol servers that expose anvil's skills to non-Claude-Code hosts (Cursor, Windsurf, ChatGPT desktop, custom agents — anything that speaks MCP).

Anvil's primary distribution is Claude Code skills. The MCP servers are the **portable rail** — same logic, different transport, broader reach.

## Servers

| Package | Wraps | Status | Why |
|---|---|---|---|
| [`@anvil/gate-mcp`](anvil-gate-mcp/) | `/pre-merge-gate` | v0.1.0 (alpha) | Most reusable artifact — rebase + tsc + tests + fitness + grep, one verdict |

### Roadmap

| Future package | Wraps | Reason |
|---|---|---|
| `@anvil/dispatch-mcp` | `/dispatch-slice` | Per-slice agent dispatch, callable from any host |
| `@anvil/recap-mcp` | `/recap` | Visual session reports, host-agnostic |
| `@anvil/grind-mcp` | `/grind` | Full orchestrator. Bigger surface; later. |

## Why MCP, not just skills?

Skills (`~/.claude/skills/<name>/SKILL.md`) are Claude Code's first-party extension format. They're great for that ecosystem.

MCP servers (the [Model Context Protocol](https://modelcontextprotocol.io/)) are a vendor-neutral way to expose tools to any AI host. As of March 2026, 5,000+ MCP servers are portable across Claude Code, Cursor, Windsurf, ChatGPT desktop, and a growing number of custom agent runtimes.

By shipping anvil's skills BOTH ways, we get:
- **Claude Code-native operators** install anvil as a skill bundle.
- **Cursor / Windsurf / other-host operators** install anvil as MCP servers.
- **Custom agent runtimes** can call anvil's gate over stdio MCP.

Same logic, two transports, no fragmentation.

## Install (development)

```bash
cd mcp-servers/<package-name>
npm install
npm run build
npm run start
```

## Publish

Each package publishes independently to npm under the `@anvil` scope:

```bash
cd mcp-servers/anvil-gate-mcp
npm version <patch|minor|major>
npm publish --access public
```

## License

All MCP servers are MIT — see anvil's [LICENSE](../LICENSE).
