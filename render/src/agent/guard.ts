import fs from "node:fs";
import path from "node:path";

/** Built-in tools the agent gets. No Bash, web, subagents or anything else. */
export const BUILTIN_TOOLS = ["Read", "Write", "Edit", "Glob"];
/** Name of the in-process MCP server (tools.ts); its tools are mcp__{name}__{tool}. */
export const MCP_SERVER = "roamory";

export type GuardRoots = {
  /** The agent's cwd; relative paths resolve against it. */
  workspace: string;
  /** Write and Edit only here (the workspace's src/). */
  writable: string;
  /** Read and Glob here too, besides the workspace (render/src/remotion, the working examples). */
  readable: string[];
};

/**
 * Why a tool call is denied, or null to allow it. Run on every call (a PreToolUse hook in run.ts),
 * so it holds even for tools the session would otherwise allow without asking.
 */
export function checkToolUse(toolName: string, input: Record<string, unknown>, roots: GuardRoots): string | null {
  if (toolName.startsWith(`mcp__${MCP_SERVER}__`)) return null;
  const readRoots = [roots.workspace, ...roots.readable];
  switch (toolName) {
    case "Read":
      return inside(input.file_path, roots.workspace, readRoots) ? null : "Read is limited to the workspace and the example sources";
    case "Glob": {
      const pattern = String(input.pattern ?? "");
      if (path.isAbsolute(pattern) || pattern.split(/[\\/]/).includes("..")) return "Glob patterns must be relative, without ..";
      return inside(input.path ?? roots.workspace, roots.workspace, readRoots) ? null : "Glob is limited to the workspace and the example sources";
    }
    case "Write":
    case "Edit":
      return inside(input.file_path, roots.workspace, [roots.writable]) ? null : `${toolName} is limited to the workspace's src/`;
    default:
      return `${toolName} is not available`;
  }
}

/** True if `p` (resolved against `cwd`) is inside one of `roots`, both as written and after following symlinks. */
function inside(p: unknown, cwd: string, roots: string[]): boolean {
  if (typeof p !== "string" || p === "") return false;
  const resolved = path.resolve(cwd, p);
  const real = realpathOfExisting(resolved);
  const realRoots = roots.map(realpathOfExisting);
  const within = (file: string, root: string) => {
    const rel = path.relative(root, file);
    return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  };
  return [resolved, real].every((file) => roots.some((r, i) => within(file, r) || within(file, realRoots[i])));
}

/** realpath of the longest existing prefix, with the rest appended (a file about to be written doesn't exist yet). */
function realpathOfExisting(p: string): string {
  let head = p;
  const tail: string[] = [];
  while (!fs.existsSync(head)) {
    const parent = path.dirname(head);
    if (parent === head) return p;
    tail.unshift(path.basename(head));
    head = parent;
  }
  return path.join(fs.realpathSync(head), ...tail);
}
