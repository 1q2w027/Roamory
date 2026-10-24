import fs from "node:fs";
import path from "node:path";
import { query, type HookCallback } from "@anthropic-ai/claude-agent-sdk";
import { ensureBrowser } from "@remotion/renderer";
import { RENDER_ROOT, type Config } from "../server/config";
import type { AgentFn } from "../server/jobs";
import { BUILTIN_TOOLS, checkToolUse, MCP_SERVER, type GuardRoots } from "./guard";
import { systemPrompt, userPrompt } from "./prompt";
import { createToolServer, newSession, type ToolContext } from "./tools";
import { createWorkspace, removeWorkspace } from "./workspace";

const MCP_TOOLS = ["look_at_clip", "preview_frames", "render_video", "submit"].map((t) => `mcp__${MCP_SERVER}__${t}`);

/**
 * The agent-mode AgentFn: builds the job's workspace and runs a Claude agent over it with only the
 * file tools (guarded to the workspace) and the four MCP tools. Jobs aborts `signal` at AGENT_TIMEOUT_S.
 * Logs turns, tool counts, cost and elapsed time, never video or frames.
 */
export function createAgentRunner(config: Config, log: (line: string) => void = console.log): AgentFn {
  const { agent } = config;
  // Anything left from a previous run is unreachable now.
  fs.rmSync(agent.workRoot, { recursive: true, force: true });
  fs.mkdirSync(agent.workRoot, { recursive: true });
  let browser: Promise<unknown> | null = null;

  return async (input, workDir, onProgress, signal) => {
    const started = Date.now();
    browser ??= ensureBrowser();
    await browser;
    const ws = createWorkspace(agent.workRoot, input, workDir, path.join(config.publicDir, "music"));
    const ctx: ToolContext = {
      input,
      ws,
      outputPath: path.join(workDir, "out.mp4"),
      maxRenders: agent.maxRenders,
      onProgress,
      signal,
      session: newSession(),
    };
    const roots: GuardRoots = { workspace: ws.dir, writable: ws.srcDir, readable: [path.join(RENDER_ROOT, "src/remotion")] };
    const guard: HookCallback = async (hook) => {
      if (hook.hook_event_name !== "PreToolUse") return {};
      const reason = checkToolUse(hook.tool_name, (hook.tool_input ?? {}) as Record<string, unknown>, roots);
      if (reason) log(`agent job=${input.jobId} denied tool=${hook.tool_name}`);
      return reason ? { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } } : {};
    };

    const abortController = new AbortController();
    const abort = () => abortController.abort();
    signal.addEventListener("abort", abort);
    let turns = 0;
    let cost = 0;
    let ending = "none";
    onProgress(0.01);
    try {
      for await (const message of query({
        prompt: userPrompt(input),
        options: {
          cwd: ws.dir,
          model: agent.model,
          effort: agent.effort,
          maxTurns: agent.maxTurns,
          abortController,
          systemPrompt: systemPrompt(agent.maxRenders),
          tools: BUILTIN_TOOLS,
          allowedTools: [...BUILTIN_TOOLS, ...MCP_TOOLS],
          // Anything not allowed above is denied; the hook keeps the allowed file tools inside the workspace.
          permissionMode: "dontAsk",
          hooks: { PreToolUse: [{ hooks: [guard] }] },
          mcpServers: { [MCP_SERVER]: createToolServer(ctx) },
          strictMcpConfig: true,
          // No user or project settings, CLAUDE.md, skills or plugins from this machine, and no transcript on disk.
          settingSources: [],
          persistSession: false,
          // Only what the agent process needs; not APP_TOKEN or the backend's settings.
          env: {
            PATH: process.env.PATH,
            HOME: process.env.HOME,
            ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
            CLAUDE_AGENT_SDK_CLIENT_APP: "roamory-render",
          },
        },
      })) {
        if (message.type === "assistant" && message.parent_tool_use_id === null) turns++;
        if (message.type === "result") {
          cost = message.total_cost_usd;
          ending = message.subtype;
        }
      }
    } catch (e) {
      // The SDK throws when aborted; Jobs reports that as agent_timeout. A crash after a valid submit still counts.
      if (!ctx.session.result) throw e;
    } finally {
      signal.removeEventListener("abort", abort);
      removeWorkspace(ws);
      const { looks, previews, renders } = ctx.session;
      const elapsed = ((Date.now() - started) / 1000).toFixed(1);
      log(
        `agent job=${input.jobId} turns=${turns} looks=${looks} previews=${previews} renders=${renders} ` +
          `submitted=${ctx.session.result !== null} ending=${ending} cost_usd=${cost.toFixed(4)} elapsed_s=${elapsed}`,
      );
    }
    if (!ctx.session.result) throw new Error(`the agent ended without a valid submit (${ending})`);
    return ctx.session.result;
  };
}
