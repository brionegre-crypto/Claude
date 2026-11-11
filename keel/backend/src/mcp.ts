import type { Env } from "./index";
import { json } from "./ai";

/**
 * Remote MCP server ("custom connector") so Claude — claude.ai, the Claude apps, and Claude Duet
 * if/when it accepts custom connectors — can read your Keel tasks, habits, notes and today's plan,
 * and add tasks / start focus. Data comes from a snapshot the iPhone uploads after each sync
 * (POST /snapshot); writes are queued and the app applies them on next sync (GET /actions).
 *
 * Minimal Streamable-HTTP JSON-RPC implementation (no SSE needed for these tools).
 * Add in Claude: Settings → Connectors → Add custom connector → https://<worker>/mcp
 */
const TOOLS = [
  {
    name: "get_today",
    description: "Today's plan, the user's single next action, top emails needing a reply, and active habit stacks.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "list_tasks",
    description: "Open tasks with due dates, energy level and micro-steps. Optional list filter.",
    inputSchema: { type: "object", properties: { list: { type: "string" } }, additionalProperties: false },
  },
  {
    name: "search_notes",
    description: "Full-text search across Keel notes. Returns titles and matching text.",
    inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"], additionalProperties: false },
  },
  {
    name: "list_promises",
    description: "Open commitments the user made in emails they sent (e.g. 'I'll send the deck Friday'), with recipient, quote and due date.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "add_task",
    description: "Add a task to Keel (syncs to Apple Reminders). Due date optional, ISO 8601.",
    inputSchema: {
      type: "object",
      properties: { title: { type: "string" }, due: { type: "string" }, list: { type: "string" } },
      required: ["title"],
      additionalProperties: false,
    },
  },
  {
    name: "start_focus",
    description: "Ask the user's iPhone to start a Keel focus session (they confirm on the phone).",
    inputSchema: { type: "object", properties: { minutes: { type: "integer" } }, required: ["minutes"], additionalProperties: false },
  },
];

type Snapshot = {
  today?: unknown;
  tasks?: { title: string; list: string; due?: string; energy: string; steps: string[] }[];
  notes?: { title: string; text: string }[];
  promises?: { promise: string; to: string; quote: string; due: string; overdue: boolean }[];
};

export async function handleMCP(req: Request, env: Env): Promise<Response> {
  const msg = (await req.json()) as { id?: number | string; method: string; params?: any };
  const reply = (result: unknown) => json({ jsonrpc: "2.0", id: msg.id, result });

  switch (msg.method) {
    case "initialize":
      return reply({
        protocolVersion: "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "keel", version: "0.1.0" },
      });
    case "notifications/initialized":
      return new Response(null, { status: 202 });
    case "tools/list":
      return reply({ tools: TOOLS });
    case "tools/call": {
      const snap = ((await env.KEEL.get("snapshot", "json")) ?? {}) as Snapshot;
      const args = msg.params?.arguments ?? {};
      const text = (t: unknown) => reply({ content: [{ type: "text", text: typeof t === "string" ? t : JSON.stringify(t, null, 2) }] });
      switch (msg.params?.name) {
        case "get_today":
          return text(snap.today ?? "No snapshot yet — open Keel on the iPhone once.");
        case "list_tasks":
          return text((snap.tasks ?? []).filter((t) => !args.list || t.list === args.list));
        case "list_promises":
          return text(snap.promises ?? []);
        case "search_notes": {
          const q = String(args.query).toLowerCase();
          return text((snap.notes ?? []).filter((n) => (n.title + n.text).toLowerCase().includes(q)).slice(0, 10));
        }
        case "add_task":
        case "start_focus": {
          const queue = ((await env.KEEL.get("actions", "json")) ?? []) as unknown[];
          queue.push({ type: msg.params.name, args, at: new Date().toISOString() });
          await env.KEEL.put("actions", JSON.stringify(queue));
          return text(`Queued. Keel will apply it on the iPhone's next sync.`);
        }
        default:
          return json({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "unknown tool" } });
      }
    }
    default:
      return json({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "method not found" } });
  }
}
