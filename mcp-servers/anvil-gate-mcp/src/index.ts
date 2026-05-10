#!/usr/bin/env node
/**
 * anvil-gate-mcp — Model Context Protocol server wrapping anvil's pre-merge gate.
 *
 * Exposes one tool: verify_pr(pr_number, options).
 * The server shells out to anvil's scripts/verify.sh and returns the verdict.
 *
 * Usage (in an MCP-capable host):
 *   1. Install: `npm install -g @anvil/gate-mcp`
 *   2. Configure your host's MCP config to point at the `anvil-gate-mcp` binary.
 *   3. The host's agents can now call `verify_pr` to gate merges.
 *
 * The server requires `ANVIL_REPO_ROOT` env var pointing at the anvil repo
 * (so it knows where verify.sh lives), or it falls back to ~/Desktop/anvil.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const ANVIL_REPO_ROOT =
  process.env.ANVIL_REPO_ROOT ??
  join(homedir(), "Desktop", "anvil");

const VERIFY_SCRIPT = join(
  ANVIL_REPO_ROOT,
  "skills",
  "pre-merge-gate",
  "scripts",
  "verify.sh"
);

if (!existsSync(VERIFY_SCRIPT)) {
  console.error(
    `anvil-gate-mcp: verify.sh not found at ${VERIFY_SCRIPT}. ` +
      `Set ANVIL_REPO_ROOT to your anvil checkout root.`
  );
  process.exit(1);
}

interface VerifyArgs {
  pr_number: number;
  worktree?: string;
  base?: string;
  skip_rebase?: boolean;
  strict?: boolean;
  cwd?: string;
}

function runVerify(args: VerifyArgs): Promise<{
  exit_code: number;
  stdout: string;
  stderr: string;
  verdict: "merge-ready" | "yellow-flags" | "blocked";
}> {
  return new Promise((resolve) => {
    const cliArgs: string[] = [String(args.pr_number)];
    if (args.worktree) cliArgs.push("--worktree", args.worktree);
    if (args.base) cliArgs.push("--base", args.base);
    if (args.skip_rebase) cliArgs.push("--skip-rebase");
    if (args.strict) cliArgs.push("--strict");

    const child = spawn(VERIFY_SCRIPT, cliArgs, {
      cwd: args.cwd ?? process.cwd(),
      env: process.env,
    });

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));

    child.on("close", (code) => {
      const verdict =
        code === 0 ? "merge-ready" : code === 2 ? "yellow-flags" : "blocked";
      resolve({ exit_code: code ?? 1, stdout, stderr, verdict });
    });
  });
}

const server = new Server(
  {
    name: "anvil-gate-mcp",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "verify_pr",
      description:
        "Run anvil's pre-merge gate against a GitHub PR. Combines rebase + tsc + " +
        "tests + architecture fitness ratchets + grep-for-forbidden-patterns + CI " +
        "verification. Returns a structured verdict (merge-ready | yellow-flags | blocked).",
      inputSchema: {
        type: "object",
        properties: {
          pr_number: {
            type: "integer",
            description: "GitHub PR number to verify.",
          },
          worktree: {
            type: "string",
            description: "Optional path to a pre-checked-out worktree (skips re-fetch).",
          },
          base: {
            type: "string",
            description: "Base branch (defaults to the project's main / default branch).",
          },
          skip_rebase: {
            type: "boolean",
            description: "If true, skip the rebase-against-base step (use when already done).",
            default: false,
          },
          strict: {
            type: "boolean",
            description: "If true, treat warnings as blocking failures.",
            default: false,
          },
          cwd: {
            type: "string",
            description:
              "Working directory for the gate run. Defaults to the host process's cwd. " +
              "Should be inside the target repo so .anvil/ config is discoverable.",
          },
        },
        required: ["pr_number"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "verify_pr") {
    throw new Error(`Unknown tool: ${name}`);
  }

  const result = await runVerify(args as unknown as VerifyArgs);

  return {
    content: [
      {
        type: "text",
        text: [
          `Verdict: ${result.verdict.toUpperCase()}`,
          ``,
          `--- stdout ---`,
          result.stdout || "(empty)",
          ``,
          `--- stderr ---`,
          result.stderr || "(empty)",
          ``,
          `Exit code: ${result.exit_code}`,
        ].join("\n"),
      },
    ],
    isError: result.verdict === "blocked",
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("anvil-gate-mcp ready (stdio)");
